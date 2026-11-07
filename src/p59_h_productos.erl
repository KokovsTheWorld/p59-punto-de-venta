-module(p59_h_productos).
-behaviour(cowboy_handler).

%% GET /api/productos?q=&categoria=&pagina=&limite=   GET /api/productos/:id

-export([init/2]).

init(Req0, Opts) ->
    Req = p59_http:atender(Req0, productos, fun manejar/2),
    {ok, Req, Opts}.

manejar(<<"GET">>, Req) ->
    case cowboy_req:binding(id, Req) of
        undefined -> listar(Req);
        Id ->
            case p59_inventario:producto(Id) of
                {ok, P} -> {200, vista(P)};
                {error, E} -> p59_http:error(E)
            end
    end;
manejar(_, _Req) ->
    p59_http:error(metodo_no_permitido).

listar(Req) ->
    Qs = cowboy_req:parse_qs(Req),
    Texto = string:lowercase(proplists:get_value(<<"q">>, Qs, <<>>)),
    Categoria = proplists:get_value(<<"categoria">>, Qs, <<>>),
    Pagina = numero(p59_http:entero_qs(Req, <<"pagina">>), 1),
    Limite = min(200, numero(p59_http:entero_qs(Req, <<"limite">>), 50)),
    Filtrados = [P || #{nombre := N, id := Id, categoria := C} = P <- p59_inventario:productos(),
                      Categoria =:= <<>> orelse C =:= Categoria,
                      Texto =:= <<>>
                          orelse string:find(string:lowercase(N), Texto) =/= nomatch
                          orelse string:find(string:lowercase(Id), Texto) =/= nomatch],
    Total = length(Filtrados),
    Pagina1 = lists:sublist(Filtrados, (max(Pagina, 1) - 1) * Limite + 1, Limite),
    {200, #{total => Total, pagina => Pagina, limite => Limite,
            categorias => [C || {C, _, _} <- p59_catalogo:categorias()],
            productos => [vista(P) || P <- Pagina1]}}.

vista(#{existencia := E, reservado := R} = P) ->
    P#{disponible => E - R}.

numero({ok, N}, _) when N > 0 -> N;
numero(_, Defecto) -> Defecto.
