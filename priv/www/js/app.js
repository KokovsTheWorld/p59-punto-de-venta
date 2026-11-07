// Vistas de la interfaz diseñada en Google Stitch, conectadas a la API Cowboy.
// Enrutador por hash, sin dependencias. Todo dato mostrado viene del backend:
// lo que Stitch inventó y el sistema no tiene (Mnesia, báscula, firmas, etc.)
// se reemplazó por la información real equivalente.

const { esc, hora, fecha, icono, tarjeta, etiqueta, boton, entrada, insignia, insigniaVenta, pid, kpi, titulo, fila } = UI;
const $vista = document.getElementById('vista');
const $ = (sel) => $vista.querySelector(sel);
const $$ = (sel) => [...$vista.querySelectorAll(sel)];
const sistema = { ivaGeneral: 1600, tc: null, nodo: '' };

function aviso(texto) {
  const t = document.getElementById('toast');
  t.textContent = texto; t.classList.remove('hidden');
  clearTimeout(aviso.t); aviso.t = setTimeout(() => t.classList.add('hidden'), 3800);
}

async function accion(fn, exito) {
  try { const r = await fn(); if (exito) aviso(exito); return r; }
  catch (e) { aviso(`Error: ${e.message}`); return null; }
}

const usdDe = (centavosMxn) => (sistema.tc ? Math.ceil((centavosMxn * 10000) / sistema.tc) : null);
const cuadricula = (contenido, cols = 'grid-cols-1 sm:grid-cols-2 lg:grid-cols-4') => `<section class="grid ${cols} gap-space-md">${contenido}</section>`;

// Semaforo de una caja con datos reales del proceso y del turno.
function nivelCaja(c) {
  if (!c.proceso.vivo) return ['Proceso caído', 'falla'];
  if (c.venta_actual && c.venta_actual.estado === 'pendiente_de_revision') return ['Cobro en revisión', 'falla'];
  if (!c.turno || c.turno.estado !== 'abierto') return ['Turno cerrado', 'alerta'];
  if (c.proceso.reinicios > 0) return [`Operando · ${c.proceso.reinicios} reinicio${c.proceso.reinicios > 1 ? 's' : ''}`, 'alerta'];
  return ['Operando', 'ok'];
}

function pestanasCaja(actual, ruta) {
  return `<div class="flex flex-wrap bg-surface-container-low rounded-lg p-1 gap-1">${[1, 2, 3, 4].map((n) => `
    <a href="#/${ruta}/${n}" class="px-space-md py-space-xs rounded font-body-sm text-body-sm ${n === actual ? 'bg-primary-container text-on-primary font-semibold' : 'text-on-surface-variant hover:bg-surface-container'}">
      ${n === actual ? '<span class="inline-block w-2 h-2 rounded-full bg-primary-fixed mr-1"></span>' : ''}Caja ${n}</a>`).join('')}</div>`;
}

// ===================================================================== TABLERO

async function tablero() {
  const [estado, { cajas }, { eventos }, corte, diag] = await Promise.all([
    API.estado(), API.cajas(), API.eventos(8), API.corte(''), API.diagnostico()]);
  const r = estado.resumen; const c = corte.consolidado; const vm = diag.vm;
  const ventasTurno = Object.fromEntries(corte.cajas.map((k) => [k.alcance.caja, k.ventas.numero]));
  const modal = c.ventas.por_modalidad; const totalModal = Object.values(modal).reduce((a, b) => a + b, 0) || 1;
  const pct = (n) => Math.round((n * 100) / totalModal);
  const raiz = estado.arbol;
  $vista.innerHTML = `<div class="flex flex-col w-full gap-space-lg">
    <div class="w-full bg-surface-container-low rounded-lg p-space-sm flex flex-wrap items-center justify-between gap-space-sm shadow-sm">
      <div class="flex flex-wrap items-center gap-space-sm">
        <div class="w-2.5 h-2.5 rounded-full bg-primary animate-pulse"></div>
        <span class="font-headline-md text-body-sm font-semibold text-primary">NODO BEAM ACTIVO</span>
        <span class="font-label-receipt text-label-receipt text-secondary">|</span>
        <span class="font-label-numeric-sm text-label-numeric-sm text-on-surface-variant font-medium">${esc(raiz.id)} ${esc(raiz.pid)}</span>
        <span class="font-label-receipt text-label-receipt text-secondary">|</span>
        <span class="font-body-sm text-body-sm text-on-surface-variant">${estado.cajas_activas}/${cajas.length} cajas atendiendo</span>
      </div>
      <div class="flex flex-wrap items-center gap-space-md">
        <span class="font-label-numeric-sm text-label-numeric-sm text-secondary">Ventas en proceso: <strong class="text-primary font-semibold">${estado.ventas_en_proceso}</strong></span>
        <div class="flex items-center gap-space-xs bg-surface-container-highest px-space-xs py-0.5 rounded">
          ${icono('database', 'text-[16px] text-tertiary')}<span class="font-label-receipt text-label-receipt font-medium text-tertiary">PERSISTENCIA LOCAL DETS</span></div>
      </div>
    </div>

    ${cuadricula([
      kpi({ titulo: 'Importe confirmado', icono: 'payments', valor: Dinero.formato(r.importe_vendido), sub: 'Libro de movimientos (MXN)', pie: `<span class="text-primary font-medium">${r.ventas} tickets</span><span>todas las cajas</span>` }),
      kpi({ titulo: 'Dólares recibidos', icono: 'attach_money', claseIcono: 'text-tertiary', claseValor: 'text-tertiary', valor: Dinero.formato(c.cobros.efectivo_usd, 'USD'), sub: `Equiv. ${Dinero.formato(c.cobros.efectivo_usd_valor_mxn)} MXN`, pie: '<span class="text-tertiary font-medium">Gaveta USD</span><span>turnos vigentes</span>' }),
      kpi({ titulo: 'Ticket promedio', icono: 'receipt_long', claseIcono: 'text-secondary', valor: Dinero.formato(r.ventas ? Math.round(r.importe_vendido / r.ventas) : 0), sub: 'Importe / tickets', pie: `<span>${r.agotados} producto(s) agotado(s)</span><span>${r.productos} SKUs</span>` }),
      kpi({ titulo: 'Transacciones', icono: 'fact_check', claseIcono: 'text-secondary', valor: r.ventas, sub: 'Tickets confirmados', pie: `<span>${r.cancelaciones} cancel. · ${r.devoluciones} devol.</span>${r.descuadres ? `<span class="text-tertiary font-medium">${r.descuadres} descuadre(s)</span>` : '<span class="text-primary font-medium">Sin descuadres</span>'}` }),
      kpi({ titulo: 'Tipo de cambio', icono: 'currency_exchange', claseValor: 'text-primary', valor: Dinero.tc(estado.tipo_cambio.valor), sub: 'USD/MXN · simulado y variable', pie: `<span>Actualizado ${hora(estado.tipo_cambio.actualizado_en)}</span>` }),
    ].join(''), 'grid-cols-1 sm:grid-cols-2 lg:grid-cols-5')}

    <section>
      ${titulo('Cajas en paralelo (procesos OTP)', 'point_of_sale', 'supervisión one_for_one · p59_cajas_sup')}
      ${cuadricula(cajas.map((k) => tarjetaCaja(k, ventasTurno[k.id] || 0)).join(''))}
    </section>

    <section class="grid grid-cols-1 lg:grid-cols-12 gap-space-md">
      <div class="lg:col-span-7 flex flex-col gap-space-md">
        <div class="${tarjeta}">
          ${titulo('Telemetría BEAM VM / Erlang/OTP 27', 'developer_board', 'recon · /api/diagnostico')}
          ${cuadricula([['Procesos', vm.procesos.toLocaleString('es-MX'), 'en la VM'], ['Memoria', `${(vm.memoria_total / 1048576).toFixed(1)} MB`, `ETS: ${(vm.memoria_ets / 1048576).toFixed(1)} MB`],
            ['Procesos (mem)', `${(vm.memoria_procesos / 1048576).toFixed(1)} MB`, 'heap de procesos'], ['Planificadores', vm.planificadores, `cola: ${vm.cola_ejecucion}`],
            ['Productos', r.productos, 'catálogo en ETS']].map(([a, b, d]) => `
            <div class="bg-surface-container-low rounded-lg p-space-sm"><div class="${etiqueta}">${a}</div>
              <div class="font-label-numeric-md text-label-numeric-md font-bold text-on-surface">${b}</div>
              <div class="font-label-receipt text-label-receipt text-secondary">${d}</div></div>`).join(''), 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-5')}
        </div>
        <div class="${tarjeta}">
          ${titulo('Árbol de supervisión (en vivo)', 'account_tree', 'pids reales')}
          <div class="max-h-[420px] overflow-y-auto">${UI.arbol(raiz, estado.reinicios)}</div>
        </div>
      </div>
      <div class="lg:col-span-5 flex flex-col gap-space-md">
        <div class="${tarjeta}">
          ${titulo('Distribución de pagos', 'donut_small', `${c.ventas.numero} transacciones · turnos vigentes`)}
          <div class="flex h-3 w-full rounded overflow-hidden bg-surface-container-high mb-space-sm">
            <div class="bg-primary" style="width:${pct(modal.efectivo_mxn)}%"></div><div class="bg-tertiary-container" style="width:${pct(modal.efectivo_usd)}%"></div>
            <div class="bg-secondary" style="width:${pct(modal.tarjeta)}%"></div><div class="bg-outline" style="width:${pct(modal.mixto)}%"></div></div>
          <div class="grid grid-cols-2 gap-space-xs">${[['Efectivo MXN', 'efectivo_mxn', 'bg-primary'], ['Efectivo USD', 'efectivo_usd', 'bg-tertiary-container'], ['Tarjeta', 'tarjeta', 'bg-secondary'], ['Mixto', 'mixto', 'bg-outline']].map(([n, k, cl]) => `
            <div class="bg-surface-container-low rounded p-space-xs"><div class="flex items-center gap-1 font-body-sm text-body-sm"><span class="w-2 h-2 rounded-full ${cl}"></span>${n}</div>
              <div class="flex justify-between font-label-numeric-md text-label-numeric-md"><span class="font-bold">${pct(modal[k])}%</span><span class="text-secondary text-label-numeric-sm">${modal[k]} tkts</span></div></div>`).join('')}</div>
        </div>
        <div class="${tarjeta}">
          ${titulo('Eventos de tolerancia a fallos', 'shield_with_heart', 'tiempo real · SSE')}
          <div class="flex flex-col gap-space-xs">${eventos.map(filaEventoCompacta).join('') || UI.vacio('Sin eventos todavía')}</div>
          <a href="#/bitacora" class="mt-space-sm inline-flex items-center gap-1 font-label-receipt text-label-receipt text-primary font-semibold">Ver bitácora completa ${icono('arrow_forward', 'text-[14px]')}</a>
        </div>
      </div>
    </section>

    <div class="${tarjeta} flex flex-wrap items-center justify-between gap-space-md">
      <div><div class="flex items-center gap-space-xs font-headline-md text-body-lg font-semibold">${icono('print', 'text-primary')} Impresora térmica (simulada)
        ${estado.impresora.pendientes.length ? insignia(`${estado.impresora.pendientes.length} ticket(s) pendiente(s)`, 'alerta') : insignia('En línea', 'ok')}</div>
        <p class="font-body-sm text-body-sm text-secondary mt-1">Imprimir ocurre después de confirmar: una impresora atascada nunca deshace una venta.</p></div>
      <div class="flex flex-wrap gap-space-sm"><a href="#/simulacion" class="${boton.secundario}">${icono('science')} Inyectar fallas</a>
        <a href="#/corte" class="${boton.primario}">${icono('calculate')} Ver corte de caja</a></div>
    </div>
  </div>`;
}

function tarjetaCaja(c, ticketsTurno) {
  const [txt, nivel] = nivelCaja(c);
  const v = c.venta_actual;
  const enRevision = v && v.estado === 'pendiente_de_revision';
  return `<a href="#/caja/${c.id}" class="${tarjeta} flex flex-col justify-between hover:ring-2 hover:ring-primary-container transition ${nivel !== 'ok' ? 'bg-gradient-to-b from-surface-container-lowest to-surface-container-low' : ''}">
    <div class="w-full flex flex-wrap items-center justify-between gap-space-xs pb-space-sm">
      <div class="flex items-center gap-space-xs"><span class="font-headline-md text-body-lg font-bold text-on-surface">Caja 0${c.id}</span>${pid(c.proceso.pid)}</div>
      ${insignia(txt, nivel, nivel !== 'ok')}</div>
    <div class="py-space-sm flex flex-col gap-space-xs">
      ${fila('Cajero asignado', esc(c.turno ? c.turno.cajero : '—'), 'font-body-sm text-body-sm font-semibold text-on-surface')}
      ${fila('Tickets del turno', `${ticketsTurno} tickets · T${c.turno ? c.turno.turno : '-'}`)}
      <div class="bg-surface-container rounded-lg p-space-xs mt-space-xs">
        ${v ? `<div class="flex justify-between items-baseline"><span class="font-label-receipt text-label-receipt ${enRevision ? 'text-error' : 'text-secondary'} font-medium">${enRevision ? 'VENTA EN REVISIÓN' : 'VENTA EN CURSO'}</span>
            <span class="font-label-receipt text-label-receipt text-secondary">${esc(v.id)} · ${v.partidas.length} partida(s)</span></div>
          <div class="flex items-baseline justify-between mt-1"><span class="font-label-numeric-md text-label-numeric-md font-bold text-on-surface">${Dinero.formato(v.totales.total)} <span class="font-label-receipt text-label-receipt text-secondary">MXN</span></span>
            <span class="font-label-numeric-sm text-label-numeric-sm text-secondary">${usdDe(v.totales.total) !== null ? `≈ ${Dinero.formato(usdDe(v.totales.total), 'USD')}` : ''}</span></div>`
        : '<div class="flex justify-between items-baseline"><span class="font-label-receipt text-label-receipt text-primary font-medium">CAJA LIBRE</span><span class="font-label-receipt text-label-receipt text-secondary">Lista para cobrar</span></div>'}
      </div>
    </div>
    <div class="pt-space-xs flex items-center justify-between text-secondary font-label-receipt text-label-receipt">
      <span class="flex items-center gap-1">${icono(c.proceso.reinicios ? 'restart_alt' : 'shield', 'text-[14px]')} ${c.proceso.reinicios ? `Reinicios: ${c.proceso.reinicios}` : 'Supervisor OK'}</span>
      <span>Buzón: ${c.proceso.buzon ?? '—'} msgs</span></div>
  </a>`;
}

