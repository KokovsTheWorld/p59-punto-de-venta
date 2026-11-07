-module(p59_metricas).
-behaviour(gen_server).

%% Contadores operativos en ETS publica (escritura directa sin pasar por el
%% proceso) y exposicion en formato de texto de Prometheus. Las cifras contables
%% (ventas, cancelaciones...) no se cuentan aqui: se derivan del libro, asi
%% /metrics nunca contradice al corte aunque este proceso se reinicie.

-export([start_link/0, incrementar/1, incrementar/2, latencia/2, inicio/1, valor/1,
         reinicios/0, prometheus/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(TAB, p59_metricas_tab).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

incrementar(Clave) ->
    incrementar(Clave, 1).

incrementar(Clave, N) ->
    try ets:update_counter(?TAB, Clave, N, {Clave, 0}) of
        _ -> ok
    catch error:badarg -> ok
    end.

latencia(Ruta, Microsegundos) ->
    incrementar({latencia_us, Ruta}, Microsegundos),
    incrementar({solicitudes, Ruta}, 1).

%% Cada proceso importante lo llama en init/1: el numero de inicios menos uno
%% es el numero de reinicios hechos por su supervisor.
inicio(Proceso) ->
    incrementar({inicios, Proceso}).

valor(Clave) ->
    try ets:lookup(?TAB, Clave) of
        [{_, V}] -> V;
        [] -> 0
    catch error:badarg -> 0
    end.

reinicios() ->
    try ets:match(?TAB, {{inicios, '$1'}, '$2'}) of
        Filas -> maps:from_list([{P, N - 1} || [P, N] <- Filas])
    catch error:badarg -> #{}
    end.

prometheus() ->
    Libro = p59_inventario:resumen(),
    Gauges =
        [{p59_ventas_confirmadas_total, counter, "Ventas confirmadas en el libro",
          maps:get(ventas, Libro)},
         {p59_ventas_canceladas_total, counter, "Tickets cancelados",
          maps:get(cancelaciones, Libro)},
         {p59_devoluciones_total, counter, "Devoluciones registradas",
          maps:get(devoluciones, Libro)},
         {p59_importe_vendido_centavos, counter, "Importe total vendido (centavos MXN)",
          maps:get(importe_vendido, Libro)},
         {p59_ventas_en_proceso, gauge, "Ventas abiertas, en cobro o en revision",
          p59_ventas_sup:activas()},
         {p59_cajas_activas, gauge, "Procesos de caja vivos", p59_caja:activas()},
         {p59_productos, gauge, "Productos en catalogo", maps:get(productos, Libro)},
         {p59_productos_agotados, gauge, "Productos activos sin existencia",
          maps:get(agotados, Libro)},
         {p59_errores_pago_total, counter, "Cobros rechazados o sin respuesta de terminal",
          valor(errores_pago)},
         {p59_pagos_en_revision_total, counter, "Ventas enviadas a revision",
          valor(ventas_en_revision)},
         {p59_reintentos_idempotentes_total, counter, "Solicitudes repetidas absorbidas",
          valor(reintentos_idempotentes)},
         {p59_sin_existencia_total, counter, "Intentos rechazados por falta de existencia",
          valor(sin_existencia)},
         {p59_descuadres_total, counter, "Turnos cerrados con diferencia",
          maps:get(descuadres, Libro)},
         {p59_procesos_erlang, gauge, "Procesos en la VM", erlang:system_info(process_count)},
         {p59_memoria_bytes, gauge, "Memoria total de la VM", erlang:memory(total)}],
    [[linea_simple(G) || G <- Gauges],
     familia(p59_reinicios_total, counter, "Reinicios por proceso supervisado",
             [{[{proceso, P}], N} || {P, N} <- maps:to_list(reinicios())]),
     familia(p59_http_solicitudes_total, counter, "Solicitudes HTTP por ruta",
             [{[{ruta, R}], valor({solicitudes, R})} || R <- rutas()]),
     familia(p59_http_latencia_microsegundos_suma, counter,
             "Suma de latencias HTTP por ruta (dividir entre solicitudes)",
             [{[{ruta, R}], valor({latencia_us, R})} || R <- rutas()])].

rutas() ->
    try ets:match(?TAB, {{solicitudes, '$1'}, '_'}) of
        Filas -> lists:sort([R || [R] <- Filas])
    catch error:badarg -> []
    end.

linea_simple({Nombre, Tipo, Ayuda, Valor}) ->
    familia(Nombre, Tipo, Ayuda, [{[], Valor}]).

familia(Nombre, Tipo, Ayuda, Muestras) ->
    N = atom_to_list(Nombre),
    ["# HELP ", N, " ", Ayuda, "\n# TYPE ", N, " ", atom_to_list(Tipo), "\n",
     [[N, etiquetas(Ets), " ", integer_to_list(V), "\n"] || {Ets, V} <- Muestras]].

etiquetas([]) -> [];
etiquetas(Ets) ->
    ["{", lists:join(",", [[atom_to_list(K), "=\"", texto(V), "\""] || {K, V} <- Ets]), "}"].

texto(V) when is_atom(V) -> atom_to_list(V);
texto(V) when is_binary(V) -> V.

init([]) ->
    ets:new(?TAB, [set, public, named_table, {write_concurrency, true}]),
    {ok, #{}}.

handle_call(_Msg, _From, S) ->
    {reply, {error, no_soportado}, S}.

handle_cast(_Msg, S) ->
    {noreply, S}.
