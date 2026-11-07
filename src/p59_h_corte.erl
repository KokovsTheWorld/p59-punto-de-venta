-module(p59_h_corte).
-behaviour(cowboy_handler).

%% GET /api/corte                         consolidado de las cajas (turnos vigentes)
%% GET /api/corte?caja=2                  turno vigente de la caja 2
%% GET /api/corte?caja=2&turno=1          un turno concreto (cerrado o vigente)
%% GET /api/corte?cajero=Ana              todos los movimientos de un cajero

-export([init/2]).

init(Req0, Opts) ->
    Req = p59_http:atender(Req0, corte, fun manejar/2),
    {ok, Req, Opts}.

manejar(<<"GET">>, Req) ->
    Cajero = proplists:get_value(<<"cajero">>, cowboy_req:parse_qs(Req)),
    Filtro = case {p59_http:entero_qs(Req, <<"caja">>), p59_http:entero_qs(Req, <<"turno">>),
                   Cajero} of
                 {invalido, _, _} -> invalido;
                 {_, invalido, _} -> invalido;
                 {{ok, C}, {ok, T}, _} -> #{caja => C, turno => T};
                 {{ok, C}, ausente, _} -> #{caja => C};
                 {ausente, _, Nombre} when is_binary(Nombre) -> #{cajero => Nombre};
                 _ -> #{}
             end,
    case Filtro of
        invalido -> p59_http:error(parametro_invalido);
        _ ->
            case p59_inventario:corte(Filtro) of
                {ok, Corte} -> {200, Corte};
                {error, E} -> p59_http:error(E)
            end
    end;
manejar(_, _Req) ->
    p59_http:error(metodo_no_permitido).
