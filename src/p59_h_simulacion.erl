-module(p59_h_simulacion).
-behaviour(cowboy_handler).

%% Inyeccion controlada de fallas para la demo (no exponer en produccion):
%% POST /api/simulacion/terminal       {"modo", "una_vez"}
%% POST /api/simulacion/impresora      {"modo": "ok" | "atascada"}
%% POST /api/simulacion/matar          {"proceso": "caja_2" | "inventario" | "terminal" | ...}
%% POST /api/simulacion/caos           prueba de caos completa (sincrona)
%% POST /api/simulacion/carga          {"tickets": 600}  simulacion en segundo plano
%% GET  /api/simulacion/carga          estado o ultimo reporte
%% POST /api/simulacion/escenarios/:letra   a | b | c | d | e

-export([init/2]).

init(Req0, Opts) ->
    Req = p59_http:atender(Req0, simulacion, fun manejar/2),
    {ok, Req, Opts}.

manejar(<<"GET">>, Req) ->
    case cowboy_req:binding(accion, Req) of
        <<"carga">> -> {200, #{reporte => p59_simulacion:ultimo()}};
        _ -> p59_http:error(ruta_no_encontrada)
    end;
manejar(<<"POST">>, Req0) ->
    case p59_http:leer_json(Req0) of
        {error, E, Req} ->
            erlang:append_element(p59_http:error(E), Req);
        {ok, Cuerpo, Req} ->
            Accion = case cowboy_req:binding(letra, Req) of
                         undefined -> cowboy_req:binding(accion, Req);
                         Letra -> {escenario, Letra}
                     end,
            erlang:append_element(accion(Accion, Cuerpo), Req)
    end;
manejar(_, _Req) ->
    p59_http:error(metodo_no_permitido).

accion(<<"terminal">>, Cuerpo) ->
    Modos = [normal, rechazar, fuera_de_linea, caida_antes_de_cobro, caida_tras_cobro, aleatorio],
    case p59_http:campo(Cuerpo, <<"modo">>, {atomo, Modos}, null) of
        {ok, Modo} when Modo =/= null ->
            UnaVez = maps:get(<<"una_vez">>, Cuerpo, false) =:= true,
            ok = p59_terminal_bancaria:fijar_modo(Modo, #{una_vez => UnaVez}),
            {200, p59_terminal_bancaria:estado()};
        _ -> p59_http:error(modo_invalido)
    end;
accion(<<"impresora">>, Cuerpo) ->
    case p59_http:campo(Cuerpo, <<"modo">>, {atomo, [ok, atascada]}, null) of
        {ok, Modo} when Modo =/= null ->
            ok = p59_impresora:fijar_modo(Modo),
            {200, #{modo => Modo, pendientes => p59_impresora:pendientes()}};
        _ -> p59_http:error(modo_invalido)
    end;
accion(<<"matar">>, Cuerpo) ->
    Permitidos = [p59_caja:nombre(N) || N <- p59_config:cajas()]
        ++ [p59_inventario, p59_terminal_bancaria, p59_impresora, p59_tipo_cambio,
            p59_ventas_sup, p59_cajas_sup, p59_eventos],
    case p59_http:campo(Cuerpo, <<"proceso">>, {atomo, Permitidos}, null) of
        {ok, Nombre} when Nombre =/= null ->
            case whereis(Nombre) of
                undefined -> p59_http:error(proceso_no_activo);
                Pid ->
                    p59_eventos:publicar(caos, falla, [<<"Se terminó "/utf8>>, atom_to_binary(Nombre),
                                                       <<" con kill desde la API"/utf8>>],
                                         #{proceso => Nombre}),
                    exit(Pid, kill),
                    {200, #{proceso => Nombre, pid => list_to_binary(pid_to_list(Pid)),
                            mensaje => <<"Proceso terminado; consulte /api/estado para ver el reinicio"/utf8>>}}
            end;
        _ -> p59_http:error(proceso_no_permitido)
    end;
accion(<<"caos">>, Cuerpo) ->
    {ok, Caja} = p59_http:campo(Cuerpo, <<"caja">>, entero, 2),
    case lists:member(Caja, p59_config:cajas()) of
        true -> {200, p59_caos:ejecutar(Caja)};
        false -> p59_http:error(caja_no_encontrada)
    end;
accion(<<"carga">>, Cuerpo) ->
    case p59_http:campo(Cuerpo, <<"tickets">>, entero, 600) of
        {ok, N} when N > 0, N =< 5000 ->
            case p59_simulacion:iniciar_async(#{tickets => N}) of
                ok -> {202, #{estado => iniciada, tickets => N}};
                {error, E} -> {409, #{error => E}}
            end;
        _ -> p59_http:error(parametro_invalido)
    end;
accion({escenario, Letra}, _Cuerpo) ->
    case lists:member(Letra, [<<"a">>, <<"b">>, <<"c">>, <<"d">>, <<"e">>]) of
        true -> {200, p59_escenarios:ejecutar(binary_to_atom(Letra))};
        false -> p59_http:error(escenario_no_encontrado)
    end;
accion(_, _) ->
    p59_http:error(ruta_no_encontrada).
