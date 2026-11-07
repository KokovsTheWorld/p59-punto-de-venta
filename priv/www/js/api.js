// Cliente de la API Cowboy del punto de venta (#59).
// Capa independiente de la vista: la interfaz de Stitch debe reutilizar este
// archivo tal cual y solo cambiar el HTML/CSS. Todos los montos son centavos.

const API = (() => {
  async function pedir(metodo, ruta, cuerpo) {
    const opciones = { method: metodo, headers: {} };
    if (cuerpo !== undefined) {
      opciones.headers['content-type'] = 'application/json';
      opciones.body = JSON.stringify(cuerpo);
    }
    const r = await fetch(ruta, opciones);
    const texto = await r.text();
    let datos = null;
    try { datos = texto ? JSON.parse(texto) : null; } catch (_) { datos = { texto }; }
    if (!r.ok && r.status !== 202) {
      const e = new Error((datos && datos.mensaje) || `HTTP ${r.status}`);
      e.status = r.status; e.datos = datos;
      throw e;
    }
    return { status: r.status, datos };
  }
  const get = (ruta) => pedir('GET', ruta).then((r) => r.datos);
  const post = (ruta, cuerpo = {}) => pedir('POST', ruta, cuerpo);
  const operacion = (p) => `${p}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

  return {
    estado: () => get('/api/estado'),
    diagnostico: () => get('/api/diagnostico'),
    productos: (q = '', pagina = 1, limite = 20, categoria = '') =>
      get(`/api/productos?q=${encodeURIComponent(q)}&pagina=${pagina}&limite=${limite}&categoria=${encodeURIComponent(categoria)}`),
    cajas: () => get('/api/cajas'),
    caja: (id) => get(`/api/cajas/${id}`),
    abrirTurno: (caja, cajero, fondo_mxn) => post(`/api/cajas/${caja}/turno`, { cajero, fondo_mxn }),
    cerrarTurno: (caja, efectivo_contado_mxn, efectivo_contado_usd) =>
      post(`/api/cajas/${caja}/turno/cerrar`, { efectivo_contado_mxn, efectivo_contado_usd }),
    ventas: (estado = '', caja = '') => get(`/api/ventas?estado=${estado}&caja=${caja}`),
    venta: (id) => get(`/api/ventas/${id}`),
    crearVenta: (caja) => post('/api/ventas', { caja, operacion_id: operacion('crear') }),
    agregar: (id, producto_id, cantidad, descuento_pct = 0) =>
      post(`/api/ventas/${id}/partidas`, { producto_id, cantidad, descuento_pct }),
    retirar: (id, producto) => pedir('DELETE', `/api/ventas/${id}/partidas/${producto}`),
    // operacion_id se genera una vez por intento de cobro: si la red falla, se
    // reintenta con el MISMO id y el servidor no cobra dos veces.
    pagar: (id, pagos, operacion_id) => post(`/api/ventas/${id}/pago`, { pagos, operacion_id }),
    revisar: (id) => post(`/api/ventas/${id}/revisar`),
    cancelarVenta: (id, motivo) => post(`/api/ventas/${id}/cancelar`, { motivo }),
    tickets: (caja = '') => get(`/api/tickets?caja=${caja}`),
    ticket: (folio) => get(`/api/tickets/${folio}`),
    cancelarTicket: (folio, caja, motivo) => post(`/api/tickets/${folio}/cancelar`, { caja, motivo }),
    devolver: (folio, caja, partidas, motivo) =>
      post(`/api/tickets/${folio}/devolucion`, { caja, partidas, motivo, operacion_id: operacion('dev') }),
    corte: (params = '') => get(`/api/corte${params}`),
    eventos: (limite = 100) => get(`/api/eventos?limite=${limite}`),
    tipoCambio: () => get('/api/tipo-cambio'),
    fijarTipoCambio: (valor) => post('/api/tipo-cambio', { valor }),
    simular: (accion, cuerpo = {}) => post(`/api/simulacion/${accion}`, cuerpo),
    escenario: (letra) => post(`/api/simulacion/escenarios/${letra}`),
    carga: () => get('/api/simulacion/carga'),
    operacion,
    // Tiempo real: Server-Sent Events con la bitacora.
    eventosEnVivo(alRecibir, alCambiarConexion) {
      const fuente = new EventSource('/api/eventos/stream');
      fuente.onmessage = (m) => alRecibir(JSON.parse(m.data));
      fuente.onopen = () => alCambiarConexion && alCambiarConexion(true);
      fuente.onerror = () => alCambiarConexion && alCambiarConexion(false);
      return fuente;
    },
  };
})();

// Dinero: enteros en centavos, nunca flotantes.
const Dinero = {
  formato(c, moneda = 'MXN') {
    if (c === null || c === undefined) return '—';
    const neg = c < 0; const a = Math.abs(c);
    const enteros = Math.floor(a / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    const s = `${moneda === 'USD' ? 'US$' : '$'}${enteros}.${String(a % 100).padStart(2, '0')}`;
    return neg ? `-${s}` : s;
  },
  // "123.4" -> 12340. Se parsea como texto para no pasar por float.
  aCentavos(texto) {
    const t = String(texto).trim().replace(/,/g, '');
    if (!/^\d+(\.\d{0,2})?$/.test(t)) return null;
    const [e, d = ''] = t.split('.');
    return parseInt(e, 10) * 100 + parseInt((d + '00').slice(0, 2), 10);
  },
  tc(v) { return v ? `${Math.floor(v / 10000)}.${String(v % 10000).padStart(4, '0')}` : '—'; },
};
