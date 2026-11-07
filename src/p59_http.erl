-module(p59_http).

%% Utilidades comunes de los manejadores Cowboy: respuesta JSON, lectura y
%% validacion del cuerpo, traduccion de errores del dominio a codigos HTTP y
%% medicion de latencia. Ningun error interno se filtra al cliente.

-compile({no_auto_import, [error/1]}).
-export([atender/3, leer_json/1, campo/4, entero_qs/2, error/1, rutas/0]).

-type respuesta() :: {cowboy:http_status(), term()} | {cowboy:http_status(), term(), cowboy_req:req()}.

rutas() ->
    [{"/api/health", p59_h_sistema, #{accion => health}},
     {"/api/estado", p59_h_sistema, #{accion => estado}},
     {"/api/diagnostico", p59_h_sistema, #{accion => diagnostico}},
     {"/api/tipo-cambio", p59_h_sistema, #{accion => tipo_cambio}},
     {"/api/productos", p59_h_productos, #{}},
     {"/api/productos/:id", p59_h_productos, #{}},
     {"/api/cajas", p59_h_cajas, #{}},
     {"/api/cajas/:id", p59_h_cajas, #{}},
     {"/api/cajas/:id/turno", p59_h_cajas, #{accion => abrir_turno}},
     {"/api/cajas/:id/turno/cerrar", p59_h_cajas, #{accion => cerrar_turno}},
     {"/api/ventas", p59_h_ventas, #{}},
     {"/api/ventas/:id", p59_h_ventas, #{}},
     {"/api/ventas/:id/partidas", p59_h_ventas, #{accion => partidas}},
     {"/api/ventas/:id/partidas/:producto", p59_h_ventas, #{accion => partidas}},
     {"/api/ventas/:id/pago", p59_h_ventas, #{accion => pago}},
     {"/api/ventas/:id/revisar", p59_h_ventas, #{accion => revisar}},
     {"/api/ventas/:id/cancelar", p59_h_ventas, #{accion => cancelar}},
     {"/api/tickets", p59_h_tickets, #{}},
     {"/api/tickets/:folio", p59_h_tickets, #{}},
     {"/api/tickets/:folio/cancelar", p59_h_tickets, #{accion => cancelar}},
     {"/api/tickets/:folio/devolucion", p59_h_tickets, #{accion => devolucion}},
     {"/api/corte", p59_h_corte, #{}},
     {"/api/eventos", p59_h_eventos, #{}},
     {"/api/eventos/stream", p59_sse_h, #{}},
     {"/api/simulacion/:accion", p59_h_simulacion, #{}},
     {"/api/simulacion/escenarios/:letra", p59_h_simulacion, #{accion => escenario}},
     {"/metrics", p59_h_metricas, #{}},
     {"/", cowboy_static, {priv_file, p59_punto_de_venta, "www/index.html"}},
     {"/[...]", cowboy_static, {priv_dir, p59_punto_de_venta, "www", [{mimetypes, cow_mimetypes, all}]}}].

%% Envuelve un manejador: mide, captura excepciones y responde JSON.
-spec atender(cowboy_req:req(), atom(), fun((binary(), cowboy_req:req()) -> respuesta())) ->
    cowboy_req:req().
atender(Req0, Ruta, Fun) ->
    T0 = erlang:monotonic_time(microsecond),
    Req = try Fun(cowboy_req:method(Req0), Req0) of
              {Status, Cuerpo} -> responder(Status, Cuerpo, Req0);
              {Status, Cuerpo, Req1} -> responder(Status, Cuerpo, Req1)
          catch
              Clase:Razon:Pila ->
                  logger:error("p59_http ~p: ~p:~p ~p", [Ruta, Clase, Razon, Pila]),
                  {S, C} = error(error_interno),
                  responder(S, C, Req0)
          end,
    p59_metricas:latencia(Ruta, erlang:monotonic_time(microsecond) - T0),
    Req.

responder(Status, Cuerpo, Req) ->
    cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json; charset=utf-8">>,
                               <<"cache-control">> => <<"no-store">>},
                     json:encode(Cuerpo), Req).

leer_json(Req0) ->
    case cowboy_req:has_body(Req0) of
        false ->
            {ok, #{}, Req0};
        true ->
            {ok, Cuerpo, Req} = cowboy_req:read_body(Req0, #{length => 65536}),
            try json:decode(Cuerpo) of
                Mapa when is_map(Mapa) -> {ok, Mapa, Req};
                _ -> {error, json_invalido, Req}
            catch error:_ -> {error, json_invalido, Req}
            end
    end.

%% Tipos admitidos: entero (>= 0), texto, atomo (de una lista cerrada), lista, mapa.
campo(Mapa, Clave, Tipo, Defecto) ->
    case maps:get(Clave, Mapa, ausente) of
        ausente -> {ok, Defecto};
        null -> {ok, Defecto};
        V -> convertir(V, Tipo)
    end.

convertir(V, entero) when is_integer(V), V >= 0 -> {ok, V};
convertir(V, texto) when is_binary(V), byte_size(V) =< 200 -> {ok, V};
convertir(V, {atomo, Permitidos}) when is_binary(V) ->
    case [A || A <- Permitidos, atom_to_binary(A) =:= V] of
        [A] -> {ok, A};
        [] -> {error, {parametro_invalido, V}}
    end;
convertir(V, lista) when is_list(V) -> {ok, V};
convertir(V, mapa) when is_map(V) -> {ok, V};
convertir(V, _Tipo) -> {error, {parametro_invalido, V}}.

entero_qs(Req, Nombre) ->
    case lists:keyfind(Nombre, 1, cowboy_req:parse_qs(Req)) of
        false -> ausente;
        {_, Valor} ->
            try binary_to_integer(Valor) of
                N when N >= 0 -> {ok, N};
                _ -> invalido
            catch error:badarg -> invalido
            end
    end.

%% Traduccion de errores del dominio a HTTP. Lo no previsto es 500 generico.
-spec error(term()) -> {cowboy:http_status(), map()}.
error({Codigo, Detalle}) when is_atom(Codigo) ->
    {Status, Cuerpo} = error(Codigo),
    {Status, Cuerpo#{detalle => detalle(Detalle)}};
error(Codigo) when is_atom(Codigo) ->
    {status(Codigo), #{error => Codigo, mensaje => mensaje(Codigo)}};
error(_) ->
    error(error_interno).

detalle(D) when is_binary(D); is_integer(D); is_atom(D) -> D;
detalle(D) when is_list(D) -> [detalle(X) || X <- D];
detalle(_) -> null.

status(C) when C =:= venta_no_encontrada; C =:= ticket_no_encontrado;
               C =:= producto_no_encontrado; C =:= caja_no_encontrada;
               C =:= turno_no_encontrado; C =:= partida_no_encontrada;
               C =:= ruta_no_encontrada -> 404;
status(C) when C =:= sin_existencia; C =:= venta_en_curso; C =:= venta_ya_pagada;
               C =:= venta_finalizada; C =:= transicion_invalida; C =:= turno_cerrado;
               C =:= turno_abierto; C =:= ticket_cancelado;
               C =:= venta_pagada_usar_cancelacion_de_ticket -> 409;
status(rechazada) -> 402;
status(metodo_no_permitido) -> 405;
status(json_invalido) -> 400;
status(C) when C =:= fuera_de_linea; C =:= tiempo_agotado; C =:= venta_no_disponible;
               C =:= caja_no_disponible; C =:= inventario_no_disponible;
               C =:= terminal_sin_respuesta -> 503;
status(error_interno) -> 500;
status(_Validacion) -> 422.

mensaje(venta_no_encontrada) -> <<"La venta no existe"/utf8>>;
mensaje(ticket_no_encontrado) -> <<"El ticket no existe"/utf8>>;
mensaje(producto_no_encontrado) -> <<"El producto no existe"/utf8>>;
mensaje(caja_no_encontrada) -> <<"La caja no existe"/utf8>>;
mensaje(turno_no_encontrado) -> <<"El turno no existe"/utf8>>;
mensaje(partida_no_encontrada) -> <<"La partida no está en la venta"/utf8>>;
mensaje(ruta_no_encontrada) -> <<"Ruta no encontrada"/utf8>>;
mensaje(sin_existencia) -> <<"No hay existencia suficiente"/utf8>>;
mensaje(venta_en_curso) -> <<"La caja ya tiene una venta en curso"/utf8>>;
mensaje(venta_ya_pagada) -> <<"La venta ya fue pagada con otra operación"/utf8>>;
mensaje(venta_finalizada) -> <<"La venta ya terminó"/utf8>>;
mensaje(transicion_invalida) -> <<"Operación no permitida en el estado actual"/utf8>>;
mensaje(turno_cerrado) -> <<"El turno de la caja está cerrado"/utf8>>;
mensaje(turno_abierto) -> <<"La caja ya tiene un turno abierto"/utf8>>;
mensaje(ticket_cancelado) -> <<"El ticket ya fue cancelado"/utf8>>;
mensaje(venta_pagada_usar_cancelacion_de_ticket) ->
    <<"La venta está pagada: cancele el ticket"/utf8>>;
mensaje(rechazada) -> <<"La terminal rechazó el cargo"/utf8>>;
mensaje(fuera_de_linea) -> <<"Terminal fuera de línea; no se realizó el cargo"/utf8>>;
mensaje(tiempo_agotado) -> <<"La operación tardó demasiado; reintente con la misma operacion_id"/utf8>>;
mensaje(terminal_sin_respuesta) -> <<"La terminal no responde"/utf8>>;
mensaje(json_invalido) -> <<"El cuerpo no es JSON válido"/utf8>>;
mensaje(venta_vacia) -> <<"La venta no tiene partidas"/utf8>>;
mensaje(pago_insuficiente) -> <<"El pago no cubre el total"/utf8>>;
mensaje(tarjeta_excede_total) -> <<"El cargo a tarjeta excede el total"/utf8>>;
mensaje(sin_tipo_de_cambio) -> <<"No hay tipo de cambio disponible"/utf8>>;
mensaje(metodo_no_permitido) -> <<"Método HTTP no permitido"/utf8>>;
mensaje(error_interno) -> <<"Error interno; consulte la bitácora del servidor"/utf8>>;
mensaje(C) -> atom_to_binary(C).
