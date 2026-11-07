-module(p59_h_eventos).
-behaviour(cowboy_handler).

%% GET /api/eventos?desde=SEQ&limite=N   bitacora reciente (mas nuevos primero)

-export([init/2]).

init(Req0, Opts) ->
    Req = p59_http:atender(Req0, eventos, fun manejar/2),
    {ok, Req, Opts}.

manejar(<<"GET">>, Req) ->
    Desde = case p59_http:entero_qs(Req, <<"desde">>) of {ok, D} -> D; _ -> 0 end,
    Limite = case p59_http:entero_qs(Req, <<"limite">>) of {ok, L} when L > 0 -> min(L, 500); _ -> 100 end,
    {200, #{eventos => p59_eventos:recientes(Desde, Limite)}};
manejar(_, _Req) ->
    p59_http:error(metodo_no_permitido).
