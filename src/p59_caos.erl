-module(p59_caos).

%% Prueba de caos reproducible. Tres experimentos, cada uno con una venta
%% abierta (con partidas) en la caja indicada:
%%   1. matar la CAJA          -> la reinicia p59_cajas_sup (one_for_one)
%%   2. matar el proceso VENTA -> lo reinicia p59_ventas_sup (transient)
%%   3. matar el INVENTARIO    -> p59_punto_de_venta_sup (rest_for_one) reinicia
%%                                inventario y sucursal; todo se reconstruye de DETS
%% En cada uno se registra que se mato, por que, que se esperaba, que ocurrio,
%% que supervisor actuo y si el inventario y el corte siguen consistentes.

-export([ejecutar/0, ejecutar/1, cli/0]).

ejecutar() ->
    ejecutar(2).

ejecutar(Caja) ->
    p59_cliente:asegurar_turno(Caja),
    p59_eventos:publicar(caos, alerta, <<"Inicia prueba de caos"/utf8>>, #{caja => Caja}),
    Experimentos = [matar_caja(Caja), matar_venta(Caja), matar_inventario(Caja)],
    Ok = lists:all(fun(#{ok := B}) -> B end, Experimentos),
    p59_eventos:publicar(caos, case Ok of true -> ok; false -> falla end,
                         [<<"Prueba de caos terminada: "/utf8>>,
                          case Ok of true -> <<"todo se recuperó"/utf8>>; false -> <<"FALLÓ"/utf8>> end], #{}),
    #{caja => Caja, ok => Ok, experimentos => Experimentos}.

cli() ->
    {ok, _} = application:ensure_all_started(p59_punto_de_venta),
    R = ejecutar(),
    Archivo = p59_simulacion:guardar_reporte("caos", R),
    [imprimir(E) || E <- maps:get(experimentos, R)],
    io:format("~nResultado: ~s~nEvidencia: ~ts~n",
              [case maps:get(ok, R) of true -> "OK"; false -> "FALLA" end, Archivo]),
    application:stop(p59_punto_de_venta),
    halt(case maps:get(ok, R) of true -> 0; false -> 1 end).

%%% ---------------------------------------------------------- experimentos

matar_caja(Caja) ->
    Nombre = p59_caja:nombre(Caja),
    {Id, Antes} = preparar(Caja),
    Otras = [{C, whereis(p59_caja:nombre(C))} || C <- p59_config:cajas(), C =/= Caja],
    PidCaja = whereis(Nombre),
    PidVenta = global:whereis_name({p59_venta, Id}),
    exit(PidCaja, kill),
    Recuperada = p59_cliente:esperar(fun() -> nuevo_pid(Nombre, PidCaja) end, 3000),
    {ok, Actual} = p59_caja:venta_actual(Caja),
    Despues = estado_venta(Id),
    Checks = [check(<<"La caja fue reiniciada con otro pid"/utf8>>, true, Recuperada),
              check(<<"La venta sobrevivió (mismo pid; no estaba enlazada a la caja)"/utf8>>,
                    PidVenta, global:whereis_name({p59_venta, Id})),
              check(<<"La caja recuperó su venta en curso desde disco"/utf8>>, Id, Actual),
              check(<<"Las partidas no cambiaron"/utf8>>, maps:get(partidas, Antes), maps:get(partidas, Despues)),
              check(<<"Las otras cajas no se reiniciaron (one_for_one)"/utf8>>, Otras,
                    [{C, whereis(p59_caja:nombre(C))} || {C, _} <- Otras])]
        ++ cerrar(Id, Despues),
    resultado(#{proceso => Nombre, pid_antes => pid(PidCaja), pid_despues => pid(whereis(Nombre)),
                por_que => <<"Simula un fallo de software en la caja con un cliente a medio cobro"/utf8>>,
                esperado => <<"La caja se reinicia sola, la venta sigue abierta con sus partidas y se puede cobrar; inventario y corte cuadran"/utf8>>,
                supervisor => p59_cajas_sup, estrategia => one_for_one, venta => Id}, Checks).

matar_venta(Caja) ->
    {Id, Antes} = preparar(Caja),
    PidVenta = global:whereis_name({p59_venta, Id}),
    exit(PidVenta, kill),
    Recuperada = p59_cliente:esperar(fun() ->
                                             P = global:whereis_name({p59_venta, Id}),
                                             is_pid(P) andalso P =/= PidVenta
                                     end, 3000),
    Despues = estado_venta(Id),
    PidNuevo = global:whereis_name({p59_venta, Id}),
    Checks = [check(<<"El proceso de la venta fue reiniciado"/utf8>>, true, Recuperada),
              check(<<"Se reconstruyó desde DETS con las mismas partidas"/utf8>>,
                    maps:get(partidas, Antes), maps:get(partidas, Despues)),
              check(<<"Sigue abierta"/utf8>>, abierta, maps:get(estado, Despues))]
        ++ cerrar(Id, Despues),
    resultado(#{proceso => <<"p59_venta ", Id/binary>>, pid_antes => pid(PidVenta),
                pid_despues => pid(PidNuevo),
                por_que => <<"Simula la caída del proceso que lleva la venta"/utf8>>,
                esperado => <<"El supervisor la reinicia (transient) y la venta se reconstruye desde disco"/utf8>>,
                supervisor => p59_ventas_sup, estrategia => simple_one_for_one, venta => Id}, Checks).

matar_inventario(Caja) ->
    {Id, Antes} = preparar(Caja),
    Libro = p59_inventario:resumen(),
    PidInv = whereis(p59_inventario),
    PidSucursal = whereis(p59_sucursal_sup),
    PidServicios = whereis(p59_servicios_sup),
    PidTerminal = whereis(p59_terminal_bancaria),
    exit(PidInv, kill),
    Recuperado = p59_cliente:esperar(
                   fun() ->
                           nuevo_pid(p59_inventario, PidInv)
                               andalso nuevo_pid(p59_sucursal_sup, PidSucursal)
                               andalso p59_caja:activas() =:= length(p59_config:cajas())
                               andalso {ok, Id} =:= p59_caja:venta_actual(Caja)
                   end, 5000),
    Despues = estado_venta(Id),
    Checks = [check(<<"Inventario reiniciado"/utf8>>, true, Recuperado),
              check(<<"La sucursal (cajas y ventas) se reinició después (rest_for_one)"/utf8>>, true,
                    whereis(p59_sucursal_sup) =/= PidSucursal),
              check(<<"Los servicios anteriores en el árbol no se tocaron"/utf8>>,
                    {PidServicios, PidTerminal},
                    {whereis(p59_servicios_sup), whereis(p59_terminal_bancaria)}),
              check(<<"El libro se reconstruyó sin perder ventas"/utf8>>,
                    maps:with([ventas, cancelaciones, devoluciones, importe_vendido], Libro),
                    maps:with([ventas, cancelaciones, devoluciones, importe_vendido], p59_inventario:resumen())),
              check(<<"La venta abierta se reconstruyó con sus partidas"/utf8>>,
                    maps:get(partidas, Antes), maps:get(partidas, Despues))]
        ++ cerrar(Id, Despues),
    resultado(#{proceso => p59_inventario, pid_antes => pid(PidInv),
                pid_despues => pid(whereis(p59_inventario)),
                por_que => <<"Simula la caída del servicio central de inventario y libro"/utf8>>,
                esperado => <<"Se reinicia el inventario y todo lo que depende de él; existencias recalculadas desde el libro; ninguna venta confirmada se pierde"/utf8>>,
                supervisor => p59_punto_de_venta_sup, estrategia => rest_for_one, venta => Id}, Checks).

%%% ---------------------------------------------------------- auxiliares

preparar(Caja) ->
    #{id := P1} = p59_cliente:producto_disponible(#{min => 3}),
    #{id := P2} = p59_cliente:producto_disponible(#{min => 3, excluir => [P1]}),
    {ok, V0} = p59_cliente:abrir_venta(Caja),
    {ok, #{id := Id} = V} = p59_cliente:agregar(V0, [{P1, 2}, {P2, 1}]),
    {Id, V}.

%% Despues de cada experimento se cobra la venta y se verifica consistencia.
cerrar(Id, #{totales := #{total := Total}, caja := Caja}) ->
    Pago = p59_venta:pagar(Id, p59_cliente:efectivo_exacto(Total), p59_cliente:operacion(<<"caos">>)),
    {ok, Corte} = p59_inventario:corte(#{caja => Caja}),
    Inv = p59_inventario:verificar_existencias(),
    [check(<<"La venta recuperada se cobra y confirma"/utf8>>, pagada,
           case Pago of {ok, #{estado := E}} -> E; Otro -> Otro end),
     check(<<"Invariante de inventario (inicial - vendidas + devueltas, sin negativos)"/utf8>>,
           true, maps:get(ok, Inv)),
     check(<<"Invariante contable del corte"/utf8>>, true, maps:get(ok, maps:get(invariante, Corte)))].

estado_venta(Id) ->
    {ok, V} = p59_venta:leer(Id),
    V.

nuevo_pid(Nombre, Anterior) ->
    P = whereis(Nombre),
    is_pid(P) andalso P =/= Anterior.

resultado(Info, Checks) ->
    Info#{ok => lists:all(fun(#{ok := B}) -> B end, Checks),
          ocurrido => Checks,
          reinicios => p59_metricas:reinicios()}.

check(Nombre, Esperado, Obtenido) ->
    #{verificacion => Nombre, ok => Esperado =:= Obtenido,
      esperado => texto(Esperado), obtenido => texto(Obtenido)}.

%% Evidencia serializable (pids y tuplas a texto).
texto(X) when is_pid(X) -> pid(X);
texto(X) when is_binary(X); is_atom(X); is_integer(X) -> X;
texto(L) when is_list(L) -> [texto(E) || E <- L];
texto(M) when is_map(M) -> maps:map(fun(_, V) -> texto(V) end, M);
texto(T) when is_tuple(T) -> texto(tuple_to_list(T));
texto(X) -> iolist_to_binary(io_lib:format("~p", [X])).

pid(P) when is_pid(P) -> list_to_binary(pid_to_list(P));
pid(_) -> null.

imprimir(#{proceso := P, pid_antes := A, pid_despues := D, supervisor := S, estrategia := E,
           ok := Ok, ocurrido := Checks}) ->
    io:format("~n--- Se mató: ~ts (~ts -> ~ts)  supervisor ~p (~p): ~s~n",
              [texto_bin(P), A, D, S, E, case Ok of true -> "OK"; false -> "FALLA" end]),
    [io:format("   [~s] ~ts~n", [case B of true -> "ok"; false -> "XX" end, N])
     || #{verificacion := N, ok := B} <- Checks].

texto_bin(A) when is_atom(A) -> atom_to_binary(A);
texto_bin(B) -> B.
