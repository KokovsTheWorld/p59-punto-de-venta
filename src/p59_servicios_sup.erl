-module(p59_servicios_sup).
-behaviour(supervisor).

%% Servicios auxiliares independientes entre si (one_for_one). Ninguno guarda
%% informacion contable: si uno se reinicia, solo se pierden contadores o la
%% bitacora reciente, nunca ventas.

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Hijos = [trabajador(M) || M <- [p59_metricas, p59_eventos, p59_punto_de_venta_server,
                                    p59_tipo_cambio, p59_terminal_bancaria, p59_impresora]],
    {ok, {#{strategy => one_for_one, intensity => 10, period => 10}, Hijos}}.

trabajador(M) ->
    #{id => M, start => {M, start_link, []}, restart => permanent,
      shutdown => 5000, type => worker}.
