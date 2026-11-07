-module(p59_calculo_tests).
-include_lib("eunit/include/eunit.hrl").

%% Pruebas de la logica pura: dinero, importes, pagos, catalogo, devoluciones
%% y corte. No arrancan procesos.

%%% ----------------------------------------------------------------- dinero

iva_redondea_medio_centavo_hacia_arriba_test() ->
    ?assertEqual(16, p59_dinero:iva(100, 1600)),
    ?assertEqual(0, p59_dinero:iva(3, 1600)),          % 0.48 -> 0
    ?assertEqual(1, p59_dinero:iva(4, 1600)),          % 0.64 -> 1
    ?assertEqual(0, p59_dinero:iva(12345, 0)),
    ?assertEqual(988, p59_dinero:iva(12345, 800)).     % 987.6 -> 988

usd_a_mxn_redondea_a_piso_test() ->
    ?assertEqual(182000, p59_dinero:usd_a_mxn(10000, 182000)),   % US$100 a 18.20
    ?assertEqual(18, p59_dinero:usd_a_mxn(1, 182000)),           % 18.2 centavos -> 18
    ?assertEqual(0, p59_dinero:usd_a_mxn(0, 182000)).

acumulado_conserva_el_total_test() ->
    %% Repartir 1000 centavos en 3 devoluciones de 1 unidad no pierde centavos.
    Partes = [p59_dinero:acumulado(1000, U, 3) - p59_dinero:acumulado(1000, U - 1, 3)
              || U <- [1, 2, 3]],
    ?assertEqual(1000, lists:sum(Partes)),
    ?assertEqual([333, 333, 334], Partes).

formato_test() ->
    ?assertEqual(<<"$1,234,567.89">>, p59_dinero:formatear(123456789)),
    ?assertEqual(<<"$0.05">>, p59_dinero:formatear(5)),
    ?assertEqual(<<"-$60.10">>, p59_dinero:formatear(-6010)),
    ?assertEqual(<<"US$50.00">>, p59_dinero:formatear_usd(5000)),
    ?assertEqual(<<"18.2000">>, p59_dinero:formatear_tc(182000)).

%%% --------------------------------------------------------------- importes

partida(Cant, Precio, Desc, Tasa) ->
    #{producto_id => <<"P1">>, nombre => <<"x">>, cantidad => Cant, precio_unitario => Precio,
      descuento_pct => Desc, tasa_iva => Tasa}.