const NIVEL_FONDO = { ok: 'bg-surface-container-low', alerta: 'bg-tertiary-fixed/40', falla: 'bg-error-container/60' };
function filaEventoCompacta(e) {
  return `<div class="rounded p-space-xs ${NIVEL_FONDO[e.nivel] || ''}">
    <div class="flex items-center justify-between gap-space-sm"><span class="font-label-receipt text-label-receipt font-semibold uppercase">${esc(e.tipo)}</span>
      <span class="font-label-numeric-sm text-label-receipt text-secondary">${hora(e.ts)}</span></div>
    <div class="flex items-start gap-space-xs mt-0.5">${insignia(UI.NIVEL_TEXTO[e.nivel], e.nivel)}<span class="font-body-sm text-body-sm text-on-surface">${esc(e.mensaje)}</span></div></div>`;
}

// ====================================================================== COBRAR

const pos = { caja: 1, venta: null, opPago: null, modo: 'efectivo_mxn', q: '', categoria: '' };

async function vistaCobrar(caja) {
  pos.caja = Number(caja);
  const c = await API.caja(pos.caja);
  pos.venta = c.venta_actual ? await API.venta(c.venta_actual.id) : null;
  const [txt, nivel] = nivelCaja(c);
  actualizarEncabezado(c);
  $vista.innerHTML = `<div class="flex flex-col gap-space-md">
    <div class="w-full bg-surface-container-low rounded-lg p-space-sm flex flex-wrap items-center justify-between gap-space-sm">
      <div class="flex flex-wrap items-center gap-space-sm">${insignia(txt, nivel)}
        <span class="font-label-numeric-sm text-label-receipt text-on-surface-variant uppercase">p59_caja_${c.id} ${esc(c.proceso.pid)} · turno ${c.turno.turno} (${esc(c.turno.estado)}) · ${esc(c.turno.cajero)}</span></div>
      ${pestanasCaja(pos.caja, 'cobrar')}
      <span class="font-label-numeric-sm text-label-numeric-sm text-on-surface-variant">T.C. MOSTRADOR: <b class="text-primary">1 USD = $${Dinero.tc(sistema.tc)} MXN</b></span>
    </div>
    <div class="grid grid-cols-1 xl:grid-cols-12 gap-space-md items-start">
      <section class="xl:col-span-7 flex flex-col gap-space-md">
        <div class="${tarjeta} flex flex-wrap gap-space-sm items-center">
          <div class="flex-1 min-w-[220px] flex items-center gap-space-xs bg-surface-container-low rounded px-space-sm">
            ${icono('barcode_scanner', 'text-secondary')}
            <input id="buscar" value="${esc(pos.q)}" class="flex-1 bg-transparent py-space-sm min-h-[44px] font-body-sm text-body-sm focus:outline-none" placeholder="Buscar por nombre o clave (P0001)" autocomplete="off"></div>
          <button id="btn-buscar" class="${boton.primario}">${icono('search')} Buscar</button>
        </div>
        <div id="categorias" class="flex gap-space-xs overflow-x-auto pb-1"></div>
        <div id="productos" class="grid grid-cols-2 md:grid-cols-3 2xl:grid-cols-4 gap-space-sm"></div>
      </section>
      <aside id="carrito" class="xl:col-span-5 bg-surface-container-low rounded-xl shadow-sm overflow-hidden xl:sticky xl:top-20 scroll-mt-20"></aside>
    </div>
    <div id="barra-total" class="hidden xl:hidden fixed left-0 right-0 bottom-16 lg:bottom-0 z-40 px-margin py-space-xs bg-primary text-on-primary flex items-center justify-between gap-space-sm shadow-lg"></div></div>`;
  let t;
  $('#buscar').oninput = (e) => { pos.q = e.target.value; clearTimeout(t); t = setTimeout(cargarProductos, 250); };
  $('#btn-buscar').onclick = cargarProductos;
  await cargarProductos();
  pintarCarrito();
}

async function cargarProductos() {
  const datos = await API.productos(pos.q, 1, 24, pos.categoria);
  $('#categorias').innerHTML = [['', 'Todos', 'star'], ...datos.categorias.map((k) => [k, k, 'sell'])].map(([v, n, ic]) => `
    <button data-cat="${esc(v)}" class="shrink-0 inline-flex items-center gap-1 px-space-md py-space-xs min-h-[40px] rounded font-body-sm text-body-sm ${v === pos.categoria ? 'bg-primary-container text-on-primary font-semibold' : 'bg-surface-container-lowest text-on-surface-variant border border-outline-variant'}">${icono(ic, 'text-[16px]')}${esc(n)}</button>`).join('');
  $$('[data-cat]').forEach((b) => { b.onclick = () => { pos.categoria = b.dataset.cat; cargarProductos(); }; });
  $('#productos').innerHTML = datos.productos.map((p) => {
    const disponible = p.activo && p.disponible > 0;
    return `<button data-p="${esc(p.id)}" ${disponible ? '' : 'disabled'} class="text-left ${tarjeta} !p-space-sm flex flex-col justify-between gap-space-xs min-h-[150px] hover:ring-2 hover:ring-primary-container transition disabled:opacity-50 disabled:hover:ring-0">
      <div class="w-full flex justify-between gap-1 items-start"><span class="font-label-receipt text-label-receipt bg-secondary-container text-on-secondary-container px-1.5 py-0.5 rounded">${esc(p.categoria)}</span>
        <span class="font-label-receipt text-label-receipt ${p.disponible <= 2 ? 'text-tertiary font-bold' : 'text-secondary'}">${p.activo ? `Stock: ${p.disponible}` : 'Inactivo'}</span></div>
      <div><div class="font-body-sm text-body-sm font-semibold text-on-surface leading-tight">${esc(p.nombre)}</div>
        <div class="font-label-receipt text-label-receipt text-secondary">${esc(p.id)} · IVA ${p.tipo_iva === 'tasa_cero' ? '0' : sistema.ivaGeneral / 100}%</div></div>
      <div class="w-full flex justify-between items-baseline bg-surface-container-low rounded px-space-xs py-1">
        <span class="font-label-numeric-md text-label-numeric-md font-bold text-primary">${Dinero.formato(p.precio)}</span>
        <span class="font-label-numeric-sm text-label-receipt text-secondary">${usdDe(p.precio) !== null ? Dinero.formato(usdDe(p.precio), 'USD') : ''}</span></div>
    </button>`;
  }).join('') || `<div class="col-span-full">${UI.vacio('Sin productos con ese criterio', 'search')}</div>`;
  $$('[data-p]').forEach((b) => { b.onclick = () => agregar(b.dataset.p, 1); });
}

const ventaViva = () => pos.venta && !['pagada', 'cancelada'].includes(pos.venta.estado);

async function agregar(producto, cantidad, descuento = 0) {
  const r = await accion(async () => {
    if (!ventaViva()) { pos.venta = (await API.crearVenta(pos.caja)).datos; pos.opPago = null; }
    return API.agregar(pos.venta.id, producto, cantidad, descuento);
  });
  if (r) { pos.venta = r.datos; pintarCarrito(); cargarProductos(); }
}

async function cambiarCantidad(producto, delta) {
  const p = pos.venta.totales.partidas.find((x) => x.producto_id === producto);
  if (delta > 0) return agregar(producto, 1, p.descuento_pct);
  const r = await accion(async () => {
    const sin = await API.retirar(pos.venta.id, producto);
    return p.cantidad > 1 ? API.agregar(pos.venta.id, producto, p.cantidad - 1, p.descuento_pct) : sin;
  });
  if (r) { pos.venta = r.datos; pintarCarrito(); cargarProductos(); }
}

const MODOS = [['efectivo_mxn', 'Efectivo MXN', 'payments'], ['efectivo_usd', 'Efectivo USD', 'attach_money'], ['tarjeta', 'Tarjeta (simulada)', 'credit_card'], ['mixto', 'Pago mixto', 'call_split']];

// En celular y tableta el comprobante queda bajo el catálogo: una barra fija
// muestra el total y lleva a él (DESIGN.md, barra de acción rápida inferior).
function pintarBarraTotal() {
  const b = document.getElementById('barra-total');
  if (!b) return;
  if (!ventaViva()) { b.classList.add('hidden'); return; }
  const t = pos.venta.totales;
  b.classList.remove('hidden');
  b.innerHTML = `<div><div class="font-label-receipt text-label-receipt uppercase opacity-90">${esc(pos.venta.id)} · ${t.articulos} artículo(s)</div>
    <div class="font-label-numeric-lg text-label-numeric-lg font-bold">${Dinero.formato(t.total)}</div></div>
    <button id="ver-venta" class="inline-flex items-center gap-1 px-space-md min-h-[44px] rounded bg-on-primary text-primary font-semibold">${icono('receipt_long', 'text-[18px]')} Ver venta y cobrar</button>`;
  document.getElementById('ver-venta').onclick = () => document.getElementById('carrito').scrollIntoView({ behavior: 'smooth' });
}

