-module(p59_corte).

%% Calculo puro del corte de caja a partir de movimientos confirmados.
%%
%% Politicas:
%%   - Cada movimiento cuenta en el turno vigente de la caja al confirmarse. Una
%%     cancelacion de un ticket de otro turno cuenta en el turno en que se hizo.
%%   - Los dolares se cuentan aparte, en dolares: el cajon tiene dos gavetas y el
%%     corte no reconvierte con un tipo de cambio distinto al de cada venta.
%%   - Las ventas en proceso se listan pero no se suman.
%%
%% Invariante contable (debe ser verdadero siempre):
%%   ventas - reembolsos =
%%       (efectivo_mxn - cambio - reembolso_efectivo)
%%     + valor_mxn_de_dolares + (tarjeta - reembolso_tarjeta)
%% y, por cada venta, suma(pagos en MXN) - cambio = total.

-export([calcular/2, sumar/1]).

-spec calcular([map()], map()) -> map().
calcular(Movs, Ctx) ->
    Ventas = [M || #{tipo := venta} = M <- Movs],
    Cancelaciones = [M || #{tipo := cancelacion} = M <- Movs],
    Devoluciones = [M || #{tipo := devolucion} = M <- Movs],
    Reembolsos = Cancelaciones ++ Devoluciones,
    Pago = fun(Metodo, Campo) ->
                   lists:sum([maps:get(Campo, P) || #{pagos := Ps} <- Ventas,
                                                    #{metodo := Mt} = P <- Ps, Mt =:= Metodo])
           end,
    Suma = fun(Campo, Lista) -> lists:sum([maps:get(Campo, M) || M <- Lista]) end,
    EfectivoMxn = Pago(efectivo_mxn, monto),
    Usd = Pago(efectivo_usd, monto),
    UsdValorMxn = Pago(efectivo_usd, monto_mxn),
    Tarjeta = Pago(tarjeta, monto_mxn),
    Cambio = Suma(cambio_mxn, Ventas),
    TotalVentas = Suma(total, Ventas),
    ReembolsoEfectivo = Suma(reembolso_efectivo, Reembolsos),
    ReembolsoTarjeta = Suma(reembolso_tarjeta, Reembolsos),
    MontoReembolsos = Suma(monto, Reembolsos),
    Fondo = maps:get(fondo_mxn, Ctx, 0),
    EsperadoMxn = Fondo + EfectivoMxn - Cambio - ReembolsoEfectivo,
    VentaNeta = TotalVentas - MontoReembolsos,
    Explicado = (EfectivoMxn - Cambio - ReembolsoEfectivo) + UsdValorMxn
        + (Tarjeta - ReembolsoTarjeta),
    VentasCuadran = lists:all(fun venta_cuadra/1, Ventas),
    Base = #{ventas => #{numero => length(Ventas), total => TotalVentas,
                         por_modalidad => por_modalidad(Ventas)},
             cobros => #{efectivo_mxn => EfectivoMxn,
                         efectivo_usd => Usd,
                         efectivo_usd_valor_mxn => UsdValorMxn,
                         tarjeta => Tarjeta,
                         cambio_entregado => Cambio},
             cancelaciones => #{numero => length(Cancelaciones),
                                monto => Suma(monto, Cancelaciones)},
             devoluciones => #{numero => length(Devoluciones),
                               monto => Suma(monto, Devoluciones)},
             reembolsos => #{efectivo => ReembolsoEfectivo, tarjeta => ReembolsoTarjeta},
             fondo_inicial => Fondo,
             venta_neta => VentaNeta,
             efectivo_esperado => #{mxn => EsperadoMxn, usd => Usd},
             en_proceso => maps:get(en_proceso, Ctx, []),
             invariante => #{ok => VentaNeta =:= Explicado andalso VentasCuadran,
                             venta_neta => VentaNeta,
                             explicado_por_medios => Explicado,
                             ventas_cuadran => VentasCuadran}},
    con_conteo(Base, maps:get(contado, Ctx, null)).

%% Suma de cortes (p. ej. consolidado de las cuatro cajas). Las cifras son
%% aditivas, por eso basta con sumar campo a campo.
-spec sumar([map()]) -> map().
sumar([]) ->
    calcular([], #{});
sumar([Primero | Resto]) ->
    lists:foldl(fun(C, Acc) -> sumar_mapas(solo_cifras(C), Acc) end, solo_cifras(Primero), Resto).

%% Lo que no es una cifra aditiva (fechas, alcance, estado) no se suma.
solo_cifras(Corte) ->
    maps:without([en_proceso, invariante, generado_en, alcance, estado_turno], Corte).

venta_cuadra(#{pagos := Pagos, cambio_mxn := Cambio, total := Total}) ->
    lists:sum([M || #{monto_mxn := M} <- Pagos]) - Cambio =:= Total.

por_modalidad(Ventas) ->
    Inicial = maps:from_list([{M, 0} || M <- [efectivo_mxn, efectivo_usd, tarjeta, mixto]]),
    lists:foldl(fun(#{modalidad := M}, Acc) -> maps:update_with(M, fun(V) -> V + 1 end, Acc) end,
                Inicial, Ventas).

con_conteo(Corte, null) ->
    Corte#{contado => null, diferencia => null, descuadre => false};
con_conteo(#{efectivo_esperado := #{mxn := Mxn, usd := Usd}} = Corte,
           #{mxn := ContadoMxn, usd := ContadoUsd} = Contado) ->
    Dif = #{mxn => ContadoMxn - Mxn, usd => ContadoUsd - Usd},
    Corte#{contado => Contado, diferencia => Dif,
           descuadre => Dif =/= #{mxn => 0, usd => 0}}.

sumar_mapas(A, B) when is_map(A), is_map(B) ->
    maps:fold(fun(K, V, Acc) ->
                      case maps:find(K, Acc) of
                          {ok, V2} -> Acc#{K => sumar_mapas(V, V2)};
                          error -> Acc#{K => V}
                      end
              end, B, A);
sumar_mapas(A, B) when is_integer(A), is_integer(B) -> A + B;
sumar_mapas(A, B) when is_boolean(A), is_boolean(B) -> A orelse B;
sumar_mapas(null, B) -> B;
sumar_mapas(A, _B) -> A.
