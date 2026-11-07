-module(p59_cliente).

%% Operaciones de alto nivel que usan la simulacion, los escenarios y la prueba
%% de caos. Pasan por la misma API Erlang que los manejadores HTTP.

-export([abrir_venta/1, abrir_venta/2, agregar/2, pagar/2, pagar/3, vender/3,
         operacion/1, efectivo_exacto/1, usd_suficiente/2, esperar/2,
         producto_disponible/1, asegurar_turno/1]).

%% Abre una venta en la caja; si la caja tiene una venta colgada de una corrida
%% previa, la cancela primero (queda registrado en la bitacora).
abrir_venta(Caja) ->
    abrir_venta(Caja, operacion(<<"crear">>)).

abrir_venta(Caja, Op) ->
    case p59_caja:iniciar_venta(Caja, Op) of
        {ok, V} -> {ok, V};
        {error, {venta_en_curso, Previa}} ->
            _ = p59_venta:cancelar(Previa, <<"Liberada para una nueva venta"/utf8>>),
            abrir_venta(Caja, Op);
        {error, caja_no_disponible} ->
            timer:sleep(20),
            abrir_venta(Caja, Op);
        Error -> Error
    end.

agregar(#{id := Id} = V, Lineas) ->
    lists:foldl(fun({P, Q}, {ok, _}) -> p59_venta:agregar(Id, P, Q, 0);
                   ({P, Q, D}, {ok, _}) -> p59_venta:agregar(Id, P, Q, D);
                   (_, Error) -> Error
                end, {ok, V}, Lineas).

pagar(V, Pagos) ->
    pagar(V, Pagos, operacion(<<"pago">>)).

pagar(#{id := Id}, Pagos, Op) ->
    p59_venta:pagar(Id, Pagos, Op).

%% Venta completa: abrir, agregar y pagar. Pagos puede ser una funcion del total.
vender(Caja, Lineas, Pagos) ->
    {ok, V0} = abrir_venta(Caja),
    case agregar(V0, Lineas) of
        {ok, #{totales := #{total := Total}} = V} ->
            P = case is_function(Pagos, 1) of true -> Pagos(Total); false -> Pagos end,
            pagar(V, P);
        Error -> Error
    end.

operacion(Prefijo) ->
    iolist_to_binary([Prefijo, $-, integer_to_binary(erlang:unique_integer([positive]))]).

efectivo_exacto(Total) ->
    [#{metodo => efectivo_mxn, monto => Total}].

%% Dolares redondeados hacia arriba al dolar entero y con margen, como pagaria
%% un cliente real con billetes.
usd_suficiente(Total, Tc) ->
    Centavos = (Total * 10000 + Tc - 1) div Tc,
    ((Centavos + 99) div 100) * 100.

%% Espera (sondeando) a que Fun() devuelva true, hasta TimeoutMs.
esperar(Fun, TimeoutMs) when TimeoutMs =< 0 ->
    Fun();
esperar(Fun, TimeoutMs) ->
    case catch Fun() of
        true -> true;
        _ -> timer:sleep(20), esperar(Fun, TimeoutMs - 20)
    end.

%% Producto activo con al menos N unidades disponibles y precio menor a Max.
producto_disponible(#{min := N} = Opts) ->
    Max = maps:get(precio_max, Opts, infinity),
    Excluir = maps:get(excluir, Opts, []),
    hd([P || #{id := Id, activo := true, existencia := E, reservado := R, precio := Pr} = P
                 <- p59_inventario:productos(),
             E - R >= N, Pr < Max, not lists:member(Id, Excluir)]).

asegurar_turno(Caja) ->
    case p59_inventario:turno(Caja) of
        {ok, #{estado := abierto} = T} -> T;
        {ok, #{cajero := C}} ->
            {ok, T} = p59_inventario:abrir_turno(Caja, C, p59_config:obtener(fondo_inicial)),
            T
    end.
