-module(p59_h_ventas).
-behaviour(cowboy_handler).

%% POST /api/ventas                        {"caja", "operacion_id"}   (o cabecera Idempotency-Key)
%% GET  /api/ventas?estado=&caja=          GET /api/ventas/:id
%% POST /api/ventas/:id/partidas           {"producto_id", "cantidad", "descuento_pct"}
%% DELETE /api/ventas/:id/partidas/:producto
%% POST /api/ventas/:id/pago               {"operacion_id", "pagos": [{"metodo", "monto"}]}
%% POST /api/ventas/:id/revisar            resuelve una venta pendiente_de_revision
%% POST /api/ventas/:id/cancelar           {"motivo", "caja"}
%% Montos siempre en centavos enteros (USD en centavos de dolar).

-export([init/2]).

init(Req0, Opts) ->
    Accion = maps:get(accion, Opts, consulta),
    Req = p59_http:atender(Req0, ventas, fun(M, R) -> manejar(Accion, M, R) end),
    {ok, Req, Opts}.

manejar(consulta, <<"POST">>, Req0) ->
    con_cuerpo(Req0, fun(Cuerpo, Req) ->
        Op = operacion(Cuerpo, Req),
        case p59_http:campo(Cuerpo, <<"caja">>, entero, null) of
            {ok, Caja} when is_integer(Caja) ->
                case lists:member(Caja, p59_config:cajas()) of
                    true -> venta(p59_caja:iniciar_venta(Caja, Op), 201);
                    false -> p59_http:error(caja_no_encontrada)
                end;
            _ -> p59_http:error(caja_requerida)
        end
    end);
manejar(consulta, <<"GET">>, Req) ->
    case cowboy_req:binding(id, Req) of
        undefined -> listar(Req);
        Id -> venta(con_proceso(p59_venta:leer(Id)))
    end;
manejar(partidas, <<"POST">>, Req0) ->
    con_cuerpo(Req0, fun(Cuerpo, _Req) ->
        case {p59_http:campo(Cuerpo, <<"producto_id">>, texto, null),
              p59_http:campo(Cuerpo, <<"cantidad">>, entero, 1),
              p59_http:campo(Cuerpo, <<"descuento_pct">>, entero, 0)} of
            {{ok, P}, {ok, C}, {ok, D}} when is_binary(P) ->
                venta(p59_venta:agregar(cowboy_req:binding(id, Req0), P, C, D));
            _ -> p59_http:error(partida_invalida)
        end
    end);
manejar(partidas, <<"DELETE">>, Req) ->
    case cowboy_req:binding(producto, Req) of
        undefined -> p59_http:error(partida_no_encontrada);
        P -> venta(p59_venta:retirar(cowboy_req:binding(id, Req), P))
    end;
manejar(pago, <<"POST">>, Req0) ->
    con_cuerpo(Req0, fun(Cuerpo, Req) ->
        case pagos(Cuerpo) of
            {ok, Pagos} ->
                venta(p59_venta:pagar(cowboy_req:binding(id, Req), Pagos, operacion(Cuerpo, Req)));
            {error, E} ->
                p59_http:error(E)
        end
    end);
manejar(revisar, <<"POST">>, Req) ->
    venta(p59_venta:revisar(cowboy_req:binding(id, Req)));
manejar(cancelar, <<"POST">>, Req0) ->
    con_cuerpo(Req0, fun(Cuerpo, Req) ->
        Id = cowboy_req:binding(id, Req),
        {ok, Motivo} = motivo(Cuerpo),
        case p59_venta:leer(Id) of
            {ok, #{estado := pagada, folio := Folio, caja := CajaVenta}} ->
                %% Venta ya confirmada: la cancelacion es un movimiento nuevo.
                case p59_http:campo(Cuerpo, <<"caja">>, entero, CajaVenta) of
                    {ok, Caja} ->
                        case p59_inventario:reembolsar(cancelacion, Folio, todo,
                                                       #{caja => Caja, motivo => Motivo}) of
                            {ok, Mov} -> {200, #{cancelacion => Mov}};
                            {error, E} -> p59_http:error(E)
                        end;
                    {error, E} -> p59_http:error(E)
                end;
            {ok, _} ->
                venta(p59_venta:cancelar(Id, Motivo));
            {error, E} ->
                p59_http:error(E)
        end
    end);
manejar(_, _, _Req) ->
    p59_http:error(metodo_no_permitido).

listar(Req) ->
    Qs = cowboy_req:parse_qs(Req),
    Estado = proplists:get_value(<<"estado">>, Qs, <<>>),
    Caja = case p59_http:entero_qs(Req, <<"caja">>) of {ok, N} -> N; _ -> null end,
    Ventas = [maps:without([historial], V)
              || {_, #{estado := E, caja := C} = V} <- p59_almacen:todos(ventas),
                 Estado =:= <<>> orelse atom_to_binary(E) =:= Estado,
                 Caja =:= null orelse C =:= Caja],
    Ordenadas = lists:reverse(lists:keysort(1, [{maps:get(creada_en, V), V} || V <- Ventas])),
    {200, #{total => length(Ventas), ventas => [V || {_, V} <- lists:sublist(Ordenadas, 100)]}}.

%% pid del gen_statem si la venta sigue viva (las finalizadas ya no tienen proceso).
con_proceso({ok, #{id := Id} = V}) ->
    Proceso = case global:whereis_name({p59_venta, Id}) of
                  Pid when is_pid(Pid) -> list_to_binary(pid_to_list(Pid));
                  undefined -> null
              end,
    {ok, V#{proceso => Proceso}};
con_proceso(Otro) ->
    Otro.

pagos(Cuerpo) ->
    case p59_http:campo(Cuerpo, <<"pagos">>, lista, []) of
        {ok, Lista} ->
            Convertidos = [{p59_http:campo(P, <<"metodo">>, {atomo, p59_importes:metodos()}, null),
                            p59_http:campo(P, <<"monto">>, entero, null)}
                           || P <- Lista, is_map(P)],
            case length(Convertidos) =:= length(Lista)
                andalso lists:all(fun({{ok, M}, {ok, X}}) -> M =/= null andalso X =/= null;
                                     (_) -> false end, Convertidos) of
                true -> {ok, [#{metodo => M, monto => X} || {{ok, M}, {ok, X}} <- Convertidos]};
                false -> {error, pago_invalido}
            end;
        Error -> Error
    end.

operacion(Cuerpo, Req) ->
    case p59_http:campo(Cuerpo, <<"operacion_id">>, texto, null) of
        {ok, Op} when is_binary(Op) -> Op;
        _ -> cowboy_req:header(<<"idempotency-key">>, Req, null)
    end.

motivo(Cuerpo) ->
    case p59_http:campo(Cuerpo, <<"motivo">>, texto, <<"Sin motivo"/utf8>>) of
        {ok, M} -> {ok, M};
        _ -> {ok, <<"Sin motivo"/utf8>>}
    end.

con_cuerpo(Req0, Fun) ->
    case p59_http:leer_json(Req0) of
        {ok, Cuerpo, Req} -> erlang:append_element(Fun(Cuerpo, Req), Req);
        {error, E, Req} -> erlang:append_element(p59_http:error(E), Req)
    end.

venta(R) -> venta(R, 200).

venta({ok, V}, Status) -> {Status, V};
venta({pendiente, V}, _) -> {202, V};
venta({error, E}, _) -> p59_http:error(E).
