-module(p59_h_tickets).
-behaviour(cowboy_handler).

%% GET  /api/tickets?caja=&turno=         movimientos del libro (ventas y reembolsos)
%% GET  /api/tickets/:folio               ticket, reembolsos, texto imprimible
%% POST /api/tickets/:folio/cancelar      {"caja", "motivo"}
%% POST /api/tickets/:folio/devolucion    {"caja", "motivo", "operacion_id",
%%                                         "partidas": [{"producto_id", "cantidad"}]}

-export([init/2]).

init(Req0, Opts) ->
    Accion = maps:get(accion, Opts, consulta),
    Req = p59_http:atender(Req0, tickets, fun(M, R) -> manejar(Accion, M, R) end),
    {ok, Req, Opts}.

manejar(consulta, <<"GET">>, Req) ->
    case cowboy_req:binding(folio, Req) of
        undefined ->
            Filtro = maps:from_list([{K, N} || K <- [caja, turno],
                                               {ok, N} <- [p59_http:entero_qs(Req, atom_to_binary(K))]]),
            Movs = p59_inventario:tickets(Filtro),
            {200, #{total => length(Movs), movimientos => lists:sublist(Movs, 100)}};
        Folio ->
            case p59_inventario:ticket(Folio) of
                {ok, #{venta := V, reembolsos := R} = T} ->
                    {200, T#{texto => p59_ticket:texto(V, R),
                             impresion => p59_impresora:estado(Folio),
                             aviso => <<"Comprobante interno de demostración; no es un CFDI 4.0"/utf8>>}};
                {error, E} ->
                    p59_http:error(E)
            end
    end;
manejar(Tipo, <<"POST">>, Req0) when Tipo =:= cancelar; Tipo =:= devolucion ->
    case p59_http:leer_json(Req0) of
        {error, E, Req} ->
            erlang:append_element(p59_http:error(E), Req);
        {ok, Cuerpo, Req} ->
            Folio = cowboy_req:binding(folio, Req),
            erlang:append_element(reembolsar(Tipo, Folio, Cuerpo), Req)
    end;
manejar(_, _, _Req) ->
    p59_http:error(metodo_no_permitido).

reembolsar(Tipo, Folio, Cuerpo) ->
    CajaDefecto = case p59_inventario:ticket(Folio) of
                      {ok, #{venta := #{caja := C}}} -> C;
                      _ -> 1
                  end,
    Datos = {p59_http:campo(Cuerpo, <<"caja">>, entero, CajaDefecto),
             p59_http:campo(Cuerpo, <<"motivo">>, texto, <<"Sin motivo"/utf8>>),
             p59_http:campo(Cuerpo, <<"operacion_id">>, texto, null),
             unidades(Tipo, Cuerpo)},
    case Datos of
        {{ok, Caja}, {ok, Motivo}, {ok, Op}, {ok, Unidades}} ->
            Ctx = #{caja => Caja, motivo => Motivo, operacion_id => Op},
            TipoMov = case Tipo of cancelar -> cancelacion; devolucion -> devolucion end,
            case p59_inventario:reembolsar(TipoMov, Folio, Unidades, Ctx) of
                {ok, Mov} -> {201, Mov};
                {error, E} -> p59_http:error(E)
            end;
        _ ->
            p59_http:error(parametro_invalido)
    end.

unidades(cancelar, _Cuerpo) ->
    {ok, todo};
unidades(devolucion, Cuerpo) ->
    case p59_http:campo(Cuerpo, <<"partidas">>, lista, []) of
        {ok, Lista} ->
            U = [{P, Q} || #{<<"producto_id">> := P, <<"cantidad">> := Q} <- Lista,
                           is_binary(P), is_integer(Q)],
            case length(U) =:= length(Lista) of
                true -> {ok, U};
                false -> {error, parametro_invalido}
            end;
        Error -> Error
    end.
