-module(p59_catalogo).

%% Generador determinista del catalogo: la misma semilla produce siempre los
%% mismos productos, precios y existencias, asi la demo y las pruebas son
%% reproducibles sin una base de datos externa.

-export([generar/2, categorias/0]).

-spec generar(pos_integer(), integer()) -> [map()].
generar(N, Semilla) ->
    S0 = rand:seed_s(exsss, {Semilla, Semilla * 7 + 1, Semilla * 13 + 2}),
    {Productos, _} = lists:mapfoldl(fun producto/2, S0, lists:seq(1, N)),
    Productos.

%% Los alimentos basicos y frutas/verduras van a tasa 0 % de IVA (LIVA art. 2-A).
categorias() ->
    [{<<"Abarrotes"/utf8>>, tasa_cero,
      [<<"Arroz"/utf8>>, <<"Frijol"/utf8>>, <<"Aceite"/utf8>>, <<"Azúcar"/utf8>>,
       <<"Harina"/utf8>>, <<"Atún"/utf8>>, <<"Pasta"/utf8>>, <<"Leche"/utf8>>]},
     {<<"Frutas y verduras"/utf8>>, tasa_cero,
      [<<"Manzana"/utf8>>, <<"Plátano"/utf8>>, <<"Jitomate"/utf8>>, <<"Aguacate"/utf8>>,
       <<"Cebolla"/utf8>>, <<"Limón"/utf8>>]},
     {<<"Bebidas"/utf8>>, general,
      [<<"Refresco"/utf8>>, <<"Agua mineral"/utf8>>, <<"Jugo"/utf8>>, <<"Café"/utf8>>,
       <<"Té helado"/utf8>>, <<"Bebida energética"/utf8>>]},
     {<<"Botanas y dulces"/utf8>>, general,
      [<<"Papas"/utf8>>, <<"Cacahuates"/utf8>>, <<"Chocolate"/utf8>>, <<"Galletas"/utf8>>,
       <<"Gomitas"/utf8>>]},
     {<<"Limpieza"/utf8>>, general,
      [<<"Detergente"/utf8>>, <<"Cloro"/utf8>>, <<"Jabón de trastes"/utf8>>,
       <<"Suavizante"/utf8>>, <<"Esponja"/utf8>>]},
     {<<"Cuidado personal"/utf8>>, general,
      [<<"Shampoo"/utf8>>, <<"Pasta dental"/utf8>>, <<"Desodorante"/utf8>>,
       <<"Jabón de tocador"/utf8>>, <<"Papel higiénico"/utf8>>]},
     {<<"Papelería"/utf8>>, general,
      [<<"Cuaderno"/utf8>>, <<"Bolígrafo"/utf8>>, <<"Lápiz"/utf8>>, <<"Marcador"/utf8>>]},
     {<<"Ferretería ligera"/utf8>>, general,
      [<<"Foco LED"/utf8>>, <<"Cinta aislante"/utf8>>, <<"Pilas AA"/utf8>>,
       <<"Extensión eléctrica"/utf8>>]}].

marcas() ->
    [<<"Del Valle Norte"/utf8>>, <<"La Frontera"/utf8>>, <<"Bajamar"/utf8>>,
     <<"Costa Azul"/utf8>>, <<"Sierra"/utf8>>, <<"Don Pancho"/utf8>>,
     <<"Pacífico"/utf8>>, <<"Rosarito"/utf8>>].

presentaciones() ->
    [<<"chico"/utf8>>, <<"mediano"/utf8>>, <<"grande"/utf8>>, <<"familiar"/utf8>>,
     <<"paquete"/utf8>>].

producto(I, S0) ->
    {{Categoria, TipoIva, Nombres}, S1} = elegir(categorias(), S0),
    {Nombre, S2} = elegir(Nombres, S1),
    {Marca, S3} = elegir(marcas(), S2),
    {Presentacion, S4} = elegir(presentaciones(), S3),
    {Precio, S5} = rand:uniform_s(900, S4),
    {Existencia, S6} = rand:uniform_s(53, S5),
    Producto = #{id => id(I),
                 nombre => <<Nombre/binary, " ", Marca/binary, " ", Presentacion/binary>>,
                 categoria => Categoria,
                 tipo_iva => TipoIva,
                 %% Precio sin IVA, multiplo de 50 centavos, entre $5.00 y $454.50.
                 precio => 450 + Precio * 50,
                 existencia_inicial => existencia_inicial(I, Existencia),
                 activo => I rem 97 =/= 0},
    {Producto, S6}.

%% Uno de cada 40 productos tiene solo 2 unidades: sirve para demostrar la
%% competencia entre cajas por las ultimas piezas.
existencia_inicial(I, _Aleatoria) when I rem 40 =:= 0 -> 2;
existencia_inicial(_I, Aleatoria) -> 7 + Aleatoria.

id(I) ->
    iolist_to_binary(io_lib:format("P~4..0b", [I])).

elegir(Lista, S0) ->
    {Indice, S1} = rand:uniform_s(length(Lista), S0),
    {lists:nth(Indice, Lista), S1}.
