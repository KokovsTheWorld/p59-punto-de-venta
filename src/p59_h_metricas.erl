-module(p59_h_metricas).
-behaviour(cowboy_handler).

%% GET /metrics en formato de texto de Prometheus (sin dependencias extra).

-export([init/2]).

init(Req0, Opts) ->
    T0 = erlang:monotonic_time(microsecond),
    Req = case cowboy_req:method(Req0) of
              <<"GET">> ->
                  cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain; version=0.0.4">>},
                                   p59_metricas:prometheus(), Req0);
              _ ->
                  cowboy_req:reply(405, #{<<"allow">> => <<"GET">>}, Req0)
          end,
    p59_metricas:latencia(metrics, erlang:monotonic_time(microsecond) - T0),
    {ok, Req, Opts}.
