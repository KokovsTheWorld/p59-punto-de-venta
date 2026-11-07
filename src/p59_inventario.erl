-module(p59_inventario).
-behaviour(gen_server).

%% Catalogo, existencias y libro de movimientos de la sucursal.
%%
%% Es el UNICO proceso que modifica existencias y el libro; todas las cajas le
%% piden reservar y confirmar, y el buzon del proceso serializa esas peticiones.
%% Eso garantiza que dos cajas no consuman la misma unidad sin usar candados.
%%
%% Punto de no retorno de una venta: la escritura de {{venta, Id}, Movimiento}
%% en la tabla DETS `movimientos` seguida de dets:sync/1. Antes de eso la venta
%% no existe para el libro; despues, ya no se puede perder. Las existencias NO se
%% guardan aparte: se recalculan al arrancar como
%%     existencia = inicial - vendidas + devueltas
%% a partir del libro, asi no hay dos fuentes de verdad que puedan divergir.
%%
%% Lecturas (catalogo, tickets, movimientos) van directo a ETS desde el proceso
%% que pregunta, sin pasar por el buzon.

-export([start_link/0,
         productos/0, producto/1, partida/3,
         reservar/2, liberar/1, confirmar/1, venta_confirmada/1,
         ticket/1, tickets/1, reembolsar/4,
         turno/1, turnos/0, abrir_turno/3, cerrar_turno/2,
         corte/1, resumen/0, verificar_existencias/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(PRODUCTOS, p59_productos).
-define(LIBRO, p59_libro).
-define(FOLIOS, p59_folios).
-define(FINALES, [pagada, cancelada]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%% ---------------------------------------------------------------- lecturas

productos() ->
    [P || {_, P} <- ets:tab2list(?PRODUCTOS)].

producto(Id) ->
    case ets:lookup(?PRODUCTOS, Id) of
        [{_, P}] -> {ok, P};
        [] -> {error, producto_no_encontrado}
    end.

%% Construye una partida con el precio y la tasa vigentes al agregarla. Valida
%% contra lo disponible en ese momento (aviso temprano); la garantia real se
%% obtiene al reservar durante el cobro.
partida(ProductoId, Cantidad, DescuentoPct) ->
    case producto(ProductoId) of
        {ok, #{activo := false}} ->
            {error, producto_inactivo};
        {ok, #{existencia := E, reservado := R} = P} when E - R >= Cantidad ->
            {ok, #{producto_id => ProductoId,
                   nombre => maps:get(nombre, P),
                   cantidad => Cantidad,
                   precio_unitario => maps:get(precio, P),
                   descuento_pct => DescuentoPct,
                   tasa_iva => tasa(maps:get(tipo_iva, P))}};
        {ok, _} ->
            {error, {sin_existencia, [ProductoId]}};
        Error ->
            Error
    end.

venta_confirmada(VentaId) ->
    case ets:lookup(?LIBRO, {venta, VentaId}) of
        [{_, Mov}] -> {ok, Mov};
        [] -> no
    end.

ticket(Folio) ->
    case ets:lookup(?FOLIOS, Folio) of
        [{_, VentaId}] ->
            {ok, Venta} = venta_confirmada(VentaId),
            {ok, #{venta => Venta, reembolsos => reembolsos_de(Folio)}};
        [] ->
            {error, ticket_no_encontrado}
    end.

%% Movimientos filtrados, del mas reciente al mas antiguo.
tickets(Filtro) ->
    Movs = [M || {_, M} <- ets:tab2list(?LIBRO), coincide(M, Filtro)],
    lists:reverse(lists:sort(fun(A, B) -> maps:get(fecha, A) =< maps:get(fecha, B) end, Movs)).

turno(Caja) ->
    p59_almacen:leer(turnos, Caja).

turnos() ->
    lists:sort([T || {_, T} <- p59_almacen:todos(turnos)]).

%%% --------------------------------------------------------- operaciones

reservar(VentaId, Lineas) ->
    gen_server:call(?MODULE, {reservar, VentaId, agrupar(Lineas)}).

liberar(VentaId) ->
    gen_server:call(?MODULE, {liberar, VentaId}).

confirmar(Venta) ->
    gen_server:call(?MODULE, {confirmar, Venta}).

%% Tipo: cancelacion (todo lo pendiente) | devolucion (Unidades = [{Id, Q}]).
reembolsar(Tipo, Folio, Unidades, Ctx) ->
    gen_server:call(?MODULE, {reembolsar, Tipo, Folio, Unidades, Ctx}).

abrir_turno(Caja, Cajero, Fondo) ->
    gen_server:call(?MODULE, {abrir_turno, Caja, Cajero, Fondo}).

cerrar_turno(Caja, Contado) ->
    gen_server:call(?MODULE, {cerrar_turno, Caja, Contado}).

%% Filtro: #{} | #{caja} | #{caja, turno} | #{cajero}. Se calcula dentro del
%% proceso para que ninguna confirmacion se intercale: es una vista consistente.
corte(Filtro) ->
    gen_server:call(?MODULE, {corte, Filtro}).

resumen() ->
    Movs = [M || {_, M} <- ets:tab2list(?LIBRO)],
    Cuenta = fun(T) -> length([x || #{tipo := Tp} <- Movs, Tp =:= T]) end,
    Productos = productos(),
    #{ventas => Cuenta(venta),
      cancelaciones => Cuenta(cancelacion),
      devoluciones => Cuenta(devolucion),
      importe_vendido => lists:sum([T || #{tipo := venta, total := T} <- Movs]),
      productos => length(Productos),
      agotados => length([x || #{activo := true, existencia := E, reservado := R} <- Productos,
                               E - R =< 0]),
      descuadres => length([x || {_, #{descuadre := true}} <- p59_almacen:todos(cortes)])}.

%% Invariante de inventario: para cada producto,
%%   existencia = inicial - vendidas + devueltas,  existencia >= reservado >= 0.
verificar_existencias() ->
    gen_server:call(?MODULE, verificar_existencias).

%%% ------------------------------------------------------------ callbacks

init([]) ->
    p59_metricas:inicio(?MODULE),
    ets:new(?PRODUCTOS, [ordered_set, protected, named_table, {read_concurrency, true}]),
    ets:new(?LIBRO, [set, protected, named_table, {read_concurrency, true}]),
    ets:new(?FOLIOS, [set, protected, named_table, {read_concurrency, true}]),
    Catalogo = p59_catalogo:generar(p59_config:obtener(num_productos),
                                    p59_config:obtener(semilla_catalogo)),
    [ets:insert(?PRODUCTOS, {Id, P#{existencia => Inicial, reservado => 0}})
     || #{id := Id, existencia_inicial := Inicial} = P <- Catalogo],
    %% Reconstruir existencias reproduciendo el libro.
    Movs = p59_almacen:todos(movimientos),
    [registrar(Clave, Mov) || {Clave, Mov} <- Movs],
    %% Recuperar reservas de cobros en curso; las de ventas ya confirmadas sobran.
    Reservas = lists:foldl(fun recuperar_reserva/2, #{}, p59_almacen:todos(reservas)),
    asegurar_turnos(),
    logger:info("p59_inventario: ~b productos, ~b movimientos, ~b reservas recuperadas",
                [length(Catalogo), length(Movs), map_size(Reservas)]),
    {ok, #{reservas => Reservas}}.

handle_call({reservar, VentaId, Lineas}, _From, S) ->
    {Respuesta, S1} = hacer_reserva(VentaId, Lineas, S),
    {reply, Respuesta, S1};
handle_call({liberar, VentaId}, _From, S) ->
    {reply, ok, quitar_reserva(VentaId, S)};
handle_call({confirmar, Venta}, _From, S) ->
    {Respuesta, S1} = hacer_confirmacion(Venta, S),
    {reply, Respuesta, S1};
handle_call({reembolsar, Tipo, Folio, Unidades, Ctx}, _From, S) ->
    {reply, hacer_reembolso(Tipo, Folio, Unidades, Ctx), S};
handle_call({abrir_turno, Caja, Cajero, Fondo}, _From, S) ->
    {reply, hacer_apertura(Caja, Cajero, Fondo), S};
handle_call({cerrar_turno, Caja, Contado}, _From, S) ->
    {reply, hacer_cierre(Caja, Contado), S};
handle_call({corte, Filtro}, _From, S) ->
    {reply, hacer_corte(Filtro), S};
handle_call(verificar_existencias, _From, S) ->
    {reply, hacer_verificacion(S), S}.

handle_cast(_Msg, S) ->
    {noreply, S}.

%%% ------------------------------------------------------------ reservas

hacer_reserva(VentaId, Lineas, #{reservas := Rs} = S) ->
    case maps:find(VentaId, Rs) of
        {ok, Lineas} ->
            {ok, S};
        _ ->
            S1 = quitar_reserva(VentaId, S),
            case faltantes(Lineas) of
                [] ->
                    ok = p59_almacen:escribir_sync(reservas, {VentaId, Lineas}),
                    [ajustar(Id, 0, Q) || {Id, Q} <- Lineas],
                    {ok, S1#{reservas := (maps:get(reservas, S1))#{VentaId => Lineas}}};
                Ids ->
                    p59_metricas:incrementar(sin_existencia),
                    p59_eventos:publicar(inventario, alerta,
                                         [<<"Sin existencia suficiente para "/utf8>>, VentaId],
                                         #{venta => VentaId, productos => Ids}),
                    {{error, {sin_existencia, Ids}}, S1}
            end
    end.

quitar_reserva(VentaId, #{reservas := Rs} = S) ->
    case maps:take(VentaId, Rs) of
        {Lineas, Rs1} ->
            [ajustar(Id, 0, -Q) || {Id, Q} <- Lineas],
            ok = p59_almacen:borrar(reservas, VentaId),
            S#{reservas := Rs1};
        error ->
            S
    end.

faltantes(Lineas) ->
    [Id || {Id, Q} <- Lineas,
           case producto(Id) of
               {ok, #{activo := true, existencia := E, reservado := R}} -> E - R < Q;
               _ -> true
           end].

recuperar_reserva({VentaId, Lineas}, Acc) ->
    case venta_confirmada(VentaId) of
        {ok, _} ->
            ok = p59_almacen:borrar(reservas, VentaId),
            Acc;
        no ->
            [ajustar(Id, 0, Q) || {Id, Q} <- Lineas],
            Acc#{VentaId => Lineas}
    end.

%%% -------------------------------------------------------- confirmacion

hacer_confirmacion(#{id := VentaId, caja := Caja, partidas := Partidas} = Venta, S) ->
    case venta_confirmada(VentaId) of
        {ok, Mov} ->
            %% Reintento: la venta ya ocurrio, se devuelve el mismo ticket.
            p59_metricas:incrementar(reintentos_idempotentes),
            {{ok, Mov}, S};
        no ->
            Lineas = agrupar([{Id, Q} || #{producto_id := Id, cantidad := Q} <- Partidas]),
            Paso = case turno_abierto(Caja) of
                       {ok, T} -> {T, hacer_reserva(VentaId, Lineas, S)};
                       Error0 -> {Error0, {Error0, S}}
                   end,
            case Paso of
                {_, {{error, _} = Error, S1}} ->
                    {Error, S1};
                {Turno, {ok, S1}} ->
                    Folio = folio(ticket, "T"),
                    Mov = p59_movimientos:venta(Venta, Folio, Turno,
                                                erlang:system_time(millisecond)),
                    Clave = {venta, VentaId},
                    true = p59_almacen:insertar_nuevo(movimientos, {Clave, Mov}),
                    ok = dets:sync(p59_almacen:tabla(movimientos)),
                    %% --- a partir de aqui la venta esta confirmada ---
                    #{reservas := Rs} = S1,
                    ok = p59_almacen:borrar(reservas, VentaId),
                    [ajustar(Id, 0, -Q) || {Id, Q} <- Lineas],
                    registrar(Clave, Mov),
                    p59_eventos:publicar(venta, ok,
                                         [<<"Ticket "/utf8>>, Folio, <<" confirmado en caja "/utf8>>,
                                          integer_to_binary(Caja), <<" por "/utf8>>,
                                          p59_dinero:formatear(maps:get(total, Mov))],
                                         #{folio => Folio, venta => VentaId, caja => Caja,
                                           total => maps:get(total, Mov),
                                           modalidad => maps:get(modalidad, Mov)}),
                    {{ok, Mov}, S1#{reservas := maps:remove(VentaId, Rs)}}
            end
    end.

%%% ---------------------------------------------- cancelacion/devolucion

hacer_reembolso(Tipo, Folio, Unidades, Ctx) ->
    Caja = maps:get(caja, Ctx),
    OperacionId = maps:get(operacion_id, Ctx, null),
    Previo = case {Tipo, OperacionId} of
                 {cancelacion, _} -> ets:lookup(?LIBRO, {cancelacion, Folio});
                 {devolucion, null} -> [];
                 {devolucion, Op} -> ets:lookup(?LIBRO, {devolucion, Op})
             end,
    case {Previo, ets:lookup(?FOLIOS, Folio), turno_abierto(Caja)} of
        {[{_, Mov}], _, _} ->
            p59_metricas:incrementar(reintentos_idempotentes),
            {ok, Mov};
        {[], [], _} ->
            {error, ticket_no_encontrado};
        {[], _, {error, _} = Error} ->
            Error;
        {[], [{_, VentaId}], {ok, #{turno := Turno, cajero := Cajero}}} ->
            {ok, Venta} = venta_confirmada(VentaId),
            N = folio(reembolso, case Tipo of cancelacion -> "C"; devolucion -> "D" end),
            Contexto = #{id => N, caja => Caja, cajero => Cajero, turno => Turno,
                         fecha => erlang:system_time(millisecond),
                         motivo => maps:get(motivo, Ctx, <<>>)},
            Pedido = case Tipo of cancelacion -> todo; devolucion -> Unidades end,
            case p59_movimientos:reembolso(Tipo, Venta, reembolsos_de(Folio), Pedido, Contexto) of
                {ok, Mov} ->
                    Clave = case Tipo of
                                cancelacion -> {cancelacion, Folio};
                                devolucion when OperacionId =:= null -> {devolucion, N};
                                devolucion -> {devolucion, OperacionId}
                            end,
                    ok = p59_almacen:escribir_sync(movimientos, {Clave, Mov}),
                    registrar(Clave, Mov),
                    p59_eventos:publicar(Tipo, alerta,
                                         [atom_to_binary(Tipo), <<" "/utf8>>, N,
                                          <<" del ticket "/utf8>>, Folio, <<" (turno "/utf8>>,
                                          integer_to_binary(maps:get(turno_original, Mov)),
                                          <<" → turno "/utf8>>, integer_to_binary(Turno), <<")"/utf8>>],
                                         #{folio => Folio, id => N, monto => maps:get(monto, Mov)}),
                    {ok, Mov};
                Error ->
                    Error
            end
    end.

reembolsos_de(Folio) ->
    lists:sort(fun(A, B) -> maps:get(fecha, A) =< maps:get(fecha, B) end,
               [M || {{T, _}, #{folio := F} = M} <- ets:tab2list(?LIBRO),
                     T =/= venta, F =:= Folio]).

%%% --------------------------------------------------------------- turnos

asegurar_turnos() ->
    Cajeros = p59_config:obtener(cajeros),
    [p59_almacen:insertar_nuevo(turnos, {Caja, nuevo_turno(Caja, 1, cajero(Caja, Cajeros),
                                                         p59_config:obtener(fondo_inicial))})
     || Caja <- p59_config:cajas()].

cajero(Caja, Cajeros) ->
    lists:nth((Caja - 1) rem length(Cajeros) + 1, Cajeros).

nuevo_turno(Caja, N, Cajero, Fondo) ->
    #{caja => Caja, turno => N, cajero => Cajero, fondo_mxn => Fondo,
      abierto_en => erlang:system_time(millisecond), estado => abierto, cerrado_en => null}.

turno_abierto(Caja) ->
    case turno(Caja) of
        {ok, #{estado := abierto} = T} -> {ok, T};
        {ok, _} -> {error, turno_cerrado};
        no_existe -> {error, caja_no_encontrada}
    end.

hacer_apertura(Caja, Cajero, Fondo) ->
    case turno(Caja) of
        no_existe -> {error, caja_no_encontrada};
        {ok, #{estado := abierto}} -> {error, turno_abierto};
        {ok, #{turno := N}} ->
            T = nuevo_turno(Caja, N + 1, Cajero, Fondo),
            ok = p59_almacen:escribir_sync(turnos, {Caja, T}),
            p59_eventos:publicar(turno, ok,
                                 [<<"Caja "/utf8>>, integer_to_binary(Caja), <<": abre turno "/utf8>>,
                                  integer_to_binary(N + 1), <<" ("/utf8>>, Cajero, <<")"/utf8>>],
                                 #{caja => Caja, turno => N + 1}),
            {ok, T}
    end.

hacer_cierre(Caja, Contado) ->
    case turno_abierto(Caja) of
        {error, _} = Error ->
            Error;
        {ok, #{turno := N} = T} ->
            Cerrado = T#{estado => cerrado, cerrado_en => erlang:system_time(millisecond)},
            Corte = corte_turno(Cerrado#{contado => Contado}),
            ok = p59_almacen:escribir_sync(cortes, {{Caja, N}, Corte}),
            ok = p59_almacen:escribir_sync(turnos, {Caja, Cerrado}),
            #{descuadre := Descuadre, diferencia := Dif} = Corte,
            p59_eventos:publicar(corte, case Descuadre of true -> alerta; false -> ok end,
                                 [<<"Corte caja "/utf8>>, integer_to_binary(Caja),
                                  <<" turno "/utf8>>, integer_to_binary(N),
                                  case Descuadre of
                                      true -> [<<": descuadre "/utf8>>,
                                               p59_dinero:formatear(maps:get(mxn, Dif)),
                                               <<" / "/utf8>>,
                                               p59_dinero:formatear_usd(maps:get(usd, Dif))];
                                      false -> <<": cuadra"/utf8>>
                                  end],
                                 #{caja => Caja, turno => N, diferencia => Dif}),
            {ok, Corte}
    end.

%%% ---------------------------------------------------------------- corte

hacer_corte(#{caja := Caja, turno := N}) ->
    case {turno(Caja), p59_almacen:leer(cortes, {Caja, N})} of
        {_, {ok, Cerrado}} -> {ok, Cerrado};
        {{ok, #{turno := N} = T}, _} -> {ok, corte_turno(T)};
        {no_existe, _} -> {error, caja_no_encontrada};
        _ -> {error, turno_no_encontrado}
    end;
hacer_corte(#{caja := Caja}) ->
    case turno(Caja) of
        {ok, T} -> {ok, corte_turno(T)};
        no_existe -> {error, caja_no_encontrada}
    end;
hacer_corte(#{cajero := Cajero}) ->
    Movs = tickets(#{cajero => Cajero}),
    Corte = p59_corte:calcular(Movs, #{en_proceso => en_proceso(#{cajero => Cajero})}),
    {ok, Corte#{alcance => #{cajero => Cajero}, generado_en => ahora()}};
hacer_corte(_Todo) ->
    Cortes = [corte_turno(T) || T <- turnos()],
    {ok, #{cajas => Cortes,
           consolidado => p59_corte:sumar(Cortes),
           en_proceso => en_proceso(#{}),
           generado_en => ahora()}}.

corte_turno(#{caja := Caja, turno := N, cajero := Cajero, fondo_mxn := Fondo} = T) ->
    Movs = tickets(#{caja => Caja, turno => N}),
    Corte = p59_corte:calcular(Movs, #{fondo_mxn => Fondo,
                                       contado => maps:get(contado, T, null),
                                       en_proceso => en_proceso(#{caja => Caja})}),
    Corte#{alcance => #{caja => Caja, turno => N, cajero => Cajero},
           estado_turno => maps:get(estado, T),
           generado_en => ahora()}.

%% Ventas que no se cuentan: siguen abiertas, cobrandose o en revision.
en_proceso(Filtro) ->
    [maps:with([id, caja, cajero, estado, total], V#{total => maps:get(total, maps:get(totales, V))})
     || {_, #{estado := E} = V} <- p59_almacen:todos(ventas),
        not lists:member(E, ?FINALES), coincide(V, Filtro)].

%%% -------------------------------------------------------- verificacion

hacer_verificacion(#{reservas := Rs}) ->
    Movs = [M || {_, M} <- ets:tab2list(?LIBRO)],
    Neto = lists:foldl(
             fun(#{tipo := Tipo, partidas := Ps}, Acc) ->
                     Signo = case Tipo of venta -> -1; _ -> 1 end,
                     lists:foldl(fun(#{producto_id := Id, cantidad := Q}, A) ->
                                         maps:update_with(Id, fun(V) -> V + Signo * Q end,
                                                          Signo * Q, A)
                                 end, Acc, Ps)
             end, #{}, Movs),
    Reservado = lists:foldl(fun({Id, Q}, A) -> maps:update_with(Id, fun(V) -> V + Q end, Q, A) end,
                            #{}, lists:append(maps:values(Rs))),
    Errores = [Id || #{id := Id, existencia_inicial := I, existencia := E, reservado := R}
                         <- productos(),
                     E =/= I + maps:get(Id, Neto, 0)
                         orelse E < 0 orelse R < 0 orelse R > E
                         orelse R =/= maps:get(Id, Reservado, 0)],
    #{ok => Errores =:= [], productos_con_error => Errores,
      productos => ets:info(?PRODUCTOS, size),
      unidades_iniciales => lists:sum([I || #{existencia_inicial := I} <- productos()]),
      unidades_actuales => lists:sum([E || #{existencia := E} <- productos()]),
      unidades_reservadas => lists:sum(maps:values(Reservado)),
      minima_existencia => lists:min([E || #{existencia := E} <- productos()])}.

%%% ------------------------------------------------------------- auxiliares

%% Aplica un movimiento ya persistido a las tablas en memoria.
registrar(Clave, #{tipo := Tipo, partidas := Ps, folio := Folio} = Mov) ->
    ets:insert(?LIBRO, {Clave, Mov}),
    case Tipo of
        venta ->
            ets:insert(?FOLIOS, {Folio, maps:get(venta_id, Mov)}),
            [ajustar(Id, -Q, 0) || #{producto_id := Id, cantidad := Q} <- Ps];
        _ ->
            [ajustar(Id, Q, 0) || #{producto_id := Id, cantidad := Q} <- Ps]
    end,
    ok.

ajustar(Id, DeltaExistencia, DeltaReservado) ->
    [{_, #{existencia := E, reservado := R} = P}] = ets:lookup(?PRODUCTOS, Id),
    ets:insert(?PRODUCTOS, {Id, P#{existencia := E + DeltaExistencia,
                                   reservado := R + DeltaReservado}}).

agrupar(Lineas) ->
    lists:sort(maps:to_list(lists:foldl(fun({Id, Q}, A) ->
                                                maps:update_with(Id, fun(V) -> V + Q end, Q, A)
                                        end, #{}, Lineas))).

coincide(M, Filtro) ->
    maps:fold(fun(K, V, Acc) -> Acc andalso maps:get(K, M, undefined) =:= V end, true, Filtro).

folio(Contador, Prefijo) ->
    N = p59_almacen:siguiente(Contador),
    iolist_to_binary(io_lib:format("~s-~6..0b", [Prefijo, N])).

tasa(tasa_cero) -> 0;
tasa(general) -> p59_config:iva_general_pb().

ahora() ->
    erlang:system_time(millisecond).
