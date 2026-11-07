-module(p59_ventas_tests).
-include_lib("eunit/include/eunit.hrl").

%% Pruebas de integracion del dominio sobre la aplicacion viva: flujo de venta,
%% pagos, cancelaciones, devoluciones, corte, idempotencia, concurrencia,
%% escenarios A-E, caos y recuperacion tras un reinicio completo.

dominio_test_() ->
    {setup, fun p59_test_util:arrancar/0, fun p59_test_util:detener/1,
     fun(_) ->
             [{timeout, 30, ?_test(flujo_completo_mxn())},
              {timeout, 30, ?_test(pago_mixto_con_tarjeta())},
              {timeout, 30, ?_test(agregar_y_retirar_partidas())},
              {timeout, 30, ?_test(cancelar_venta_abierta_libera_reserva())}]
     end}.

%% Cada grupo siguiente arranca su propia aplicacion: no dependen del orden.
devoluciones_test_() ->
    con_app(fun devolucion_parcial_y_cancelacion/0).

idempotencia_test_() ->
    con_app(fun idempotencia_creacion_y_pago/0).

concurrencia_reservas_test_() ->
    con_app(fun cincuenta_procesos_por_dos_unidades/0).

concurrencia_cajas_test_() ->
    con_app(fun cuatro_cajas_por_las_ultimas_piezas/0).

turno_cerrado_test_() ->
    con_app(fun no_se_vende_con_turno_cerrado/0).

