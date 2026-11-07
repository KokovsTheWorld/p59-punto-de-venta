-module(p59_h_sistema).
-behaviour(cowboy_handler).

%% /api/health, /api/estado, /api/diagnostico (recon), /api/tipo-cambio

-export([init/2, arbol/1]).

init(Req0, #{accion := Accion} = Opts) ->
    Req = p59_http:atender(Req0, Accion, fun(M, R) -> manejar(Accion, M, R) end),
    {ok, Req, Opts}.

manejar(health, <<"GET">>, _Req) ->
    {200, #{estado => ok, servicio => p59_punto_de_venta,
            ping => p59_punto_de_venta_server:ping()}};
manejar(estado, <<"GET">>, _Req) ->
    {200, #{sistema => p59_punto_de_venta_server:state(),
            resumen => p59_inventario:resumen(),
            ventas_en_proceso => p59_ventas_sup:activas(),
            cajas_activas => p59_caja:activas(),
            tipo_cambio => p59_tipo_cambio:actual(),
            terminal => p59_terminal_bancaria:estado(),
            impresora => #{pendientes => p59_impresora:pendientes()},
            reinicios => p59_metricas:reinicios(),
            arbol => arbol(p59_punto_de_venta_sup)}};
manejar(diagnostico, <<"GET">>, _Req) ->
    {200, #{memoria => [proceso(P) || P <- recon:proc_count(memory, 8)],
            buzon => [proceso(P) || P <- recon:proc_count(message_queue_len, 5)],
            reducciones => [proceso(P) || P <- recon:proc_count(reductions, 5)],
            vm => #{procesos => erlang:system_info(process_count),
                    memoria_total => erlang:memory(total),
                    memoria_procesos => erlang:memory(processes),
                    memoria_ets => erlang:memory(ets),
                    planificadores => erlang:system_info(schedulers_online),
                    cola_ejecucion => erlang:statistics(run_queue)}}};
manejar(tipo_cambio, <<"GET">>, _Req) ->
    {200, p59_tipo_cambio:actual()};
manejar(tipo_cambio, <<"POST">>, Req0) ->
    case p59_http:leer_json(Req0) of
        {ok, Cuerpo, Req} ->
            case p59_http:campo(Cuerpo, <<"valor">>, entero, null) of
                {ok, V} when is_integer(V) ->
                    case p59_tipo_cambio:fijar(V) of
                        ok -> {200, p59_tipo_cambio:actual(), Req};
                        {error, E} -> erlang:append_element(p59_http:error(E), Req)
                    end;
                _ -> erlang:append_element(p59_http:error(tipo_de_cambio_fuera_de_rango), Req)
            end;
        {error, E, Req} -> erlang:append_element(p59_http:error(E), Req)
    end;
manejar(_, _, _Req) ->
    p59_http:error(metodo_no_permitido).

%% Arbol de supervision tal como esta ahora mismo (pids reales).
arbol(Sup) ->
    #{id => Sup, pid => texto(whereis(Sup)), tipo => supervisor,
      hijos => [hijo(Hijo) || Hijo <- lists:reverse(supervisor:which_children(Sup))]}.

hijo({p59_ventas_sup, Pid, supervisor, _}) ->
    Ventas = lists:sort([Id || {p59_venta, Id} <- global:registered_names()]),
    #{id => p59_ventas_sup, pid => texto(Pid), tipo => supervisor, vivo => is_pid(Pid),
      hijos => [#{id => <<"venta ", Id/binary>>, pid => texto(global:whereis_name({p59_venta, Id})),
                  tipo => worker, vivo => true} || Id <- Ventas]};
hijo({Id, Pid, supervisor, _}) when is_pid(Pid) ->
    (arbol_de(Pid))#{id => Id};
hijo({Id, Pid, Tipo, _}) ->
    #{id => Id, pid => texto(Pid), tipo => Tipo, vivo => is_pid(Pid)}.

arbol_de(Pid) ->
    #{pid => texto(Pid), tipo => supervisor, vivo => true,
      hijos => [hijo(H) || H <- lists:reverse(supervisor:which_children(Pid))]}.

proceso({Pid, Valor, Info}) ->
    Nombre = case Info of
                 [N | _] when is_atom(N) -> N;
                 _ -> null
             end,
    Inicial = case lists:keyfind(initial_call, 1, Info) of
                  {_, {M, F, A}} -> iolist_to_binary(io_lib:format("~p:~p/~p", [M, F, A]));
                  _ -> null
              end,
    #{pid => texto(Pid), valor => Valor, nombre => Nombre, llamada_inicial => Inicial}.

texto(Pid) when is_pid(Pid) -> list_to_binary(pid_to_list(Pid));
texto(_) -> null.
