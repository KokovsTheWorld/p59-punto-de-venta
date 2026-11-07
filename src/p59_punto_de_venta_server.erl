-module(p59_punto_de_venta_server).
-behaviour(gen_server).

%% Servicio de estado del sistema: responde ping y datos generales del nodo
%% (version, arranque) para /api/health y /api/estado.

-export([start_link/0, ping/0, state/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

ping() ->
  gen_server:call(?MODULE, ping).

state() ->
  gen_server:call(?MODULE, state).

%% Estado como mapa para poder agregar campos del dominio sin romper los callbacks.
init([]) ->
  logger:info("~s iniciado", [?MODULE], #{proyecto => p59_punto_de_venta}),
  p59_metricas:inicio(?MODULE),
  {ok, #{iniciado_en => erlang:system_time(second)}}.

handle_call(ping, _From, State) ->
  {reply, pong, State};
handle_call(state, _From, #{iniciado_en := Inicio} = State) ->
  {ok, Vsn} = application:get_key(p59_punto_de_venta, vsn),
  Info = State#{nodo => node(),
                version => list_to_binary(Vsn),
                otp => list_to_binary(erlang:system_info(otp_release)),
                segundos_activo => erlang:system_time(second) - Inicio,
                iva_general_pb => p59_config:iva_general_pb()},
  {reply, Info, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.
