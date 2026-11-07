-module(p59_escenarios).

%% Escenarios de falla inyectada del problema (A-E). Cada uno ejecuta los pasos
%% contra el sistema vivo y devuelve evidencia verificable: que se esperaba, que
%% se obtuvo y si coincide. Se usan desde eunit, desde la API
%% (POST /api/simulacion/escenarios/:letra) y desde scripts/escenarios.sh.

-export([ejecutar/1, todos/0, cli/0]).

-define(CAJA, 4).

todos() ->
    [ejecutar(L) || L <- [a, b, c, d, e]].

ejecutar(Letra) ->
    {Titulo, Fun} = escenario(Letra),
    T0 = erlang:monotonic_time(millisecond),
    p59_eventos:publicar(escenario, alerta, [<<"Inicia escenario "/utf8>>,
                                             string:uppercase(atom_to_binary(Letra)),
                                             <<": "/utf8>>, Titulo], #{}),
    p59_cliente:asegurar_turno(?CAJA),
    {Pasos, Checks} = Fun(),
    Ok = lists:all(fun(#{ok := B}) -> B end, Checks),
    p59_eventos:publicar(escenario, case Ok of true -> ok; false -> falla end,
                         [<<"Escenario "/utf8>>, string:uppercase(atom_to_binary(Letra)),
                          case Ok of true -> <<": OK"/utf8>>; false -> <<": FALLÓ"/utf8>> end], #{}),
    #{escenario => Letra, titulo => Titulo, ok => Ok, pasos => Pasos,
      verificaciones => Checks, duracion_ms => erlang:monotonic_time(millisecond) - T0}.

%% Punto de entrada de scripts/escenarios.sh.
cli() ->
    {ok, _} = application:ensure_all_started(p59_punto_de_venta),
    application:set_env(p59_punto_de_venta, terminal_timeout_ms, 500),
    Resultados = todos(),
    Archivo = p59_simulacion:guardar_reporte("escenarios", #{escenarios => Resultados}),
    [begin
         io:format("~n=== Escenario ~s: ~ts -> ~s~n",
                   [string:uppercase(atom_to_list(L)), T, case Ok of true -> "OK"; false -> "FALLA" end]),
         [io:format("   [~s] ~ts~n", [case B of true -> "ok"; false -> "XX" end, N])
          || #{verificacion := N, ok := B} <- Cs]
     end || #{escenario := L, titulo := T, ok := Ok, verificaciones := Cs} <- Resultados],
    Ok = lists:all(fun(#{ok := B}) -> B end, Resultados),
    io:format("~nResultado: ~s~nEvidencia: ~ts~n", [case Ok of true -> "OK"; false -> "FALLA" end, Archivo]),
    application:stop(p59_punto_de_venta),
    halt(case Ok of true -> 0; false -> 1 end).

escenario(a) -> {<<"Terminal bancaria cae a mitad del cobro"/utf8>>, fun terminal/0};
escenario(b) -> {<<"Cancelación de un ticket del turno anterior"/utf8>>, fun turno_anterior/0};
escenario(c) -> {<<"Reintento de red: la misma confirmación llega varias veces"/utf8>>, fun reintento/0};
escenario(d) -> {<<"Pago en dólares con cambio en pesos"/utf8>>, fun dolares/0};
escenario(e) -> {<<"Corte de caja con ventas en proceso"/utf8>>, fun en_proceso/0}.

%%% ------------------------------------------------------------------- A

terminal() ->
    #{id := Prod} = p59_cliente:producto_disponible(#{min => 2}),
    %% A1: la terminal cobra pero la respuesta nunca llega.
    {ok, V0} = p59_cliente:abrir_venta(?CAJA),
    {ok, #{id := Id, totales := #{total := Total}}} = p59_cliente:agregar(V0, [{Prod, 1}]),
    {ok, Antes} = p59_inventario:producto(Prod),
    ok = p59_terminal_bancaria:fijar_modo(caida_tras_cobro, #{una_vez => true}),
    Op = p59_cliente:operacion(<<"pago-a">>),
    R1 = p59_venta:pagar(Id, [#{metodo => tarjeta, monto => Total}], Op),
    {ok, Durante} = p59_inventario:producto(Prod),
    {ok, #{referencia_terminal := Ref}} = p59_venta:leer(Id),
    Libro1 = p59_inventario:venta_confirmada(Id),
    %% Reintento del cliente con la misma operacion: se consulta al banco primero.
    R2 = p59_venta:pagar(Id, [#{metodo => tarjeta, monto => Total}], Op),
    {ok, Despues} = p59_inventario:producto(Prod),
    %% A2: la terminal cae ANTES de que el cargo llegue al banco.
    {ok, W0} = p59_cliente:abrir_venta(?CAJA),
    {ok, #{id := Id2, totales := #{total := Total2}}} = p59_cliente:agregar(W0, [{Prod, 1}]),
    ok = p59_terminal_bancaria:fijar_modo(caida_antes_de_cobro, #{una_vez => true}),
    S1 = p59_venta:pagar(Id2, [#{metodo => tarjeta, monto => Total2}], p59_cliente:operacion(<<"p">>)),
    S2 = p59_venta:revisar(Id2),
    S3 = p59_venta:pagar(Id2, p59_cliente:efectivo_exacto(Total2), p59_cliente:operacion(<<"p">>)),
    {Pasos, Checks} =
        {[paso(<<"A1 cobro con terminal que cae tras cobrar"/utf8>>, estado(R1)),
          paso(<<"A1 reintento con la misma operacion_id"/utf8>>, estado(R2)),
          paso(<<"A2 cobro con terminal que cae antes de cobrar"/utf8>>, estado(S1)),
          paso(<<"A2 revisión"/utf8>>, estado(S2)),
          paso(<<"A2 cobro en efectivo"/utf8>>, estado(S3))],
         [check(<<"A1: la venta queda en revisión, no pagada"/utf8>>, pendiente_de_revision, estado(R1)),
          check(<<"A1: no hay movimiento en el libro mientras está en revisión"/utf8>>, no, Libro1),
          check(<<"A1: la unidad queda apartada (reservada), no vendida"/utf8>>,
                {maps:get(existencia, Antes), maps:get(reservado, Antes) + 1},
                {maps:get(existencia, Durante), maps:get(reservado, Durante)}),
          check(<<"A1: el reintento confirma con el cargo ya hecho"/utf8>>, pagada, estado(R2)),
          check(<<"A1: el banco registra el cargo de esa referencia (sin cobrar de nuevo)"/utf8>>, true,
                element(1, p59_terminal_bancaria:consultar(Ref)) =:= aprobado),
          check(<<"A1: existencia descontada exactamente una vez"/utf8>>,
                maps:get(existencia, Antes) - 1, maps:get(existencia, Despues)),
          check(<<"A2: sin respuesta → revisión"/utf8>>, pendiente_de_revision, estado(S1)),
          check(<<"A2: el banco no registra el cargo → la venta vuelve a abierta"/utf8>>,
                abierta, estado(S2)),
          check(<<"A2: se cobra en efectivo y se confirma"/utf8>>, pagada, estado(S3))]},
    {Pasos, Checks}.

%%% ------------------------------------------------------------------- B

turno_anterior() ->
    #{id := Prod} = p59_cliente:producto_disponible(#{min => 3}),
    {ok, Antes} = p59_inventario:producto(Prod),
    {ok, #{folio := Folio, totales := #{total := Total}}} =
        p59_cliente:vender(?CAJA, [{Prod, 2}], fun p59_cliente:efectivo_exacto/1),
    {ok, #{turno := TurnoA}} = p59_inventario:turno(?CAJA),
    {ok, #{efectivo_esperado := Esperado}} = p59_inventario:corte(#{caja => ?CAJA}),
    {ok, CorteA} = p59_inventario:cerrar_turno(?CAJA, Esperado),
    {ok, #{turno := TurnoB, fondo_mxn := FondoB}} =
        p59_inventario:abrir_turno(?CAJA, <<"Diego (turno siguiente)"/utf8>>, 100000),
    {ok, Canc} = p59_inventario:reembolsar(cancelacion, Folio, todo,
                                           #{caja => ?CAJA, motivo => <<"Cliente devolvió todo"/utf8>>}),
    {ok, Canc2} = p59_inventario:reembolsar(cancelacion, Folio, todo,
                                            #{caja => ?CAJA, motivo => <<"Reintento"/utf8>>}),
    %% Se recalcula desde el libro (no desde el corte guardado) para comprobar
    %% que la cancelacion no altero los movimientos del turno anterior.
    CorteA2 = p59_corte:calcular(p59_inventario:tickets(#{caja => ?CAJA, turno => TurnoA}), #{}),
    {ok, CorteB} = p59_inventario:corte(#{caja => ?CAJA, turno => TurnoB}),
    {ok, Despues} = p59_inventario:producto(Prod),
    {ok, #{reembolsos := Reembolsos}} = p59_inventario:ticket(Folio),
    {[paso(<<"Venta en turno anterior"/utf8>>, #{folio => Folio, turno => TurnoA, total => Total}),
      paso(<<"Cierre del turno anterior"/utf8>>, maps:with([efectivo_esperado, diferencia], CorteA)),
      paso(<<"Apertura del turno actual"/utf8>>, #{turno => TurnoB}),
      paso(<<"Cancelación en el turno actual"/utf8>>,
           maps:with([id, turno, turno_original, monto, reembolso_efectivo], Canc))],
     [check(<<"El corte del turno anterior no cambia"/utf8>>,
            maps:get(ventas, CorteA), maps:get(ventas, CorteA2)),
      check(<<"La cancelación se registra en el turno actual"/utf8>>, TurnoB, maps:get(turno, Canc)),
      check(<<"Conserva referencia al turno original"/utf8>>, TurnoA, maps:get(turno_original, Canc)),
      check(<<"El corte actual muestra la cancelación"/utf8>>, #{numero => 1, monto => Total},
            maps:get(cancelaciones, CorteB)),
      check(<<"Efectivo esperado = fondo - reembolso"/utf8>>, FondoB - Total,
            maps:get(mxn, maps:get(efectivo_esperado, CorteB))),
      check(<<"Invariante contable del turno actual"/utf8>>, true,
            maps:get(ok, maps:get(invariante, CorteB))),
      check(<<"Cancelar dos veces devuelve el mismo movimiento"/utf8>>,
            maps:get(id, Canc), maps:get(id, Canc2)),
      check(<<"El ticket conserva su historia (1 reembolso)"/utf8>>, 1, length(Reembolsos)),
      check(<<"Las unidades regresan al inventario"/utf8>>,
            maps:get(existencia, Antes), maps:get(existencia, Despues))]}.

%%% ------------------------------------------------------------------- C

reintento() ->
    #{id := Prod} = p59_cliente:producto_disponible(#{min => 2}),
    OpCrear = p59_cliente:operacion(<<"crear-c">>),
    {ok, #{id := Id} = V} = p59_cliente:abrir_venta(?CAJA, OpCrear),
    {ok, #{id := IdRepetida}} = p59_caja:iniciar_venta(?CAJA, OpCrear),
    {ok, #{totales := #{total := Total}}} = p59_cliente:agregar(V, [{Prod, 1}]),
    {ok, Antes} = p59_inventario:producto(Prod),
    Ventas0 = maps:get(ventas, p59_inventario:resumen()),
    Op = p59_cliente:operacion(<<"pago-c">>),
    Yo = self(),
    %% Cinco "reintentos de red" simultaneos de la misma confirmacion.
    [spawn(fun() -> Yo ! {pago, p59_venta:pagar(Id, p59_cliente:efectivo_exacto(Total), Op)} end)
     || _ <- lists:seq(1, 5)],
    Resultados = [receive {pago, R} -> R after 15000 -> timeout end || _ <- lists:seq(1, 5)],
    Folios = lists:usort([F || {ok, #{folio := F}} <- Resultados]),
    {ok, Despues} = p59_inventario:producto(Prod),
    Distinta = p59_venta:pagar(Id, p59_cliente:efectivo_exacto(Total), <<"otra-operacion">>),
    {[paso(<<"Creación repetida con la misma operacion_id"/utf8>>, #{primera => Id, segunda => IdRepetida}),
      paso(<<"5 confirmaciones simultáneas"/utf8>>, [estado(R) || R <- Resultados])],
     [check(<<"La creación repetida devuelve la misma venta"/utf8>>, Id, IdRepetida),
      check(<<"Las 5 respuestas son exitosas"/utf8>>, 5, length([x || {ok, _} <- Resultados])),
      check(<<"Todas devuelven el mismo folio"/utf8>>, 1, length(Folios)),
      check(<<"Una sola venta nueva en el libro"/utf8>>, Ventas0 + 1,
            maps:get(ventas, p59_inventario:resumen())),
      check(<<"Inventario descontado una sola vez"/utf8>>,
            maps:get(existencia, Antes) - 1, maps:get(existencia, Despues)),
      check(<<"Otra operacion_id sobre la venta pagada se rechaza"/utf8>>,
            {error, venta_ya_pagada}, Distinta)]}.

%%% ------------------------------------------------------------------- D

dolares() ->
    #{valor := TcOriginal} = p59_tipo_cambio:actual(),
    ok = p59_tipo_cambio:fijar(175000),
    #{id := Prod} = p59_cliente:producto_disponible(#{min => 1, precio_max => 50000}),
    {ok, V0} = p59_cliente:abrir_venta(?CAJA),
    {ok, #{totales := #{total := Total}} = V} = p59_cliente:agregar(V0, [{Prod, 1}]),
    Usd = p59_cliente:usd_suficiente(Total, 175000) + 500,
    {ok, #{folio := Folio, cobro := Cobro}} =
        p59_cliente:pagar(V, [#{metodo => efectivo_usd, monto => Usd}]),
    ok = p59_tipo_cambio:fijar(190000),
    {ok, #{venta := Ticket}} = p59_inventario:ticket(Folio),
    ok = p59_tipo_cambio:fijar(TcOriginal),
    ValorMxn = (Usd * 175000) div 10000,
    {[paso(<<"Tipo de cambio fijado"/utf8>>, #{tipo_cambio => <<"17.5000">>}),
      paso(<<"Pago"/utf8>>, #{total_mxn => Total, recibido_usd => Usd, folio => Folio})],
     [check(<<"Dólares valorados al tipo de cambio de la operación (piso)"/utf8>>, ValorMxn,
            maps:get(recibido_mxn, Cobro)),
      check(<<"Cambio entregado en pesos"/utf8>>, ValorMxn - Total, maps:get(cambio_mxn, Cobro)),
      check(<<"El ticket registra el tipo de cambio usado"/utf8>>, 175000, maps:get(tipo_cambio, Ticket)),
      check(<<"Un cambio posterior del tipo de cambio no altera el ticket"/utf8>>, 175000,
            maps:get(tipo_cambio, element(2, p59_inventario:venta_confirmada(maps:get(venta_id, Ticket))))),
      check(<<"pagos(MXN) - cambio = total"/utf8>>, Total,
            maps:get(recibido_mxn, Cobro) - maps:get(cambio_mxn, Cobro))]}.

%%% ------------------------------------------------------------------- E

en_proceso() ->
    #{id := Prod} = p59_cliente:producto_disponible(#{min => 2}),
    {ok, Antes} = p59_inventario:corte(#{caja => ?CAJA}),
    {ok, V0} = p59_cliente:abrir_venta(?CAJA),
    {ok, #{id := Id, totales := #{total := Total}} = V} = p59_cliente:agregar(V0, [{Prod, 1}]),
    {ok, Durante} = p59_inventario:corte(#{caja => ?CAJA}),
    {ok, _} = p59_cliente:pagar(V, p59_cliente:efectivo_exacto(Total)),
    {ok, Despues} = p59_inventario:corte(#{caja => ?CAJA}),
    NumVentas = fun(C) -> maps:get(numero, maps:get(ventas, C)) end,
    {[paso(<<"Venta abierta sin pagar"/utf8>>, #{venta => Id, total => Total}),
      paso(<<"Corte con la venta en proceso"/utf8>>,
           #{ventas => NumVentas(Durante), en_proceso => maps:get(en_proceso, Durante)})],
     [check(<<"La venta en proceso no se cuenta como vendida"/utf8>>, NumVentas(Antes), NumVentas(Durante)),
      check(<<"El efectivo esperado no cambia por la venta en proceso"/utf8>>,
            maps:get(efectivo_esperado, Antes), maps:get(efectivo_esperado, Durante)),
      check(<<"El corte la lista como 'en proceso'"/utf8>>, true,
            lists:any(fun(#{id := I}) -> I =:= Id end, maps:get(en_proceso, Durante))),
      check(<<"Al pagarla, entra al corte"/utf8>>, NumVentas(Antes) + 1, NumVentas(Despues)),
      check(<<"Invariante contable"/utf8>>, true, maps:get(ok, maps:get(invariante, Despues)))]}.

%%% ------------------------------------------------------------ auxiliares

estado({ok, #{estado := E}}) -> E;
estado({pendiente, #{estado := E}}) -> E;
estado({error, R}) -> {error, R};
estado(Otro) -> Otro.

paso(Descripcion, Datos) ->
    #{paso => Descripcion, datos => json_seguro(Datos)}.

check(Nombre, Esperado, Obtenido) ->
    #{verificacion => Nombre, ok => Esperado =:= Obtenido,
      esperado => json_seguro(Esperado), obtenido => json_seguro(Obtenido)}.

%% Convierte tuplas a listas para poder serializar la evidencia a JSON.
json_seguro(T) when is_tuple(T) -> [json_seguro(X) || X <- tuple_to_list(T)];
json_seguro(L) when is_list(L) -> [json_seguro(X) || X <- L];
json_seguro(M) when is_map(M) -> maps:map(fun(_, V) -> json_seguro(V) end, M);
json_seguro(X) -> X.
