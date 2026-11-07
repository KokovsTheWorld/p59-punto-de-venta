-module(p59_venta).
-behaviour(gen_statem).

%% Una venta = un proceso gen_statem, registrado globalmente como {p59_venta, Id}.
%%
%%   abierta ──pagar──▶ procesando_pago ──confirmada──▶ pagada (final)
%%     ▲  │                 │      │
%%     │  └──cancelar──▶ cancelada (final)
%%     │                    │      └─terminal sin respuesta / falla al confirmar─▶ pendiente_de_revision
%%     └──rechazo, sin existencia, turno cerrado◀─┘                                   │
%%     ◀──────────────── revisar: el banco no registra el cargo ◀──────────────────────┤
%%                       revisar: el banco si lo registra ──▶ pagada ◀────────────────┘
%%
%% Una venta pagada nunca regresa a otro estado: su cancelacion es un movimiento
%% nuevo del libro (p59_inventario:reembolsar/4), no un cambio de esta venta.
%%
%% El estado completo se guarda en DETS en cada transicion, y antes de hablar con
%% la terminal se fuerza a disco junto con la referencia del cargo. Si el proceso
%% muere, su supervisor (transient) lo reinicia y init/1 lo reconstruye desde
%% disco; si murio en medio del cobro pasa a pendiente_de_revision, porque no
%% sabemos si el banco cobro.

-export([start_link/1, nueva/1, leer/1, agregar/4, retirar/2, pagar/3, revisar/1,
         cancelar/2, estados/0, finales/0]).
-export([callback_mode/0, init/1, handle_event/4]).

-define(FINALES, [pagada, cancelada]).

estados() -> [abierta, procesando_pago, pendiente_de_revision, pagada, cancelada].
finales() -> ?FINALES.

start_link(Id) ->
    gen_statem:start_link({global, {?MODULE, Id}}, ?MODULE, Id, []).

%%% --------------------------------------------------------------------- API

-spec nueva(map()) -> map().
nueva(#{id := Id, caja := Caja, cajero := Cajero, turno := Turno} = Datos) ->
    #{id => Id, caja => Caja, cajero => Cajero, turno => Turno,
      creada_en => erlang:system_time(millisecond),
      estado => abierta,
      partidas => [],
      totales => p59_importes:totales([]),
      cobro => null,
      operacion_creacion => maps:get(operacion_id, Datos, null),
      operacion_pago => null,
      intento => 0,
      referencia_terminal => null,
      autorizacion => null,
      folio => null,
      ultimo_error => null,
      arranques => 0,
      historial => [hito(abierta, <<"Venta iniciada"/utf8>>)]}.

leer(Id) ->
    case p59_almacen:leer(ventas, Id) of
        {ok, V} -> {ok, V};
        no_existe -> {error, venta_no_encontrada}
    end.

agregar(Id, ProductoId, Cantidad, DescuentoPct) ->
    llamar(Id, {agregar, ProductoId, Cantidad, DescuentoPct}).

retirar(Id, ProductoId) ->
    llamar(Id, {retirar, ProductoId}).

