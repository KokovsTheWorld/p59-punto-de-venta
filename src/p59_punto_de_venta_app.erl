-module(p59_punto_de_venta_app).
-behaviour(application).

-export([start/2, prep_stop/1, stop/1]).

-define(LISTENER, p59_http).

%% Primero el arbol OTP (dominio) y despues el listener HTTP: Cowboy solo acepta
%% conexiones cuando las cajas y el inventario ya estan listos.
start(_StartType, _StartArgs) ->
  {ok, Sup} = p59_punto_de_venta_sup:start_link(),
  Rutas = cowboy_router:compile([{'_', p59_http:rutas()}]),
  case cowboy:start_clear(?LISTENER, [{port, p59_config:puerto()}],
                          #{env => #{dispatch => Rutas}}) of
    {ok, _} ->
      logger:info("p59_punto_de_venta escuchando en el puerto ~b", [ranch:get_port(?LISTENER)]),
      {ok, Sup};
    {error, Razon} ->
      {error, {http, Razon}}
  end.

prep_stop(State) ->
  _ = cowboy:stop_listener(?LISTENER),
  State.

stop(_State) ->
  ok.
