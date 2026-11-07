-module(p59_sucursal_sup).
-behaviour(supervisor).

%% Supervisor de la sucursal: ventas y cajas.
%% rest_for_one: si cae el supervisor de ventas (y con el todas las ventas en
%% memoria), las cajas se reinician despues y, al arrancar, reconstruyen desde
%% disco la venta que cada una tenia en curso. Si cae solo el supervisor de
%% cajas, las ventas no se tocan.

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    p59_metricas:inicio(?MODULE),
    Hijos = [#{id => p59_ventas_sup, start => {p59_ventas_sup, start_link, []},
               restart => permanent, shutdown => infinity, type => supervisor},
             #{id => p59_cajas_sup, start => {p59_cajas_sup, start_link, []},
               restart => permanent, shutdown => infinity, type => supervisor}],
    {ok, {#{strategy => rest_for_one, intensity => 5, period => 10}, Hijos}}.
