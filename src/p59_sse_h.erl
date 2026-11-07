-module(p59_sse_h).
-behaviour(cowboy_loop).

%% GET /api/eventos/stream: Server-Sent Events con la bitacora en tiempo real.
%% Cada conexion es un proceso que se une al grupo pg de eventos; pg lo saca del
%% grupo automaticamente cuando la conexion se cierra.

-export([init/2, info/3]).

-define(LATIDO_MS, 15000).

init(Req0, State) ->
    Req = cowboy_req:stream_reply(200, #{<<"content-type">> => <<"text/event-stream">>,
                                         <<"cache-control">> => <<"no-cache">>}, Req0),
    ok = p59_eventos:suscribir(),
    [enviar(E, Req) || E <- lists:reverse(p59_eventos:recientes(0, 20))],
    erlang:send_after(?LATIDO_MS, self(), latido),
    {cowboy_loop, Req, State}.

info({p59_evento, Evento}, Req, State) ->
    enviar(Evento, Req),
    {ok, Req, State};
info(latido, Req, State) ->
    cowboy_req:stream_body(<<": latido\n\n">>, nofin, Req),
    erlang:send_after(?LATIDO_MS, self(), latido),
    {ok, Req, State};
info(_Msg, Req, State) ->
    {ok, Req, State}.

enviar(#{seq := Seq} = Evento, Req) ->
    cowboy_req:stream_body(["id: ", integer_to_binary(Seq), "\ndata: ", json:encode(Evento), "\n\n"],
                           nofin, Req).
