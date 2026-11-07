-module(p59_movimientos).

%% Construccion pura de los registros del libro de movimientos. Un movimiento
%% nunca se modifica ni se borra: las cancelaciones y devoluciones son
%% movimientos nuevos que referencian el folio original.

-export([venta/4, reembolso/5, unidades_devueltas/2]).

-spec venta(map(), binary(), map(), integer()) -> map().
venta(#{id := VentaId, caja := Caja, totales := Totales, cobro := Cobro} = Venta,
      Folio, #{turno := Turno, cajero := Cajero}, Fecha) ->
    #{tipo => venta,
      folio => Folio,
      venta_id => VentaId,
      caja => Caja,
      cajero => Cajero,
      turno => Turno,
      fecha => Fecha,
      partidas => maps:get(partidas, Totales),
      articulos => maps:get(articulos, Totales),
      subtotal => maps:get(subtotal, Totales),
      descuentos => maps:get(descuentos, Totales),
      iva => maps:get(iva, Totales),
      total => maps:get(total, Totales),
      pagos => maps:get(pagos, Cobro),
      modalidad => maps:get(modalidad, Cobro),
      recibido_mxn => maps:get(recibido_mxn, Cobro),
      cambio_mxn => maps:get(cambio_mxn, Cobro),
      tipo_cambio => maps:get(tipo_cambio, Cobro),
      autorizacion => maps:get(autorizacion, Venta, null)}.

%% Devolucion parcial o cancelacion (= devolver todo lo que falte) de un ticket.
%% Relacionados son los reembolsos previos del mismo folio. El monto de cada
%% partida se calcula con acumulados (p59_dinero:acumulado/3) para que la suma de
%% todas las devoluciones de un ticket sea exactamente su total.
%% Politica de reembolso: primero se revierte a tarjeta lo que se cobro con
%% tarjeta y el resto se entrega en efectivo MXN. Nunca se entregan dolares.
-spec reembolso(devolucion | cancelacion, map(), [map()],
                [{binary(), pos_integer()}] | todo, map()) -> {ok, map()} | {error, term()}.
reembolso(Tipo, #{tipo := venta} = Venta, Relacionados, Unidades0, Ctx) ->
    case [cancelado || #{tipo := cancelacion} <- Relacionados] of
        [_ | _] ->
            {error, ticket_cancelado};
        [] ->
            Devueltas = unidades_devueltas(Venta, Relacionados),
            Unidades = case Unidades0 of
                           todo -> pendientes(Venta, Devueltas);
                           _ -> agrupar(Unidades0)
                       end,
            case validar_unidades(Unidades, Venta, Devueltas) of
                ok -> {ok, construir(Tipo, Venta, Relacionados, Unidades, Devueltas, Ctx)};
                Error -> Error
            end
    end.

-spec unidades_devueltas(map(), [map()]) -> #{binary() => non_neg_integer()}.
unidades_devueltas(#{partidas := Partidas}, Relacionados) ->
    Inicial = maps:from_list([{Id, 0} || #{producto_id := Id} <- Partidas]),
    lists:foldl(
      fun(#{partidas := Ps}, Acc) ->
              lists:foldl(fun(#{producto_id := Id, cantidad := Q}, A) ->
                                  maps:update_with(Id, fun(V) -> V + Q end, Q, A)
                          end, Acc, Ps)
      end, Inicial, Relacionados).

pendientes(#{partidas := Partidas}, Devueltas) ->
    [{Id, C - maps:get(Id, Devueltas)} || #{producto_id := Id, cantidad := C} <- Partidas,
                                          C > maps:get(Id, Devueltas)].

agrupar(Unidades) ->
    maps:to_list(lists:foldl(fun({Id, Q}, Acc) ->
                                     maps:update_with(Id, fun(V) -> V + Q end, Q, Acc)
                             end, #{}, Unidades)).

validar_unidades([], _Venta, _Devueltas) ->
    {error, sin_unidades_por_devolver};
validar_unidades(Unidades, #{partidas := Partidas}, Devueltas) ->
    Vendidas = maps:from_list([{Id, C} || #{producto_id := Id, cantidad := C} <- Partidas]),
    Invalidas = [Id || {Id, Q} <- Unidades,
                       not (is_integer(Q) andalso Q > 0
                            andalso maps:is_key(Id, Vendidas)
                            andalso maps:get(Id, Devueltas) + Q =< maps:get(Id, Vendidas))],
    case Invalidas of
        [] -> ok;
        _ -> {error, {cantidad_no_devolvible, Invalidas}}
    end.

construir(Tipo, Venta, Relacionados, Unidades, Devueltas, Ctx) ->
    #{partidas := Partidas, pagos := Pagos} = Venta,
    PorId = maps:from_list([{Id, P} || #{producto_id := Id} = P <- Partidas]),
    Lineas = [begin
                  #{cantidad := N, importe := Imp, nombre := Nombre} = maps:get(Id, PorId),
                  R = maps:get(Id, Devueltas),
                  Monto = p59_dinero:acumulado(Imp, R + Q, N) - p59_dinero:acumulado(Imp, R, N),
                  #{producto_id => Id, nombre => Nombre, cantidad => Q, importe => Monto}
              end || {Id, Q} <- Unidades],
    Monto = lists:sum([I || #{importe := I} <- Lineas]),
    TarjetaCobrada = lists:sum([M || #{metodo := tarjeta, monto_mxn := M} <- Pagos]),
    TarjetaRevertida = lists:sum([maps:get(reembolso_tarjeta, M) || M <- Relacionados]),
    ATarjeta = min(Monto, TarjetaCobrada - TarjetaRevertida),
    #{tipo => Tipo,
      id => maps:get(id, Ctx),
      folio => maps:get(folio, Venta),
      venta_id => maps:get(venta_id, Venta),
      caja => maps:get(caja, Ctx),
      cajero => maps:get(cajero, Ctx),
      turno => maps:get(turno, Ctx),
      fecha => maps:get(fecha, Ctx),
      motivo => maps:get(motivo, Ctx, <<>>),
      caja_original => maps:get(caja, Venta),
      turno_original => maps:get(turno, Venta),
      partidas => Lineas,
      monto => Monto,
      reembolso_tarjeta => ATarjeta,
      reembolso_efectivo => Monto - ATarjeta}.
