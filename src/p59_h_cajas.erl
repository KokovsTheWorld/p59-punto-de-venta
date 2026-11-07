-module(p59_h_cajas).
-behaviour(cowboy_handler).

%% GET  /api/cajas                  GET /api/cajas/:id
%% POST /api/cajas/:id/turno        {"cajero", "fondo_mxn"}          abre turno
%% POST /api/cajas/:id/turno/cerrar {"efectivo_contado_mxn", "efectivo_contado_usd"}

-export([init/2]).

init(Req0, Opts) ->
    Accion = maps:get(accion, Opts, consulta),
    Req = p59_http:atender(Req0, cajas, fun(M, R) -> manejar(Accion, M, R) end),
    {ok, Req, Opts}.

manejar(consulta, <<"GET">>, Req) ->
    case cowboy_req:binding(id, Req) of
        undefined -> {200, #{cajas => [C || {ok, C} <- p59_caja:todas()]}};
        Id -> con_caja(Id, fun(N) -> resultado(p59_caja:info(N)) end)
    end;
manejar(abrir_turno, <<"POST">>, Req0) ->
    con_cuerpo(Req0, fun(Cuerpo) ->
        con_caja(cowboy_req:binding(id, Req0), fun(N) ->
            case {p59_http:campo(Cuerpo, <<"cajero">>, texto, null),
                  p59_http:campo(Cuerpo, <<"fondo_mxn">>, entero,
                                 p59_config:obtener(fondo_inicial))} of
                {{ok, Cajero}, {ok, Fondo}} when is_binary(Cajero), Cajero =/= <<>> ->
                    resultado(p59_inventario:abrir_turno(N, Cajero, Fondo), 201);
                _ ->
                    p59_http:error(cajero_requerido)
            end
        end)
    end);
manejar(cerrar_turno, <<"POST">>, Req0) ->
    con_cuerpo(Req0, fun(Cuerpo) ->
        con_caja(cowboy_req:binding(id, Req0), fun(N) ->
            case {p59_http:campo(Cuerpo, <<"efectivo_contado_mxn">>, entero, null),
                  p59_http:campo(Cuerpo, <<"efectivo_contado_usd">>, entero, 0)} of
                {{ok, Mxn}, {ok, Usd}} when is_integer(Mxn) ->
                    resultado(p59_inventario:cerrar_turno(N, #{mxn => Mxn, usd => Usd}));
                _ ->
                    p59_http:error(conteo_requerido)
            end
        end)
    end);
manejar(_, _, _Req) ->
    p59_http:error(metodo_no_permitido).

con_caja(Id, Fun) ->
    try binary_to_integer(Id) of
        N -> case lists:member(N, p59_config:cajas()) of
                 true -> Fun(N);
                 false -> p59_http:error(caja_no_encontrada)
             end
    catch error:badarg -> p59_http:error(caja_no_encontrada)
    end.

con_cuerpo(Req0, Fun) ->
    case p59_http:leer_json(Req0) of
        {ok, Cuerpo, Req} -> erlang:append_element(Fun(Cuerpo), Req);
        {error, E, Req} -> erlang:append_element(p59_http:error(E), Req)
    end.

resultado(R) -> resultado(R, 200).

resultado({ok, V}, Status) -> {Status, V};
resultado({error, E}, _) -> p59_http:error(E).
