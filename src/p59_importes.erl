-module(p59_importes).

%% Calculo puro de importes de una venta y validacion de pagos.
%% No depende de procesos: todo se puede probar con eunit directamente.

-export([linea/1, totales/1, aplicar_pagos/3, metodos/0]).

-type partida() :: #{producto_id := binary(), cantidad := pos_integer(),
                     precio_unitario := non_neg_integer(), descuento_pct := 0..100,
                     tasa_iva := non_neg_integer(), _ => _}.
-type metodo() :: efectivo_mxn | efectivo_usd | tarjeta.
-export_type([partida/0, metodo/0]).

metodos() -> [efectivo_mxn, efectivo_usd, tarjeta].

%% IVA calculado y redondeado por partida (politica documentada en el README):
%% el total del ticket es la suma de importes de partida.
-spec linea(partida()) -> map().
linea(#{cantidad := C, precio_unitario := P, descuento_pct := D, tasa_iva := T} = Partida) ->
    Bruto = C * P,
    Descuento = (Bruto * D + 50) div 100,
    Base = Bruto - Descuento,
    Iva = p59_dinero:iva(Base, T),
    Partida#{bruto => Bruto, descuento => Descuento, base => Base, iva => Iva,
             importe => Base + Iva}.

-spec totales([partida()]) -> map().
totales(Partidas) ->
    Lineas = [linea(P) || P <- Partidas],
    Suma = fun(K) -> lists:sum([maps:get(K, L) || L <- Lineas]) end,
    #{partidas => Lineas,
      articulos => Suma(cantidad),
      subtotal => Suma(base),
      descuentos => Suma(descuento),
      iva => Suma(iva),
      total => Suma(importe)}.

%% Valora cada pago en pesos y calcula el cambio. Reglas:
%%   - el cambio siempre se entrega en efectivo MXN;
%%   - la tarjeta no puede exceder el total (no se da cambio de un cargo);
%%   - los dolares se valoran con el tipo de cambio capturado, redondeando a piso.
-spec aplicar_pagos(pos_integer(), [map()], pos_integer() | null) ->
    {ok, map()} | {error, term()}.
aplicar_pagos(Total, _Pagos, _Tc) when Total =< 0 ->
    {error, venta_vacia};
aplicar_pagos(Total, Pagos, Tc) ->
    case validar(Pagos, Tc) of
        ok ->
            Valorados = [valorar(P, Tc) || P <- Pagos],
            Recibido = lists:sum([M || #{monto_mxn := M} <- Valorados]),
            Tarjeta = lists:sum([M || #{metodo := tarjeta, monto_mxn := M} <- Valorados]),
            if
                Tarjeta > Total -> {error, tarjeta_excede_total};
                Recibido < Total -> {error, {pago_insuficiente, Total - Recibido}};
                true ->
                    {ok, #{pagos => Valorados,
                           recibido_mxn => Recibido,
                           cambio_mxn => Recibido - Total,
                           modalidad => modalidad(Valorados),
                           tipo_cambio => Tc}}
            end;
        Error ->
            Error
    end.

validar([], _Tc) ->
    {error, sin_pagos};
validar(Pagos, Tc) ->
    Metodos = [maps:get(metodo, P, invalido) || P <- Pagos],
    Montos = [maps:get(monto, P, invalido) || P <- Pagos],
    UsaUsd = lists:member(efectivo_usd, Metodos),
    case {lists:all(fun(M) -> lists:member(M, metodos()) end, Metodos),
          lists:all(fun(M) -> is_integer(M) andalso M > 0 end, Montos),
          length([tarjeta || tarjeta <- Metodos]) =< 1} of
        {false, _, _} -> {error, metodo_invalido};
        {_, false, _} -> {error, monto_invalido};
        {_, _, false} -> {error, mas_de_una_tarjeta};
        _ when UsaUsd, not (is_integer(Tc) andalso Tc > 0) -> {error, sin_tipo_de_cambio};
        _ -> ok
    end.

valorar(#{metodo := efectivo_usd, monto := M}, Tc) ->
    #{metodo => efectivo_usd, moneda => usd, monto => M,
      monto_mxn => p59_dinero:usd_a_mxn(M, Tc)};
valorar(#{metodo := Metodo, monto := M}, _Tc) ->
    #{metodo => Metodo, moneda => mxn, monto => M, monto_mxn => M}.

modalidad(Valorados) ->
    case lists:usort([M || #{metodo := M} <- Valorados]) of
        [Unico] -> Unico;
        _ -> mixto
    end.
