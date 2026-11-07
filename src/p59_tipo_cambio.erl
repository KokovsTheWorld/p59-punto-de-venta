-module(p59_tipo_cambio).
-behaviour(gen_server).

%% Tipo de cambio MXN/USD simulado y variable. No consulta ningun servicio
%% externo: camina aleatoriamente +/-0.3 % cada tipo_cambio_variacion_ms y puede
%% fijarse a mano desde la API. Cada venta registra el valor que uso.

-export([start_link/0, actual/0, fijar/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(MIN, 100000).  % 10.0000
-define(MAX, 300000).  % 30.0000

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec actual() -> #{valor := pos_integer(), actualizado_en := integer()}.
actual() ->
    gen_server:call(?MODULE, actual).

fijar(Valor) when is_integer(Valor), Valor >= ?MIN, Valor =< ?MAX ->
    gen_server:call(?MODULE, {fijar, Valor});
fijar(_) ->
    {error, tipo_de_cambio_fuera_de_rango}.

init([]) ->
    p59_metricas:inicio(?MODULE),
    programar(),
    {ok, #{valor => p59_config:obtener(tipo_cambio_inicial),
           actualizado_en => erlang:system_time(millisecond),
           rand => rand:seed_s(exsss, 2026)}}.

handle_call(actual, _From, S) ->
    {reply, maps:with([valor, actualizado_en], S), S};
handle_call({fijar, Valor}, _From, S) ->
    S1 = actualizar(Valor, S),
    {reply, ok, S1}.

handle_cast(_Msg, S) ->
    {noreply, S}.

handle_info(variar, #{valor := V, rand := R0} = S) ->
    {Paso, R1} = rand:uniform_s(61, R0),
    Nuevo = max(?MIN, min(?MAX, V + V * (Paso - 31) div 10000)),
    programar(),
    {noreply, actualizar(Nuevo, S#{rand := R1})};
handle_info(_Msg, S) ->
    {noreply, S}.

actualizar(Valor, S) ->
    p59_eventos:publicar(tipo_cambio, ok,
                         [<<"Tipo de cambio: "/utf8>>, p59_dinero:formatear_tc(Valor)],
                         #{valor => Valor}),
    S#{valor := Valor, actualizado_en := erlang:system_time(millisecond)}.

programar() ->
    case p59_config:obtener(tipo_cambio_variacion_ms) of
        Ms when is_integer(Ms), Ms > 0 -> erlang:send_after(Ms, self(), variar);
        _ -> ok
    end.
