-module(p59_ticket).

%% Representacion imprimible del ticket. Es un COMPROBANTE INTERNO de la demo:
%% no es un CFDI, no tiene sello digital ni timbre de un PAC.

-export([texto/2]).

-define(ANCHO, 44).

-spec texto(map(), [map()]) -> binary().
texto(#{folio := Folio, venta_id := VentaId, caja := Caja, cajero := Cajero, turno := Turno,
        fecha := Fecha, partidas := Partidas} = V, Reembolsos) ->
    Lineas =
        [centrar(<<"TIENDA DEMO — PUNTO DE VENTA #59"/utf8>>),
         centrar(<<"Tijuana, B.C."/utf8>>),
         centrar(<<"COMPROBANTE INTERNO — NO ES CFDI"/utf8>>),
         separador(),
         [<<"Ticket: "/utf8>>, Folio, <<"   Venta: "/utf8>>, VentaId],
         [<<"Caja "/utf8>>, integer_to_binary(Caja), <<"  Turno "/utf8>>, integer_to_binary(Turno),
          <<"  Cajero: "/utf8>>, Cajero],
         [<<"Fecha: "/utf8>>, fecha(Fecha)],
         separador()]
        ++ lists:append([partida(P) || P <- Partidas])
        ++ [separador(),
            par(<<"Subtotal"/utf8>>, p59_dinero:formatear(maps:get(subtotal, V))),
            par(<<"Descuentos"/utf8>>, p59_dinero:formatear(-maps:get(descuentos, V))),
            par(<<"IVA"/utf8>>, p59_dinero:formatear(maps:get(iva, V))),
            par(<<"TOTAL"/utf8>>, p59_dinero:formatear(maps:get(total, V))),
            separador()]
        ++ [pago(P) || P <- maps:get(pagos, V)]
        ++ tipo_cambio(V)
        ++ [par(<<"Cambio (MXN)"/utf8>>, p59_dinero:formatear(maps:get(cambio_mxn, V)))]
        ++ autorizacion(V)
        ++ lists:append([reembolso(R) || R <- Reembolsos])
        ++ [separador(), centrar(<<"Gracias por su compra"/utf8>>)],
    unicode:characters_to_binary([[L, $\n] || L <- Lineas]).

partida(#{nombre := Nombre, cantidad := C, precio_unitario := P, descuento := D,
          tasa_iva := T, importe := I}) ->
    [Nombre,
     par(iolist_to_binary([<<"  "/utf8>>, integer_to_binary(C), <<" x "/utf8>>,
                           p59_dinero:formatear(P), <<"  IVA "/utf8>>,
                           integer_to_binary(T div 100), <<"%"/utf8>>,
                           case D of 0 -> <<>>; _ -> [<<"  desc "/utf8>>, p59_dinero:formatear(D)] end]),
         p59_dinero:formatear(I))].

pago(#{metodo := efectivo_usd, monto := M, monto_mxn := Mxn}) ->
    par(<<"Efectivo USD "/utf8>>, iolist_to_binary([p59_dinero:formatear_usd(M), <<" = "/utf8>>,
                                                     p59_dinero:formatear(Mxn)]));
pago(#{metodo := efectivo_mxn, monto := M}) ->
    par(<<"Efectivo MXN"/utf8>>, p59_dinero:formatear(M));
pago(#{metodo := tarjeta, monto := M}) ->
    par(<<"Tarjeta (simulada)"/utf8>>, p59_dinero:formatear(M)).

tipo_cambio(#{tipo_cambio := Tc, pagos := Pagos}) when is_integer(Tc) ->
    case [x || #{metodo := efectivo_usd} <- Pagos] of
        [] -> [];
        _ -> [par(<<"Tipo de cambio"/utf8>>, p59_dinero:formatear_tc(Tc))]
    end;
tipo_cambio(_) -> [].

autorizacion(#{autorizacion := A}) when is_binary(A) -> [par(<<"Autorización"/utf8>>, A)];
autorizacion(_) -> [].

reembolso(#{tipo := Tipo, id := Id, monto := M, fecha := F, turno := T}) ->
    [separador(),
     [string:uppercase(atom_to_binary(Tipo)), <<" "/utf8>>, Id, <<" "/utf8>>, fecha(F)],
     par([<<"  turno "/utf8>>, integer_to_binary(T)], p59_dinero:formatear(-M))].

par(Izq, Der) ->
    I = unicode:characters_to_list(Izq),
    D = unicode:characters_to_list(Der),
    Relleno = max(1, ?ANCHO - length(I) - length(D)),
    [I, lists:duplicate(Relleno, $\s), D].

centrar(Texto) ->
    T = unicode:characters_to_list(Texto),
    [lists:duplicate(max(0, (?ANCHO - length(T)) div 2), $\s), T].

separador() ->
    lists:duplicate(?ANCHO, $-).

fecha(Ms) ->
    {{A, Me, D}, {H, Mi, S}} = calendar:system_time_to_local_time(Ms, millisecond),
    iolist_to_binary(io_lib:format("~4..0b-~2..0b-~2..0b ~2..0b:~2..0b:~2..0b", [A, Me, D, H, Mi, S])).
