-module(p59_terminal_bancaria).
-behaviour(gen_server).

%% Terminal bancaria SIMULADA. No hay integracion con ningun banco.
%%
%% El "banco" guarda sus autorizaciones en su propio archivo DETS porque, en la
%% realidad, el registro del banco sobrevive a una caida de la terminal: es lo
%% que permite preguntar despues "¿se cobro la referencia X?".
%%
%% Modos de falla inyectables:
%%   normal               autoriza
%%   rechazar             rechaza el cargo
%%   fuera_de_linea       no hay conexion; se sabe que no se cobro
%%   caida_antes_de_cobro no responde y el cargo NO llego al banco
%%   caida_tras_cobro     no responde pero el banco SI autorizo
%%   aleatorio            mezcla de los anteriores segun probabilidades
%% Con una_vez = true el modo se aplica a una sola operacion y vuelve a normal.

-export([start_link/0, cobrar/2, consultar/1, revertir/1, fijar_modo/2, estado/0]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2]).

-define(BANCO, p59_banco_simulado).
-define(MODOS, [normal, rechazar, fuera_de_linea, caida_antes_de_cobro,
                caida_tras_cobro, aleatorio]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec cobrar(binary(), pos_integer()) ->
    {ok, binary()} | {error, rechazada | fuera_de_linea | sin_respuesta}.
cobrar(Referencia, Monto) ->
    llamar({cobrar, Referencia, Monto}).

-spec consultar(binary()) -> {aprobado, binary()} | no_encontrado | {error, sin_respuesta}.
consultar(Referencia) ->
    llamar({consultar, Referencia}).

revertir(Referencia) ->
    llamar({revertir, Referencia}).

fijar_modo(Modo, Opciones) ->
    case lists:member(Modo, ?MODOS) of
        true -> gen_server:call(?MODULE, {modo, Modo, Opciones});
        false -> {error, modo_invalido}
    end.

estado() ->
    gen_server:call(?MODULE, estado).

%% El llamador nunca muere por la terminal: un timeout o una terminal caida se
%% traducen en sin_respuesta y la venta decide (normalmente, revision).
llamar(Msg) ->
    Timeout = p59_config:obtener(terminal_timeout_ms),
    try
        gen_server:call(?MODULE, Msg, Timeout)
    catch
        exit:{timeout, _} -> {error, sin_respuesta};
        exit:{noproc, _} -> {error, sin_respuesta};
        exit:{_, {gen_server, call, _}} -> {error, sin_respuesta}
    end.

init([]) ->
    process_flag(trap_exit, true),
    Archivo = filename:join(p59_config:data_dir(), "banco_simulado.dets"),
    ok = filelib:ensure_dir(Archivo),
    {ok, _} = dets:open_file(?BANCO, [{file, Archivo}, {type, set}, {repair, true}]),
    p59_metricas:inicio(?MODULE),
    {ok, #{modo => normal, una_vez => false,
           prob => #{rechazo => 30, caida => 15},   % por mil, solo en modo aleatorio
           rand => rand:seed_s(exsss, 5959)}}.

handle_call({cobrar, Ref, Monto}, _From, S0) ->
    {Modo, S} = modo_efectivo(S0),
    case Modo of
        normal ->
            {reply, {ok, autorizar(Ref, Monto)}, S};
        rechazar ->
            evento(alerta, [<<"Terminal: cargo rechazado "/utf8>>, Ref], Ref),
            {reply, {error, rechazada}, S};
        fuera_de_linea ->
            evento(falla, [<<"Terminal fuera de línea "/utf8>>, Ref], Ref),
            {reply, {error, fuera_de_linea}, S};
        caida_antes_de_cobro ->
            evento(falla, [<<"Terminal cayó antes de cobrar "/utf8>>, Ref], Ref),
            {noreply, S};
        caida_tras_cobro ->
            _ = autorizar(Ref, Monto),
            evento(falla, [<<"Terminal cayó tras cobrar "/utf8>>, Ref], Ref),
            {noreply, S}
    end;
handle_call({consultar, _Ref}, _From, #{modo := fuera_de_linea} = S) ->
    {reply, {error, sin_respuesta}, S};
handle_call({consultar, Ref}, _From, S) ->
    Respuesta = case dets:lookup(?BANCO, Ref) of
                    [{_, #{estado := aprobado, autorizacion := Aut}}] -> {aprobado, Aut};
                    _ -> no_encontrado
                end,
    {reply, Respuesta, S};
handle_call({revertir, Ref}, _From, S) ->
    case dets:lookup(?BANCO, Ref) of
        [{_, Registro}] -> ok = dets:insert(?BANCO, {Ref, Registro#{estado => revertido}});
        [] -> ok
    end,
    {reply, ok, S};
handle_call({modo, Modo, Opciones}, _From, S) ->
    evento(case Modo of normal -> ok; _ -> alerta end,
           [<<"Terminal en modo "/utf8>>, atom_to_binary(Modo)], null),
    {reply, ok, S#{modo := Modo,
                   una_vez := maps:get(una_vez, Opciones, false),
                   prob := maps:merge(maps:get(prob, S), maps:get(prob, Opciones, #{}))}};
handle_call(estado, _From, S) ->
    {reply, maps:with([modo, una_vez, prob], S), S}.

handle_cast(_Msg, S) ->
    {noreply, S}.

terminate(_Reason, _S) ->
    dets:close(?BANCO).

modo_efectivo(#{modo := aleatorio, prob := #{rechazo := PR, caida := PC}, rand := R0} = S) ->
    {X, R1} = rand:uniform_s(1000, R0),
    Modo = if X =< PR -> rechazar;
              X =< PR + PC div 2 -> caida_tras_cobro;
              X =< PR + PC -> caida_antes_de_cobro;
              true -> normal
           end,
    {Modo, S#{rand := R1}};
modo_efectivo(#{modo := Modo, una_vez := true} = S) ->
    {Modo, S#{modo := normal, una_vez := false}};
modo_efectivo(#{modo := Modo} = S) ->
    {Modo, S}.

%% Idempotente por referencia: repetir el cargo de una referencia ya aprobada
%% devuelve la misma autorizacion y no cobra dos veces.
autorizar(Ref, Monto) ->
    case dets:lookup(?BANCO, Ref) of
        [{_, #{estado := aprobado, autorizacion := Aut}}] ->
            Aut;
        _ ->
            Aut = iolist_to_binary(io_lib:format("AUT~6..0b", [erlang:unique_integer([positive]) rem 1000000])),
            ok = dets:insert(?BANCO, {Ref, #{estado => aprobado, monto => Monto,
                                             autorizacion => Aut}}),
            ok = dets:sync(?BANCO),
            Aut
    end.

evento(Nivel, Mensaje, Ref) ->
    p59_eventos:publicar(terminal, Nivel, Mensaje, #{referencia => Ref}).
