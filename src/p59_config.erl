-module(p59_config).

%% Lectura centralizada de la configuracion. Las variables de entorno P59_*
%% tienen prioridad sobre sys.config para poder ajustar el release sin recompilar.

-export([obtener/1, data_dir/0, puerto/0, cajas/0, iva_general_pb/0]).

-define(APP, p59_punto_de_venta).

-spec obtener(atom()) -> term().
obtener(Clave) ->
    application:get_env(?APP, Clave, predeterminado(Clave)).

data_dir() ->
    case os:getenv("P59_DATA_DIR") of
        false -> obtener(data_dir);
        Dir -> Dir
    end.

puerto() ->
    case os:getenv("P59_PUERTO") of
        false -> obtener(puerto);
        P -> list_to_integer(P)
    end.

cajas() ->
    lists:seq(1, obtener(num_cajas)).

iva_general_pb() ->
    obtener(iva_general_pb).

predeterminado(data_dir) -> "data";
predeterminado(puerto) -> 8059;
predeterminado(num_cajas) -> 4;
predeterminado(num_productos) -> 800;
predeterminado(semilla_catalogo) -> 59;
%% 16 % general; 800 para el estimulo de la region fronteriza norte (ver README).
predeterminado(iva_general_pb) -> 1600;
%% Diezmilesimos de peso por dolar: 182000 = 18.2000 MXN/USD (valor simulado).
predeterminado(tipo_cambio_inicial) -> 182000;
predeterminado(tipo_cambio_variacion_ms) -> 30000;
predeterminado(terminal_timeout_ms) -> 3000;
predeterminado(fondo_inicial) -> 100000;
predeterminado(cajeros) -> [<<"Ana">>, <<"Beto">>, <<"Carla">>, <<"Diego">>];
predeterminado(_) -> undefined.
