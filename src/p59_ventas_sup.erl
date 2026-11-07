-module(p59_ventas_sup).
-behaviour(supervisor).

%% Un hijo p59_venta por venta en curso (simple_one_for_one, transient):
%%   - termina con normal al quedar pagada o cancelada y NO se reinicia;
%%   - si cae por error se reinicia y se reconstruye desde DETS.
%% Los argumentos del hijo son solo el Id: un reinicio nunca reutiliza un estado
%% viejo en memoria, siempre lee el ultimo guardado. Por eso quien crea una venta
%% (p59_caja) la escribe primero en disco y despues llama a reanudar/1.

-export([start_link/0, reanudar/1, activas/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% Arranca (o localiza, si ya corre) el proceso de una venta guardada.
-spec reanudar(binary()) -> {ok, pid() | finalizada} | {error, term()}.
reanudar(Id) ->
    case supervisor:start_child(?MODULE, [Id]) of
        {ok, undefined} -> {ok, finalizada};
        {ok, Pid} -> {ok, Pid};
        {error, {already_started, Pid}} -> {ok, Pid};
        {error, _} = Error -> Error
    end.

activas() ->
    try proplists:get_value(active, supervisor:count_children(?MODULE), 0)
    catch exit:_ -> 0
    end.

init([]) ->
    p59_metricas:inicio(?MODULE),
    Hijo = #{id => p59_venta,
             start => {p59_venta, start_link, []},
             restart => transient,
             shutdown => 5000,
             type => worker},
    {ok, {#{strategy => simple_one_for_one, intensity => 20, period => 10}, [Hijo]}}.
