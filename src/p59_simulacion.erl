-module(p59_simulacion).

%% Simulacion del escenario del problema, con tiempo acelerado:
%%   - 4 cajas cobrando en paralelo (un proceso Erlang por caja),
%%   - 600 tickets confirmados sobre el catalogo de 800 productos,
%%   - pagos en efectivo MXN, USD, tarjeta y mixtos,
%%   - terminal bancaria con fallas aleatorias (rechazos y caidas),
%%   - reintentos de red duplicados,
%%   - cambio de turno a la mitad, con cancelaciones de tickets del turno anterior
%%     y devoluciones parciales,
%%   - caida forzada de la caja 3 a mitad de la corrida,
%%   - cortes de caja y verificacion de invariantes al final.
%% Las decisiones de cada caja usan una semilla fija; el resultado exacto depende
%% ademas de como se intercalan las cajas, que es justo lo que se quiere probar.

-export([ejecutar/0, ejecutar/1, cli/0, iniciar_async/1, ultimo/0, guardar_reporte/2]).

-define(PREFIJO, <<"sim">>).

ejecutar() ->
    ejecutar(#{}).

ejecutar(Opts0) ->
    Opts = maps:merge(#{tickets => 600, semilla => 2026, caos => true,
                        terminal_timeout_ms => 400}, Opts0),
    #{tickets := Meta} = Opts,
    Cajas = p59_config:cajas(),
    TimeoutPrevio = p59_config:obtener(terminal_timeout_ms),
    application:set_env(p59_punto_de_venta, terminal_timeout_ms, maps:get(terminal_timeout_ms, Opts)),
    [p59_cliente:asegurar_turno(C) || C <- Cajas],
    TurnosIniciales = maps:from_list([{C, maps:get(turno, element(2, p59_inventario:turno(C)))}
                                      || C <- Cajas]),
    Inicio = resumen_libro(),
    p59_eventos:publicar(simulacion, alerta, [<<"Simulación iniciada: "/utf8>>,
                                              integer_to_binary(Meta), <<" tickets"/utf8>>], #{}),
    ok = p59_terminal_bancaria:fijar_modo(aleatorio, #{prob => #{rechazo => 30, caida => 15}}),
    T0 = erlang:monotonic_time(millisecond),
    Confirmados = counters:new(1, []),
    Activos = [P || #{id := P, activo := true} <- p59_inventario:productos()],
    PorCaja = Meta div length(Cajas),
    Mitad = PorCaja div 2,
    %% Fase 1: primera mitad de cada caja en el turno inicial.
    F1 = correr(Cajas, fun(C) -> trabajador(C, Mitad, 1, Opts, Activos, Confirmados, TurnosIniciales) end),
    %% Cambio de turno: la caja 3 cuenta $50.00 de menos (descuadre esperado).
    Cortes1 = [cambiar_turno(C) || C <- Cajas],
    %% Fase 2: resto, con cancelaciones del turno anterior, devoluciones y caos.
    Caos = case maps:get(caos, Opts) of
               true -> lanzar_caos(Confirmados, Mitad * length(Cajas) + PorCaja div 2);
               false -> null
           end,
    F2 = correr(Cajas, fun(C) ->
                           Restantes = PorCaja - Mitad + case C of 1 -> Meta rem length(Cajas); _ -> 0 end,
                           trabajador(C, Restantes, 2, Opts, Activos, Confirmados, TurnosIniciales)
                       end),
    ok = p59_terminal_bancaria:fijar_modo(normal, #{}),
    application:set_env(p59_punto_de_venta, terminal_timeout_ms, TimeoutPrevio),
    DuracionMs = erlang:monotonic_time(millisecond) - T0,
    Stats = sumar_stats(F1 ++ F2),
    EvidenciaCaos = esperar_caos(Caos),
    {ok, CorteFinal} = p59_inventario:corte(#{}),
    Cortes2 = maps:get(cajas, CorteFinal),
    Fin = resumen_libro(),
    Invariantes = invariantes(Cortes1 ++ Cortes2),
    Reporte = #{meta_tickets => Meta,
                tickets_confirmados => maps:get(ventas, Fin) - maps:get(ventas, Inicio),
                duracion_ms => DuracionMs,
                tickets_por_segundo => (maps:get(ventas, Fin) - maps:get(ventas, Inicio)) * 1000
                    div max(1, DuracionMs),
                operaciones => Stats,
                caos => EvidenciaCaos,
                cortes_turno_1 => [resumir_corte(C) || C <- Cortes1],
                cortes_turno_2 => [resumir_corte(C) || C <- Cortes2],
                consolidado_turno_2 => resumir_corte(maps:get(consolidado, CorteFinal)),
                invariantes => Invariantes,
                ok => maps:get(ok, Invariantes)},
    p59_eventos:publicar(simulacion, case maps:get(ok, Reporte) of true -> ok; false -> falla end,
                         [<<"Simulación terminada: "/utf8>>,
                          integer_to_binary(maps:get(tickets_confirmados, Reporte)),
                          <<" tickets en "/utf8>>, integer_to_binary(DuracionMs), <<" ms"/utf8>>], #{}),
    persistent_term:put({?MODULE, ultimo}, Reporte),
    Reporte.

%% Para la API: corre en segundo plano y deja el resultado en ultimo/0.
iniciar_async(Opts) ->
    case whereis(p59_simulacion_corrida) of
        undefined ->
            Pid = spawn(fun() ->
                                persistent_term:put({?MODULE, ultimo}, #{estado => corriendo}),
                                R = try ejecutar(Opts)
                                    catch C:E:St ->
                                            logger:error("simulacion: ~p:~p ~p", [C, E, St]),
                                            #{estado => error}
                                    end,
                                persistent_term:put({?MODULE, ultimo}, R)
                        end),
            register(p59_simulacion_corrida, Pid),
            ok;
        _ ->
            {error, simulacion_en_curso}
    end.

ultimo() ->
    persistent_term:get({?MODULE, ultimo}, null).

%% Punto de entrada de scripts/simular.sh.
cli() ->
    {ok, _} = application:ensure_all_started(p59_punto_de_venta),
    Tickets = case os:getenv("P59_TICKETS") of false -> 600; T -> list_to_integer(T) end,
    R = ejecutar(#{tickets => Tickets}),
    Archivo = guardar_reporte("simulacion", R),
    imprimir(R),
    io:format("~nReporte completo: ~ts~n", [Archivo]),
    application:stop(p59_punto_de_venta),
    halt(case maps:get(ok, R) of true -> 0; false -> 1 end).

guardar_reporte(Nombre, Datos) ->
    {{A, M, D}, {H, Mi, S}} = calendar:local_time(),
    Archivo = filename:join("logs", io_lib:format("~s-~4..0b~2..0b~2..0b-~2..0b~2..0b~2..0b.json",
                                                  [Nombre, A, M, D, H, Mi, S])),
    ok = filelib:ensure_dir(Archivo),
    ok = file:write_file(Archivo, json:format(Datos)),
    lists:flatten(Archivo).

%%% ------------------------------------------------------------ trabajador

correr(Cajas, Fun) ->
    Yo = self(),
    Pids = [spawn_link(fun() -> Yo ! {fin, self(), Fun(C)} end) || C <- Cajas],
    [receive {fin, P, R} -> R end || P <- Pids].

trabajador(Caja, Meta, Fase, Opts, Activos, Confirmados, Turnos) ->
    Semilla = maps:get(semilla, Opts),
    R0 = rand:seed_s(exsss, {Semilla, Caja, Fase}),
    ciclo(#{caja => Caja, meta => Meta, hechos => 0, intentos => 0, fase => Fase, rand => R0,
            activos => list_to_tuple(Activos), confirmados => Confirmados,
            turno_anterior => maps:get(Caja, Turnos), stats => #{}}).

ciclo(#{hechos := H, meta := M, stats := Stats}) when H >= M ->
    Stats;
ciclo(#{intentos := I, meta := M, stats := Stats}) when I > M * 4 ->
    Stats#{abandonado => 1};
ciclo(S0) ->
    S1 = extras(S0),
    S2 = un_ticket(S1#{intentos := maps:get(intentos, S1) + 1}),
    ciclo(S2).

%% En la fase 2 algunas iteraciones cancelan un ticket del turno anterior o
%% devuelven una pieza de un ticket del turno actual.
extras(#{fase := 1} = S) ->
    S;
extras(#{caja := Caja, rand := R0, turno_anterior := TurnoAnt} = S) ->
    {X, R1} = rand:uniform_s(100, R0),
    S1 = S#{rand := R1},
    if
        X =< 3 ->
            case [F || #{tipo := venta, folio := F} <- p59_inventario:tickets(#{caja => Caja, turno => TurnoAnt}),
                       no_cancelado(F)] of
                [] -> S1;
                [Folio | _] ->
                    Res = p59_inventario:reembolsar(cancelacion, Folio, todo,
                                                    #{caja => Caja, motivo => <<"Simulación: cancelación de turno anterior"/utf8>>}),
                    contar(S1, case Res of {ok, _} -> cancelaciones_turno_anterior; _ -> errores_cancelacion end)
            end;
        X =< 6 ->
            {ok, #{turno := T}} = p59_inventario:turno(Caja),
            case [M || #{tipo := venta, folio := F} = M <- p59_inventario:tickets(#{caja => Caja, turno => T}),
                       no_cancelado(F)] of
                [] -> S1;
                Candidatos ->
                    {Idx, R2} = rand:uniform_s(length(Candidatos), R1),
                    #{folio := Folio, partidas := [#{producto_id := P} | _]} = lists:nth(Idx, Candidatos),
                    Res = p59_inventario:reembolsar(devolucion, Folio, [{P, 1}],
                                                    #{caja => Caja, motivo => <<"Simulación: devolución"/utf8>>,
                                                      operacion_id => p59_cliente:operacion(<<"dev">>)}),
                    contar(S1#{rand := R2}, case Res of {ok, _} -> devoluciones; _ -> devoluciones_rechazadas end)
            end;
        true ->
            S1
    end.

no_cancelado(Folio) ->
    {ok, #{reembolsos := R}} = p59_inventario:ticket(Folio),
    [x || #{tipo := cancelacion} <- R] =:= [].

un_ticket(#{caja := Caja, rand := R0, activos := Activos} = S) ->
    {ok, V0} = p59_cliente:abrir_venta(Caja, p59_cliente:operacion(?PREFIJO)),
    {NumLineas, R1} = rand:uniform_s(4, R0),
    {Lineas, R2} = lists:mapfoldl(fun(_, R) ->
                                          {Idx, Ra} = rand:uniform_s(tuple_size(Activos), R),
                                          {Q, Rb} = rand:uniform_s(3, Ra),
                                          {Dsc, Rc} = rand:uniform_s(10, Rb),
                                          {{element(Idx, Activos), Q, case Dsc of 1 -> 10; _ -> 0 end}, Rc}
                                  end, R1, lists:seq(1, NumLineas)),
    {V, S1} = lists:foldl(fun({P, Q, D}, {Vacc, Sacc}) ->
                                  case p59_venta:agregar(maps:get(id, V0), P, Q, D) of
                                      {ok, V1} -> {V1, Sacc};
                                      {error, {sin_existencia, _}} -> {Vacc, contar(Sacc, partidas_sin_existencia)};
                                      {error, _} -> {Vacc, contar(Sacc, partidas_rechazadas)}
                                  end
                          end, {V0, S#{rand := R2}}, Lineas),
    case V of
        #{partidas := []} ->
            {ok, _} = p59_venta:cancelar(maps:get(id, V), <<"Simulación: sin partidas"/utf8>>),
            contar(S1, ventas_abandonadas);
        _ ->
            cobrar(V, S1, 3)
    end.

cobrar(#{id := Id}, S, 0) ->
    _ = p59_venta:cancelar(Id, <<"Simulación: cliente se retira tras varios intentos"/utf8>>),
    contar(S, ventas_abandonadas);
cobrar(#{id := Id, totales := #{total := Total}} = V, #{rand := R0} = S, Intentos) ->
    {X, R1} = rand:uniform_s(100, R0),
    {Dup, R2} = rand:uniform_s(100, R1),
    {Pagos, Tipo} = pagos(X, Total),
    Op = p59_cliente:operacion(?PREFIJO),
    S1 = S#{rand := R2},
    Resultado = case Dup =< 5 of
                    true -> duplicado(Id, Pagos, Op);
                    false -> p59_venta:pagar(Id, Pagos, Op)
                end,
    S2 = case Dup =< 5 of true -> contar(S1, reintentos_duplicados_enviados); false -> S1 end,
    case Resultado of
        {ok, #{estado := pagada}} ->
            counters:add(maps:get(confirmados, S2), 1, 1),
            contar(contar(S2#{hechos := maps:get(hechos, S2) + 1}, Tipo), tickets);
        {pendiente, _} ->
            resolver_revision(V, contar(S2, enviadas_a_revision), Intentos);
        {error, rechazada} ->
            cobrar(V, contar(S2, tarjetas_rechazadas), Intentos - 1);
        {error, {sin_existencia, _}} ->
            {ok, _} = p59_venta:cancelar(Id, <<"Simulación: otra caja tomó las últimas piezas"/utf8>>),
            contar(S2, competencia_por_existencia);
        {error, Otro} ->
            logger:info("simulacion: cobro ~ts -> ~p", [Id, Otro]),
            cobrar(V, contar(S2, otros_errores_cobro), Intentos - 1)
    end.

resolver_revision(#{id := Id} = V, S, Intentos) ->
    case p59_venta:revisar(Id) of
        {ok, #{estado := pagada}} ->
            counters:add(maps:get(confirmados, S), 1, 1),
            contar(contar(S#{hechos := maps:get(hechos, S) + 1}, revisiones_resueltas_cobradas), tickets);
        {ok, #{estado := abierta} = V1} ->
            cobrar(V1, contar(S, revisiones_resueltas_sin_cargo), Intentos - 1);
        _ ->
            timer:sleep(50),
            resolver_revision(V, S, Intentos)
    end.

%% Dos solicitudes identicas en paralelo, como un reintento de red.
duplicado(Id, Pagos, Op) ->
    Yo = self(),
    Ref = make_ref(),
    spawn(fun() -> Yo ! {Ref, p59_venta:pagar(Id, Pagos, Op)} end),
    R1 = p59_venta:pagar(Id, Pagos, Op),
    R2 = receive {Ref, R} -> R after 30000 -> timeout end,
    case {R1, R2} of
        {{ok, #{folio := F}}, {ok, #{folio := F}}} -> R1;
        {{ok, _}, {ok, _}} -> error({folios_distintos, R1, R2});
        {{ok, _}, _} -> R1;
        _ -> R2
    end.

pagos(X, Total) when X =< 45 ->
    %% Efectivo redondeado hacia arriba a billetes de $50.
    {[#{metodo => efectivo_mxn, monto => ((Total + 4999) div 5000) * 5000}], efectivo_mxn};
pagos(X, Total) when X =< 70 ->
    {[#{metodo => tarjeta, monto => Total}], tarjeta};
pagos(X, Total) when X =< 85 ->
    #{valor := Tc} = p59_tipo_cambio:actual(),
    %% Margen de un dolar por si el tipo de cambio se mueve entre leerlo y cobrar.
    {[#{metodo => efectivo_usd, monto => p59_cliente:usd_suficiente(Total, Tc) + 100}], efectivo_usd};
pagos(_X, Total) ->
    Tarjeta = Total div 2,
    {[#{metodo => tarjeta, monto => Tarjeta},
      #{metodo => efectivo_mxn, monto => ((Total - Tarjeta + 1999) div 2000) * 2000}], mixto}.

contar(#{stats := St} = S, Clave) ->
    S#{stats := maps:update_with(Clave, fun(V) -> V + 1 end, 1, St)}.

sumar_stats(Lista) ->
    lists:foldl(fun(M, Acc) -> maps:fold(fun(K, V, A) -> maps:update_with(K, fun(X) -> X + V end, V, A) end,
                                         Acc, M) end, #{}, Lista).

%%% ----------------------------------------------------------------- turnos

cambiar_turno(Caja) ->
    {ok, #{efectivo_esperado := #{mxn := Mxn, usd := Usd}}} = p59_inventario:corte(#{caja => Caja}),
    Faltante = case Caja of 3 -> 5000; _ -> 0 end,
    {ok, Corte} = p59_inventario:cerrar_turno(Caja, #{mxn => Mxn - Faltante, usd => Usd}),
    {ok, #{cajero := Anterior}} = p59_inventario:turno(Caja),
    {ok, _} = p59_inventario:abrir_turno(Caja, <<Anterior/binary, " (tarde)"/utf8>>,
                                         p59_config:obtener(fondo_inicial)),
    Corte.

%%% ------------------------------------------------------------------- caos

lanzar_caos(Confirmados, Umbral) ->
    Yo = self(),
    Ref = make_ref(),
    spawn(fun() ->
                  esperar_umbral(Confirmados, Umbral),
                  Antes = whereis(p59_caja:nombre(3)),
                  {ok, VentaEnCurso} = p59_caja:venta_actual(3),
                  exit(Antes, kill),
                  p59_eventos:publicar(caos, falla, <<"Simulación: caja 3 terminada con kill"/utf8>>, #{}),
                  Reinicio = p59_cliente:esperar(fun() ->
                                                         P = whereis(p59_caja:nombre(3)),
                                                         is_pid(P) andalso P =/= Antes
                                                 end, 5000),
                  Yo ! {Ref, #{proceso => p59_caja_3,
                               pid_antes => pid(Antes),
                               pid_despues => pid(whereis(p59_caja:nombre(3))),
                               venta_en_curso_al_matar => VentaEnCurso,
                               tickets_confirmados_al_matar => counters:get(Confirmados, 1),
                               reiniciada => Reinicio,
                               supervisor => p59_cajas_sup,
                               estrategia => one_for_one}}
          end),
    Ref.

esperar_umbral(Contador, Umbral) ->
    case counters:get(Contador, 1) >= Umbral of
        true -> ok;
        false -> timer:sleep(5), esperar_umbral(Contador, Umbral)
    end.

esperar_caos(null) -> null;
esperar_caos(Ref) ->
    receive {Ref, Evidencia} -> Evidencia after 10000 -> #{error => caos_no_ejecutado} end.

pid(P) when is_pid(P) -> list_to_binary(pid_to_list(P));
pid(_) -> null.

%%% ------------------------------------------------------------ invariantes

invariantes(Cortes) ->
    Inventario = p59_inventario:verificar_existencias(),
    Ventas = [M || #{tipo := venta} = M <- p59_inventario:tickets(#{})],
    VentaIds = [V || #{venta_id := V} <- Ventas],
    Folios = [F || #{folio := F} <- Ventas],
    CortesOk = lists:all(fun(#{invariante := #{ok := Ok}}) -> Ok end, Cortes),
    Descuadres = [maps:get(alcance, C) || #{descuadre := true} = C <- Cortes],
    #{inventario => Inventario,
      cortes_cuadran => CortesOk,
      una_venta_por_ticket => length(VentaIds) =:= length(lists:usort(VentaIds)),
      folios_unicos => length(Folios) =:= length(lists:usort(Folios)),
      descuadres_detectados => Descuadres,
      ok => maps:get(ok, Inventario) andalso CortesOk
          andalso length(VentaIds) =:= length(lists:usort(VentaIds))
          andalso length(Folios) =:= length(lists:usort(Folios))}.

resumir_corte(C) ->
    maps:with([alcance, ventas, cobros, cancelaciones, devoluciones, efectivo_esperado,
               contado, diferencia, descuadre, venta_neta, invariante], C).

resumen_libro() ->
    p59_inventario:resumen().

imprimir(R) ->
    #{tickets_confirmados := N, duracion_ms := D, operaciones := Ops, invariantes := Inv} = R,
    io:format("~n=== Simulacion #59: ~b tickets confirmados en ~b ms (~b tickets/s) ===~n",
              [N, D, maps:get(tickets_por_segundo, R)]),
    io:format("Operaciones:~n"),
    [io:format("  ~-36s ~b~n", [K, V]) || {K, V} <- lists:sort(maps:to_list(Ops))],
    io:format("Caos: ~p~n", [maps:get(caos, R)]),
    io:format("Cortes turno 1 (cerrados):~n"),
    [imprimir_corte(C) || C <- maps:get(cortes_turno_1, R)],
    io:format("Cortes turno 2 (vigentes):~n"),
    [imprimir_corte(C) || C <- maps:get(cortes_turno_2, R)],
    io:format("Invariantes: inventario=~p cortes=~p una_venta_por_ticket=~p folios_unicos=~p~n",
              [maps:get(ok, maps:get(inventario, Inv)), maps:get(cortes_cuadran, Inv),
               maps:get(una_venta_por_ticket, Inv), maps:get(folios_unicos, Inv)]),
    io:format("Resultado: ~s~n", [case maps:get(ok, R) of true -> "OK"; false -> "FALLA" end]).

imprimir_corte(#{alcance := #{caja := C, turno := T}, ventas := #{numero := N, total := Tot},
                 cancelaciones := #{numero := Nc}, devoluciones := #{numero := Nd},
                 efectivo_esperado := #{mxn := E}, diferencia := Dif, invariante := #{ok := Ok}}) ->
    io:format("  caja ~b turno ~b: ~3b ventas ~14ts  canc ~b dev ~b  esperado ~12ts  dif ~ts  invariante ~p~n",
              [C, T, N, p59_dinero:formatear(Tot), Nc, Nd, p59_dinero:formatear(E),
               case Dif of null -> <<"-">>; #{mxn := M} -> p59_dinero:formatear(M) end, Ok]).
