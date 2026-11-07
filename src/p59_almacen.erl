-module(p59_almacen).
-behaviour(gen_server).

%% Dueno de las tablas DETS (persistencia local en disco). Las tablas quedan
%% abiertas mientras viva este proceso; cualquier proceso puede leer y escribir
%% en ellas por nombre. Si este proceso cae, el supervisor raiz (rest_for_one)
%% reinicia todo lo que depende del disco.

-export([start_link/0, tabla/1, leer/2, escribir/2, escribir_sync/2, insertar_nuevo/2,
         borrar/2, todos/1, siguiente/1, tablas/0]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2]).

%% ventas:        {VentaId, Snapshot}           estado vivo de cada venta
%% movimientos:   {{Tipo, Clave}, Movimiento}   libro mayor (fuente de verdad)
%% reservas:      {VentaId, [{ProductoId, Q}]}  unidades apartadas durante el cobro
%% turnos:        {Caja, Turno}                 turno vigente por caja
%% cortes:        {{Caja, Turno}, Corte}        cortes cerrados
%% cajas:         {Caja, Estado}                venta en curso de cada caja
%% idempotencia:  {OperacionId, Resultado}      claves de reintento
%% contadores:    {Nombre, N}                   folios
tablas() ->
    [ventas, movimientos, reservas, turnos, cortes, cajas, idempotencia, contadores].

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

tabla(Nombre) ->
    list_to_atom("p59_dets_" ++ atom_to_list(Nombre)).

leer(T, Clave) ->
    case dets:lookup(tabla(T), Clave) of
        [{_, Valor}] -> {ok, Valor};
        [] -> no_existe
    end.

escribir(T, {Clave, Valor}) ->
    ok = dets:insert(tabla(T), {Clave, Valor}).

%% Escribe y fuerza a disco. Se usa en los puntos de no retorno.
escribir_sync(T, Objeto) ->
    ok = escribir(T, Objeto),
    ok = dets:sync(tabla(T)).

insertar_nuevo(T, Objeto) ->
    dets:insert_new(tabla(T), Objeto).

borrar(T, Clave) ->
    ok = dets:delete(tabla(T), Clave).

todos(T) ->
    dets:foldl(fun(Obj, Acc) -> [Obj | Acc] end, [], tabla(T)).

siguiente(Contador) ->
    dets:update_counter(tabla(contadores), Contador, 1).

init([]) ->
    process_flag(trap_exit, true),
    Dir = p59_config:data_dir(),
    ok = filelib:ensure_path(Dir),
    [abrir(T, Dir) || T <- tablas()],
    [dets:insert_new(tabla(contadores), {C, 0}) || C <- [venta, ticket, reembolso]],
    logger:info("p59_almacen: tablas DETS abiertas en ~ts", [Dir]),
    p59_metricas:inicio(?MODULE),
    {ok, #{dir => Dir}}.

handle_call(dir, _From, #{dir := Dir} = S) ->
    {reply, Dir, S};
handle_call(_Msg, _From, S) ->
    {reply, {error, no_soportado}, S}.

handle_cast(_Msg, S) ->
    {noreply, S}.

terminate(_Reason, _S) ->
    [dets:close(tabla(T)) || T <- tablas()],
    ok.

abrir(T, Dir) ->
    Archivo = filename:join(Dir, atom_to_list(T) ++ ".dets"),
    {ok, _} = dets:open_file(tabla(T), [{file, Archivo}, {type, set},
                                        {repair, true}, {auto_save, 1000}]).
