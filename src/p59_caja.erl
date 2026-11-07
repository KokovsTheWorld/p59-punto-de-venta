-module(p59_caja).
-behaviour(gen_server).

%% Una caja registradora = un gen_server registrado como p59_caja_N.
%%
%% Serializa lo que ocurre en esa caja (una venta en curso a la vez, claves de
%% idempotencia para crear ventas) y vigila su venta en curso con un monitor,
%% NO con un enlace: si la caja muere, la venta sigue viva bajo p59_ventas_sup;
%% si la venta muere, la caja no cae con ella. Al reiniciarse, la caja lee de
%% disco cual era su venta en curso y vuelve a vigilarla.

-export([start_link/1, nombre/1, iniciar_venta/2, venta_actual/1, info/1, todas/0,
         activas/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(N) ->
    gen_server:start_link({local, nombre(N)}, ?MODULE, N, []).

nombre(N) ->
    list_to_atom("p59_caja_" ++ integer_to_list(N)).

iniciar_venta(N, OperacionId) ->
    llamar(N, {iniciar_venta, OperacionId}).

venta_actual(N) ->
    llamar(N, venta_actual).

activas() ->
    length([N || N <- p59_config:cajas(), whereis(nombre(N)) =/= undefined]).

todas() ->
    [info(N) || N <- p59_config:cajas()].

info(N) ->
    case lists:member(N, p59_config:cajas()) of
        false ->
            {error, caja_no_encontrada};
        true ->
            Pid = whereis(nombre(N)),
            Venta = case catch venta_actual(N) of
                        {ok, Id} when is_binary(Id) ->
                            {ok, V} = p59_venta:leer(Id),
                            maps:with([id, estado, totales, partidas, cobro, ultimo_error], V);
                        _ -> null
                    end,
            Turno = case p59_inventario:turno(N) of {ok, T} -> T; _ -> null end,
            {ok, #{id => N,
                   proceso => (proceso_info(Pid))#{vivo => is_pid(Pid), pid => pid_texto(Pid),
                                reinicios => maps:get(nombre(N), p59_metricas:reinicios(), 0)},
                   turno => Turno,
                   venta_actual => Venta,
                   recientes => lists:sublist(p59_inventario:tickets(#{caja => N}), 10)}}
    end.

llamar(N, Msg) ->
    try gen_server:call(nombre(N), Msg, 10000)
    catch exit:{timeout, _} -> {error, tiempo_agotado};
          exit:_ -> {error, caja_no_disponible}
    end.

%%% ---------------------------------------------------------------- callbacks

init(N) ->
    p59_metricas:inicio(nombre(N)),
    S0 = #{caja => N, venta => null, monitor => null},
    S = case p59_almacen:leer(cajas, N) of
            {ok, #{venta_actual := Id}} when is_binary(Id) -> vigilar(Id, S0);
            _ -> S0
        end,
    case maps:get(nombre(N), p59_metricas:reinicios(), 0) of
        0 -> ok;
        R -> p59_eventos:publicar(caja, alerta,
                                  [<<"Caja "/utf8>>, integer_to_binary(N),
                                   <<" reiniciada por su supervisor (reinicio #"/utf8>>,
                                   integer_to_binary(R), <<"); venta en curso: "/utf8>>,
                                   texto(maps:get(venta, S))],
                                  #{caja => N, venta => maps:get(venta, S)})
    end,
    {ok, S}.

handle_call({iniciar_venta, Op}, _From, S) ->
    {Respuesta, S1} = nueva_venta(Op, S),
    {reply, Respuesta, S1};
handle_call(venta_actual, _From, #{venta := Id} = S) ->
    {reply, {ok, Id}, S}.

handle_cast(_Msg, S) ->
    {noreply, S}.

handle_info({'DOWN', Ref, process, _Pid, normal}, #{monitor := Ref, venta := Id} = S) ->
    {noreply, liberar_si_final(Id, S#{monitor := null})};
handle_info({'DOWN', Ref, process, _Pid, _Razon}, #{monitor := Ref, venta := Id} = S) ->
    %% La venta cayo: su supervisor la reinicia. Volvemos a buscarla en un momento.
    erlang:send_after(50, self(), {recuperar, Id}),
    {noreply, S#{monitor := null}};
handle_info({recuperar, Id}, #{venta := Id, monitor := null} = S) ->
    {noreply, vigilar(Id, S)};
handle_info(_Msg, S) ->
    {noreply, S}.

%%% --------------------------------------------------------------- auxiliares

nueva_venta(Op, #{caja := N} = S0) ->
    S = case S0 of
            #{venta := Previa} when is_binary(Previa) -> liberar_si_final(Previa, S0);
            _ -> S0
        end,
    case {repetida(Op), S, p59_inventario:turno(N)} of
        {{ok, Id}, _, _} ->
            %% Reintento de red de la misma solicitud: misma venta, nada nuevo.
            p59_metricas:incrementar(reintentos_idempotentes),
            {p59_venta:leer(Id), S};
        {_, #{venta := Actual}, _} when is_binary(Actual) ->
            {{error, {venta_en_curso, Actual}}, S};
        {_, _, {ok, #{estado := abierto, turno := Turno, cajero := Cajero}}} ->
            Id = iolist_to_binary(io_lib:format("V-~6..0b", [p59_almacen:siguiente(venta)])),
            Venta = p59_venta:nueva(#{id => Id, caja => N, cajero => Cajero, turno => Turno,
                                      operacion_id => Op}),
            %% Primero todo a disco (venta, clave de idempotencia y venta en curso
            %% de la caja) y despues el proceso: si la caja muere en medio, al
            %% reiniciarse encuentra la venta y la reanuda.
            ok = p59_almacen:escribir_sync(ventas, {Id, Venta}),
            case Op of
                null -> ok;
                _ -> ok = p59_almacen:escribir_sync(idempotencia, {{crear_venta, Op}, Id})
            end,
            _ = persistir(S#{venta := Id}),
            {{ok, Venta}, vigilar(Id, S)};
        {_, _, {ok, _}} ->
            {{error, turno_cerrado}, S};
        {_, _, no_existe} ->
            {{error, caja_no_encontrada}, S}
    end.

repetida(null) -> no;
repetida(Op) -> p59_almacen:leer(idempotencia, {crear_venta, Op}).

vigilar(Id, #{caja := N} = S) ->
    case p59_venta:leer(Id) of
        {ok, #{estado := E}} when E =:= pagada; E =:= cancelada ->
            persistir(S#{venta := null, monitor := null});
        {ok, _} ->
            case p59_ventas_sup:reanudar(Id) of
                {ok, Pid} when is_pid(Pid) ->
                    persistir(S#{venta := Id, monitor := erlang:monitor(process, Pid)});
                _ ->
                    persistir(S#{venta := null, monitor := null})
            end;
        {error, _} ->
            logger:warning("p59_caja ~b: venta ~ts no encontrada", [N, Id]),
            persistir(S#{venta := null, monitor := null})
    end.

liberar_si_final(Id, S) ->
    case p59_venta:leer(Id) of
        {ok, #{estado := E}} when E =:= pagada; E =:= cancelada ->
            case S of
                #{monitor := Ref} when is_reference(Ref) -> erlang:demonitor(Ref, [flush]);
                _ -> ok
            end,
            persistir(S#{venta := null, monitor := null});
        _ ->
            S
    end.

persistir(#{caja := N, venta := Id} = S) ->
    ok = p59_almacen:escribir(cajas, {N, #{venta_actual => Id}}),
    S.

%% Datos reales del proceso para la ficha tecnica de la interfaz.
proceso_info(Pid) when is_pid(Pid) ->
    case erlang:process_info(Pid, [message_queue_len, memory, reductions]) of
        [{_, Buzon}, {_, Memoria}, {_, Reducciones}] ->
            #{buzon => Buzon, memoria => Memoria, reducciones => Reducciones};
        undefined ->
            #{}
    end;
proceso_info(_) ->
    #{}.

pid_texto(undefined) -> null;
pid_texto(Pid) -> list_to_binary(pid_to_list(Pid)).

texto(null) -> <<"ninguna"/utf8>>;
texto(B) -> B.