function pintarCarrito() {
  const el = document.getElementById('carrito');
  if (!el) return;
  pintarBarraTotal();
  const v = pos.venta;
  const cab = (sub) => `<div class="p-space-md text-center border-b border-dashed border-outline-variant bg-surface-container-lowest">
    <div class="flex items-center justify-center gap-space-xs font-headline-md text-body-lg font-bold">${icono('receipt_long', 'text-primary')} COMPROBANTE DE VENTA</div>
    <div class="font-label-receipt text-label-receipt text-on-surface-variant uppercase">Comprobante interno — no es CFDI</div>${sub}</div>`;
  if (!ventaViva()) {
    el.innerHTML = cab('') + `<div class="p-space-md">${UI.vacio('Toque un producto para iniciar una venta en esta caja.', 'barcode_scanner')}
      ${v && v.estado === 'pagada' ? `<a href="#/venta/${v.id}" class="${boton.secundario} w-full">${icono('receipt')} Ver último ticket ${esc(v.folio)}</a>` : ''}</div>`;
    return;
  }
  const t = v.totales;
  const revision = v.estado === 'pendiente_de_revision';
  el.innerHTML = cab(`<div class="flex justify-between mt-space-xs font-label-receipt text-label-receipt text-secondary"><span>Venta: ${esc(v.id)}</span><span>Caja ${v.caja} · ${esc(v.cajero)}</span><span>${hora(v.creada_en)}</span></div>`) + `
    <div class="px-space-md py-space-sm bg-surface-container-lowest max-h-[340px] overflow-y-auto divide-y divide-surface-container-high">
      ${t.partidas.map((p) => `<div class="flex items-center gap-space-sm py-space-sm">
        <div class="flex-1 min-w-0"><div class="font-body-sm text-body-sm font-semibold truncate">${esc(p.nombre)}</div>
          <div class="font-label-receipt text-label-receipt text-secondary">${p.cantidad} x ${Dinero.formato(p.precio_unitario)} · IVA ${p.tasa_iva / 100}%${p.descuento ? ` · desc ${Dinero.formato(p.descuento)}` : ''}</div></div>
        ${revision ? '' : `<div class="flex items-center gap-1"><button data-menos="${esc(p.producto_id)}" class="w-8 h-8 rounded bg-surface-container font-bold">−</button>
          <span class="w-6 text-center font-label-numeric-sm text-label-numeric-sm">${p.cantidad}</span>
          <button data-mas="${esc(p.producto_id)}" class="w-8 h-8 rounded bg-surface-container font-bold">+</button></div>`}
        <div class="text-right w-24"><div class="font-label-numeric-sm text-label-numeric-sm font-semibold">${Dinero.formato(p.importe)}</div></div>
        ${revision ? '' : `<button data-quitar="${esc(p.producto_id)}" class="text-secondary hover:text-error" title="Quitar partida">${icono('close', 'text-[18px]')}</button>`}
      </div>`).join('') || UI.vacio('Venta sin partidas')}</div>
    <div class="px-space-md py-space-sm flex flex-col gap-1 border-t border-surface-container-high">
      ${fila('Subtotal', Dinero.formato(t.subtotal))}${fila('Descuentos', Dinero.formato(-t.descuentos))}
      ${fila(`IVA <span class="font-label-receipt text-label-receipt bg-primary-fixed text-on-primary-fixed-variant px-1 rounded">${sistema.ivaGeneral / 100}% general · 0% básicos</span>`, Dinero.formato(t.iva))}
      <div class="flex justify-between items-end mt-space-xs"><div><div class="${etiqueta}">Total a pagar</div>
        <div class="font-headline-xl text-headline-xl-mobile lg:text-headline-xl font-bold text-primary">${Dinero.formato(t.total)}</div><div class="font-label-receipt text-label-receipt text-primary">MXN</div></div>
        <div class="text-right"><div class="${etiqueta}">Total en dólares</div>
          <div class="font-label-numeric-lg text-label-numeric-lg font-bold text-on-surface">≈ ${usdDe(t.total) !== null ? Dinero.formato(usdDe(t.total), 'USD') : '—'}</div><div class="font-label-receipt text-label-receipt text-secondary">T.C. ${Dinero.tc(sistema.tc)}</div></div></div>
      ${v.ultimo_error && !revision ? `<div class="mt-space-xs">${insignia(`Último intento: ${v.ultimo_error}`, 'alerta')}</div>` : ''}
    </div>
    ${revision ? `<div class="m-space-md p-space-md rounded-lg bg-error-container text-on-error-container">
        <div class="flex items-center gap-space-xs font-semibold">${icono('dangerous')} La terminal no respondió: no sabemos si se cobró</div>
        <p class="font-body-sm text-body-sm mt-1">La venta NO está pagada y las piezas siguen apartadas. Consultar al banco confirma la venta si el cargo existe, o la reabre si no existe. Nunca se cobra dos veces.</p>
        <div class="flex flex-wrap gap-space-sm mt-space-sm"><button id="revisar" class="${boton.primario}">${icono('published_with_changes')} Consultar al banco y resolver</button>
          <button id="cancelar" class="${boton.secundario}">${icono('cancel')} Cancelar venta</button></div></div>` : `
    <div class="px-space-md pb-space-md flex flex-col gap-space-sm">
      <div class="${etiqueta}">Forma de pago</div>
      <div class="grid grid-cols-2 gap-space-xs">${MODOS.map(([m, n, ic]) => `<button data-modo="${m}" class="inline-flex items-center justify-center gap-space-xs min-h-[44px] rounded font-body-sm text-body-sm font-semibold ${pos.modo === m ? 'bg-primary text-on-primary' : 'bg-surface-container-lowest text-on-surface border border-outline-variant'}">${icono(ic, 'text-[18px]')}${n}</button>`).join('')}</div>
      <div class="bg-surface-container-lowest rounded-lg p-space-sm flex flex-col gap-space-xs">
        <div class="flex flex-wrap items-center justify-between gap-1"><span class="font-body-sm text-body-sm font-medium">Importe recibido</span>
          <div class="flex gap-1">${[['usd', 2000, 'US$20'], ['usd', 5000, 'US$50'], ['mxn', 50000, '$500 MXN'], ['exacto', 0, 'Exacto']].map(([k, m, n]) => `<button data-rapido="${k}:${m}" class="${boton.suave} font-label-receipt text-label-receipt">${n}</button>`).join('')}</div></div>
        ${['efectivo_usd', 'mixto'].includes(pos.modo) ? `<label class="flex items-center gap-space-xs"><span class="w-20 shrink-0 whitespace-nowrap font-label-numeric-sm text-label-numeric-sm text-secondary">USD US$</span><input id="p-usd" inputmode="decimal" class="${entrada}" placeholder="0.00"></label>` : ''}
        ${['efectivo_mxn', 'mixto'].includes(pos.modo) ? `<label class="flex items-center gap-space-xs"><span class="w-20 shrink-0 whitespace-nowrap font-label-numeric-sm text-label-numeric-sm text-secondary">MXN $</span><input id="p-mxn" inputmode="decimal" class="${entrada}" placeholder="0.00"></label>` : ''}
        ${['tarjeta', 'mixto'].includes(pos.modo) ? `<label class="flex items-center gap-space-xs"><span class="w-20 shrink-0 whitespace-nowrap font-label-numeric-sm text-label-numeric-sm text-secondary">Tarjeta $</span><input id="p-tarjeta" inputmode="decimal" class="${entrada}" placeholder="0.00" value="${pos.modo === 'tarjeta' ? (t.total / 100).toFixed(2) : ''}"></label>` : ''}
        <div id="cambio" class="flex justify-between items-center border-t border-dashed border-outline-variant pt-space-xs"></div>
      </div>
      <button id="pagar" ${t.partidas.length ? '' : 'disabled'} class="w-full inline-flex items-center justify-center gap-space-sm min-h-[64px] rounded-lg bg-primary text-on-primary font-headline-md text-body-lg font-bold hover:bg-primary-container disabled:opacity-50">
        ${icono('print', 'text-[24px]')} COBRAR E IMPRIMIR TICKET ${icono('chevron_right')}</button>
      <button id="cancelar" class="${boton.secundario}">${icono('cancel')} Cancelar venta</button>
    </div>`}`;

  $$('#carrito [data-mas]').forEach((b) => { b.onclick = () => cambiarCantidad(b.dataset.mas, 1); });
  $$('#carrito [data-menos]').forEach((b) => { b.onclick = () => cambiarCantidad(b.dataset.menos, -1); });
  $$('#carrito [data-quitar]').forEach((b) => {
    b.onclick = async () => { const r = await accion(() => API.retirar(v.id, b.dataset.quitar)); if (r) { pos.venta = r.datos; pintarCarrito(); cargarProductos(); } };
  });
  $$('#carrito [data-modo]').forEach((b) => { b.onclick = () => { pos.modo = b.dataset.modo; pintarCarrito(); }; });
  $$('#carrito [data-rapido]').forEach((b) => {
    b.onclick = () => {
      const [k, m] = b.dataset.rapido.split(':');
      const poner = (id, cent) => { const i = document.getElementById(id); if (i) i.value = (cent / 100).toFixed(2); };
      if (k === 'exacto') poner(pos.modo === 'efectivo_usd' ? 'p-usd' : pos.modo === 'tarjeta' ? 'p-tarjeta' : 'p-mxn', pos.modo === 'efectivo_usd' ? usdDe(t.total) : t.total);
      else if (k === 'usd') { if (!document.getElementById('p-usd')) { pos.modo = 'efectivo_usd'; pintarCarrito(); } poner('p-usd', Number(m)); }
      else { if (!document.getElementById('p-mxn')) { pos.modo = 'efectivo_mxn'; pintarCarrito(); } poner('p-mxn', Number(m)); }
      previsualizarCambio();
    };
  });
  $$('#carrito input').forEach((i) => { i.oninput = previsualizarCambio; });
  const enlazar = (id, fn) => { const b = document.getElementById(id); if (b) b.onclick = fn; };
  enlazar('pagar', cobrar);
  enlazar('revisar', async () => { const r = await accion(() => API.revisar(v.id)); if (r) { pos.venta = r.datos; terminarSiPagada(); pintarCarrito(); } });
  enlazar('cancelar', async () => { const r = await accion(() => API.cancelarVenta(v.id, 'Cancelada desde la caja'), 'Venta cancelada'); if (r) { pos.venta = r.datos; pintarCarrito(); cargarProductos(); } });
  previsualizarCambio();
}

function pagosCapturados() {
  return [['efectivo_mxn', 'p-mxn'], ['efectivo_usd', 'p-usd'], ['tarjeta', 'p-tarjeta']]
    .map(([metodo, id]) => ({ metodo, el: document.getElementById(id) }))
    .filter((p) => p.el && p.el.value.trim() !== '')
    .map((p) => ({ metodo: p.metodo, monto: Dinero.aCentavos(p.el.value) }));
}

// Vista previa local; el servidor recalcula con el tipo de cambio que captura al cobrar.
function previsualizarCambio() {
  const el = document.getElementById('cambio');
  if (!el || !pos.venta) return;
  const pagos = pagosCapturados();
  if (pagos.some((p) => p.monto === null)) { el.innerHTML = insignia('Monto inválido (use 123.45)', 'falla'); return; }
  const recibido = pagos.reduce((s, p) => s + (p.metodo === 'efectivo_usd' ? Math.floor((p.monto * (sistema.tc || 0)) / 10000) : p.monto), 0);
  const dif = recibido - pos.venta.totales.total;
  el.innerHTML = dif >= 0
    ? `<span class="font-label-receipt text-label-receipt uppercase text-secondary">Cambio a entregar<br>(T.C. ${Dinero.tc(sistema.tc)})</span><span class="font-label-numeric-lg text-label-numeric-lg font-bold text-primary">${Dinero.formato(dif)} <span class="text-label-receipt">MXN</span></span>`
    : `<span class="font-label-receipt text-label-receipt uppercase text-secondary">Falta por cubrir</span><span class="font-label-numeric-md text-label-numeric-md font-bold text-error">${Dinero.formato(-dif)}</span>`;
}

async function cobrar() {
  const pagos = pagosCapturados();
  if (!pagos.length || pagos.some((p) => p.monto === null || p.monto <= 0)) { aviso('Capture montos válidos (use 123.45)'); return; }
  // Mismo operacion_id mientras no cambie el resultado: un doble clic o un
  // reintento por red no cobra dos veces.
  pos.opPago = pos.opPago || API.operacion('pago');
  document.getElementById('pagar').disabled = true;
  try {
    const r = await API.pagar(pos.venta.id, pagos, pos.opPago);
    pos.venta = r.datos;
    if (r.status === 202) aviso('Terminal sin respuesta: la venta quedó en revisión');
    terminarSiPagada();
  } catch (e) {
    aviso(`No se cobró: ${e.message}`);
    pos.opPago = null;
    pos.venta = await API.venta(pos.venta.id);
  }
  pintarCarrito();
}

function terminarSiPagada() {
  if (pos.venta.estado === 'pagada') {
    aviso(`Venta confirmada: ticket ${pos.venta.folio}`);
    location.hash = `#/venta/${pos.venta.id}`;
  }
}

// ============================================================== DETALLE DE CAJA