%% Pagos: [#{metodo := efectivo_mxn | efectivo_usd | tarjeta, monto := centavos}].
%% OperacionId identifica el intento de cobro del cliente: repetirlo devuelve el
%% mismo resultado y nunca cobra ni confirma dos veces.
pagar(Id, Pagos, OperacionId) ->
    llamar(Id, {pagar, Pagos, OperacionId}).

revisar(Id) ->
    llamar(Id, revisar).

cancelar(Id, Motivo) ->
    llamar(Id, {cancelar, Motivo}).

llamar(Id, Msg) ->
    case leer(Id) of
        {error, _} = Error ->
            Error;
        {ok, #{estado := E} = V} ->
            case lists:member(E, ?FINALES) of
                true -> finalizada(Msg, V);
                false -> llamar_proceso(Id, Msg, 1)
            end
    end.

llamar_proceso(Id, Msg, Intentos) ->
    case proceso(Id) of
        {ok, Pid} when is_pid(Pid) ->
            try
                gen_statem:call(Pid, Msg, timeout(Msg))
            catch
                exit:{timeout, _} ->
                    {error, tiempo_agotado};
                exit:{_, {gen_statem, call, _}} when Intentos > 0 ->
                    %% El proceso termino (p. ej. otra solicitud la pago primero) o
                    %% se esta reiniciando: se vuelve a decidir con lo que hay en disco.
                    reintentar(Id, Msg, Intentos - 1)
            end;
        {ok, finalizada} ->
            reintentar(Id, Msg, 0);
        {error, _} ->
            {error, venta_no_disponible}
    end.

%% Si el proceso no esta vivo (p. ej. tras un reinicio de la sucursal) se
%% reconstruye desde disco antes de atender la solicitud.
proceso(Id) ->
    case global:whereis_name({?MODULE, Id}) of
        undefined -> p59_ventas_sup:reanudar(Id);
        Pid -> {ok, Pid}
    end.

reintentar(Id, Msg, Intentos) ->
    {ok, #{estado := E} = V} = leer(Id),
    case lists:member(E, ?FINALES) of
        true -> finalizada(Msg, V);
        false when Intentos > 0 -> llamar_proceso(Id, Msg, Intentos);
        false -> {error, venta_no_disponible}
    end.

%% Respuestas para ventas que ya terminaron (su proceso ya no existe).
finalizada({pagar, _, Op}, #{estado := pagada, operacion_pago := Op} = V) when Op =/= null ->
    p59_metricas:incrementar(reintentos_idempotentes),
    {ok, V};
finalizada({pagar, _, _}, #{estado := pagada}) ->
    {error, venta_ya_pagada};
finalizada({cancelar, _}, #{estado := cancelada} = V) ->
    {ok, V};
finalizada({cancelar, _}, #{estado := pagada}) ->
    {error, venta_pagada_usar_cancelacion_de_ticket};
finalizada(revisar, V) ->
    {ok, V};
finalizada(_, #{estado := E}) ->
    {error, {venta_finalizada, E}}.

timeout({pagar, _, _}) -> 3 * p59_config:obtener(terminal_timeout_ms) + 5000;
timeout(_) -> 2 * p59_config:obtener(terminal_timeout_ms) + 5000.

%%% --------------------------------------------------------------- callbacks

callback_mode() ->
    handle_event_function.

init(Id) ->
    case leer(Id) of
        {ok, #{estado := E}} when E =:= pagada; E =:= cancelada ->
            ignore;
        {ok, V0} ->
            V = V0#{arranques => maps:get(arranques, V0, 0) + 1},
            recuperada(V),
            reconstruir(V);
        {error, Razon} ->
            {stop, Razon}
    end.

%% Si murio en procesando_pago no sabemos si el banco cobro: o el libro ya la
%% tiene (se confirmo justo antes de morir) o queda en revision.
reconstruir(#{id := Id, estado := procesando_pago} = V) ->
    case consultar_libro(Id) of
        {ok, Mov} ->
            guardar(pagada(V, Mov)),
            ignore;
        _ ->
            V1 = a_revision(V, <<"Proceso interrumpido durante el cobro"/utf8>>),
            {ok, pendiente_de_revision, V1}
    end;
reconstruir(#{estado := E} = V) ->
    guardar(V),
    {ok, E, V}.

handle_event({call, From}, Msg, Estado, V) ->
    {Siguiente, V1, Respuesta} = evento(Msg, Estado, V),
    case lists:member(Siguiente, ?FINALES) of
        true -> {stop_and_reply, normal, [{reply, From, Respuesta}], V1};
        false -> {next_state, Siguiente, V1, [{reply, From, Respuesta}]}
    end;
handle_event(info, _Msg, _Estado, _V) ->
    keep_state_and_data.

%%% ----------------------------------------------------------------- eventos

evento({agregar, ProductoId, Cantidad, Desc}, abierta, V)
  when is_integer(Cantidad), Cantidad > 0, Cantidad =< 999,
       is_integer(Desc), Desc >= 0, Desc =< 100 ->
    #{partidas := Partidas} = V,
    Previa = lists:sum([Q || #{producto_id := P, cantidad := Q} <- Partidas, P =:= ProductoId]),
    case p59_inventario:partida(ProductoId, Previa + Cantidad, Desc) of
        {ok, Partida} ->
            V1 = recalcular(V, reemplazar(ProductoId, Partida, Partidas)),
            {abierta, V1, {ok, V1}};
        Error ->
            {abierta, V, Error}
    end;
evento({agregar, _, _, _}, abierta, V) ->
    {abierta, V, {error, partida_invalida}};
evento({retirar, ProductoId}, abierta, #{partidas := Partidas} = V) ->
    case [P || #{producto_id := P} <- Partidas, P =:= ProductoId] of
        [] -> {abierta, V, {error, partida_no_encontrada}};
        _ ->
            V1 = recalcular(V, [P || #{producto_id := Id} = P <- Partidas, Id =/= ProductoId]),
            {abierta, V1, {ok, V1}}
    end;
evento({pagar, Pagos, Op}, abierta, V) ->
    cobrar(Pagos, Op, V);
evento({pagar, Pagos, Op}, pendiente_de_revision, V) ->
    %% Reintento de cobro: primero se averigua que paso con el intento anterior,
    %% para no cobrar dos veces al cliente.
    case revision(V) of
        {abierta, V1, _} -> cobrar(Pagos, Op, V1);
        Resultado -> Resultado
    end;
evento(revisar, pendiente_de_revision, V) ->
    revision(V);
evento(revisar, Estado, V) ->
    {Estado, V, {ok, V}};
evento({cancelar, Motivo}, abierta, V) ->
    V1 = cancelada(V, Motivo),
    {cancelada, V1, {ok, V1}};
evento({cancelar, Motivo}, pendiente_de_revision, V) ->
    case revision(V) of
        {abierta, V1, _} ->
            V2 = cancelada(V1, Motivo),
            {cancelada, V2, {ok, V2}};
        {pagada, V1, _} ->
            {pagada, V1, {error, venta_pagada_usar_cancelacion_de_ticket}};
        {Estado, V1, _} ->
            {Estado, V1, {error, terminal_sin_respuesta}}
    end;
evento(_Msg, Estado, V) ->
    {Estado, V, {error, {transicion_invalida, Estado}}}.

%%% ------------------------------------------------------------------- cobro

cobrar(_Pagos, _Op, #{partidas := []} = V) ->
    {abierta, V, {error, venta_vacia}};
cobrar(Pagos, Op, #{id := Id, totales := #{total := Total}, intento := Intento0} = V0) ->
    %% Politica: el tipo de cambio se captura al iniciar el cobro y queda
    %% registrado en la venta y en el ticket.
    Tc = try maps:get(valor, p59_tipo_cambio:actual()) catch exit:_ -> null end,
    case p59_importes:aplicar_pagos(Total, Pagos, Tc) of
        {error, Razon} ->
            {abierta, V0, {error, Razon}};
        {ok, Cobro} ->
            Intento = Intento0 + 1,
            Ref = case monto_tarjeta(Cobro) of
                      0 -> null;
                      _ -> <<Id/binary, "-", (integer_to_binary(Intento))/binary>>
                  end,
            V1 = transicion(V0#{cobro => Cobro, operacion_pago => Op, intento => Intento,
                                referencia_terminal => Ref, autorizacion => null,
                                ultimo_error => null},
                            procesando_pago, <<"Cobro iniciado"/utf8>>),
            ok = guardar_sync(V1),
            case con_inventario(fun() -> p59_inventario:reservar(Id, lineas(V1)) end) of
                ok -> cargar_tarjeta(V1);
                {error, Razon} -> {abierta, volver_abierta(V1, Razon), {error, Razon}}
            end
    end.

cargar_tarjeta(#{referencia_terminal := null} = V) ->
    confirmar(V);
cargar_tarjeta(#{referencia_terminal := Ref, cobro := Cobro} = V) ->
    case p59_terminal_bancaria:cobrar(Ref, monto_tarjeta(Cobro)) of
        {ok, Aut} ->
            confirmar(V#{autorizacion => Aut});
        {error, sin_respuesta} ->
            p59_metricas:incrementar(errores_pago),
            V1 = a_revision(V, <<"Terminal sin respuesta: no se sabe si se cobró"/utf8>>),
            {pendiente_de_revision, V1, {pendiente, V1}};
        {error, Razon} ->
            p59_metricas:incrementar(errores_pago),
            {abierta, volver_abierta(V, Razon), {error, Razon}}
    end.

confirmar(#{id := Id} = V) ->
    case con_inventario(fun() -> p59_inventario:confirmar(V) end) of
        {ok, Mov} ->
            V1 = pagada(V, Mov),
            ok = guardar(V1),
            p59_impresora:imprimir(maps:get(folio, Mov)),
            {pagada, V1, {ok, V1}};
        {error, inventario_no_disponible} ->
            V1 = a_revision(V, <<"Confirmación interrumpida"/utf8>>),
            {pendiente_de_revision, V1, {pendiente, V1}};
        {error, Razon} ->
            %% El libro rechazo la venta (turno cerrado, sin existencia): si ya se
            %% cobro con tarjeta, se revierte el cargo antes de reabrir la venta.
            revertir_cargo(V),
            logger:info("p59_venta ~ts: confirmacion rechazada ~p", [Id, Razon]),
            {abierta, volver_abierta(V, Razon), {error, Razon}}
    end.

revision(#{id := Id, referencia_terminal := Ref} = V) ->
    case consultar_libro(Id) of
        {ok, Mov} ->
            V1 = pagada(V, Mov),
            ok = guardar(V1),
            {pagada, V1, {ok, V1}};
        _ when Ref =:= null ->
            confirmar(V);
        _ ->
            case p59_terminal_bancaria:consultar(Ref) of
                {aprobado, Aut} ->
                    confirmar(V#{autorizacion => Aut});
                no_encontrado ->
                    V1 = volver_abierta(V, cargo_no_realizado),
                    {abierta, V1, {ok, V1}};
                {error, _} ->
                    {pendiente_de_revision, V, {pendiente, V}}
            end
    end.

revertir_cargo(#{autorizacion := null}) -> ok;
revertir_cargo(#{referencia_terminal := Ref}) -> p59_terminal_bancaria:revertir(Ref).

%%% -------------------------------------------------------------- transiciones

transicion(V, Estado, Detalle) ->
    V#{estado => Estado, historial => maps:get(historial, V) ++ [hito(Estado, Detalle)]}.

volver_abierta(#{id := Id} = V, Razon) ->
    _ = con_inventario(fun() -> p59_inventario:liberar(Id) end),
    V1 = transicion(V#{cobro => null, referencia_terminal => null, autorizacion => null,
                       ultimo_error => razon_texto(Razon)},
                    abierta, [<<"Cobro no completado: "/utf8>>, razon_texto(Razon)]),
    ok = guardar(V1),
    V1.

a_revision(#{id := Id, caja := Caja} = V, Detalle) ->
    p59_metricas:incrementar(ventas_en_revision),
    p59_eventos:publicar(venta, falla, [<<"Venta "/utf8>>, Id, <<" en revisión: "/utf8>>, Detalle],
                         #{venta => Id, caja => Caja}),
    V1 = transicion(V, pendiente_de_revision, Detalle),
    ok = guardar_sync(V1),
    V1.

pagada(V, #{folio := Folio, cajero := Cajero, turno := Turno}) ->
    transicion(V#{folio => Folio, turno_contable => Turno, cajero_contable => Cajero},
               pagada, [<<"Confirmada con ticket "/utf8>>, Folio]).

cancelada(#{id := Id, caja := Caja} = V, Motivo) ->
    _ = con_inventario(fun() -> p59_inventario:liberar(Id) end),
    V1 = transicion(V#{motivo_cancelacion => Motivo}, cancelada,
                    [<<"Cancelada: "/utf8>>, Motivo]),
    ok = guardar(V1),
    p59_eventos:publicar(venta, alerta, [<<"Venta "/utf8>>, Id, <<" cancelada antes de pagar"/utf8>>],
                         #{venta => Id, caja => Caja}),
    V1.

recuperada(#{arranques := 1}) ->
    ok;
recuperada(#{id := Id, caja := Caja, estado := Estado}) ->
    p59_metricas:incrementar(ventas_recuperadas),
    p59_eventos:publicar(venta, alerta,
                         [<<"Venta "/utf8>>, Id, <<" reconstruida desde disco ("/utf8>>,
                          atom_to_binary(Estado), <<")"/utf8>>],
                         #{venta => Id, caja => Caja}).

%%% --------------------------------------------------------------- auxiliares

recalcular(V, Partidas) ->
    V1 = V#{partidas => Partidas, totales => p59_importes:totales(Partidas)},
    ok = guardar(V1),
    V1.

reemplazar(ProductoId, Partida, Partidas) ->
    case lists:any(fun(#{producto_id := P}) -> P =:= ProductoId end, Partidas) of
        true -> [case P of #{producto_id := ProductoId} -> Partida; _ -> P end || P <- Partidas];
        false -> Partidas ++ [Partida]
    end.

lineas(#{partidas := Partidas}) ->
    [{Id, Q} || #{producto_id := Id, cantidad := Q} <- Partidas].

monto_tarjeta(#{pagos := Pagos}) ->
    lists:sum([M || #{metodo := tarjeta, monto_mxn := M} <- Pagos]).

consultar_libro(Id) ->
    try p59_inventario:venta_confirmada(Id)
    catch error:badarg -> {error, inventario_no_disponible}
    end.

%% El inventario puede estar reiniciandose (prueba de caos): la venta no debe
%% morir por eso, sino quedar en un estado coherente.
con_inventario(Fun) ->
    try Fun()
    catch exit:_ -> {error, inventario_no_disponible}
    end.

guardar(#{id := Id} = V) ->
    p59_almacen:escribir(ventas, {Id, V}).

guardar_sync(#{id := Id} = V) ->
    p59_almacen:escribir_sync(ventas, {Id, V}).

hito(Estado, Detalle) ->
    #{estado => Estado, en => erlang:system_time(millisecond),
      detalle => unicode:characters_to_binary(Detalle)}.

razon_texto(R) when is_atom(R) -> atom_to_binary(R);
razon_texto({R, _}) when is_atom(R) -> atom_to_binary(R);
razon_texto(_) -> <<"error">>.
