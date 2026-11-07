-module(p59_punto_de_venta_tests).
-include_lib("eunit/include/eunit.hrl").

%% Arranque de la aplicacion y forma del arbol de supervision.

arbol_de_supervision_test_() ->
  {setup, fun p59_test_util:arrancar/0, fun p59_test_util:detener/1,
   fun(_) ->
     [?_assertEqual(pong, p59_punto_de_venta_server:ping()),
      ?_assert(is_map(p59_punto_de_venta_server:state())),
      ?_test(estrategias()),
      ?_test(procesos_registrados()),
      ?_assertEqual(800, length(p59_inventario:productos())),
      ?_assertEqual(4, p59_caja:activas()),
      ?_test(turnos_iniciales()),
      ?_assert(maps:get(ok, p59_inventario:verificar_existencias()))]
   end}.

estrategias() ->
  %% El estado interno de supervisor es #state{name, strategy, ...}.
  Estrategia = fun(Sup) -> element(3, sys:get_state(Sup)) end,
  ?assertEqual(rest_for_one, Estrategia(p59_punto_de_venta_sup)),
  ?assertEqual(rest_for_one, Estrategia(p59_sucursal_sup)),
  ?assertEqual(one_for_one, Estrategia(p59_cajas_sup)),
  ?assertEqual(one_for_one, Estrategia(p59_servicios_sup)),
  ?assertEqual(simple_one_for_one, Estrategia(p59_ventas_sup)),
  %% Orden de arranque: almacen antes que inventario y este antes que la sucursal.
  Ids = [Id || {Id, _, _, _} <- lists:reverse(supervisor:which_children(p59_punto_de_venta_sup))],
  ?assertEqual([p59_pg, p59_servicios_sup, p59_almacen, p59_inventario, p59_sucursal_sup], Ids).

procesos_registrados() ->
  [?assert(is_pid(whereis(N))) || N <- [p59_almacen, p59_inventario, p59_metricas, p59_eventos,
                                        p59_tipo_cambio, p59_terminal_bancaria, p59_impresora,
                                        p59_caja_1, p59_caja_2, p59_caja_3, p59_caja_4]].

turnos_iniciales() ->
  Turnos = p59_inventario:turnos(),
  ?assertEqual(4, length(Turnos)),
  ?assert(lists:all(fun(#{estado := E, turno := T}) -> E =:= abierto andalso T =:= 1 end, Turnos)).