async function vistaCaja(id) {
  const n = Number(id);
  const [c, corte, estado] = await Promise.all([API.caja(n), API.corte(`?caja=${n}`), API.estado()]);
  const [txt, nivel] = nivelCaja(c);
  const sup = estado.arbol.hijos.find((h) => h.id === 'p59_sucursal_sup')?.hijos.find((h) => h.id === 'p59_cajas_sup');
  const t = c.turno; const co = corte.cobros;
  actualizarEncabezado(c);
  $vista.innerHTML = `<div class="flex flex-col gap-space-lg">
    <div class="${tarjeta} flex flex-wrap items-center justify-between gap-space-md">
      <div class="flex flex-wrap items-center gap-space-sm"><span class="flex items-center gap-space-xs bg-surface-container-low px-space-sm py-space-xs rounded font-headline-md text-body-lg font-semibold">${icono('point_of_sale', 'text-primary')} Terminal POS</span>
        ${pestanasCaja(n, 'caja')}</div>
      <div class="flex items-center gap-space-sm bg-surface-container-low rounded-lg px-space-md py-space-xs">${insignia(txt, nivel, nivel !== 'ok')}
        <span class="font-label-receipt text-label-receipt text-secondary">${c.proceso.reinicios} reinicio(s) registrados</span></div>
    </div>
    <div class="grid grid-cols-1 lg:grid-cols-12 gap-space-md items-start">
      <div class="lg:col-span-7 flex flex-col gap-space-md">
        <div class="${tarjeta}">
          ${titulo('Ficha técnica gen_server OTP', 'developer_board', 'Erlang/OTP 27')}
          <div class="bg-surface-container-low rounded-lg p-space-sm">
            <div class="flex justify-between ${UI.etiqueta} mb-space-xs"><span>Árbol de supervisión local</span><span>Estrategia: one_for_one</span></div>
            <div class="flex flex-col sm:flex-row items-stretch gap-space-sm">
              <div class="flex-1 bg-surface-container-lowest rounded p-space-sm"><div class="flex justify-between"><span class="font-label-receipt text-label-receipt bg-secondary-container text-on-secondary-container px-1.5 rounded">SUPERVISOR</span><span class="font-label-numeric-sm text-label-receipt">${esc(sup?.pid)}</span></div>
                <div class="font-semibold mt-1">p59_cajas_sup</div><div class="font-label-receipt text-label-receipt text-secondary">intensidad: 10 reinicios / 10 s</div></div>
              <div class="flex items-center justify-center text-secondary">${icono('arrow_right_alt')}</div>
              <div class="flex-1 bg-surface-container-lowest rounded p-space-sm border-2 border-primary-container"><div class="flex justify-between"><span class="font-label-receipt text-label-receipt bg-primary-container text-on-primary px-1.5 rounded">WORKER (gen_server)</span><span class="font-label-numeric-sm text-label-receipt text-primary font-semibold">${esc(c.proceso.pid)}</span></div>
                <div class="font-semibold mt-1">p59_caja_${n}</div><div class="font-label-receipt text-label-receipt text-primary">src/p59_caja.erl · permanent</div></div>
            </div>
          </div>
          <div class="grid grid-cols-2 md:grid-cols-4 gap-space-sm mt-space-sm">${[['Buzón', `${c.proceso.buzon ?? '—'} msgs`, 'message_queue_len'], ['Memoria', c.proceso.memoria ? `${(c.proceso.memoria / 1024).toFixed(1)} KB` : '—', 'process_info'],
            ['Reducciones', (c.proceso.reducciones ?? 0).toLocaleString('es-MX'), 'trabajo acumulado'], ['Reinicios', c.proceso.reinicios, 'desde el arranque']].map(([a, b, d]) => `
            <div class="bg-surface-container-low rounded-lg p-space-sm"><div class="font-body-sm text-body-sm text-secondary">${a}</div><div class="font-label-numeric-lg text-label-numeric-lg font-bold">${b}</div><div class="font-label-receipt text-label-receipt text-secondary">${d}</div></div>`).join('')}</div>
          <p class="font-body-sm text-body-sm text-secondary mt-space-sm">La caja <b>monitorea</b> su venta en curso sin enlazarse a ella: si la caja cae, la venta sobrevive y la caja la recupera desde DETS al reiniciarse.</p>
        </div>
        <div class="${tarjeta}">
          ${titulo('Acciones de control y diagnóstico OTP', 'tune')}
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-space-sm">
            <a href="#/cobrar/${n}" class="flex flex-col items-center gap-1 rounded-lg bg-surface-container-low p-space-md text-center hover:bg-surface-container">${icono('point_of_sale', 'text-primary')}<span class="font-semibold">Ir a cobrar</span><span class="font-label-receipt text-label-receipt text-secondary">venta en esta caja</span></a>
            <a href="#/corte?caja=${n}" class="flex flex-col items-center gap-1 rounded-lg bg-surface-container-low p-space-md text-center hover:bg-surface-container">${icono('lock_clock', 'text-primary')}<span class="font-semibold">Corte y cierre de turno</span><span class="font-label-receipt text-label-receipt text-secondary">arqueo X / Z</span></a>
            <button id="matar" class="flex flex-col items-center gap-1 rounded-lg bg-error-container p-space-md text-center text-on-error-container hover:opacity-90">${icono('bolt')}<span class="font-semibold">Simular crash (kill)</span><span class="font-label-numeric-sm text-label-receipt">exit(Pid, kill)</span></button>
          </div>
        </div>
      </div>
      <div class="lg:col-span-5 flex flex-col gap-space-md">
        <div class="${tarjeta}">
          ${titulo('Métricas del turno en curso', 'monitoring', `Turno ${t.turno} · ${t.estado}`)}
          <div class="flex items-center gap-space-sm bg-surface-container-low rounded-lg p-space-sm mb-space-sm">
            <div class="w-12 h-12 rounded-lg bg-primary-container flex items-center justify-center">${icono('person', 'text-on-primary')}</div>
            <div class="flex-1"><div class="font-semibold">${esc(t.cajero)}</div><div class="font-body-sm text-body-sm text-secondary">Apertura: ${fecha(t.abierto_en)}</div></div></div>
          <div class="${UI.etiqueta} mb-space-xs">Fondo inicial de caja</div>
          <div class="grid grid-cols-2 gap-space-xs mb-space-sm"><div class="bg-surface-container-low rounded p-space-xs"><div class="font-label-receipt text-label-receipt text-secondary">Fondo MXN</div><div class="font-label-numeric-md text-label-numeric-md">${Dinero.formato(t.fondo_mxn)}</div></div>
            <div class="bg-surface-container-low rounded p-space-xs"><div class="font-label-receipt text-label-receipt text-secondary">Fondo USD</div><div class="font-label-numeric-md text-label-numeric-md">${Dinero.formato(0, 'USD')}</div></div></div>
          <div class="${UI.etiqueta} mb-space-xs">Desglose de cobros del turno</div>
          <div class="flex flex-col gap-1">
            <div class="flex justify-between bg-surface-container-low rounded p-space-xs"><span>${icono('payments', 'text-[18px]')} Efectivo MXN</span><span class="font-label-numeric-sm">${Dinero.formato(co.efectivo_mxn)}</span></div>
            <div class="flex justify-between bg-surface-container-low rounded p-space-xs"><span>${icono('attach_money', 'text-[18px]')} Efectivo USD</span><span class="font-label-numeric-sm text-right">${Dinero.formato(co.efectivo_usd, 'USD')}<br><span class="text-secondary">(${Dinero.formato(co.efectivo_usd_valor_mxn)} MXN)</span></span></div>
            <div class="flex justify-between bg-surface-container-low rounded p-space-xs"><span>${icono('credit_card', 'text-[18px]')} Tarjeta</span><span class="font-label-numeric-sm">${Dinero.formato(co.tarjeta)}</span></div>
          </div>
          <div class="mt-space-sm rounded-lg bg-primary-container text-on-primary p-space-md">
            <div class="flex justify-between font-label-receipt text-label-receipt uppercase opacity-90"><span>Efectivo esperado en cajón</span>${icono('move_to_inbox', 'text-[20px]')}</div>
            <div class="flex flex-wrap justify-between items-end gap-space-sm mt-1"><div><div class="font-label-receipt text-label-receipt opacity-80">Gaveta MXN</div><div class="font-headline-xl text-headline-xl-mobile font-bold">${Dinero.formato(corte.efectivo_esperado.mxn)}</div></div>
              <div class="text-right"><div class="font-label-receipt text-label-receipt opacity-80">Gaveta USD</div><div class="font-label-numeric-lg text-label-numeric-lg font-bold">${Dinero.formato(corte.efectivo_esperado.usd, 'USD')}</div></div></div>
            <div class="font-label-receipt text-label-receipt opacity-80 mt-space-xs border-t border-on-primary/20 pt-space-xs">Fondo + efectivo − cambio − reembolsos. ${corte.invariante.ok ? 'Invariante contable: cuadra.' : 'Invariante contable: NO CUADRA.'}</div>
          </div>
        </div>
        <div class="${tarjeta}">
          ${titulo('Venta en curso', 'shopping_cart')}
          ${c.venta_actual ? `<a href="#/venta/${c.venta_actual.id}" class="flex justify-between items-center bg-surface-container-low rounded p-space-sm"><span class="font-semibold">${esc(c.venta_actual.id)}</span>${insigniaVenta(c.venta_actual.estado)}<span class="font-label-numeric-sm">${Dinero.formato(c.venta_actual.totales.total)}</span></a>` : UI.vacio('Caja libre', 'check_circle')}
        </div>
      </div>
    </div>
    <div class="${tarjeta}">
      ${titulo(`Transacciones recientes de caja #${n}`, 'receipt_long', 'últimos 10 movimientos del libro')}
      <div class="overflow-x-auto"><table class="w-full text-left"><thead class="bg-surface-container-low ${UI.etiqueta}"><tr>
        <th class="p-space-sm">Folio</th><th class="p-space-sm">Hora</th><th class="p-space-sm">Tipo / método</th><th class="p-space-sm text-right">Monto MXN</th><th class="p-space-sm text-right">Monto USD</th><th class="p-space-sm">Turno</th></tr></thead>
        <tbody class="divide-y divide-surface-container-high">${c.recientes.map((m) => {
          const usd = m.tipo === 'venta' ? m.pagos.filter((p) => p.metodo === 'efectivo_usd').reduce((s, p) => s + p.monto, 0) : 0;
          return `<tr class="${m.tipo !== 'venta' ? 'bg-error-container/30' : ''}"><td class="p-space-sm font-label-numeric-sm font-semibold"><a class="text-primary" href="#/venta/${m.venta_id}">${esc(m.tipo === 'venta' ? m.folio : m.id)}</a></td>
            <td class="p-space-sm font-label-numeric-sm text-secondary">${hora(m.fecha)}</td>
            <td class="p-space-sm"><span class="font-label-receipt text-label-receipt bg-surface-container px-1.5 py-0.5 rounded">${m.tipo === 'venta' ? esc(m.modalidad) : `${esc(m.tipo)} de ${esc(m.folio)}`}</span></td>
            <td class="p-space-sm text-right font-label-numeric-sm font-semibold ${m.tipo !== 'venta' ? 'text-error' : ''}">${Dinero.formato(m.tipo === 'venta' ? m.total : -m.monto)}</td>
            <td class="p-space-sm text-right font-label-numeric-sm">${usd ? Dinero.formato(usd, 'USD') : '—'}</td><td class="p-space-sm font-label-numeric-sm">${m.turno}</td></tr>`;
        }).join('') || `<tr><td colspan="6">${UI.vacio('Sin operaciones todavía')}</td></tr>`}</tbody></table></div>
    </div></div>`;
  $('#matar').onclick = async () => {
    if (!confirm(`¿Terminar el proceso p59_caja_${n} con exit(Pid, kill)? Su supervisor lo reiniciará.`)) return;
    await accion(() => API.simular('matar', { proceso: `p59_caja_${n}` }), `p59_caja_${n} terminada; observe el pid nuevo`);
    setTimeout(() => vistaCaja(n), 400);
  };
}

// ============================================================= DETALLE DE VENTA

async function vistaVentas() {
  const { ventas } = await API.ventas();
  $vista.innerHTML = `<div class="${tarjeta}">${titulo('Ventas recientes', 'receipt_long', 'seleccione una para ver su máquina de estados')}
    <div class="overflow-x-auto"><table class="w-full text-left"><thead class="bg-surface-container-low ${UI.etiqueta}"><tr><th class="p-space-sm">Venta</th><th class="p-space-sm">Estado</th><th class="p-space-sm">Caja</th><th class="p-space-sm">Ticket</th><th class="p-space-sm">Creada</th><th class="p-space-sm text-right">Total</th></tr></thead>
    <tbody class="divide-y divide-surface-container-high">${ventas.map((v) => `<tr class="hover:bg-surface-container-low cursor-pointer" onclick="location.hash='#/venta/${v.id}'">
      <td class="p-space-sm font-label-numeric-sm font-semibold text-primary">${esc(v.id)}</td><td class="p-space-sm">${insigniaVenta(v.estado)}</td><td class="p-space-sm">${v.caja}</td>
      <td class="p-space-sm font-label-numeric-sm">${esc(v.folio || '—')}</td><td class="p-space-sm font-label-numeric-sm text-secondary">${hora(v.creada_en)}</td>
      <td class="p-space-sm text-right font-label-numeric-sm">${Dinero.formato(v.totales.total)}</td></tr>`).join('') || `<tr><td colspan="6">${UI.vacio('Aún no hay ventas')}</td></tr>`}</tbody></table></div></div>`;
}

async function vistaVenta(id) {
  const v = await API.venta(id);
  const t = v.folio ? await API.ticket(v.folio) : null;
  const cancelado = t && t.reembolsos.some((r) => r.tipo === 'cancelacion');
  const t0 = v.creada_en;
  const ICONO_ESTADO = { abierta: 'shopping_cart', procesando_pago: 'hourglass_top', pendiente_de_revision: 'warning', pagada: 'verified', cancelada: 'cancel' };
  $vista.innerHTML = `<div class="flex flex-col gap-space-md">
    <div class="${tarjeta} flex flex-wrap justify-between gap-space-md">
      <div class="flex gap-space-md"><div class="w-12 h-12 rounded-lg bg-primary-container flex items-center justify-center">${icono('receipt_long', 'text-on-primary text-[28px]')}</div>
        <div><div class="flex flex-wrap items-center gap-space-xs"><span class="font-label-numeric-lg text-label-numeric-lg font-bold">${v.folio ? `Folio ${esc(v.folio)}` : `Venta ${esc(v.id)}`}</span>
          <span class="font-label-receipt text-label-receipt bg-surface-container px-1.5 rounded">CAJA #${v.caja} · ${esc(v.id)}</span>
          ${v.estado === 'pagada' ? `<span class="font-label-receipt text-label-receipt bg-primary-fixed text-on-primary-fixed-variant px-1.5 rounded">● PERSISTIDA EN LIBRO DETS</span>` : insigniaVenta(v.estado)}
          ${cancelado ? insignia('Ticket cancelado', 'alerta') : ''}</div>
          <div class="font-label-receipt text-label-receipt text-secondary mt-1">Creada: ${fecha(v.creada_en)} · Cajero: ${esc(v.cajero)} · Nodo: ${esc(sistema.nodo)}</div></div></div>
      <div class="flex flex-wrap gap-space-sm items-start">
        <a href="#/venta" class="${boton.secundario}">${icono('view_list')} Todas las ventas</a>
        ${t && !cancelado ? `<button id="ir-devolucion" class="${boton.secundario} !bg-error-container !text-on-error-container !border-0">${icono('assignment_return')} Emitir devolución</button>` : ''}
        ${['abierta', 'pendiente_de_revision'].includes(v.estado) ? `<a href="#/cobrar/${v.caja}" class="${boton.primario}">${icono('point_of_sale')} Continuar en caja ${v.caja}</a>` : ''}
      </div>
    </div>
    <div class="grid grid-cols-1 lg:grid-cols-12 gap-space-md items-start">
      <div class="lg:col-span-7 flex flex-col gap-space-md">
        <div class="${tarjeta}">
          <div class="flex flex-wrap justify-between items-start gap-space-sm mb-space-md"><div>
            <div class="font-headline-md text-headline-md flex items-center gap-space-xs">${icono('hub', 'text-primary')} gen_statem: p59_venta</div>
            <div class="font-label-numeric-sm text-label-receipt text-secondary">PID: ${esc(v.proceso || 'terminado (estado final)')} · supervisor p59_ventas_sup · transient · arranques: ${v.arranques}</div></div>
            ${insigniaVenta(v.estado)}</div>
          <ol class="flex flex-col gap-space-sm">${v.historial.map((h, i) => {
            const ultimo = i === v.historial.length - 1;
            return `<li class="flex gap-space-sm rounded-lg p-space-sm ${ultimo && h.estado === 'pagada' ? 'bg-primary-fixed/50' : 'bg-surface-container-low'}">
              <div class="w-8 h-8 shrink-0 rounded-full ${ultimo ? 'bg-primary text-on-primary' : 'bg-primary-container text-on-primary'} flex items-center justify-center font-label-numeric-sm">${ultimo ? icono(ICONO_ESTADO[h.estado] || 'check', 'text-[18px]') : i + 1}</div>
              <div class="flex-1 min-w-0"><div class="flex flex-wrap justify-between gap-space-xs"><span class="font-label-numeric-md text-label-numeric-md font-semibold">\`${esc(h.estado)}\`</span>
                <span class="flex items-center gap-space-xs">${insigniaVenta(h.estado)}<span class="font-label-numeric-sm text-label-receipt text-secondary">[+${(h.en - t0).toLocaleString('es-MX')} ms]</span></span></div>
                <div class="font-body-sm text-body-sm text-on-surface-variant">${esc(h.detalle)}</div></div></li>`;
          }).join('')}</ol>
        </div>
        <div class="${tarjeta}">
          ${titulo('Partidas y cobro', 'shopping_cart')}
          ${v.totales.partidas.map((p) => fila(`${p.cantidad} x ${esc(p.nombre)}`, Dinero.formato(p.importe))).join('') || UI.vacio('Sin partidas')}
          <div class="border-t border-dashed border-outline-variant mt-space-xs pt-space-xs">${fila('<b>Total</b>', `<b>${Dinero.formato(v.totales.total)}</b>`)}</div>
          ${v.cobro ? `<div class="mt-space-sm grid grid-cols-2 sm:grid-cols-4 gap-space-xs">${[['Modalidad', esc(v.cobro.modalidad)], ['Recibido', Dinero.formato(v.cobro.recibido_mxn)], ['Cambio', Dinero.formato(v.cobro.cambio_mxn)], ['T.C.', Dinero.tc(v.cobro.tipo_cambio)]].map(([a, b]) => `
            <div class="bg-surface-container-low rounded p-space-xs"><div class="${UI.etiqueta}">${a}</div><div class="font-label-numeric-sm text-label-numeric-sm">${b}</div></div>`).join('')}</div>` : ''}
          ${v.ultimo_error ? `<div class="mt-space-sm">${insignia(`Último error de cobro: ${v.ultimo_error}`, 'alerta')}</div>` : ''}
        </div>
        <div class="${tarjeta}">
          ${titulo('Persistencia en DETS', 'database', 'data/*.dets')}
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-space-sm">
            <div><div class="${UI.etiqueta}">Tabla ventas</div><div class="font-label-numeric-sm">{${esc(v.id)}, Estado}</div><div class="font-body-sm text-body-sm text-secondary">Se guarda en cada transición</div></div>
            <div><div class="${UI.etiqueta}">Tabla movimientos</div><div class="font-label-numeric-sm">${t ? `{venta, ${esc(v.id)}}` : '— sin confirmar —'}</div><div class="font-body-sm text-body-sm text-secondary">${t ? `Punto de no retorno: folio ${esc(v.folio)}` : 'No existe para el libro todavía'}</div></div>
            <div><div class="${UI.etiqueta}">Turno contable</div><div class="font-label-numeric-sm">${t ? `Caja ${t.venta.caja} · turno ${t.venta.turno}` : '—'}</div><div class="font-body-sm text-body-sm text-secondary">Turno vigente al confirmar</div></div>
          </div>
        </div>
      </div>
      <div class="lg:col-span-5 flex flex-col gap-space-md">
        <div class="${tarjeta}">${t ? UI.ticketTermico(t, sistema.ivaGeneral) : UI.vacio('El ticket se emite al confirmar la venta.', 'receipt')}
          ${t ? `<div class="flex flex-col gap-1 mt-space-sm font-label-receipt text-label-receipt text-secondary"><span>${icono('print', 'text-[16px]')} Impresora simulada: ${esc(t.impresion)}</span><span>${esc(t.aviso)}</span></div>` : ''}</div>
        ${t && !cancelado ? `<div id="devolucion" class="${tarjeta}">
          ${titulo('Cancelación o devolución', 'assignment_return')}
          <p class="font-body-sm text-body-sm text-secondary mb-space-sm">Se registra como movimiento nuevo en el turno vigente de la caja elegida. El ticket original no se modifica.</p>
          <div class="grid grid-cols-2 gap-space-sm mb-space-sm"><label class="font-body-sm text-body-sm">Caja<select id="caja-dev" class="${entrada}">${[1, 2, 3, 4].map((k) => `<option ${k === t.venta.caja ? 'selected' : ''}>${k}</option>`).join('')}</select></label>
            <label class="font-body-sm text-body-sm">Motivo<input id="motivo" class="${entrada}" placeholder="Motivo"></label></div>
          ${t.venta.partidas.map((p) => `<div class="flex items-center justify-between gap-space-sm py-1"><span class="font-body-sm text-body-sm flex-1">${esc(p.nombre)} <span class="text-secondary">(de ${p.cantidad})</span></span>
            <input type="number" min="0" max="${p.cantidad}" value="0" data-dev="${esc(p.producto_id)}" class="${entrada} !w-20"></div>`).join('')}
          <div class="flex flex-wrap gap-space-sm mt-space-sm"><button id="devolver" class="${boton.secundario}">${icono('assignment_return')} Registrar devolución</button>
            <button id="cancelar-ticket" class="${boton.peligro}">${icono('cancel')} Cancelar ticket completo</button></div></div>` : ''}
      </div>
    </div></div>`;
  if (!t || cancelado) return;
  $('#ir-devolucion').onclick = () => $('#devolucion').scrollIntoView({ behavior: 'smooth' });
  const caja = () => Number($('#caja-dev').value);
  const motivo = () => $('#motivo').value || 'Sin motivo';
  $('#cancelar-ticket').onclick = async () => {
    if (confirm(`¿Cancelar el ticket ${v.folio}? Se reembolsa ${Dinero.formato(v.totales.total)} menos lo ya devuelto.`)
        && await accion(() => API.cancelarTicket(v.folio, caja(), motivo()), 'Ticket cancelado')) vistaVenta(id);
  };
  $('#devolver').onclick = async () => {
    const partidas = $$('[data-dev]').map((i) => ({ producto_id: i.dataset.dev, cantidad: parseInt(i.value, 10) || 0 })).filter((p) => p.cantidad > 0);
    if (!partidas.length) { aviso('Indique cuántas piezas se devuelven'); return; }
    if (await accion(() => API.devolver(v.folio, caja(), partidas, motivo()), 'Devolución registrada')) vistaVenta(id);
  };
}

// ======================================================================= CORTE

const corteUI = { modo: 'x' };

async function vistaCorte(params) {
  const q = new URLSearchParams(params);
  const datos = await API.corte(params ? `?${params}` : '');
  const consolidado = !!datos.cajas;
  const turnoVigente = !consolidado && datos.alcance.caja ? (await API.caja(datos.alcance.caja)).turno : null;
  const c = consolidado ? { ...datos.consolidado, alcance: {}, en_proceso: datos.en_proceso, invariante: { ok: datos.cajas.every((k) => k.invariante.ok) } } : datos;
  const a = c.alcance;
  const puedeCerrar = !consolidado && c.estado_turno === 'abierto';
  const cuadro = (cl, et, tit, sub, filas, pie, ok) => `<div class="${tarjeta}">
    <div class="flex justify-between items-start gap-space-xs mb-space-xs"><div class="flex items-center gap-space-xs"><span class="font-label-receipt text-label-receipt px-1.5 py-0.5 rounded ${cl}">${et}</span><span class="font-semibold">${tit}</span></div>${ok}</div>
    <div class="font-label-receipt text-label-receipt text-secondary mb-space-sm">${sub}</div>${filas}
    <div class="mt-space-sm bg-surface-container-low rounded p-space-sm">${pie}</div></div>`;
  const dif = (v, mon) => (v === null || v === undefined ? '<span class="text-secondary">sin conteo</span>'
    : `<span class="${v === 0 ? 'text-primary' : 'text-error'} font-bold">${v === 0 ? '✓ ' : ''}${Dinero.formato(v, mon)}</span>`);
  const okDe = (v) => (v === null || v === undefined ? insignia('Abierto', 'ok') : v === 0 ? insignia('Cuadrada', 'ok') : insignia('Descuadre', 'alerta'));
  const total = c.cobros.efectivo_mxn - c.cobros.cambio_entregado - c.reembolsos.efectivo + c.cobros.efectivo_usd_valor_mxn + c.cobros.tarjeta - c.reembolsos.tarjeta;
  const parte = (n) => (total > 0 ? Math.max(0, Math.round((n * 100) / total)) : 0);
  const efNeto = c.cobros.efectivo_mxn - c.cobros.cambio_entregado - c.reembolsos.efectivo;
  const tarNeta = c.cobros.tarjeta - c.reembolsos.tarjeta;

  $vista.innerHTML = `<div class="flex flex-col gap-space-md">
    <div class="${tarjeta} flex flex-wrap justify-between gap-space-md">
      <div><div class="${UI.etiqueta}">${consolidado ? 'Consolidado · turnos vigentes de las 4 cajas' : a.caja ? `Caja #${a.caja} · turno ${a.turno} (${esc(c.estado_turno)})` : `Cajero ${esc(a.cajero)} · todos sus movimientos`} · Sucursal Tijuana Centro #59</div>
        <h1 class="font-headline-lg text-headline-lg-mobile lg:text-headline-lg font-semibold">Arqueo y cierre de caja</h1>
        <div class="font-body-sm text-body-sm text-secondary flex flex-wrap gap-space-md">${a.cajero ? `<span>${icono('badge', 'text-[16px]')} Cajero titular: <b>${esc(a.cajero)}</b></span>` : ''}<span>${icono('schedule', 'text-[16px]')} Generado: ${fecha(c.generado_en || datos.generado_en)}</span></div></div>
      <div class="flex flex-col gap-space-sm items-end">
        <div class="flex flex-wrap gap-space-xs items-end">
          <label class="flex flex-col font-label-receipt text-label-receipt text-secondary">CAJA<select id="f-caja" class="${entrada} !w-28"><option value="">Todas</option>${[1, 2, 3, 4].map((n) => `<option ${q.get('caja') == n ? 'selected' : ''}>${n}</option>`).join('')}</select></label>
          <label class="flex flex-col font-label-receipt text-label-receipt text-secondary">TURNO<input id="f-turno" type="number" min="1" value="${esc(q.get('turno') || '')}" class="${entrada} !w-20"></label>
          <label class="flex flex-col font-label-receipt text-label-receipt text-secondary">CAJERO<input id="f-cajero" value="${esc(q.get('cajero') || '')}" class="${entrada} !w-32"></label>
          <button id="filtrar" class="${boton.primario}">${icono('search')}</button></div>
        <div class="flex rounded-lg bg-surface-container-low p-1">
          <button data-modo-corte="x" class="inline-flex items-center gap-1 px-space-sm py-space-xs rounded font-body-sm text-body-sm ${corteUI.modo === 'x' ? 'bg-surface-container-lowest font-semibold' : 'text-on-surface-variant'}">${icono('visibility', 'text-[18px]')} Corte parcial X (informativo)</button>
          <button data-modo-corte="z" ${puedeCerrar ? '' : 'disabled'} class="inline-flex items-center gap-1 px-space-sm py-space-xs rounded font-body-sm text-body-sm disabled:opacity-40 ${corteUI.modo === 'z' && puedeCerrar ? 'bg-primary-container text-on-primary font-semibold' : 'text-on-surface-variant'}">${icono('verified', 'text-[18px]')} Corte final Z (cierre de turno)</button></div>
      </div>
    </div>

    ${corteUI.modo === 'z' && puedeCerrar ? `<div class="rounded-lg bg-surface-container-low p-space-md flex flex-wrap items-end justify-between gap-space-md border border-primary-container">
      <div class="flex gap-space-sm"><div class="w-10 h-10 rounded bg-primary-container flex items-center justify-center">${icono('lock', 'text-on-primary')}</div>
        <div><div class="font-semibold">Modo: corte final Z (cierre de turno)</div><div class="font-label-receipt text-label-receipt text-secondary max-w-xl">Capture el efectivo contado. Al cerrar, el corte se guarda en DETS y no cambia más; las cancelaciones posteriores cuentan en el turno siguiente.</div></div></div>
      <div class="flex flex-wrap gap-space-sm items-end">
        <label class="flex flex-col font-label-receipt text-label-receipt text-secondary">CONTADO MXN<input id="contado-mxn" inputmode="decimal" class="${entrada} !w-36" placeholder="${(c.efectivo_esperado.mxn / 100).toFixed(2)}"></label>
        <label class="flex flex-col font-label-receipt text-label-receipt text-secondary">CONTADO USD<input id="contado-usd" inputmode="decimal" class="${entrada} !w-32" placeholder="${(c.efectivo_esperado.usd / 100).toFixed(2)}"></label>
        <button id="cerrar-turno" class="${boton.primario}">${icono('print')} Cerrar turno y generar corte Z</button></div></div>` : ''}
    ${turnoVigente && turnoVigente.turno === a.turno && turnoVigente.estado === 'cerrado' ? `<div class="rounded-lg bg-surface-container-low p-space-sm flex flex-wrap justify-between items-center gap-space-sm">${insignia('Turno cerrado: corte Z definitivo', 'ok')}
      <button id="abrir-turno" class="${boton.primario}">${icono('lock_open')} Abrir turno siguiente</button></div>` : ''}

    <div class="grid grid-cols-1 md:grid-cols-3 gap-space-md">
      ${cuadro('bg-primary-container text-on-primary', 'MXN', 'Efectivo moneda nacional', 'Arqueo físico vs. cálculo en libros',
        fila('Fondo inicial de apertura:', Dinero.formato(c.fondo_inicial)) + fila('Ventas cobradas en efectivo:', Dinero.formato(c.cobros.efectivo_mxn))
        + fila('Cambio entregado:', Dinero.formato(-c.cobros.cambio_entregado)) + fila('Reembolsos en efectivo:', Dinero.formato(-c.reembolsos.efectivo), 'font-label-numeric-sm text-label-numeric-sm text-error'),
        fila('SISTEMA ESPERADO MXN', `<b>${Dinero.formato(c.efectivo_esperado.mxn)}</b>`) + fila('FÍSICO CONTADO MXN', c.contado ? Dinero.formato(c.contado.mxn) : '—') + fila('<b>Diferencia:</b>', dif(c.diferencia?.mxn)), okDe(c.diferencia?.mxn))}
      ${cuadro('bg-tertiary-container text-on-tertiary', 'USD', 'Dólares americanos (efectivo)', 'Gaveta separada; sin reconversión',
        fila('Fondo inicial en dólares:', Dinero.formato(0, 'USD')) + fila('Ventas en efectivo USD:', Dinero.formato(c.cobros.efectivo_usd, 'USD'))
        + fila('Equivalencia (TC de cada venta):', `${Dinero.formato(c.cobros.efectivo_usd_valor_mxn)} MXN`) + fila('Reembolsos en dólares:', Dinero.formato(0, 'USD')),
        fila('SISTEMA ESPERADO USD', `<b>${Dinero.formato(c.efectivo_esperado.usd, 'USD')}</b>`) + fila('FÍSICO CONTADO USD', c.contado ? Dinero.formato(c.contado.usd, 'USD') : '—') + fila('<b>Diferencia USD:</b>', dif(c.diferencia?.usd, 'USD')), okDe(c.diferencia?.usd))}
      ${cuadro('bg-secondary-container text-on-secondary-container', 'TARJETA', 'Tarjetas (terminal simulada)', 'Cargos autorizados y reversos',
        fila('Cobrado con tarjeta:', Dinero.formato(c.cobros.tarjeta)) + fila('Ventas solo tarjeta:', `${c.ventas.por_modalidad.tarjeta} ops`) + fila('Ventas mixtas:', `${c.ventas.por_modalidad.mixto} ops`)
        + fila('Reversos a tarjeta:', Dinero.formato(-c.reembolsos.tarjeta), 'font-label-numeric-sm text-label-numeric-sm text-error'),
        fila('NETO EN TARJETA', `<b>${Dinero.formato(tarNeta)}</b>`) + fila('Comprobante', '<span class="font-label-receipt">simulado, sin banco real</span>'), insignia('Operando', 'ok'))}
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-space-md items-start">
      <div class="lg:col-span-7 flex flex-col gap-space-md">
        <div class="${tarjeta}">
          <div class="flex flex-wrap justify-between items-end gap-space-sm mb-space-sm"><div>${titulo('Resumen consolidado de ventas', 'account_balance_wallet')}
            <div class="font-label-receipt text-label-receipt text-secondary -mt-space-sm">Ventas ${c.ventas.numero} · cancelaciones ${c.cancelaciones.numero} · devoluciones ${c.devoluciones.numero}</div></div>
            <div class="text-right"><div class="${UI.etiqueta}">Venta neta</div><div class="font-label-numeric-lg text-label-numeric-lg font-bold text-primary">${Dinero.formato(c.venta_neta)} MXN</div></div></div>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-space-sm">${[['Efectivo MXN neto', efNeto, 'cobrado − cambio − reembolsos'], ['Efectivo USD (valor MXN)', c.cobros.efectivo_usd_valor_mxn, `${Dinero.formato(c.cobros.efectivo_usd, 'USD')} al TC de cada venta`], ['Tarjeta neta', tarNeta, 'cargos − reversos']].map(([n, v, d]) => `
            <div class="bg-surface-container-low rounded p-space-sm"><div class="${UI.etiqueta}">${n}</div><div class="font-label-numeric-md text-label-numeric-md font-bold">${Dinero.formato(v)}</div><div class="font-label-receipt text-label-receipt text-secondary">${d}</div></div>`).join('')}</div>
          <div class="mt-space-sm bg-surface-container-low rounded p-space-sm"><div class="flex justify-between ${UI.etiqueta} mb-1"><span>Distribución de medios de pago</span><span>participación</span></div>
            <div class="flex h-2.5 rounded overflow-hidden bg-surface-container-high"><div class="bg-primary" style="width:${parte(efNeto)}%"></div><div class="bg-tertiary-container" style="width:${parte(c.cobros.efectivo_usd_valor_mxn)}%"></div><div class="bg-secondary" style="width:${parte(tarNeta)}%"></div></div>
            <div class="flex flex-wrap gap-space-md mt-1 font-label-receipt text-label-receipt"><span>● Efectivo MXN ${parte(efNeto)}%</span><span class="text-tertiary">● Efectivo USD ${parte(c.cobros.efectivo_usd_valor_mxn)}%</span><span class="text-secondary">● Tarjeta ${parte(tarNeta)}%</span></div></div>
        </div>
        <div class="${tarjeta}">
          ${titulo('Invariante contable y ventas en proceso', 'rule')}
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-space-sm">
            <div class="flex gap-space-sm bg-surface-container-low rounded p-space-sm"><div class="w-10 h-10 shrink-0 rounded ${c.invariante.ok ? 'bg-primary-container' : 'bg-error'} flex items-center justify-center">${icono(c.invariante.ok ? 'verified' : 'dangerous', 'text-on-primary')}</div>
              <div><div class="font-semibold">${c.invariante.ok ? 'El corte cuadra' : 'EL CORTE NO CUADRA'}</div><div class="font-label-receipt text-label-receipt text-secondary">ventas − reembolsos = efectivo neto + USD (valor) + tarjeta neta${c.invariante.venta_neta !== undefined ? ` · ${Dinero.formato(c.invariante.venta_neta)} = ${Dinero.formato(c.invariante.explicado_por_medios)}` : ''}</div></div></div>
            <div class="flex gap-space-sm bg-surface-container-low rounded p-space-sm"><div class="w-10 h-10 shrink-0 rounded ${c.en_proceso.length ? 'bg-tertiary-container' : 'bg-surface-container-highest'} flex items-center justify-center">${icono('hourglass_top', 'text-on-primary')}</div>
              <div><div class="font-semibold">${c.en_proceso.length} venta(s) en proceso</div><div class="font-label-receipt text-label-receipt text-secondary">Listadas, NO sumadas: no están confirmadas en el libro.</div>
                ${c.en_proceso.map((v) => `<a class="block font-label-numeric-sm text-label-receipt text-primary" href="#/venta/${v.id}">${esc(v.id)} · caja ${v.caja} · ${esc(UI.TEXTO_ESTADO[v.estado])} · ${Dinero.formato(v.total)}</a>`).join('')}</div></div>
          </div>
          ${consolidado ? `<div class="mt-space-sm grid grid-cols-2 lg:grid-cols-4 gap-space-xs">${datos.cajas.map((k) => `<a href="#/corte?caja=${k.alcance.caja}" class="bg-surface-container-low rounded p-space-xs hover:bg-surface-container">
            <div class="flex justify-between font-semibold"><span>Caja ${k.alcance.caja} · T${k.alcance.turno}</span>${icono(k.invariante.ok ? 'check_circle' : 'dangerous', `text-[18px] ${k.invariante.ok ? 'text-primary' : 'text-error'}`)}</div>
            <div class="font-label-numeric-sm text-label-receipt">${k.ventas.numero} ventas · ${Dinero.formato(k.ventas.total)}</div></a>`).join('')}</div>` : ''}
        </div>
      </div>
      <div class="lg:col-span-5 ${tarjeta}">
        <div class="flex justify-between ${UI.etiqueta} mb-space-sm"><span>Previsualización térmica (80 mm)</span>${icono('receipt_long', 'text-[18px]')}</div>
        <pre class="ticket-termico mx-auto bg-surface-container-low p-space-sm font-label-receipt text-label-receipt whitespace-pre-wrap">${esc(textoCorte(c, consolidado))}</pre>
      </div>
    </div></div>`;

  $('#filtrar').onclick = () => {
    const p = new URLSearchParams();
    if ($('#f-caja').value) p.set('caja', $('#f-caja').value);
    if ($('#f-turno').value) p.set('turno', $('#f-turno').value);
    if ($('#f-cajero').value) p.set('cajero', $('#f-cajero').value);
    location.hash = `#/corte?${p}`;
  };
  $$('[data-modo-corte]').forEach((b) => { b.onclick = () => { corteUI.modo = b.dataset.modoCorte; vistaCorte(params); }; });
  const cerrar = $('#cerrar-turno');
  if (cerrar) cerrar.onclick = async () => {
    const mxn = Dinero.aCentavos($('#contado-mxn').value || '0'); const usd = Dinero.aCentavos($('#contado-usd').value || '0');
    if (mxn === null || usd === null) { aviso('Montos inválidos'); return; }
    if (await accion(() => API.cerrarTurno(a.caja, mxn, usd), `Turno ${a.turno} de la caja ${a.caja} cerrado`)) {
      corteUI.modo = 'x'; location.hash = `#/corte?caja=${a.caja}&turno=${a.turno}`;
    }
  };
  const abrir = $('#abrir-turno');
  if (abrir) abrir.onclick = async () => {
    const cajero = prompt('Nombre del cajero del nuevo turno');
    if (cajero && await accion(() => API.abrirTurno(a.caja, cajero, 100000), 'Turno abierto')) location.hash = `#/corte?caja=${a.caja}`;
  };
}

