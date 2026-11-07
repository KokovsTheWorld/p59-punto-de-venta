-module(p59_dinero).

%% Aritmetica monetaria exacta. Convenciones de todo el sistema:
%%   - montos en centavos (enteros), nunca flotantes;
%%   - tasas en puntos base: 1600 = 16 %;
%%   - tipo de cambio en diezmilesimos de peso por dolar: 182000 = 18.2000.

-export([iva/2, usd_a_mxn/2, acumulado/3, formatear/1, formatear_usd/1,
         formatear_tc/1]).

%% Redondeo a medio centavo hacia arriba, aplicado por partida.
-spec iva(non_neg_integer(), non_neg_integer()) -> non_neg_integer().
iva(Base, TasaPb) when Base >= 0, TasaPb >= 0 ->
    (Base * TasaPb + 5000) div 10000.

%% Piso: la tienda nunca acredita mas pesos de los que valen los dolares recibidos.
-spec usd_a_mxn(non_neg_integer(), pos_integer()) -> non_neg_integer().
usd_a_mxn(CentavosUsd, TipoCambio) when CentavosUsd >= 0, TipoCambio > 0 ->
    (CentavosUsd * TipoCambio) div 10000.

%% Parte acumulada de Monto que corresponde a Unidades de Total. Las devoluciones
%% parciales usan diferencias de acumulados para que la suma de las partes sea
%% exactamente el monto original, sin centavos perdidos ni sobrantes.
-spec acumulado(non_neg_integer(), non_neg_integer(), pos_integer()) -> non_neg_integer().
acumulado(Monto, Unidades, Total) when Unidades =< Total ->
    (Monto * Unidades) div Total.

-spec formatear(integer()) -> binary().
formatear(Centavos) when Centavos < 0 ->
    <<"-", (formatear(-Centavos))/binary>>;
formatear(Centavos) ->
    <<"$", (cifra(Centavos))/binary>>.

formatear_usd(Centavos) when Centavos < 0 ->
    <<"-", (formatear_usd(-Centavos))/binary>>;
formatear_usd(Centavos) ->
    <<"US$", (cifra(Centavos))/binary>>.

formatear_tc(TipoCambio) ->
    iolist_to_binary(io_lib:format("~b.~4..0b", [TipoCambio div 10000, TipoCambio rem 10000])).

cifra(Centavos) ->
    Enteros = miles(integer_to_list(Centavos div 100)),
    iolist_to_binary(io_lib:format("~s.~2..0b", [Enteros, Centavos rem 100])).

miles(Digitos) when length(Digitos) =< 3 ->
    Digitos;
miles(Digitos) ->
    {Cabeza, Cola} = lists:split(length(Digitos) - 3, Digitos),
    miles(Cabeza) ++ "," ++ Cola.
