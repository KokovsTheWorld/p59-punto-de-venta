-module(p59_test_util).

%% Arranque aislado de la aplicacion para pruebas: cada fixture usa su propio
%% directorio de datos temporal, puerto aleatorio y una terminal con timeout corto.

-export([arrancar/0, detener/1, reiniciar_app/1, dir_temporal/0]).

arrancar() ->
    Dir = dir_temporal(),
    iniciar(Dir),
    Dir.

detener(Dir) ->
    application:stop(p59_punto_de_venta),
    file:del_dir_r(Dir),
    ok.

%% Para la app y la vuelve a levantar sobre los MISMOS archivos (simula un apagon).
reiniciar_app(Dir) ->
    ok = application:stop(p59_punto_de_venta),
    iniciar(Dir).

iniciar(Dir) ->
    logger:set_primary_config(level, error),
    _ = application:load(p59_punto_de_venta),
    [application:set_env(p59_punto_de_venta, K, V)
     || {K, V} <- [{data_dir, Dir}, {puerto, 0}, {terminal_timeout_ms, 300},
                   {tipo_cambio_variacion_ms, 0}, {tipo_cambio_inicial, 182000}]],
    {ok, _} = application:ensure_all_started(p59_punto_de_venta),
    ok.

dir_temporal() ->
    Base = filename:join(["_build", "test", "datos"]),
    Dir = filename:join(Base, integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(Dir),
    Dir.