function textoCorte(c, consolidado) {
  const a = c.alcance; const W = 40;
  const l = (izq, der = '') => `${izq}${' '.repeat(Math.max(1, W - izq.length - der.length))}${der}`;
  const linea = '-'.repeat(W);
  return [
    '*'.repeat(W), '   COMPROBANTE INTERNO — NO ES CFDI', `   ${consolidado ? 'CORTE CONSOLIDADO' : c.estado_turno === 'cerrado' ? 'CORTE FINAL Z' : 'CORTE PARCIAL X'}`, '*'.repeat(W),
    'SUCURSAL: TIJUANA CENTRO #59',
    consolidado ? 'ALCANCE: 4 CAJAS, TURNOS VIGENTES' : a.caja ? `CAJA: ${a.caja}   TURNO: ${a.turno}` : `CAJERO: ${a.cajero}`,
    a.cajero && a.caja ? `CAJERO: ${a.cajero}` : '', `FECHA: ${fecha(c.generado_en || Date.now())}`, linea,
    l('FONDO APERTURA MXN:', Dinero.formato(c.fondo_inicial)), l('VENTAS (' + c.ventas.numero + '):', Dinero.formato(c.ventas.total)),
    l('EFECTIVO MXN:', Dinero.formato(c.cobros.efectivo_mxn)), l('EFECTIVO USD:', Dinero.formato(c.cobros.efectivo_usd, 'USD')),
    l('  VALOR MXN:', Dinero.formato(c.cobros.efectivo_usd_valor_mxn)), l('TARJETA:', Dinero.formato(c.cobros.tarjeta)),
    l('CAMBIO ENTREGADO:', Dinero.formato(-c.cobros.cambio_entregado)),
    l(`CANCELACIONES (${c.cancelaciones.numero}):`, Dinero.formato(-c.cancelaciones.monto)), l(`DEVOLUCIONES (${c.devoluciones.numero}):`, Dinero.formato(-c.devoluciones.monto)),
    '='.repeat(W), l('ESPERADO MXN:', Dinero.formato(c.efectivo_esperado.mxn)), l('ESPERADO USD:', Dinero.formato(c.efectivo_esperado.usd, 'USD')),
    c.contado ? l('CONTADO MXN:', Dinero.formato(c.contado.mxn)) : '', c.contado ? l('CONTADO USD:', Dinero.formato(c.contado.usd, 'USD')) : '',
    c.diferencia ? l('DIFERENCIA MXN:', Dinero.formato(c.diferencia.mxn)) : '', l('VENTA NETA:', Dinero.formato(c.venta_neta)),
    l('INVARIANTE CONTABLE:', c.invariante.ok ? 'CUADRA' : 'NO CUADRA'), l('VENTAS EN PROCESO:', `${c.en_proceso.length} (no sumadas)`), linea,
    '  Frontera POS #59 · Erlang/OTP 27', '  Persistencia local DETS',
  ].filter((x) => x !== '').join('\n');
}

