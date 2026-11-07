-module(p59_http_tests).
-include_lib("eunit/include/eunit.hrl").

%% Pruebas de la API Cowboy con un cliente HTTP real (httpc) sobre un puerto
%% aleatorio.

api_test_() ->
    {setup,
     fun() ->
             Dir = p59_test_util:arrancar(),
             {ok, _} = application:ensure_all_started(inets),
             Dir
     end,
     fun p59_test_util:detener/1,
     fun(_) ->
             [?_test(sistema()),
              ?_test(productos()),
              {timeout, 30, ?_test(venta_por_http())},
              ?_test(validaciones()),
              ?_test(corte_y_metricas()),
              ?_test(simulacion_de_fallas())]
     end}.

sistema() ->
    ?assertMatch({200, #{<<"estado">> := <<"ok">>}}, consultar("/api/health")),
    {200, Estado} = consultar("/api/estado"),
    ?assertMatch(#{<<"cajas_activas">> := 4, <<"arbol">> := #{<<"id">> := <<"p59_punto_de_venta_sup">>}},
                 Estado),
    ?assertMatch({200, #{<<"memoria">> := [_ | _]}}, consultar("/api/diagnostico")),
    ?assertMatch({200, #{<<"cajas">> := [_, _, _, _]}}, consultar("/api/cajas")),
    ?assertMatch({200, #{<<"id">> := 3, <<"turno">> := #{<<"estado">> := <<"abierto">>}}},
                 consultar("/api/cajas/3")),
    ?assertMatch({404, _}, consultar("/api/cajas/9")),
    ?assertMatch({200, #{<<"valor">> := 182000}}, consultar("/api/tipo-cambio")).

productos() ->
    ?assertMatch({200, #{<<"total">> := 800, <<"productos">> := [_ | _]}}, consultar("/api/productos")),
    {200, #{<<"productos">> := Pag}} = consultar("/api/productos?limite=5&pagina=2"),
    ?assertEqual(5, length(Pag)),
    ?assertMatch({200, #{<<"id">> := <<"P0001">>, <<"disponible">> := _}}, consultar("/api/productos/P0001")),
    ?assertMatch({404, #{<<"error">> := <<"producto_no_encontrado">>}}, consultar("/api/productos/X999")).

venta_por_http() ->
    {201, #{<<"id">> := Id}} = post("/api/ventas", #{caja => 1, operacion_id => <<"http-1">>}),
    %% Reintento de red de la creacion: misma venta.
    {201, #{<<"id">> := Id}} = post("/api/ventas", #{caja => 1, operacion_id => <<"http-1">>}),
    {200, #{<<"totales">> := #{<<"total">> := Total}}} =
        post(["/api/ventas/", Id, "/partidas"], #{producto_id => <<"P0003">>, cantidad => 2}),
    Pago = #{operacion_id => <<"pago-http">>,
             pagos => [#{metodo => <<"efectivo_mxn">>, monto => Total + 500}]},
    {200, #{<<"estado">> := <<"pagada">>, <<"folio">> := Folio}} = post(["/api/ventas/", Id, "/pago"], Pago),
    {200, #{<<"folio">> := Folio}} = post(["/api/ventas/", Id, "/pago"], Pago),
    {200, Ticket} = consultar(["/api/tickets/", Folio]),
    ?assertMatch(#{<<"venta">> := #{<<"total">> := Total, <<"cambio_mxn">> := 500}}, Ticket),
    ?assertNotEqual(nomatch, binary:match(maps:get(<<"texto">>, Ticket), <<"NO ES CFDI">>)),
    ?assertMatch({200, #{<<"estado">> := <<"pagada">>}}, consultar(["/api/ventas/", Id])),
    ?assertMatch({200, #{<<"ventas">> := [_ | _]}}, consultar("/api/ventas?estado=pagada")),
    {201, #{<<"tipo">> := <<"devolucion">>}} =
        post(["/api/tickets/", Folio, "/devolucion"],
             #{caja => 1, operacion_id => <<"d1">>, partidas => [#{producto_id => <<"P0003">>, cantidad => 1}]}),
    {200, #{<<"cancelacion">> := #{<<"tipo">> := <<"cancelacion">>}}} =
        post(["/api/ventas/", Id, "/cancelar"], #{motivo => <<"prueba">>}),
    ?assertMatch({409, #{<<"error">> := <<"ticket_cancelado">>}},
                 post(["/api/tickets/", Folio, "/devolucion"],
                      #{partidas => [#{producto_id => <<"P0003">>, cantidad => 1}]})).

validaciones() ->
    {201, #{<<"id">> := Id}} = post("/api/ventas", #{caja => 2}),
    ?assertMatch({422, #{<<"error">> := <<"venta_vacia">>}},
                 post(["/api/ventas/", Id, "/pago"], #{pagos => [#{metodo => <<"efectivo_mxn">>, monto => 100}]})),
    {200, _} = post(["/api/ventas/", Id, "/partidas"], #{producto_id => <<"P0005">>, cantidad => 1}),
    ?assertMatch({422, #{<<"error">> := <<"pago_insuficiente">>}},
                 post(["/api/ventas/", Id, "/pago"], #{pagos => [#{metodo => <<"efectivo_mxn">>, monto => 1}]})),
    ?assertMatch({422, #{<<"error">> := <<"pago_invalido">>}},
                 post(["/api/ventas/", Id, "/pago"], #{pagos => [#{metodo => <<"cheque">>, monto => 1}]})),
    ?assertMatch({422, #{<<"error">> := <<"pago_invalido">>}},
                 post(["/api/ventas/", Id, "/pago"], #{pagos => [#{metodo => <<"efectivo_mxn">>, monto => 10.5}]})),
    ?assertMatch({409, #{<<"error">> := <<"venta_en_curso">>}}, post("/api/ventas", #{caja => 2})),
    ?assertMatch({404, _}, post("/api/ventas", #{caja => 7})),
    ?assertMatch({400, #{<<"error">> := <<"json_invalido">>}}, peticion(post, "/api/ventas", <<"{no-json">>)),
    ?assertMatch({404, _}, consultar("/api/ventas/V-999999")),
    ?assertMatch({405, _}, peticion(put, "/api/ventas", <<"{}">>)),
    ?assertMatch({200, #{<<"estado">> := <<"cancelada">>}}, post(["/api/ventas/", Id, "/cancelar"], #{})).

corte_y_metricas() ->
    {200, Corte} = consultar("/api/corte"),
    ?assertMatch(#{<<"cajas">> := [_, _, _, _], <<"consolidado">> := _}, Corte),
    ?assertMatch({200, #{<<"invariante">> := #{<<"ok">> := true}}}, consultar("/api/corte?caja=1")),
    ?assertMatch({200, _}, consultar("/api/corte?cajero=Ana")),
    ?assertMatch({422, _}, consultar("/api/corte?caja=abc")),
    {200, Cierre} = post("/api/cajas/4/turno/cerrar", #{efectivo_contado_mxn => 99000}),
    ?assertMatch(#{<<"descuadre">> := true, <<"diferencia">> := #{<<"mxn">> := -1000}}, Cierre),
    ?assertMatch({201, #{<<"turno">> := 2}}, post("/api/cajas/4/turno", #{cajero => <<"Eva">>})),
    {200, Texto} = peticion_texto("/metrics"),
    [?assertNotEqual(nomatch, binary:match(Texto, M))
     || M <- [<<"p59_ventas_confirmadas_total ">>, <<"p59_productos 800">>, <<"p59_cajas_activas 4">>,
              <<"p59_descuadres_total ">>, <<"p59_http_solicitudes_total{ruta=\"ventas\"}">>]],
    ?assertMatch({200, #{<<"eventos">> := [_ | _]}}, consultar("/api/eventos?limite=5")).

simulacion_de_fallas() ->
    ?assertMatch({200, #{<<"modo">> := <<"rechazar">>}},
                 post("/api/simulacion/terminal", #{modo => <<"rechazar">>, una_vez => true})),
    {201, #{<<"id">> := Id}} = post("/api/ventas", #{caja => 3}),
    {200, #{<<"totales">> := #{<<"total">> := T}}} =
        post(["/api/ventas/", Id, "/partidas"], #{producto_id => <<"P0007">>}),
    ?assertMatch({402, #{<<"error">> := <<"rechazada">>}},
                 post(["/api/ventas/", Id, "/pago"], #{pagos => [#{metodo => <<"tarjeta">>, monto => T}]})),
    ?assertMatch({200, #{<<"estado">> := <<"pagada">>}},
                 post(["/api/ventas/", Id, "/pago"], #{pagos => [#{metodo => <<"tarjeta">>, monto => T}]})),
    ?assertMatch({422, _}, post("/api/simulacion/terminal", #{modo => <<"explotar">>})),
    ?assertMatch({422, _}, post("/api/simulacion/matar", #{proceso => <<"kernel_sup">>})),
    Pid = whereis(p59_caja_1),
    ?assertMatch({200, _}, post("/api/simulacion/matar", #{proceso => <<"p59_caja_1">>})),
    ?assert(p59_cliente:esperar(fun() -> is_pid(whereis(p59_caja_1)) andalso whereis(p59_caja_1) =/= Pid end,
                                2000)),
    ?assertMatch({200, #{<<"ok">> := true}}, post("/api/simulacion/escenarios/c", #{})).

%%% ---------------------------------------------------------------- cliente

url(Ruta) ->
    "http://127.0.0.1:" ++ integer_to_list(ranch:get_port(p59_http)) ++ binary_to_list(iolist_to_binary(Ruta)).

consultar(Ruta) ->
    {ok, {{_, Status, _}, _, Cuerpo}} = httpc:request(get, {url(Ruta), []}, [], [{body_format, binary}]),
    {Status, json:decode(Cuerpo)}.

post(Ruta, Mapa) ->
    peticion(post, Ruta, json:encode(Mapa)).

peticion(Metodo, Ruta, Cuerpo) ->
    {ok, {{_, Status, _}, _, Resp}} =
        httpc:request(Metodo, {url(Ruta), [], "application/json", Cuerpo}, [], [{body_format, binary}]),
    {Status, json:decode(Resp)}.

peticion_texto(Ruta) ->
    {ok, {{_, Status, _}, _, Cuerpo}} = httpc:request(get, {url(Ruta), []}, [], [{body_format, binary}]),
    {Status, Cuerpo}.