linea_con_descuento_e_iva_test() ->
    L = p59_importes:linea(partida(3, 1999, 10, 1600)),
    %% bruto 59.97, descuento 6.00 (5.997 redondeado), base 53.97, IVA 8.64
    ?assertMatch(#{bruto := 5997, descuento := 600, base := 5397, iva := 864, importe := 6261}, L).

totales_suman_por_partida_test() ->
    T = p59_importes:totales([partida(1, 10000, 0, 1600),
                              (partida(2, 2550, 0, 0))#{producto_id => <<"P2">>}]),
    ?assertMatch(#{subtotal := 15100, iva := 1600, total := 16700, articulos := 3}, T),
    #{partidas := Ls, total := Total} = T,
    ?assertEqual(Total, lists:sum([maps:get(importe, L) || L <- Ls])).

venta_vacia_no_se_cobra_test() ->
    ?assertEqual({error, venta_vacia}, p59_importes:aplicar_pagos(0, [], 182000)).

pago_mxn_con_cambio_test() ->
    {ok, C} = p59_importes:aplicar_pagos(16700, [#{metodo => efectivo_mxn, monto => 20000}], 182000),
    ?assertMatch(#{cambio_mxn := 3300, recibido_mxn := 20000, modalidad := efectivo_mxn}, C).

pago_usd_con_cambio_en_pesos_test() ->
    %% US$10.00 a 18.2000 = $182.00; total $167.00 -> cambio $15.00 en pesos
    {ok, C} = p59_importes:aplicar_pagos(16700, [#{metodo => efectivo_usd, monto => 1000}], 182000),
    ?assertMatch(#{cambio_mxn := 1500, recibido_mxn := 18200, modalidad := efectivo_usd,
                   tipo_cambio := 182000}, C),
    [#{moneda := usd, monto := 1000, monto_mxn := 18200}] = maps:get(pagos, C).

pago_mixto_test() ->
    Pagos = [#{metodo => tarjeta, monto => 10000},
             #{metodo => efectivo_usd, monto => 200},
             #{metodo => efectivo_mxn, monto => 5000}],
    {ok, C} = p59_importes:aplicar_pagos(16700, Pagos, 182000),
    %% 100.00 + 36.40 + 50.00 = 186.40 -> cambio 19.40
    ?assertMatch(#{modalidad := mixto, recibido_mxn := 18640, cambio_mxn := 1940}, C).

invariante_pagos_menos_cambio_es_total_test() ->
    [begin
         {ok, #{pagos := Ps, cambio_mxn := Cambio}} = p59_importes:aplicar_pagos(Total, Pagos, Tc),
         ?assertEqual(Total, lists:sum([M || #{monto_mxn := M} <- Ps]) - Cambio)
     end || {Total, Pagos, Tc} <- [{1, [#{metodo => efectivo_usd, monto => 1}], 182000},
                                   {99999, [#{metodo => efectivo_usd, monto => 10000}], 199999},
                                   {5000, [#{metodo => tarjeta, monto => 5000}], null},
                                   {5001, [#{metodo => tarjeta, monto => 1},
                                           #{metodo => efectivo_mxn, monto => 6000}], null}]].

pagos_invalidos_test() ->
    Total = 10000,
    ?assertMatch({error, {pago_insuficiente, 1}},
                 p59_importes:aplicar_pagos(Total, [#{metodo => efectivo_mxn, monto => 9999}], 182000)),
    ?assertEqual({error, tarjeta_excede_total},
                 p59_importes:aplicar_pagos(Total, [#{metodo => tarjeta, monto => 10001}], 182000)),
    ?assertEqual({error, sin_tipo_de_cambio},
                 p59_importes:aplicar_pagos(Total, [#{metodo => efectivo_usd, monto => 9000}], null)),
    ?assertEqual({error, metodo_invalido},
                 p59_importes:aplicar_pagos(Total, [#{metodo => cheque, monto => 10000}], 182000)),
    ?assertEqual({error, monto_invalido},
                 p59_importes:aplicar_pagos(Total, [#{metodo => efectivo_mxn, monto => -5}], 182000)),
    ?assertEqual({error, monto_invalido},
                 p59_importes:aplicar_pagos(Total, [#{metodo => efectivo_mxn, monto => 100.0}], 182000)),
    ?assertEqual({error, mas_de_una_tarjeta},
                 p59_importes:aplicar_pagos(Total, [#{metodo => tarjeta, monto => 1},
                                                    #{metodo => tarjeta, monto => 1}], 182000)),
    ?assertEqual({error, sin_pagos}, p59_importes:aplicar_pagos(Total, [], 182000)).

%%% ---------------------------------------------------------------- catalogo

catalogo_800_productos_deterministas_test() ->
    A = p59_catalogo:generar(800, 59),
    ?assertEqual(800, length(A)),
    ?assertEqual(A, p59_catalogo:generar(800, 59)),
    Ids = [Id || #{id := Id} <- A],
    ?assertEqual(800, length(lists:usort(Ids))),
    ?assert(lists:all(fun(#{precio := P, existencia_inicial := E}) ->
                              is_integer(P) andalso P > 0 andalso E > 0
                      end, A)),
    ?assert(length([x || #{activo := false} <- A]) > 0),
    ?assertNotEqual(A, p59_catalogo:generar(800, 60)).

%%% ------------------------------------------------------------ devoluciones

venta_de_prueba() ->
    #{partidas := Ps} = T =
        p59_importes:totales([partida(3, 1000, 0, 1600),
                              (partida(1, 333, 0, 0))#{producto_id => <<"P2">>}]),
    #{tipo => venta, folio => <<"T-1">>, venta_id => <<"V-1">>, caja => 1, turno => 1,
      partidas => Ps, total => maps:get(total, T),
      pagos => [#{metodo => tarjeta, monto => 2000, monto_mxn => 2000},
                #{metodo => efectivo_mxn, monto => 2000, monto_mxn => 2000}]}.

ctx(N) -> #{id => N, caja => 2, cajero => <<"Beto">>, turno => 5, fecha => 1}.

devoluciones_parciales_suman_el_total_test() ->
    V = venta_de_prueba(),
    {ok, D1} = p59_movimientos:reembolso(devolucion, V, [], [{<<"P1">>, 1}], ctx(<<"D1">>)),
    {ok, D2} = p59_movimientos:reembolso(devolucion, V, [D1], [{<<"P1">>, 1}], ctx(<<"D2">>)),
    {ok, C} = p59_movimientos:reembolso(cancelacion, V, [D1, D2], todo, ctx(<<"C1">>)),
    ?assertEqual(maps:get(total, V), lists:sum([maps:get(monto, M) || M <- [D1, D2, C]])),
    %% Primero se revierte la tarjeta (20.00) y despues efectivo.
    ?assertEqual(2000, lists:sum([maps:get(reembolso_tarjeta, M) || M <- [D1, D2, C]])),
    ?assertMatch(#{turno := 5, turno_original := 1, caja_original := 1}, C).

no_se_devuelve_mas_de_lo_vendido_test() ->
    V = venta_de_prueba(),
    ?assertMatch({error, {cantidad_no_devolvible, [<<"P1">>]}},
                 p59_movimientos:reembolso(devolucion, V, [], [{<<"P1">>, 4}], ctx(<<"D">>))),
    ?assertMatch({error, {cantidad_no_devolvible, [<<"X">>]}},
                 p59_movimientos:reembolso(devolucion, V, [], [{<<"X">>, 1}], ctx(<<"D">>))),
    {ok, C} = p59_movimientos:reembolso(cancelacion, V, [], todo, ctx(<<"C">>)),
    ?assertEqual({error, ticket_cancelado},
                 p59_movimientos:reembolso(devolucion, V, [C], [{<<"P1">>, 1}], ctx(<<"D">>))).

%%% ------------------------------------------------------------------ corte

corte_cuadra_con_ventas_y_reembolsos_test() ->
    V = venta_de_prueba(),
    Venta = V#{modalidad => mixto, cambio_mxn => 4000 - maps:get(total, V)},
    {ok, D} = p59_movimientos:reembolso(devolucion, Venta, [], [{<<"P2">>, 1}], ctx(<<"D">>)),
    C = p59_corte:calcular([Venta, D], #{fondo_mxn => 100000, contado => #{mxn => 0, usd => 0}}),
    ?assert(maps:get(ok, maps:get(invariante, C))),
    ?assertEqual(maps:get(total, V) - maps:get(monto, D), maps:get(venta_neta, C)),
    ?assert(maps:get(descuadre, C)),
    Esperado = 100000 + 2000 - maps:get(cambio_mxn, Venta) - maps:get(reembolso_efectivo, D),
    ?assertEqual(#{mxn => Esperado, usd => 0}, maps:get(efectivo_esperado, C)),
    ?assertEqual(#{mxn => -Esperado, usd => 0}, maps:get(diferencia, C)).

corte_detecta_venta_que_no_cuadra_test() ->
    Mala = (venta_de_prueba())#{modalidad => mixto, cambio_mxn => 0},
    C = p59_corte:calcular([Mala], #{}),
    ?assertNot(maps:get(ok, maps:get(invariante, C))).

corte_sumado_test() ->
    V = (venta_de_prueba())#{modalidad => tarjeta, cambio_mxn => 4000 - maps:get(total, venta_de_prueba())},
    C1 = p59_corte:calcular([V], #{fondo_mxn => 100}),
    S = p59_corte:sumar([C1#{generado_en => 1793920000000}, C1#{generado_en => 1793920000000}]),
    ?assertNot(maps:is_key(generado_en, S)),
    ?assertEqual(2, maps:get(numero, maps:get(ventas, S))),
    ?assertEqual(200, maps:get(fondo_inicial, S)).
