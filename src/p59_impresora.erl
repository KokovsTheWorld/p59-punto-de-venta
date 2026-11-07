-module(p59_impresora).
-behaviour(gen_server).

%% Impresora de tickets SIMULADA. Imprimir es posterior a la confirmacion y
%% asincrono: una impresora atascada deja tickets pendientes de imprimir, pero
%% nunca deshace ni retrasa una venta ya confirmada.

-export([start_link/0, imprimir/1, estado/1, fijar_modo/1, pendientes/0]).
-export([init/1, handle_call/3, handle_cast/2]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

imprimir(Folio) ->
    gen_server:cast(?MODULE, {imprimir, Folio}).

estado(Folio) ->
    try gen_server:call(?MODULE, {estado, Folio}, 1000)
    catch exit:_ -> desconocido
    end.

pendientes() ->
    gen_server:call(?MODULE, pendientes).

fijar_modo(Modo) when Modo =:= ok; Modo =:= atascada ->
    gen_server:call(?MODULE, {modo, Modo});
fijar_modo(_) ->
    {error, modo_invalido}.

init([]) ->
    p59_metricas:inicio(?MODULE),
    {ok, #{modo => ok, impresos => #{}, pendientes => []}}.

handle_call({estado, Folio}, _From, #{impresos := I, pendientes := P} = S) ->
    Estado = case {maps:is_key(Folio, I), lists:member(Folio, P)} of
                 {true, _} -> impreso;
                 {_, true} -> pendiente;
                 _ -> desconocido
             end,
    {reply, Estado, S};
handle_call(pendientes, _From, #{pendientes := P} = S) ->
    {reply, lists:reverse(P), S};
handle_call({modo, ok}, _From, #{pendientes := P} = S) ->
    S1 = lists:foldl(fun marcar_impreso/2, S#{modo := ok, pendientes := []}, lists:reverse(P)),
    p59_eventos:publicar(impresora, ok, [<<"Impresora en línea; reimpresos: "/utf8>>,
                                         integer_to_binary(length(P))], #{}),
    {reply, ok, S1};
handle_call({modo, atascada}, _From, S) ->
    p59_eventos:publicar(impresora, falla, <<"Impresora atascada"/utf8>>, #{}),
    {reply, ok, S#{modo := atascada}}.

handle_cast({imprimir, Folio}, #{modo := ok} = S) ->
    {noreply, marcar_impreso(Folio, S)};
handle_cast({imprimir, Folio}, #{modo := atascada, pendientes := P} = S) ->
    p59_eventos:publicar(impresora, alerta,
                         [<<"Ticket pendiente de imprimir "/utf8>>, Folio], #{folio => Folio}),
    {noreply, S#{pendientes := [Folio | P]}}.

marcar_impreso(Folio, #{impresos := I} = S) ->
    S#{impresos := I#{Folio => erlang:system_time(millisecond)}}.
