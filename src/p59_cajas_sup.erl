-module(p59_cajas_sup).
-behaviour(supervisor).

%% one_for_one: las cajas son independientes; si cae la caja 2, las otras tres
%% siguen cobrando y solo la 2 se reinicia.

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    p59_metricas:inicio(?MODULE),
    Cajas = [#{id => p59_caja:nombre(N),
               start => {p59_caja, start_link, [N]},
               restart => permanent,
               shutdown => 5000,
               type => worker} || N <- p59_config:cajas()],
    {ok, {#{strategy => one_for_one, intensity => 10, period => 10}, Cajas}}.
