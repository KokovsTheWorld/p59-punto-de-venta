// Componentes visuales del diseño de Google Stitch (design/stitch/), reescritos
// como funciones que reciben datos reales de la API. Las clases de Tailwind se
// escriben completas (nunca concatenadas) para que el compilador las encuentre.

const UI = (() => {
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const hora = (ms) => (ms ? new Date(ms).toLocaleTimeString('es-MX', { hour12: false }) : '—');
  const fecha = (ms) => (ms ? new Date(ms).toLocaleString('es-MX', { hour12: false }) : '—');
  const icono = (nombre, clases = 'text-[20px]') => `<span class="material-symbols-outlined ${clases}">${nombre}</span>`;

  const tarjeta = 'bg-surface-container-lowest rounded-xl p-space-md shadow-sm';
  const etiqueta = 'font-label-receipt text-label-receipt text-secondary uppercase';
  const boton = {
    primario: 'inline-flex items-center justify-center gap-space-xs px-space-md py-space-sm min-h-[44px] rounded bg-primary-container text-on-primary font-semibold hover:bg-primary transition-colors disabled:opacity-50',
    secundario: 'inline-flex items-center justify-center gap-space-xs px-space-md py-space-sm min-h-[44px] rounded bg-surface-container-low text-on-surface font-medium border border-outline-variant hover:bg-surface-container transition-colors disabled:opacity-50',
    peligro: 'inline-flex items-center justify-center gap-space-xs px-space-md py-space-sm min-h-[44px] rounded bg-error text-on-error font-semibold hover:opacity-90 transition-opacity disabled:opacity-50',
    suave: 'inline-flex items-center justify-center gap-space-xs px-space-sm py-space-xs rounded bg-surface-container text-on-surface-variant font-medium hover:bg-surface-container-high transition-colors disabled:opacity-50',
  };
  const entrada = 'w-full bg-surface-container-lowest border border-outline-variant rounded px-space-sm py-space-sm min-h-[44px] font-label-numeric-sm text-label-numeric-sm text-on-surface focus:outline-none focus:ring-2 focus:ring-primary-container';

  // Insignia semantica: siempre icono + punto + texto (DESIGN.md, "Status Indicators").
  const NIVELES = {
    ok: { caja: 'bg-primary-fixed text-on-primary-fixed-variant', punto: 'bg-primary', icono: 'check_circle' },
    alerta: { caja: 'bg-tertiary-fixed text-on-tertiary-fixed-variant', punto: 'bg-tertiary-container', icono: 'warning' },
    falla: { caja: 'bg-error-container text-on-error-container', punto: 'bg-error', icono: 'dangerous' },
  };
  function insignia(texto, nivel = 'ok', pulso = false) {
    const n = NIVELES[nivel] || NIVELES.ok;
    return `<span class="inline-flex items-center gap-1 px-2 py-1 rounded-full ${n.caja} whitespace-nowrap">
      <span class="w-2 h-2 rounded-full ${n.punto} ${pulso ? 'animate-pulse' : ''}"></span>
      ${icono(n.icono, 'text-[14px]')}
      <span class="font-body-sm text-label-receipt font-bold">${esc(texto)}</span></span>`;
  }
  const NIVEL_ESTADO = { abierta: 'ok', procesando_pago: 'alerta', pendiente_de_revision: 'falla', pagada: 'ok', cancelada: 'alerta' };
  const TEXTO_ESTADO = {
    abierta: 'Abierta', procesando_pago: 'Procesando pago', pendiente_de_revision: 'Pendiente de revisión',
    pagada: 'Pagada', cancelada: 'Cancelada',
  };
  const insigniaVenta = (e) => insignia(TEXTO_ESTADO[e] || e, NIVEL_ESTADO[e] || 'ok', e === 'pendiente_de_revision');
  const NIVEL_TEXTO = { ok: 'Operando', alerta: 'Alerta', falla: 'Falla' };

  const pid = (p) => `<span class="font-label-numeric-sm text-label-receipt bg-surface-container-highest px-1.5 py-0.5 rounded text-on-surface-variant">${esc(p || '—')}</span>`;

  function kpi({ titulo, icono: ic, valor, sub = '', pie = '', claseValor = 'text-on-surface', claseIcono = 'text-primary' }) {
    return `<div class="${tarjeta} flex flex-col justify-between">
      <div class="flex items-center justify-between text-secondary mb-space-xs">
        <span class="font-body-sm text-body-sm font-medium">${titulo}</span>${icono(ic, `${claseIcono} text-[20px]`)}</div>
      <div class="flex flex-col">
        <span class="font-label-numeric-lg text-label-numeric-lg font-bold tracking-tight ${claseValor}">${valor}</span>
        <span class="font-label-receipt text-label-receipt text-secondary mt-0.5">${sub}</span></div>
      ${pie ? `<div class="mt-space-sm pt-space-xs flex items-center justify-between font-label-receipt text-label-receipt text-secondary">${pie}</div>` : ''}
    </div>`;
  }

  function titulo(texto, ic, derecha = '') {
    return `<div class="flex flex-wrap items-center justify-between gap-space-sm mb-space-md">
      <h2 class="font-headline-md text-headline-md text-on-surface flex items-center gap-space-xs">${icono(ic, 'text-primary text-[22px]')}${texto}</h2>
      ${derecha ? `<span class="font-label-receipt text-label-receipt text-secondary uppercase">${derecha}</span>` : ''}</div>`;
  }

  function fila(izq, der, claseDer = 'font-label-numeric-sm text-label-numeric-sm text-on-surface') {
    return `<div class="flex items-center justify-between gap-space-sm py-1">
      <span class="font-body-sm text-body-sm text-secondary">${izq}</span><span class="${claseDer} text-right">${der}</span></div>`;
  }

  // Arbol de supervision vivo (DESIGN.md, "Erlang/OTP Supervision Tree Visualizer").
  const ESTRATEGIAS = {
    p59_punto_de_venta_sup: 'rest_for_one', p59_servicios_sup: 'one_for_one', p59_sucursal_sup: 'rest_for_one',
    p59_ventas_sup: 'simple_one_for_one · transient', p59_cajas_sup: 'one_for_one',
  };
  function arbol(nodo, reinicios = {}, nivel = 0) {
    const sup = nodo.tipo === 'supervisor';
    const r = reinicios[nodo.id] || 0;
    const estado = nodo.vivo === false ? insignia('Falla', 'falla') : r > 0 ? insignia(`${r} reinicio${r > 1 ? 's' : ''}`, 'alerta') : insignia('Operando', 'ok');
    const hijos = nodo.hijos || [];
    return `<div class="${nivel ? 'pl-space-md border-l border-outline-variant ml-space-xs' : ''}">
      <div class="my-1 flex flex-wrap items-center gap-space-xs rounded p-space-xs ${sup ? 'bg-surface-container-low' : 'bg-surface-container-lowest border border-surface-container-high'}">
        <span class="font-label-receipt text-label-receipt px-1.5 py-0.5 rounded ${sup ? 'bg-primary-container text-on-primary' : 'bg-surface-container-highest text-on-surface-variant'}">${sup ? 'supervisor' : 'worker'}</span>
        <span class="font-label-numeric-sm text-label-numeric-sm font-semibold text-on-surface">${esc(nodo.id)}</span>
        <span class="font-label-numeric-sm text-label-receipt text-secondary">${esc(nodo.pid || '')}</span>
        ${ESTRATEGIAS[nodo.id] ? `<span class="font-label-receipt text-label-receipt text-primary">${ESTRATEGIAS[nodo.id]}</span>` : ''}
        <span class="ml-auto">${estado}</span>
      </div>
      ${hijos.map((h) => arbol(h, reinicios, nivel + 1)).join('')}
    </div>`;
  }

  // Ticket termico de 80 mm a partir del movimiento confirmado del libro.
  function ticketTermico(t, ivaGeneral) {
    const v = t.venta;
    const l = (a, b, cls = '') => `<div class="flex justify-between gap-space-sm ${cls}"><span>${a}</span><span class="text-right">${b}</span></div>`;
    const sep = '<div class="my-space-xs border-t border-dashed border-outline"></div>';
    const usd = v.pagos.some((p) => p.metodo === 'efectivo_usd');
    return `<div class="ticket-termico mx-auto bg-surface-container-lowest p-space-md font-label-receipt text-label-receipt text-on-surface">
      <div class="bg-surface-container-low text-center py-space-xs mb-space-sm">
        <div class="font-bold">*** COMPROBANTE INTERNO — NO ES CFDI ***</div>
        <div class="text-secondary">SIN VALIDEZ FISCAL · CONTROL DE MOSTRADOR</div></div>
      <div class="text-center mb-space-sm"><div class="font-label-numeric-md text-label-numeric-md font-bold">FRONTERA POS #59</div>
        <div>Sucursal Tijuana Centro · Tijuana, B.C.</div></div>
      ${l(`TICKET: ${esc(v.folio)}`, `CAJA: ${v.caja}`)}${l(`VENTA: ${esc(v.venta_id)}`, `TURNO: ${v.turno}`)}
      ${l(`CAJERO: ${esc(v.cajero)}`, '')}${l(`FECHA: ${fecha(v.fecha)}`, '')}${sep}
      ${v.partidas.map((p) => `<div>${p.cantidad} x ${esc(p.nombre)}</div>
        ${l(`&nbsp;&nbsp;${Dinero.formato(p.precio_unitario)} · IVA ${p.tasa_iva / 100}%${p.descuento ? ` · desc ${Dinero.formato(p.descuento)}` : ''}`, Dinero.formato(p.importe))}`).join('')}
      ${sep}${l('SUBTOTAL:', Dinero.formato(v.subtotal))}${l('DESCUENTOS:', Dinero.formato(-v.descuentos))}
      ${l(`IVA (${ivaGeneral ? ivaGeneral / 100 : 16}% general / 0% básicos):`, Dinero.formato(v.iva))}
      <div class="flex justify-between items-baseline mt-space-xs"><span class="font-label-numeric-md text-label-numeric-md font-bold">TOTAL MXN:</span>
        <span class="font-label-numeric-lg text-label-numeric-lg font-bold text-primary">${Dinero.formato(v.total)}</span></div>
      ${usd ? l('T.C. DE LA VENTA:', `${Dinero.tc(v.tipo_cambio)} MXN`) : ''}${sep}
      <div class="bg-surface-container-low p-space-xs">
        <div class="font-bold mb-1">FORMA DE PAGO ${v.modalidad === 'mixto' ? 'MIXTA' : ''}</div>
        ${v.pagos.map((p) => p.metodo === 'efectivo_usd'
          ? l(`- Efectivo dólares (${Dinero.formato(p.monto, 'USD')}):`, Dinero.formato(p.monto_mxn))
          : l(`- ${p.metodo === 'tarjeta' ? `Tarjeta simulada${v.autorizacion ? ` (Aut: ${esc(v.autorizacion)})` : ''}` : 'Efectivo MXN'}:`, Dinero.formato(p.monto))).join('')}
        ${l('<b>CAMBIO ENTREGADO (MXN):</b>', `<b>${Dinero.formato(v.cambio_mxn)}</b>`)}</div>
      ${t.reembolsos.map((r) => `${sep}${l(`${r.tipo.toUpperCase()} ${esc(r.id)}`, Dinero.formato(-r.monto), 'text-error font-bold')}
        <div class="text-secondary">turno ${r.turno} (original ${r.turno_original}) · ${hora(r.fecha)} · ${esc(r.motivo)}</div>`).join('')}
      ${sep}<div class="text-center text-secondary">Gracias por su compra.<br>Este ticket no es un comprobante fiscal (CFDI).</div>
    </div>`;
  }

  function vacio(texto, ic = 'info') {
    return `<div class="flex flex-col items-center justify-center gap-space-xs py-space-lg text-secondary text-center">
      ${icono(ic, 'text-[32px]')}<span class="font-body-sm text-body-sm">${texto}</span></div>`;
  }

  return {
    esc, hora, fecha, icono, tarjeta, etiqueta, boton, entrada, insignia, insigniaVenta, NIVEL_TEXTO,
    pid, kpi, titulo, fila, arbol, ticketTermico, vacio, TEXTO_ESTADO,
  };
})();
