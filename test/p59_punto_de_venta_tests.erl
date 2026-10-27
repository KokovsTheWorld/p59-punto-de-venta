-module(p59_punto_de_venta_tests).
-include_lib("eunit/include/eunit.hrl").

arbol_de_supervision_test_() ->
  {setup,
   fun() -> {ok, Pid} = p59_punto_de_venta_sup:start_link(), Pid end,
   fun(Pid) ->
     unlink(Pid),
     exit(Pid, shutdown)
   end,
   fun(_) ->
     [?_assertEqual(pong, p59_punto_de_venta_server:ping()),
      ?_assert(is_map(p59_punto_de_venta_server:state()))]
   end}.