// ===================================================================== BITACORA

const bit = { eventos: [], nivel: 'todos', tipo: 'todos', texto: '' };

async function vistaBitacora() {
  const [{ eventos }, estado] = await Promise.all([API.eventos(500), API.estado()]);
  bit.eventos = eventos;
  const reinicios = Object.entries(estado.reinicios).filter(([, n]) => n > 0);
  $vista.innerHTML = `<div class="flex flex-col gap-space-md">
    <div class="${tarjeta} flex flex-wrap justify-between gap-space-md items-center">
      <div class="flex gap-space-sm items-center"><div class="w-12 h-12 rounded-lg bg-surface-container-low flex items-center justify-center">${icono('terminal', 'text-primary text-[28px]')}</div>
        <div><div class="flex flex-wrap items-center gap-space-xs"><span class="font-headline-md text-headline-md">Bitácora OTP y auditoría BEAM</span><span class="font-label-numeric-sm text-label-receipt bg-surface-container px-1.5 rounded">${esc(sistema.nodo)}</span></div>
          <div class="${UI.etiqueta}">Supervisión concurrente en tiempo real · Tijuana Centro #59</div></div></div>
      <div class="flex flex-wrap gap-space-sm"><span id="ingestion" class="inline-flex items-center gap-1 px-space-sm py-space-xs rounded bg-surface-container-low text-primary font-body-sm text-body-sm"><span class="w-2 h-2 rounded-full bg-primary animate-pulse"></span></span>
        <button id="exportar" class="${boton.secundario}">${icono('download')} Exportar CSV</button>
        <button id="limpiar" class="${boton.secundario}">${icono('cleaning_services')} Limpiar vista</button></div>
    </div>
    <div class="${tarjeta} flex flex-col gap-space-sm">
      <div class="flex flex-wrap justify-between gap-space-sm"><div id="niveles" class="flex flex-wrap gap-space-xs"></div>
        <div class="flex items-center gap-space-xs bg-surface-container-low rounded px-space-sm min-w-[260px]">${icono('search', 'text-secondary')}<input id="texto" class="flex-1 bg-transparent py-space-sm font-body-sm text-body-sm focus:outline-none" placeholder="Buscar por pid, venta, folio, caja…" value="${esc(bit.texto)}"></div></div>
      <div class="flex flex-wrap items-center gap-space-xs"><span class="${UI.etiqueta}">Origen:</span><div id="tipos" class="flex flex-wrap gap-1"></div></div>
    </div>
    <div class="grid grid-cols-1 lg:grid-cols-12 gap-space-md items-start">
      <div class="lg:col-span-8 ${tarjeta}">${titulo('Secuencia de eventos OTP', 'view_list', 'más recientes primero')}
        <div id="lista" class="flex flex-col gap-space-xs"></div>
        <div class="mt-space-sm bg-surface-container-low rounded p-space-xs flex justify-between font-label-receipt text-label-receipt text-secondary"><span id="buffer"></span><span class="text-primary font-semibold">Tiempo real: SSE /api/eventos/stream</span></div></div>
      <div class="lg:col-span-4 flex flex-col gap-space-md">
        <div class="${tarjeta}">${titulo('Salud del nodo OTP', 'ecg_heart')}
          <div class="flex flex-col gap-space-sm">
            <div class="bg-surface-container-low rounded-lg p-space-sm"><div class="font-body-sm text-body-sm text-secondary">Cajas activas</div><div class="font-label-numeric-lg text-label-numeric-lg font-bold">${estado.cajas_activas} / 4</div></div>
            <div class="bg-surface-container-low rounded-lg p-space-sm"><div class="font-body-sm text-body-sm text-secondary">Reinicios supervisados</div>
              <div class="font-label-numeric-lg text-label-numeric-lg font-bold">${reinicios.reduce((s, [, n]) => s + n, 0)}</div>
              ${reinicios.map(([p, n]) => `<div class="flex justify-between font-label-numeric-sm text-label-receipt"><span>${esc(p)}</span><span>${n}</span></div>`).join('') || '<div class="font-label-receipt text-label-receipt text-secondary">Ningún proceso se ha reiniciado</div>'}</div>
            <div class="bg-surface-container-low rounded-lg p-space-sm"><div class="font-body-sm text-body-sm text-secondary">Ventas en proceso</div><div class="font-label-numeric-lg text-label-numeric-lg font-bold">${estado.ventas_en_proceso}</div></div>
          </div></div>
        <div class="${tarjeta}">${titulo('Regla de estados semánticos', 'rule')}
          <p class="font-body-sm text-body-sm text-secondary mb-space-sm">Criterio de diagnóstico, nunca solo por color:</p>
          ${[['ok', 'Operación normal o recuperación exitosa'], ['alerta', 'Reinicio supervisado, cancelación, descuadre'], ['falla', 'Proceso terminado, terminal sin respuesta']].map(([n, d]) => `
            <div class="flex justify-between items-center gap-space-sm bg-surface-container-low rounded p-space-xs mb-1">${insignia(UI.NIVEL_TEXTO[n], n)}<span class="font-label-receipt text-label-receipt text-secondary text-right">${d}</span></div>`).join('')}</div>
      </div>
    </div></div>`;
  $('#texto').oninput = (e) => { bit.texto = e.target.value.toLowerCase(); pintarBitacora(); };
  $('#exportar').onclick = exportarCsv;
  $('#limpiar').onclick = () => { bit.eventos = []; pintarBitacora(); };
  vistaBitacora.agregar = (e) => { bit.eventos.unshift(e); pintarBitacora(); };
  pintarBitacora();
}

