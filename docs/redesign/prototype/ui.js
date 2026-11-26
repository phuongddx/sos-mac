/* SOS Mac — shared UI building blocks (icons, formatters, lifecycle frame pieces). */
'use strict';
(function () {
  /* SF Symbols stand-ins: same names as the SwiftUI symbol in the comment. Stroke 1.7 on a 24 grid. */
  const P = {
    sparkles: 'M12 3l1.8 4.7 4.7 1.8-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8z M18.5 15l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z', // sparkles
    wand: 'M4 20L15 9 M13 7l4 4 M17.5 3v3 M16 4.5h3 M20.5 9v2 M19.5 10h2 M9 3v2 M8 4h2', // wand.and.stars
    trash: 'M4 7h16 M9 7V4.5h6V7 M6 7l1 13h10l1-13 M10 11v6 M14 11v6', // trash
    docs: 'M8 7V4h8l4 4v10h-4 M4 8h8l4 4v8H4z', // doc.on.doc
    grid: 'M4 4h16v16H4z M4 9.33h16 M4 14.67h16 M9.33 4v16 M14.67 4v16', // square.grid.3x3
    cloud: 'M7 18.5h10.5a4 4 0 0 0 .5-7.97A6 6 0 0 0 6.6 9.6 4.5 4.5 0 0 0 7 18.5z', // icloud
    appx: 'M4 5h16v4H4z M5.5 9v10.5h13V9 M10 12.5l4 4 M14 12.5l-4 4', // xmark.bin
    updater: 'M19.5 13a7.5 7.5 0 0 1-13.4 4.1 M4.5 11a7.5 7.5 0 0 1 13.4-4.1 M18.5 3.5v3.6h-3.6 M5.5 20.5v-3.6h3.6', // arrow.triangle.2.circlepath
    gauge: 'M4 17a8 8 0 1 1 16 0 M12 17l3.5-4.5 M7 13.5h.01 M12 9.5v.01 M17 13.5h.01', // gauge.with.dots.needle
    shield: 'M12 3l7 3v6c0 4.4-3 7.6-7 9-4-1.4-7-4.6-7-9V6z M9 12l2 2 4-4', // checkmark.shield
    shieldplain: 'M12 3l7 3v6c0 4.4-3 7.6-7 9-4-1.4-7-4.6-7-9V6z', // shield
    check: 'M5 12.5l4.5 4.5L19 7.5', // checkmark
    minus: 'M6 12h12', // minus
    plus: 'M12 5v14 M5 12h14',
    chevR: 'M9.5 6l6 6-6 6', chevL: 'M14.5 6l-6 6 6 6', chevD: 'M6 9.5l6 6 6-6',
    x: 'M6.5 6.5l11 11 M17.5 6.5l-11 11', // xmark
    search: 'M10.5 17a6.5 6.5 0 1 0 0-13 6.5 6.5 0 0 0 0 13z M15.5 15.5L20 20', // magnifyingglass
    folder: 'M3 7.5A2 2 0 0 1 5 5.5h4l2 2h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z', // folder
    doc: 'M6.5 3h7.5l4 4v14H6.5z M14 3v4h4', // doc
    warn: 'M12 4l9 16H3z M12 10v4 M12 17v.01', // exclamationmark.triangle
    info: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M12 11v5 M12 7.8v.01', // info.circle
    lock: 'M6 11h12v9H6z M8.5 11V8a3.5 3.5 0 0 1 7 0v3', // lock
    memory: 'M3.5 7h17v10h-17z M8 7v10 M12 7v10 M16 7v10 M6 17v3 M18 17v3 M6 4v3 M18 4v3', // memorychip
    network: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M3 12h18 M12 3c3 3.2 3 14.8 0 18 M12 3c-3 3.2-3 14.8 0 18', // network
    restore: 'M9 14L4 9l5-5 M4 9h10a6 6 0 0 1 0 12h-3', // arrow.uturn.backward
    drive: 'M3 14h18v5H3z M5 14l2-8h10l2 8 M16.5 16.5h.01', // externaldrive
    house: 'M4 11l8-7 8 7 M6 9.5V20h12V9.5 M10 20v-5h4v5', // house
    cpu: 'M7 7h10v10H7z M10 10h4v4h-4z M10 3.5V7 M14 3.5V7 M10 17v3.5 M14 17v3.5 M3.5 10H7 M3.5 14H7 M17 10h3.5 M17 14h3.5', // cpu
    thermo: 'M10 13.5V5a2 2 0 0 1 4 0v8.5a4 4 0 1 1-4 0z M12 9v6', // thermometer.medium
    box: 'M3 5h18v4H3z M5 9v10h14V9 M10 13h4', // archivebox
    photo: 'M3 5h18v14H3z M3 16l5-5 4 4 3-3 6 6 M16 9.5h.01', // photo
    film: 'M4 4h16v16H4z M8 4v16 M16 4v16 M4 8h4 M4 12h4 M4 16h4 M16 8h4 M16 12h4 M16 16h4', // film
    music: 'M9 18V5l11-2v13 M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0z M20 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0z', // music.note
    code: 'M8 7l-5 5 5 5 M16 7l5 5-5 5 M13.5 4l-3 16', // chevron.left.forwardslash.chevron.right
    app: 'M7 4h10a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3z', // app
    external: 'M14 4h6v6 M20 4l-9 9 M18 14v6H4V6h6', // arrow.up.forward.square
    power: 'M12 3v8 M7 6a8 8 0 1 0 10 0', // power
    link: 'M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1 M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1-1', // link
    clock: 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M12 7v5l3 2', // clock
    eyeslash: 'M3 3l18 18 M10.6 6.1A9.8 9.8 0 0 1 12 6c6.5 0 10 6 10 6a17 17 0 0 1-2.9 3.6 M6.6 7.6C3.6 9.4 2 12 2 12s3.5 6 10 6a9.6 9.6 0 0 0 4.4-1 M9.9 9.9a3 3 0 0 0 4.2 4.2', // eye.slash
    bag: 'M5 8h14l-1 12H6z M9 8V6.5a3 3 0 0 1 6 0V8', // bag (App Store)
    stop: 'M7.5 7.5h9v9h-9z', // stop
    reveal: 'M3 7.5A2 2 0 0 1 5 5.5h4l2 2h8a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z M10 13h5 M13 11l2 2-2 2', // folder + arrow
    play: 'M8 5l11 7-11 7z',
    key: 'M14.5 9.5a3.5 3.5 0 1 1 0 .01z M12 12l-8 8 M7 17l2 2 M9 15l2 2', // key
    list: 'M9 6h11 M9 12h11 M9 18h11 M4.5 6h.01 M4.5 12h.01 M4.5 18h.01',
    bolt: 'M13 3L5 14h6l-1 7 8-11h-6z',
  };
  const ic = (n, cls = '') => `<svg class="i ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${P[n] || P.doc}"/></svg>`;

  /* ByteCountFormatter(.file)-style: decimal units, GB 2 dp, MB 1 dp, KB 0 dp */
  const fmt = b => {
    if (b == null) return '—';
    if (b >= 1e9) return (b / 1e9).toFixed(2) + ' GB';
    if (b >= 1e6) return (b / 1e6).toFixed(1) + ' MB';
    if (b >= 1e3) return Math.round(b / 1e3) + ' KB';
    return b + ' bytes';
  };
  const fmtSplit = b => { const s = fmt(b); const i = s.lastIndexOf(' '); return [s.slice(0, i), s.slice(i + 1)]; };
  const n = x => Number(x).toLocaleString('en-US');
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const plural = (k, one, many) => `${n(k)} ${k === 1 ? one : (many || one + 's')}`;
  const sum = (arr, f = x => x.size) => arr.reduce((s, x) => s + (f(x) || 0), 0);

  const tile = (hue, icon, cls = '') => `<span class="tile ${cls}" style="--h:${hue}">${ic(icon)}</span>`;
  const badge = (kind, text, icon) => `<span class="badge ${kind}">${icon ? ic(icon) : ''}${text}</span>`;
  const btn = (label, o = {}) => `<button class="btn ${o.cls || ''}" ${o.act ? `data-act="${o.act}"` : ''} ${o.go ? `data-go="${o.go}"` : ''} ${o.id ? `data-id="${o.id}"` : ''} ${o.disabled ? 'disabled' : ''} ${o.aria ? `aria-label="${o.aria}"` : ''}>${o.icon ? ic(o.icon) : ''}${o.spin ? '<span class="spinner spin"></span>' : ''}${label}</button>`;
  const cb = (state, o = {}) => `<button class="cb" role="checkbox" aria-checked="${state}" ${o.act ? `data-act="${o.act}"` : ''} ${o.id ? `data-id="${o.id}"` : ''} ${o.key ? `data-key="${o.key}"` : ''} ${o.disabled ? 'disabled' : ''} aria-label="${esc(o.label || 'Select')}">${state === true || state === 'true' ? ic('check') : state === 'mixed' ? ic('minus') : ''}</button>`;

  /* round CTA with optional progress ring */
  const C = 2 * Math.PI * 44;
  const cta = o => {
    let ring = '';
    if (o.ring === 'indet') ring = `<svg class="ring indet" viewBox="0 0 94 94"><circle class="track" cx="47" cy="47" r="44"/><circle class="bar" cx="47" cy="47" r="44" stroke-dasharray="${C * 0.22} ${C}"/></svg>`;
    else if (typeof o.ring === 'number') ring = `<svg class="ring" viewBox="0 0 94 94"><circle class="track" cx="47" cy="47" r="44"/><circle class="bar" cx="47" cy="47" r="44" stroke-dasharray="${C}" stroke-dashoffset="${C * (1 - o.ring)}"/></svg>`;
    return `<button class="cta${o.stop ? ' stop' : ''}" ${o.act ? `data-act="${o.act}"` : ''} ${o.go ? `data-go="${o.go}"` : ''} ${o.disabled ? 'disabled' : ''} aria-label="${esc(o.aria || o.label)}">${ring}<span>${o.label}</span></button>`;
  };
  const dock = o => `<div class="dock"><div class="side">${o.left || ''}</div>${o.cta || '<span></span>'}<div class="side r">${o.right || ''}</div></div>`;
  const meta = html => `<div class="meta">${html}</div>`;

  const startView = o => `
    <div class="start">
      <div class="orb"><div class="glyph">${ic(o.icon)}</div></div>
      <div>
        <div class="eyebrow"><span class="dot"></span>${o.eyebrow}</div>
        <h1 class="display">${o.title}</h1>
        <p class="lede">${o.lede}</p>
        ${o.bullets ? `<ul class="bullets">${o.bullets.map(b => `<li><span class="bi">${ic(b[0])}</span><div><div class="bt">${b[1]}</div><div class="bs">${b[2]}</div></div></li>`).join('')}</ul>` : ''}
        ${o.note ? `<div class="note">${ic('info')}<span>${o.note}</span></div>` : ''}
        ${o.extra || ''}
      </div>
    </div>`;

  const steps = list => `<div class="steps">${list.map(s => `<div class="step ${s.st}"><span class="sd">${s.st === 'done' ? ic('check') : s.st === 'failed' ? ic('x') : ''}</span><span class="st">${s.label}</span><span class="sm">${s.meta || ''}</span></div>`).join('')}</div>`;
  const progress = (v, left, right) => `${v == null ? '' : `<div class="progress" role="progressbar" aria-valuenow="${Math.round(v * 100)}" aria-valuemin="0" aria-valuemax="100"><i style="width:${(v * 100).toFixed(1)}%"></i></div>`}<div class="progress-meta"><span>${left || ''}</span><span>${right || ''}</span></div>`;
  const scanView = o => `
    <div class="scan">
      <div class="orb scanning"><div class="glyph">${ic(o.icon)}</div></div>
      <div>
        <div class="eyebrow"><span class="dot" style="background:var(--neon-cyan)"></span>${o.eyebrow || 'Scanning'}</div>
        <h2 class="t1" style="margin-top:8px">${o.title}</h2>
        ${o.lede ? `<p class="lede" style="margin-bottom:4px">${o.lede}</p>` : ''}
        ${o.steps ? steps(o.steps) : '<div style="height:12px"></div>'}
        ${o.progress ? progress(...o.progress) : ''}
        ${o.path ? `<div class="path-line mono"><span>${esc(o.path)}</span></div>` : ''}
        ${o.extra || ''}
      </div>
    </div>`;

  const resultsHead = o => `
    <div class="results-head">
      <div>
        <div class="eyebrow"><span class="dot"></span>${o.eyebrow || 'Results'}</div>
        <h2 class="t1" style="margin-top:8px">${o.title}</h2>
        <div class="muted">${o.sub || ''}</div>
      </div>
      <div class="row">${o.right || ''}</div>
    </div>`;
  const rtile = o => `
    <div class="rtile ${o.cls || ''}" style="--h:${o.hue}">
      <div class="top">${tile(o.hue, o.icon)}<span class="lbl">${o.label}</span></div>
      ${o.check ? `<span class="check">${ic('check')}</span>` : ''}
      <div class="big">${o.big}${o.unit ? `<small>${o.unit}</small>` : ''}</div>
      <div class="cap">${o.cap || ''}</div>
      ${o.body || ''}
      <div class="foot">${o.foot || ''}</div>
    </div>`;

  const doneView = o => `
    <div class="done-wrap">
      <div class="done-card">
        <div class="orb done"><div class="glyph">${ic(o.icon || 'check')}</div></div>
        <div>
          <div class="eyebrow"><span class="dot" style="background:var(--neon-lime)"></span>${o.eyebrow || 'Done'}</div>
          <h2 class="t1" style="margin-top:8px">${o.title}</h2>
          <div class="muted">${o.sub || ''}</div>
          <div class="stats">${o.stats.map(([k, v, c]) => `<div><div class="k">${k}</div><div class="v ${c || ''}">${v}</div></div>`).join('')}</div>
          <div class="actions">${o.actions}</div>
          ${o.hint ? `<div class="note mt12">${ic('info')}<span>${o.hint}</span></div>` : ''}
        </div>
      </div>
      ${o.extra || ''}
    </div>`;

  const emptyView = o => `
    <div class="empty"><div>
      <div class="ei ${o.kind || ''}">${ic(o.icon)}</div>
      <h2 class="t1">${o.title}</h2>
      <p>${o.text}</p>
      <div class="actions" style="justify-content:center">${o.actions || ''}</div>
    </div></div>`;

  const banner = (kind, icon, title, text, action) => `<div class="banner ${kind}">${ic(icon)}<div class="bx"><b>${title}</b>${text ? `<span>${text}</span>` : ''}</div>${action || ''}</div>`;

  const alertBox = o => `
    <div class="scrim">
      <div class="alert ${o.wide ? 'wide' : ''}" role="alertdialog" aria-modal="true" aria-labelledby="dlg-t" ${o.style ? `style="${o.style}"` : ''}>
        <div class="ai ${o.warn ? 'warn' : ''}" style="--h:${o.hue || 'var(--primary)'}">${ic(o.icon)}</div>
        <h4 id="dlg-t">${o.title}</h4>
        ${o.body}
        <div class="abtns">${o.buttons}</div>
      </div>
    </div>`;
  const alist = (items, max = 5) => {
    const shown = items.slice(0, max);
    const more = items.length - shown.length;
    return `<div class="alist">${shown.map(i => `<div><span>${esc(i.name)}</span><span>${fmt(i.size)}</span></div>`).join('')}${more > 0 ? `<div><span class="muted">and ${plural(more, 'more item')}</span><span>${fmt(sum(items.slice(max)))}</span></div>` : ''}</div>`;
  };

  const reviewbar = o => `<div class="reviewbar">${o.left || ''}<div class="sum">${o.sum}</div>${o.cta || ''}</div>`;
  const manyOf = noun => noun.endsWith('y') ? noun.slice(0, -1) + 'ies' : noun + 's';
  const selSum = (count, bytes, noun = 'item') => count
    ? `<b>${plural(count, noun, manyOf(noun))}</b> · <b>${fmt(bytes)}</b> selected`
    : `No ${manyOf(noun)} selected`;

  Object.assign(SOS, { ic, fmt, fmtSplit, n, esc, plural, sum, tile, badge, btn, cb, cta, dock, meta, startView, steps, progress, scanView, resultsHead, rtile, doneView, emptyView, banner, alertBox, alist, reviewbar, selSum });
})();
