-module(p59_punto_de_venta_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% Arbol (ver README, seccion "Arquitectura OTP"):
%%
%%   p59_punto_de_venta_sup        rest_for_one
%%   ├── p59_pg                    grupos pg para difundir eventos (SSE)
%%   ├── p59_servicios_sup         one_for_one: metricas, eventos, estado,
%%   │                             tipo de cambio, terminal, impresora
%%   ├── p59_almacen               tablas DETS
%%   ├── p59_inventario            catalogo, existencias, libro, turnos
%%   └── p59_sucursal_sup          rest_for_one
%%       ├── p59_ventas_sup        simple_one_for_one de p59_venta (transient)
%%       └── p59_cajas_sup         one_for_one de 4 p59_caja
%%
%% rest_for_one porque cada hijo depende de los anteriores: si cae el almacen
%% (disco), se reinicia todo lo que lo usa; si cae el inventario, la sucursal se
%% reinicia despues y las ventas se reconstruyen desde disco. Si cae una caja,
%% el problema se queda dentro de p59_cajas_sup.
init([]) ->
    Hijos = [#{id => p59_pg, start => {pg, start_link, [p59_pg]},
               restart => permanent, shutdown => 5000, type => worker},
             #{id => p59_servicios_sup, start => {p59_servicios_sup, start_link, []},
               restart => permanent, shutdown => infinity, type => supervisor},
             #{id => p59_almacen, start => {p59_almacen, start_link, []},
               restart => permanent, shutdown => 10000, type => worker},
             #{id => p59_inventario, start => {p59_inventario, start_link, []},
               restart => permanent, shutdown => 5000, type => worker},
             #{id => p59_sucursal_sup, start => {p59_sucursal_sup, start_link, []},
               restart => permanent, shutdown => infinity, type => supervisor}],
    {ok, {#{strategy => rest_for_one, intensity => 10, period => 60}, Hijos}}.