function pintarBitacora() {
  const lista = document.getElementById('lista');
  if (!lista) return;
  const cuenta = (n) => bit.eventos.filter((e) => n === 'todos' || e.nivel === n).length;
  document.getElementById('ingestion').lastChild.textContent = ` Ingestión viva (${bit.eventos.length} evts)`;
  const NIV = { todos: ['Todos', 'view_list'], ok: ['Operando', 'check_circle'], alerta: ['Alerta', 'warning'], falla: ['Falla', 'dangerous'] };
  document.getElementById('niveles').innerHTML = Object.entries(NIV).map(([n, [txt, ic]]) => `
    <button data-nivel="${n}" class="inline-flex items-center gap-1 px-space-sm py-space-xs min-h-[40px] rounded font-body-sm text-body-sm ${bit.nivel === n ? 'bg-primary-container text-on-primary font-semibold' : 'bg-surface-container-low text-on-surface'}">${icono(ic, 'text-[18px]')}${txt}<span class="font-label-numeric-sm px-1 rounded bg-surface-container-highest text-on-surface">${cuenta(n)}</span></button>`).join('');
  const tipos = ['todos', ...new Set(bit.eventos.map((e) => e.tipo))];
  document.getElementById('tipos').innerHTML = tipos.map((t) => `<button data-tipo="${esc(t)}" class="px-space-xs py-0.5 rounded font-label-numeric-sm text-label-receipt ${bit.tipo === t ? 'bg-secondary-container text-on-secondary-container font-bold' : 'bg-surface-container-low text-on-surface-variant'}">${esc(t)}</button>`).join('');
  $$('[data-nivel]').forEach((b) => { b.onclick = () => { bit.nivel = b.dataset.nivel; pintarBitacora(); }; });
  $$('[data-tipo]').forEach((b) => { b.onclick = () => { bit.tipo = b.dataset.tipo; pintarBitacora(); }; });
  const visibles = bit.eventos.filter((e) => (bit.nivel === 'todos' || e.nivel === bit.nivel) && (bit.tipo === 'todos' || e.tipo === bit.tipo)
    && (!bit.texto || `${e.mensaje} ${JSON.stringify(e.datos)}`.toLowerCase().includes(bit.texto)));
  lista.innerHTML = visibles.slice(0, 300).map((e) => `
    <div class="grid grid-cols-[auto_1fr] sm:grid-cols-[auto_auto_1fr_auto] gap-space-xs sm:gap-space-sm items-start rounded p-space-sm ${NIVEL_FONDO[e.nivel] || ''}">
      <span class="font-label-numeric-sm text-label-numeric-sm text-secondary">${hora(e.ts)}</span>${insignia(UI.NIVEL_TEXTO[e.nivel], e.nivel)}
      <span class="col-span-2 sm:col-span-1 font-body-sm text-body-sm text-on-surface">${esc(e.mensaje)}</span>
      <span class="hidden sm:inline font-label-receipt text-label-receipt bg-surface-container px-1.5 rounded">${esc(e.tipo)}</span></div>`).join('') || UI.vacio('No hay eventos con ese filtro');
  document.getElementById('buffer').textContent = `BUFFER: ${visibles.length} visibles / ${bit.eventos.length} en memoria (servidor guarda los últimos 500)`;
}

function exportarCsv() {
  const fila = (e) => [new Date(e.ts).toISOString(), e.nivel, e.tipo, `"${String(e.mensaje).replace(/"/g, '""')}"`].join(',');
  const csv = ['fecha,nivel,tipo,mensaje', ...bit.eventos.map(fila)].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  a.download = `bitacora-p59-${Date.now()}.csv`; a.click();
}

// =================================================================== SIMULACION

const sim = { consola: [] };

