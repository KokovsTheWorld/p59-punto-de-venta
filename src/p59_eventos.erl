-module(p59_eventos).
-behaviour(gen_server).

%% Bitacora de eventos y alertas. Guarda los ultimos ?MAX en ETS y los difunde a
%% los suscriptores (conexiones SSE) mediante el grupo pg ?GRUPO. La bitacora es
%% informativa: lo contable vive en el libro de movimientos, no aqui.

-export([start_link/0, publicar/4, recientes/2, suscribir/0, mensaje/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(TAB, p59_eventos_tab).
-define(MAX, 500).
-define(SCOPE, p59_pg).
-define(GRUPO, eventos).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Nivel: ok | alerta | falla. Nunca bloquea ni falla al publicador.
-spec publicar(atom(), ok | alerta | falla, iodata(), map()) -> ok.
publicar(Tipo, Nivel, Mensaje, Datos) ->
    gen_server:cast(?MODULE, {publicar, Tipo, Nivel, unicode:characters_to_binary(Mensaje), Datos}).

-spec recientes(non_neg_integer(), pos_integer()) -> [map()].
recientes(Desde, Limite) ->
    case ets:whereis(?TAB) of
        undefined -> [];
        _ ->
            Eventos = ets:select_reverse(?TAB, [{{'$1', '$2'}, [{'>', '$1', Desde}], ['$2']}],
                                         Limite),
            case Eventos of
                {Lista, _Cont} -> Lista;
                '$end_of_table' -> []
            end
    end.

suscribir() ->
    pg:join(?SCOPE, ?GRUPO, self()).

mensaje(Evento) ->
    {p59_evento, Evento}.

init([]) ->
    ets:new(?TAB, [ordered_set, protected, named_table, {read_concurrency, true}]),
    {ok, #{seq => 0}}.

handle_call(_Msg, _From, S) ->
    {reply, {error, no_soportado}, S}.

handle_cast({publicar, Tipo, Nivel, Mensaje, Datos}, #{seq := Seq0} = S) ->
    Seq = Seq0 + 1,
    Evento = #{seq => Seq, ts => erlang:system_time(millisecond), tipo => Tipo,
               nivel => Nivel, mensaje => Mensaje, datos => Datos},
    ets:insert(?TAB, {Seq, Evento}),
    ets:delete(?TAB, Seq - ?MAX),
    [P ! mensaje(Evento) || P <- pg:get_members(?SCOPE, ?GRUPO)],
    {noreply, S#{seq := Seq}}.
