-module(p59_punto_de_venta_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
  p59_punto_de_venta_sup:start_link().

stop(_State) ->
  ok.