async function vistaSimulacion() {
  const [estado, carga, { cajas }] = await Promise.all([API.estado(), API.carga(), API.cajas()]);
  const reinicios = Object.values(estado.reinicios).reduce((a, b) => a + b, 0);
  $vista.innerHTML = `<div class="flex flex-col gap-space-md">
    <div class="rounded-lg overflow-hidden"><div class="franja-peligro"></div>
      <div class="bg-tertiary-container text-on-tertiary p-space-sm flex flex-wrap justify-between items-center gap-space-sm">
        <div class="flex gap-space-sm items-start">${icono('warning')}<div><div class="font-semibold uppercase">Modo simulación — laboratorio de tolerancia a fallos BEAM</div>
          <div class="font-body-sm text-body-sm opacity-90">Inyección de fallas en vivo sobre las 4 cajas y los servicios de la sucursal. Banco, terminal, impresora y tipo de cambio son simulados.</div></div></div>
        <span class="font-label-numeric-sm text-label-receipt bg-inverse-surface text-inverse-on-surface px-space-xs py-0.5 rounded">SIN IMPACTO FISCAL NI HARDWARE · OTP 27</span></div></div>

    <div class="${tarjeta} flex flex-wrap justify-between gap-space-md">
      <div><h1 class="font-headline-lg text-headline-lg-mobile lg:text-headline-lg font-semibold flex items-center gap-space-xs">${icono('science', 'text-primary text-[28px]')} Demostración en vivo: inyección de fallas OTP</h1>
        <p class="font-body-sm text-body-sm text-secondary">Cada proceso se reinicia según la estrategia de su supervisor y reconstruye su estado desde DETS.</p></div>
      <div class="flex flex-wrap gap-space-xs items-start">
        <span class="font-label-numeric-sm text-label-receipt bg-surface-container-low px-space-sm py-space-xs rounded">REINICIOS GLOBALES: <b>${reinicios}</b></span>
        <span class="font-label-numeric-sm text-label-receipt bg-surface-container-low px-space-sm py-space-xs rounded">TERMINAL: <b>${esc(estado.terminal.modo)}</b></span></div>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-12 gap-space-md items-start">
      <div class="lg:col-span-7 flex flex-col gap-space-md">
        <div class="${tarjeta}">${titulo('Escenarios del problema', 'fact_check', 'verificaciones automáticas')}
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-space-xs">${[['a', 'A · Terminal cae a mitad del cobro', 'credit_card'], ['b', 'B · Cancelar ticket del turno anterior', 'history'], ['c', 'C · Reintento de red duplicado', 'sync_alt'],
            ['d', 'D · Pago en dólares, cambio en pesos', 'currency_exchange'], ['e', 'E · Corte con ventas en proceso', 'calculate']].map(([l, t, ic]) => `
            <button data-esc="${l}" class="${boton.secundario} !justify-start text-left">${icono(ic, 'text-primary')}${t}</button>`).join('')}
            <button id="caos" class="${boton.peligro} !justify-start">${icono('bolt')} Prueba de caos completa</button></div></div>

        <div>${titulo('Inyectores de falla por actor', 'bolt', `${cajas.length} cajas registradas`)}
          <div class="flex flex-col gap-space-sm">${cajas.map((c) => `<div class="${tarjeta} !p-space-sm">
            <div class="flex flex-wrap justify-between items-center gap-space-xs"><span class="flex items-center gap-1 font-semibold">${icono('point_of_sale', 'text-[18px]')} Caja 0${c.id} · ${esc(c.turno.cajero)}</span>
              <span class="flex items-center gap-space-xs">${insignia(...nivelCaja(c))}${pid(c.proceso.pid)}</span></div>
            <div class="font-body-sm text-body-sm text-secondary my-1">${c.venta_actual ? `Venta en curso ${esc(c.venta_actual.id)} (${esc(UI.TEXTO_ESTADO[c.venta_actual.estado])}) — debe sobrevivir al crash de la caja.` : 'Sin venta en curso.'}</div>
            <button data-matar="p59_caja_${c.id}" class="w-full inline-flex items-center justify-center gap-space-xs min-h-[40px] rounded bg-error text-on-error font-semibold">${icono('cancel', 'text-[18px]')} exit(Pid, kill)</button></div>`).join('')}
            <div class="${tarjeta} !p-space-sm"><div class="flex justify-between items-center font-semibold mb-1"><span class="flex items-center gap-1">${icono('database', 'text-[18px]')} Servicios centrales</span><span class="font-label-receipt text-label-receipt text-secondary">rest_for_one / one_for_one</span></div>
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-space-xs">${[['p59_inventario', 'Inventario y libro'], ['p59_terminal_bancaria', 'Terminal bancaria'], ['p59_ventas_sup', 'Supervisor de ventas']].map(([p, n]) => `
                <button data-matar="${p}" class="inline-flex flex-col items-center justify-center min-h-[52px] rounded bg-error-container text-on-error-container font-semibold">${n}<span class="font-label-numeric-sm text-label-receipt">${p}</span></button>`).join('')}</div></div>
          </div></div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-space-md">
          <div class="${tarjeta}">${titulo('Terminal bancaria', 'contactless')}
            <div class="flex flex-wrap gap-1">${[['normal', 'Normal'], ['rechazar', 'Rechazar'], ['fuera_de_linea', 'Fuera de línea'], ['caida_antes_de_cobro', 'Cae antes de cobrar'], ['caida_tras_cobro', 'Cae tras cobrar'], ['aleatorio', 'Aleatorio']].map(([m, n]) => `
              <button data-terminal="${m}" class="${estado.terminal.modo === m ? 'bg-tertiary-container text-on-tertiary' : 'bg-surface-container-low text-on-surface'} px-space-sm py-space-xs min-h-[40px] rounded font-body-sm text-body-sm">${n}</button>`).join('')}</div>
            <p class="font-label-receipt text-label-receipt text-secondary mt-space-xs">Las fallas aplican a la siguiente operación (normal y aleatorio son permanentes).</p></div>
          <div class="${tarjeta}">${titulo('Impresora y carga', 'print')}
            <div class="flex gap-space-xs mb-space-sm"><button data-imp="ok" class="${boton.suave}">En línea</button><button data-imp="atascada" class="${boton.suave}">Atascar</button>
              <span class="font-label-receipt text-label-receipt text-secondary self-center">pendientes: ${estado.impresora.pendientes.length}</span></div>
            <button id="carga" class="${boton.primario} w-full">${icono('bolt')} 4 cajas · 600 tickets</button>
            <div id="estado-carga" class="mt-space-xs">${resumenCarga(carga.reporte)}</div></div>
        </div>
      </div>

      <div class="lg:col-span-5 flex flex-col gap-space-md">
        <div class="${tarjeta}">${titulo('Monitor de observabilidad (árbol OTP)', 'account_tree', 'en vivo')}
          <div class="max-h-[520px] overflow-y-auto">${UI.arbol(estado.arbol, estado.reinicios)}</div></div>
        <div class="rounded-xl overflow-hidden bg-[#0b0f17] text-[#d1fae5] shadow-sm">
          <div class="flex justify-between items-center px-space-sm py-space-xs bg-[#131b26]"><span class="flex items-center gap-1 font-label-numeric-sm text-label-receipt"><span class="w-2.5 h-2.5 rounded-full bg-[#f87171]"></span><span class="w-2.5 h-2.5 rounded-full bg-[#fbbf24]"></span><span class="w-2.5 h-2.5 rounded-full bg-[#10b981]"></span>&nbsp;${esc(sistema.nodo)}</span>
            <button id="limpiar-consola" class="font-label-receipt text-label-receipt text-[#9ca3af]">Limpiar</button></div>
          <pre id="consola" class="p-space-sm h-72 overflow-y-auto font-label-receipt text-label-receipt whitespace-pre-wrap"></pre></div>
      </div>
    </div></div>`;
  pintarConsola();
  $$('[data-esc]').forEach((b) => { b.onclick = async () => {
    b.disabled = true; consola(`> POST /api/simulacion/escenarios/${b.dataset.esc}`);
    const r = await accion(() => API.escenario(b.dataset.esc)); b.disabled = false; if (r) mostrarResultado(r.datos);
  }; });
  $('#caos').onclick = async () => { consola('> POST /api/simulacion/caos (mata caja, venta e inventario)'); const r = await accion(() => API.simular('caos')); if (r) mostrarResultado(r.datos); vistaSimulacion(); };
  $$('[data-matar]').forEach((b) => { b.onclick = async () => {
    consola(`> exit(whereis(${b.dataset.matar}), kill)`);
    await accion(() => API.simular('matar', { proceso: b.dataset.matar }), `${b.dataset.matar} terminado`);
    setTimeout(vistaSimulacion, 500);
  }; });
  $$('[data-terminal]').forEach((b) => { b.onclick = async () => {
    await accion(() => API.simular('terminal', { modo: b.dataset.terminal, una_vez: !['normal', 'aleatorio'].includes(b.dataset.terminal) }), `Terminal: ${b.dataset.terminal}`);
    vistaSimulacion();
  }; });
  $$('[data-imp]').forEach((b) => { b.onclick = () => accion(() => API.simular('impresora', { modo: b.dataset.imp }), `Impresora: ${b.dataset.imp}`); });
  $('#limpiar-consola').onclick = () => { sim.consola = []; pintarConsola(); };
  $('#carga').onclick = async () => {
    if (!(await accion(() => API.simular('carga', { tickets: 600 }), 'Simulación iniciada'))) return;
    consola('> simulación de carga: 4 cajas, 600 tickets');
    const sondeo = setInterval(async () => {
      const { reporte } = await API.carga();
      const el = document.getElementById('estado-carga');
      if (!el) { clearInterval(sondeo); return; }
      el.innerHTML = resumenCarga(reporte);
      if (reporte && reporte.estado !== 'corriendo') { clearInterval(sondeo); consola(`< carga terminada: ${reporte.tickets_confirmados} tickets, invariantes ${reporte.ok ? 'OK' : 'FALLA'}`); }
    }, 1000);
  };
}

function resumenCarga(r) {
  if (!r) return '<span class="font-label-receipt text-label-receipt text-secondary">Sin corridas en esta sesión.</span>';
  if (r.estado === 'corriendo') return insignia('Corriendo…', 'alerta', true);
  if (r.estado === 'error') return insignia('Error', 'falla');
  return `${insignia(r.ok ? 'Invariantes OK' : 'Falla', r.ok ? 'ok' : 'falla')}
    <div class="font-label-numeric-sm text-label-receipt mt-1">${r.tickets_confirmados} tickets en ${r.duracion_ms} ms · ${r.tickets_por_segundo} t/s</div>`;
}

function consola(linea) {
  sim.consola.push(`[${hora(Date.now())}] ${linea}`);
  if (sim.consola.length > 300) sim.consola.shift();
  pintarConsola();
}
function pintarConsola() {
  const el = document.getElementById('consola');
  if (!el) return;
  el.textContent = sim.consola.join('\n') || '=PROGRESS REPORT=== consola de la demo\n  Las acciones y los eventos en vivo aparecen aquí.';
  el.scrollTop = el.scrollHeight;
}

function mostrarResultado(r) {
  const checks = r.verificaciones || (r.experimentos || []).flatMap((e) =>
    [{ verificacion: `--- se mató ${e.proceso} (${e.pid_antes} -> ${e.pid_despues}) · ${e.supervisor} (${e.estrategia})`, ok: e.ok }, ...e.ocurrido]);
  consola(`< ${r.titulo || 'Prueba de caos'}: ${r.ok ? 'OK' : 'FALLA'}`);
  checks.forEach((c) => consola(`  [${c.ok ? 'ok' : 'XX'}] ${c.verificacion}${c.ok ? '' : ` (esperado ${JSON.stringify(c.esperado)}, obtenido ${JSON.stringify(c.obtenido)})`}`));
}

// =================================================================== ENRUTADOR

function actualizarEncabezado(c) {
  document.getElementById('cajero-encabezado').textContent = `Caja ${c.id} · ${c.turno.cajero}`;
  document.getElementById('turno-encabezado').textContent = `Turno ${c.turno.turno} (${c.turno.estado})`;
}

const rutas = [
  [/^#?\/?$/, () => tablero()],
  [/^#\/(?:cobrar|pos)\/(\d)$/, (m) => vistaCobrar(m[1])],
  [/^#\/caja\/(\d)$/, (m) => vistaCaja(m[1])],
  [/^#\/venta$/, () => vistaVentas()],
  [/^#\/venta\/([\w-]+)$/, (m) => vistaVenta(m[1])],
  [/^#\/ticket\/([\w-]+)$/, async (m) => { const t = await API.ticket(m[1]); location.replace(`#/venta/${t.venta.venta_id}`); }],
  [/^#\/corte(?:\?(.*))?$/, (m) => vistaCorte(m[1] || '')],
  [/^#\/bitacora$/, () => vistaBitacora()],
  [/^#\/simulacion$/, () => vistaSimulacion()],
];
let vistaActual = '';

const CLASE_MENU = {
  activo: 'px-space-sm py-2 rounded-lg bg-primary-container text-on-primary font-semibold font-body-sm text-body-sm',
  inactivo: 'px-space-sm py-2 rounded-lg text-on-surface-variant hover:bg-surface-container hover:text-on-surface transition-colors font-body-sm text-body-sm font-medium',
  movilActivo: 'flex flex-col items-center gap-0.5 py-space-xs text-[11px] text-primary font-semibold',
  movilInactivo: 'flex flex-col items-center gap-0.5 py-space-xs text-[11px] text-on-surface-variant',
};

async function navegar() {
  const h = location.hash || '#/';
  vistaActual = h;
  const seccion = h.split('/')[1]?.split('?')[0] || '';
  const sec = seccion === 'pos' ? 'cobrar' : seccion === 'ticket' ? 'venta' : seccion;
  document.querySelectorAll('#menu a').forEach((a) => { a.className = a.dataset.ruta === sec ? CLASE_MENU.activo : CLASE_MENU.inactivo; });
  document.querySelectorAll('#menu-movil a').forEach((a) => { a.className = a.dataset.ruta === sec ? CLASE_MENU.movilActivo : CLASE_MENU.movilInactivo; });
  for (const [re, fn] of rutas) {
    const m = h.match(re);
    if (m) {
      try { await fn(m); } catch (e) { $vista.innerHTML = `<div class="${tarjeta}">${insignia('Error', 'falla')} ${esc(e.message)}</div>`; }
      return;
    }
  }
  $vista.innerHTML = `<div class="${tarjeta}">${UI.vacio('Ruta no encontrada', 'search')}</div>`;
}

// Datos del sistema para el encabezado (tipo de cambio, nodo, IVA vigente).
async function refrescarSistema() {
  try {
    const e = await API.estado();
    sistema.ivaGeneral = e.sistema.iva_general_pb; sistema.tc = e.tipo_cambio.valor; sistema.nodo = e.sistema.nodo;
    document.getElementById('tc-encabezado').textContent = Dinero.tc(sistema.tc);
    document.getElementById('nodo-encabezado').textContent = `${sistema.nodo} [${e.resumen.productos} SKUs]`;
  } catch (_) { /* el indicador de conexion ya refleja la falla */ }
}

document.getElementById('tema').onclick = () => {
  const oscuro = document.documentElement.classList.toggle('dark');
  try { localStorage.setItem('p59-tema', oscuro ? 'oscuro' : 'claro'); } catch (_) {}
};

// Tiempo real: los eventos SSE refrescan la vista activa y alimentan bitácora y consola.
let refresco;
API.eventosEnVivo((e) => {
  if (e.tipo === 'tipo_cambio') { sistema.tc = e.datos.valor; document.getElementById('tc-encabezado').textContent = Dinero.tc(sistema.tc); }
  if (vistaActual.startsWith('#/bitacora') && vistaBitacora.agregar) vistaBitacora.agregar(e);
  if (vistaActual.startsWith('#/simulacion')) consola(`[${e.nivel}] ${e.tipo}: ${e.mensaje}`);
  if (vistaActual === '#/' || vistaActual === '' || vistaActual.startsWith('#/caja')) { clearTimeout(refresco); refresco = setTimeout(navegar, 400); }
}, (conectado) => {
  document.getElementById('conexion').innerHTML = conectado
    ? '<span class="w-2 h-2 rounded-full bg-primary animate-pulse"></span><span class="font-body-sm text-body-sm font-medium text-primary">En vivo</span>'
    : '<span class="w-2 h-2 rounded-full bg-error"></span><span class="font-body-sm text-body-sm font-medium text-error">Sin conexión</span>';
  if (conectado) refrescarSistema();
});

window.addEventListener('hashchange', navegar);
refrescarSistema().then(navegar);