escenarios_test_() ->
    {setup, fun p59_test_util:arrancar/0, fun p59_test_util:detener/1,
     fun(_) ->
             [{timeout, 60, ?_assertMatch(#{ok := true}, sin_detalle(p59_escenarios:ejecutar(L)))}
              || L <- [a, b, c, d, e]]
     end}.

caos_test_() ->
    {setup, fun p59_test_util:arrancar/0, fun p59_test_util:detener/1,
     fun(_) -> [{timeout, 60, ?_assertMatch(#{ok := true}, sin_detalle(p59_caos:ejecutar(2)))}] end}.

simulacion_reducida_test_() ->
    {setup, fun p59_test_util:arrancar/0, fun p59_test_util:detener/1,
     fun(_) ->
             [{timeout, 120,
               ?_test(begin
                          R = p59_simulacion:ejecutar(#{tickets => 120, terminal_timeout_ms => 200}),
                          ?assertEqual(120, maps:get(tickets_confirmados, R)),
                          ?assertMatch(#{ok := true}, maps:get(invariantes, R)),
                          ?assertMatch(#{reiniciada := true}, maps:get(caos, R))
                      end)}]
     end}.

recuperacion_tras_apagon_test_() ->
    {setup, fun p59_test_util:arrancar/0, fun p59_test_util:detener/1,
     fun(Dir) -> [{timeout, 60, ?_test(apagon(Dir))}] end}.

con_app(Fun) ->
    {setup, fun p59_test_util:arrancar/0, fun p59_test_util:detener/1,
     fun(_) -> [{timeout, 60, ?_test(Fun())}] end}.

%% Si falla, que eunit muestre que verificacion fallo y no todo el reporte.
sin_detalle(#{ok := true}) -> #{ok => true};
sin_detalle(R) -> R.

%%% ------------------------------------------------------------------ flujos

flujo_completo_mxn() ->
    #{id := P} = disponible(3),
    {ok, Antes} = p59_inventario:producto(P),
    {ok, V0} = p59_caja:iniciar_venta(1, null),
    ?assertMatch(#{estado := abierta, caja := 1, cajero := <<"Ana">>}, V0),
    {ok, #{totales := #{total := Total}} = V} = p59_cliente:agregar(V0, [{P, 2}]),
    ?assert(Total > 0),
    Pago = Total + 10000,
    {ok, Pagada} = p59_cliente:pagar(V, [#{metodo => efectivo_mxn, monto => Pago}]),
    ?assertMatch(#{estado := pagada, folio := <<"T-", _/binary>>}, Pagada),
    #{folio := Folio, cobro := #{cambio_mxn := Cambio}} = Pagada,
    ?assertEqual(10000, Cambio),
    {ok, #{venta := Mov}} = p59_inventario:ticket(Folio),
    ?assertMatch(#{total := Total, caja := 1, turno := 1, modalidad := efectivo_mxn}, Mov),
    {ok, Despues} = p59_inventario:producto(P),
    ?assertEqual(maps:get(existencia, Antes) - 2, maps:get(existencia, Despues)),
    Texto = p59_ticket:texto(Mov, []),
    ?assertNotEqual(nomatch, binary:match(Texto, <<"NO ES CFDI">>)),
    ?assertNotEqual(nomatch, binary:match(Texto, Folio)),
    %% Una venta pagada no vuelve atras.
    ?assertEqual({error, venta_pagada_usar_cancelacion_de_ticket},
                 p59_venta:cancelar(maps:get(id, V), <<"x">>)),
    ?assertEqual({error, {venta_finalizada, pagada}},
                 p59_venta:agregar(maps:get(id, V), P, 1, 0)).

pago_mixto_con_tarjeta() ->
    #{id := P} = disponible(2),
    {ok, V0} = p59_caja:iniciar_venta(2, null),
    {ok, #{totales := #{total := Total}} = V} = p59_cliente:agregar(V0, [{P, 1}]),
    Tarjeta = Total div 2,
    Pagos = [#{metodo => tarjeta, monto => Tarjeta},
             #{metodo => efectivo_usd, monto => 100},
             #{metodo => efectivo_mxn, monto => Total}],
    {ok, #{cobro := Cobro, autorizacion := Aut}} = p59_cliente:pagar(V, Pagos),
    ?assertMatch(#{modalidad := mixto}, Cobro),
    ?assert(is_binary(Aut)),
    #{recibido_mxn := Recibido, cambio_mxn := Cambio} = Cobro,
    ?assertEqual(Total, Recibido - Cambio).

agregar_y_retirar_partidas() ->
    #{id := P1} = disponible(5),
    #{id := P2} = p59_cliente:producto_disponible(#{min => 5, excluir => [P1]}),
    {ok, V0} = p59_caja:iniciar_venta(3, null),
    Id = maps:get(id, V0),
    {ok, _} = p59_venta:agregar(Id, P1, 1, 0),
    {ok, _} = p59_venta:agregar(Id, P1, 2, 0),
    {ok, #{partidas := Ps}} = p59_venta:agregar(Id, P2, 1, 15),
    ?assertMatch([#{producto_id := P1, cantidad := 3}, #{producto_id := P2, descuento_pct := 15}], Ps),
    {ok, #{partidas := [#{producto_id := P2}]}} = p59_venta:retirar(Id, P1),
    ?assertEqual({error, partida_no_encontrada}, p59_venta:retirar(Id, P1)),
    ?assertEqual({error, partida_invalida}, p59_venta:agregar(Id, P1, 0, 0)),
    ?assertEqual({error, partida_invalida}, p59_venta:agregar(Id, P1, 1, 101)),
    ?assertEqual({error, producto_no_encontrado}, p59_venta:agregar(Id, <<"NOPE">>, 1, 0)),
    [#{id := Inactivo} | _] = [X || #{activo := false} = X <- p59_inventario:productos()],
    ?assertEqual({error, producto_inactivo}, p59_venta:agregar(Id, Inactivo, 1, 0)),
    ?assertMatch({ok, #{estado := cancelada}}, p59_venta:cancelar(Id, <<"prueba">>)).

cancelar_venta_abierta_libera_reserva() ->
    #{id := P} = disponible(2),
    {ok, V0} = p59_caja:iniciar_venta(4, null),
    {ok, #{id := Id, totales := #{total := Total}}} = p59_cliente:agregar(V0, [{P, 1}]),
    ok = p59_terminal_bancaria:fijar_modo(caida_antes_de_cobro, #{una_vez => true}),
    {pendiente, _} = p59_venta:pagar(Id, [#{metodo => tarjeta, monto => Total}], <<"op-r">>),
    {ok, #{reservado := 1}} = p59_inventario:producto(P),
    ?assertMatch({ok, #{estado := cancelada}}, p59_venta:cancelar(Id, <<"cliente se fue">>)),
    {ok, #{reservado := 0}} = p59_inventario:producto(P),
    ?assertEqual(no, p59_inventario:venta_confirmada(Id)),
    %% El historial conserva cada transicion.
    {ok, #{historial := H}} = p59_venta:leer(Id),
    ?assertEqual([abierta, procesando_pago, pendiente_de_revision, abierta, cancelada],
                 [E || #{estado := E} <- H]).

devolucion_parcial_y_cancelacion() ->
    #{id := P} = disponible(4),
    {ok, #{folio := Folio, totales := #{total := Total}}} =
        p59_cliente:vender(1, [{P, 3}], fun p59_cliente:efectivo_exacto/1),
    {ok, #{existencia := E0}} = p59_inventario:producto(P),
    Ctx = #{caja => 1, motivo => <<"defecto">>, operacion_id => <<"dev-1">>},
    {ok, D} = p59_inventario:reembolsar(devolucion, Folio, [{P, 1}], Ctx),
    %% Reintento de la misma devolucion: mismo movimiento, no se repite.
    {ok, D} = p59_inventario:reembolsar(devolucion, Folio, [{P, 1}], Ctx),
    {ok, #{existencia := E1}} = p59_inventario:producto(P),
    ?assertEqual(E0 + 1, E1),
    ?assertMatch({error, {cantidad_no_devolvible, _}},
                 p59_inventario:reembolsar(devolucion, Folio, [{P, 3}], Ctx#{operacion_id => <<"dev-2">>})),
    {ok, C} = p59_inventario:reembolsar(cancelacion, Folio, todo, #{caja => 1}),
    ?assertEqual(Total, maps:get(monto, D) + maps:get(monto, C)),
    {ok, #{existencia := E2}} = p59_inventario:producto(P),
    ?assertEqual(E0 + 3, E2),
    {ok, #{reembolsos := R}} = p59_inventario:ticket(Folio),
    ?assertEqual([devolucion, cancelacion], [T || #{tipo := T} <- R]),
    {ok, Corte} = p59_inventario:corte(#{caja => 1}),
    ?assertMatch(#{cancelaciones := #{numero := 1}, devoluciones := #{numero := 1},
                   venta_neta := 0, invariante := #{ok := true}}, Corte),
    ?assertEqual(#{mxn => 100000, usd => 0}, maps:get(efectivo_esperado, Corte)),
    ?assert(maps:get(ok, p59_inventario:verificar_existencias())).

idempotencia_creacion_y_pago() ->
    #{id := P} = disponible(2),
    {ok, #{id := Id} = V} = p59_caja:iniciar_venta(2, <<"crear-1">>),
    ?assertMatch({ok, #{id := Id}}, p59_caja:iniciar_venta(2, <<"crear-1">>)),
    ?assertMatch({error, {venta_en_curso, Id}}, p59_caja:iniciar_venta(2, <<"crear-2">>)),
    {ok, #{totales := #{total := Total}}} = p59_cliente:agregar(V, [{P, 1}]),
    Pagos = p59_cliente:efectivo_exacto(Total),
    {ok, #{folio := F}} = p59_venta:pagar(Id, Pagos, <<"pago-1">>),
    {ok, #{folio := F}} = p59_venta:pagar(Id, Pagos, <<"pago-1">>),
    ?assertEqual({error, venta_ya_pagada}, p59_venta:pagar(Id, Pagos, <<"pago-2">>)),
    ?assertEqual(1, maps:get(ventas, p59_inventario:resumen())),
    %% Una confirmacion repetida directa al libro tampoco duplica.
    {ok, Venta} = p59_venta:leer(Id),
    {ok, #{folio := F}} = p59_inventario:confirmar(Venta),
    ?assertEqual(1, maps:get(ventas, p59_inventario:resumen())).

%%% ------------------------------------------------------------- concurrencia

cincuenta_procesos_por_dos_unidades() ->
    [#{id := P, existencia := 2} | _] = [X || #{existencia_inicial := 2, activo := true} = X
                                                  <- p59_inventario:productos()],
    Yo = self(),
    [spawn(fun() ->
                   Id = <<"X-", (integer_to_binary(N))/binary>>,
                   Yo ! {N, p59_inventario:reservar(Id, [{P, 1}])}
           end) || N <- lists:seq(1, 50)],
    Resultados = [receive {N, R} -> R end || N <- lists:seq(1, 50)],
    ?assertEqual(2, length([ok || ok <- Resultados])),
    ?assertEqual(48, length([e || {error, {sin_existencia, [_]}} <- Resultados])),
    {ok, #{existencia := 2, reservado := 2}} = p59_inventario:producto(P),
    [p59_inventario:liberar(<<"X-", (integer_to_binary(N))/binary>>) || N <- lists:seq(1, 50)],
    {ok, #{reservado := 0}} = p59_inventario:producto(P).

cuatro_cajas_por_las_ultimas_piezas() ->
    [#{id := P} | _] = [X || #{existencia_inicial := 2, activo := true} = X <- p59_inventario:productos()],
    %% Las cuatro cajas meten la pieza al carrito (hay 2 disponibles para cada una)...
    Ventas = [begin
                  {ok, V} = p59_caja:iniciar_venta(C, null),
                  {ok, V1} = p59_cliente:agregar(V, [{P, 1}]),
                  V1
              end || C <- [1, 2, 3, 4]],
    %% ...y cobran al mismo tiempo, cada una desde su propio proceso.
    Yo = self(),
    [spawn(fun() -> Yo ! {Id, p59_cliente:pagar(V, p59_cliente:efectivo_exacto(T))} end)
     || #{id := Id, totales := #{total := T}} = V <- Ventas],
    Resultados = [receive {Id, R} -> R end || #{id := Id} <- Ventas],
    ?assertEqual(2, length([x || {ok, #{estado := pagada}} <- Resultados])),
    ?assertEqual(2, length([x || {error, {sin_existencia, [_]}} <- Resultados])),
    {ok, #{existencia := 0, reservado := 0}} = p59_inventario:producto(P),
    ?assert(maps:get(ok, p59_inventario:verificar_existencias())).

no_se_vende_con_turno_cerrado() ->
    #{id := P} = disponible(2),
    {ok, V} = p59_caja:iniciar_venta(3, null),
    {ok, #{id := Id, totales := #{total := T}}} = p59_cliente:agregar(V, [{P, 1}]),
    {ok, #{efectivo_esperado := Esperado}} = p59_inventario:corte(#{caja => 3}),
    {ok, Corte} = p59_inventario:cerrar_turno(3, Esperado),
    ?assertMatch(#{descuadre := false, en_proceso := [#{id := Id}], estado_turno := cerrado}, Corte),
    ?assertMatch({ok, #{estado_turno := cerrado}}, p59_inventario:corte(#{caja => 3, turno => 1})),
    ?assertEqual({error, turno_cerrado}, p59_venta:pagar(Id, p59_cliente:efectivo_exacto(T), <<"t">>)),
    %% La caja sigue teniendo la venta en curso; no se puede abrir otra.
    ?assertEqual({error, {venta_en_curso, Id}}, p59_caja:iniciar_venta(3, null)),
    {ok, #{turno := 2}} = p59_inventario:abrir_turno(3, <<"Carla">>, 50000),
    ?assertMatch({ok, #{estado := pagada}}, p59_venta:pagar(Id, p59_cliente:efectivo_exacto(T), <<"t2">>)),
    %% La venta iniciada en el turno 1 cuenta en el turno en que se confirmo.
    {ok, #{ventas := #{numero := 1}}} = p59_inventario:corte(#{caja => 3, turno => 2}),
    {ok, #{ventas := #{numero := 0}}} = p59_inventario:corte(#{caja => 3, turno => 1}).

%%% ------------------------------------------------------------ recuperacion

apagon(Dir) ->
    #{id := P} = disponible(3),
    {ok, #{folio := Folio}} = p59_cliente:vender(1, [{P, 1}], fun p59_cliente:efectivo_exacto/1),
    {ok, V} = p59_caja:iniciar_venta(2, null),
    {ok, #{id := Abierta, partidas := Partidas}} = p59_cliente:agregar(V, [{P, 2}]),
    Resumen = p59_inventario:resumen(),
    {ok, #{existencia := E}} = p59_inventario:producto(P),
    p59_test_util:reiniciar_app(Dir),
    %% Nada confirmado se perdio y la venta abierta sigue en su caja.
    ?assertEqual(Resumen, p59_inventario:resumen()),
    ?assertMatch({ok, _}, p59_inventario:ticket(Folio)),
    {ok, #{existencia := E}} = p59_inventario:producto(P),
    ?assertEqual({ok, Abierta}, p59_caja:venta_actual(2)),
    {ok, #{estado := abierta, partidas := Partidas, totales := #{total := T}}} = p59_venta:leer(Abierta),
    ?assertMatch({ok, #{estado := pagada}},
                 p59_venta:pagar(Abierta, p59_cliente:efectivo_exacto(T), <<"tras-apagon">>)),
    ?assert(maps:get(ok, p59_inventario:verificar_existencias())).

disponible(N) ->
    p59_cliente:producto_disponible(#{min => N, excluir => escasos()}).

escasos() ->
    [Id || #{id := Id, existencia_inicial := 2} <- p59_inventario:productos()].
