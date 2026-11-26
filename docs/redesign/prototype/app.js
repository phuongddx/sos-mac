/* SOS Mac — prototype controller: state, routing, events, timers. */
'use strict';
(function () {
  const { ic, fmt, esc, tile, n } = SOS;
  const q = new URLSearchParams(location.search);
  const firstState = sc => SOS.STATES[sc][0];
  const S = {
    screen: SOS.MODS[q.get('screen')] ? q.get('screen') : 'dashboard',
    state: null, theme: (q.get('theme') || '').toLowerCase() === 'light' ? 'light' : 'dark', palette: ['a', 'b', 'c'].includes((q.get('palette') || '').toLowerCase()) ? q.get('palette').toLowerCase() : 'a',
    dialog: q.get('dialog') || null, chrome: q.get('chrome') !== '0', sel: {}, group: {}, focus: {}, prog: 0, dupMode: q.get('dup') === 'similar' ? 'similar' : 'exact',
    app: q.get('app') || 'slack', lens: { path: 'home', view: 'folder', sel: null, cart: new Set() }, cloud: 'icloud',
    pop: q.get('pop') === '1', toast: null, login: true, cpu: SOS.SYS.cpu, ack: false, restored: new Set(), last: null,
  };
  S.state = SOS.STATES[S.screen].includes(q.get('state')) ? q.get('state') : firstState(S.screen);
  if (S.state === 'scanning' || S.state === 'cleaning') S.prog = 0.62;
  if (S.dialog === '1') S.dialog = null;
  let timer = null, toastTimer = null, frozen = q.get('freeze') === '1' || !S.chrome;

  /* ---------------- render ---------------- */
  const sidebar = () => {
    const s = SOS.SYS;
    const groups = SOS.ORDER.map(([label, ids]) => `<div class="nav-group">${label ? `<div class="nav-label">${label}</div>` : ''}${ids.map(id => {
      const m = SOS.MODS[id], cur = S.screen === id;
      const busy = !cur && false;
      return `<button class="nav-row" data-nav="${id}" ${cur ? 'aria-current="page"' : ''}>${tile(m.hue, m.icon)}<span>${m.label}</span>${busy ? '<span class="state-dot"></span>' : ''}</button>`;
    }).join('')}</div>`).join('');
    return `<aside class="sidebar"><div class="traffic" aria-hidden="true"><i></i><i></i><i></i></div><nav class="nav" aria-label="Modules">${groups}</nav>
      <div class="side-foot"><div class="row"><b>${s.volume}</b><span>${fmt(s.free)} free</span></div>
      <div class="meter sm" role="meter" aria-label="Storage used" aria-valuenow="${Math.round(s.used / s.total * 100)}"><i style="width:${(s.used / s.total * 100).toFixed(1)}%;background:var(--gradient-soft)"></i></div>
      <div class="row" style="margin:6px 0 0"><span>${fmt(s.used)} of ${fmt(s.total)} used</span></div></div></aside>`;
  };

  const backTarget = () => (S.screen === 'protection' && S.state === 'quarantine' ? 'start' : 'results');

  function render() {
    SOS.onEnter(S);
    const view = SOS.views[S.screen](S) || SOS.views[S.screen]({ ...S, state: firstState(S.screen) });
    const hue = SOS.MODS[S.screen].hue;
    const dialog = view.dialog || (S.dialog ? SOS.dialogFor(S) : '');
    const toolbar = `<header class="toolbar ${view.solid ? 'solid' : ''}">
      ${view.back ? `<button class="back" data-act="goto" data-id="${backTarget()}" aria-label="Back to ${esc(view.back)}">${ic('chevL')}${esc(view.back)}</button>` : ''}
      <div><div class="title">${esc(view.title)}</div></div>${view.subtitle ? `<div class="subtitle">${esc(view.subtitle)}</div>` : ''}
      <div class="tools">${view.tools || ''}${S.screen === 'protection' && !['quarantine'].includes(S.state) ? `<button class="btn plain" data-act="goto" data-id="quarantine">${ic('lock')}Quarantine</button>` : ''}</div></header>`;
    const toast = S.toast ? `<div class="toast" role="status">${ic('info')}<span>${esc(S.toast)}</span></div>` : '';
    document.getElementById('stage').innerHTML = `<div class="window" data-screen="${S.screen}" data-state="${S.state}">${sidebar()}
      <main class="content" style="--hue:${hue}">${toolbar}<div class="canvas">${view.canvas || ''}</div>${view.bottom || ''}${toast}${dialog}</main></div>`;
    renderPopover();
    renderDevbar();
    applyPhase();
    syncURL();
    fit();
  }

  function renderPopover() {
    const pop = document.getElementById('popover'), s = SOS.SYS, mem = s.inUse / s.mem.total;
    pop.hidden = !S.pop;
    document.querySelector('#menubar [data-act="pop"]')?.setAttribute('aria-expanded', S.pop);
    const cpuEl = document.querySelector('#menubar .cpu'); if (cpuEl) cpuEl.textContent = `CPU ${S.cpu}%`;
    if (!S.pop) return;
    pop.innerHTML = `<div class="pop-head">${tile(SOS.MODS.performance.hue, 'gauge')}<div><div class="t">SOS Mac</div><div class="s">Updates every 2 seconds</div></div></div>
      <div class="pop-cards">
        <div class="pop-card"><div class="k">${ic('cpu')}CPU</div><div class="v"><span data-live="cpu">${S.cpu}</span>%</div><div class="meter sm"><i data-live="cpu-bar" style="width:${S.cpu}%;background:var(--gradient-soft)"></i></div></div>
        <div class="pop-card"><div class="k">${ic('memory')}Memory</div><div class="v">${Math.round(mem * 100)}%</div><div class="sub">${fmt(s.inUse)} of ${fmt(s.mem.total)}</div></div>
      </div>
      <div class="pop-actions"><button data-act="open-app">${ic('app')}Open SOS Mac<span class="kbd">⌘O</span></button><button data-act="toast" data-id="Quits the menu bar widget">${ic('power')}Quit Widget<span class="kbd">⌘Q</span></button></div>`;
  }

  function renderDevbar() {
    const bar = document.getElementById('devbar');
    if (!bar) return;
    const opts = Object.keys(SOS.MODS).map(k => `<option value="${k}" ${k === S.screen ? 'selected' : ''}>${SOS.MODS[k].label}</option>`).join('');
    bar.innerHTML = `<div class="grp"><span class="lbl">Screen</span><select data-dev="screen" aria-label="Screen">${opts}</select></div>
      <div class="grp"><span class="lbl">State</span>${SOS.STATES[S.screen].map(st => `<button class="chip" data-dev="state" data-id="${st}" aria-pressed="${st === S.state}">${SOS.STATE_LABEL[st]}</button>`).join('')}</div>
      <div class="grp"><span class="lbl">Theme</span><button class="chip" data-dev="theme" data-id="dark" aria-pressed="${S.theme === 'dark'}">Dark</button><button class="chip" data-dev="theme" data-id="light" aria-pressed="${S.theme === 'light'}">Light</button></div>
      <div class="grp"><span class="lbl">Palette</span>${['a', 'b', 'c'].map(p => `<button class="chip" data-dev="palette" data-id="${p}" aria-pressed="${S.palette === p}">${p.toUpperCase()}</button>`).join('')}</div>
      <span class="spacer"></span>
      <a href="board.html">All screens</a><a href="tokens.html">Tokens</a><a href="palettes.html">Palettes</a><a href="needs-engine-work.html">Needs engine work</a>`;
  }

  /* keep CSS animations continuous across re-renders */
  function applyPhase() {
    const t = performance.now(), st = document.documentElement.style;
    st.setProperty('--phase-pulse', `-${Math.round(t % 2400)}ms`);
    st.setProperty('--phase-ring', `-${Math.round(t % 1400)}ms`);
    st.setProperty('--phase-spin', `-${Math.round(t % 900)}ms`);
  }

  function syncURL() {
    const p = new URLSearchParams();
    p.set('screen', S.screen); p.set('state', S.state);
    if (S.theme !== 'dark') p.set('theme', S.theme);
    if (S.palette !== 'a') p.set('palette', S.palette);
    if (!S.chrome) p.set('chrome', '0');
    if (S.dialog) p.set('dialog', S.dialog);
    if (S.screen === 'duplicates' && S.dupMode === 'similar') p.set('dup', 'similar');
    if (S.pop) p.set('pop', '1');
    if (q.get('freeze')) p.set('freeze', q.get('freeze'));
    if (q.get('devbar')) p.set('devbar', q.get('devbar'));
    try { history.replaceState(null, '', '?' + p.toString()); } catch (e) { /* file:// or sandboxed */ }
  }

  function fit() {
    const stage = document.getElementById('stage');
    const avail = S.chrome ? window.innerWidth - 32 : window.innerWidth;
    const scale = S.chrome ? Math.min(1, avail / 1200) : avail / 1200;
    stage.style.transform = scale === 1 ? '' : `scale(${scale})`;
    stage.style.height = scale === 1 ? '' : `${(760 + (S.chrome ? 68 : 0)) * scale}px`;
  }

  /* ---------------- flow ---------------- */
  const set = (patch) => { Object.assign(S, patch); render(); };
  function go(state) {
    clearInterval(timer); timer = null;
    S.state = state; S.dialog = null; S.ack = false;
    if (state === 'scanning' || state === 'cleaning') { S.prog = 0; if (!frozen) run(state); else S.prog = 0.62; }
    render();
    document.querySelector('.canvas')?.scrollTo(0, 0);
  }
  function run(state) {
    const dur = state === 'scanning' ? (S.screen === 'protection' ? 5200 : 3600) : 2200, t0 = performance.now();
    timer = setInterval(() => {
      S.prog = Math.min(1, (performance.now() - t0) / dur);
      if (S.prog >= 1) { clearInterval(timer); timer = null; go(state === 'scanning' ? 'results' : 'done'); return; }
      render();
    }, 120);
  }
  function nav(screen) {
    clearInterval(timer); timer = null;
    S.screen = screen; S.state = firstState(screen); S.dialog = null; S.ack = false;
    if (screen === 'cloud') S.cloud = 'icloud';
    render();
  }
  function toast(msg) {
    S.toast = msg; clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { S.toast = null; render(); }, 2600);
    render();
  }
  function confirm() {
    const key = SOS.keyFor(S);
    if (S.screen === 'spacelens') {
      const items = SOS.lensCartItems(S);
      S.last = { key: 'lens', count: items.length, bytes: SOS.sum(items) };
      S.lens.cart.clear(); S.lens.sel = null;
    } else {
      const items = SOS.selected(S, key);
      S.last = { key, count: items.length, bytes: SOS.sum(items) };
      S.sel[key] = new Set();
    }
    go('cleaning');
  }

  const toggle = (set, id) => (set.has(id) ? set.delete(id) : set.add(id));
  const A = {
    scan: () => go('scanning'),
    'scan-again': () => go(S.screen === 'updater' || S.screen === 'uninstaller' ? 'scanning' : 'scanning'),
    stop: () => go(firstState(S.screen)),
    review: () => go('review'),
    goto: id => go(id),
    clean: () => set({ dialog: SOS.dialogKind(S), ack: false }),
    confirm,
    'cancel-dialog': () => set({ dialog: null, ack: false }),
    ack: () => set({ ack: !S.ack }),
    sel: id => { toggle(SOS.selSet(S, SOS.ctx.key), id); render(); },
    selall: () => {
      const set = SOS.selSet(S, SOS.ctx.key), items = SOS.ctx.group ? SOS.ctx.group.items : SOS.ctx.groups.flatMap(g => g.items);
      items.filter(i => !i.keep).forEach(i => set.add(i.id)); render();
    },
    selnone: () => {
      const set = SOS.selSet(S, SOS.ctx.key), items = SOS.ctx.group ? SOS.ctx.group.items : SOS.ctx.groups.flatMap(g => g.items);
      items.forEach(i => set.delete(i.id)); render();
    },
    group: id => { S.group[S.screen] = id; S.focus[S.screen] = null; render(); },
    focus: id => { S.focus[S.screen] = id; render(); },
    mode: id => { S.dupMode = id; render(); },
    app: id => { S.app = id; go('review'); },
    'app-review': id => { S.app = id || S.app; go('review'); },
    prov: id => { S.cloud = id; if (S.state === 'drive' || id !== 'icloud') S.state = id === 'icloud' ? 'start' : S.state === 'drive' ? 'start' : S.state; render(); },
    'lens-sel': id => { S.lens.sel = S.lens.sel === id ? null : id; render(); },
    'lens-open': id => { S.lens.path = id; S.lens.sel = null; render(); },
    'lens-crumb': id => { S.lens.path = id; S.lens.sel = null; render(); },
    'lens-view': id => { S.lens.view = id; S.lens.sel = null; render(); },
    'lens-cart': id => { toggle(S.lens.cart, id); render(); },
    'lens-review': () => go('review'),
    'lens-cancel': () => go('results'),
    'perf-run': id => {
      if (id === 'dns') return toast('DNS cache flushed');
      S.state = 'running'; render();
      setTimeout(() => { if (S.screen === 'performance' && S.state === 'running') go('actiondone'); }, 1600);
    },
    pop: () => set({ pop: !S.pop }),
    login: () => set({ login: !S.login }),
    restore: id => { S.restored.add(id); toast('Restored to its original location'); },
    'open-trash': () => toast('Opens the Trash in Finder'),
    'open-app': () => set({ pop: false }),
    'run-smartcare': () => { S.screen = 'smartcare'; go('scanning'); },
    toast: id => toast(id),
  };

  document.addEventListener('click', e => {
    const dev = e.target.closest('[data-dev]');
    if (dev && dev.tagName === 'BUTTON') {
      const k = dev.dataset.dev, v = dev.dataset.id;
      if (k === 'state') { S.prog = 0.62; clearInterval(timer); timer = null; S.dialog = null; S.state = v; if ((v === 'scanning' || v === 'cleaning') && !frozen) run(v); render(); }
      if (k === 'theme') { S.theme = v; applyTheme(); render(); }
      if (k === 'palette') { S.palette = v; applyTheme(); render(); }
      return;
    }
    const navEl = e.target.closest('[data-nav],[data-go]');
    if (navEl && !navEl.disabled) { nav(navEl.dataset.nav || navEl.dataset.go); return; }
    const el = e.target.closest('[data-act]');
    if (!el || el.disabled) return;
    const fn = A[el.dataset.act];
    if (fn) { if (el.tagName !== 'INPUT') e.preventDefault(); fn(el.dataset.id); }
    else if (S.pop && !e.target.closest('#popover')) set({ pop: false });
  });
  document.addEventListener('dblclick', e => {
    const c = e.target.closest('.cell'); if (!c) return;
    const d = SOS.lensFind(S, c.dataset.id); if (d && d.drill) A['lens-open'](d.drill);
  });
  document.addEventListener('change', e => {
    if (e.target.matches('[data-dev="screen"]')) nav(e.target.value);
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') { if (S.dialog) set({ dialog: null, ack: false }); else if (S.state === 'review' && S.screen === 'spacelens') go('results'); else if (S.pop) set({ pop: false }); }
    if (e.key === ' ' || e.key === 'Enter') {
      const r = e.target.closest('.irow[data-act], .grow[data-act]');
      if (r && e.target === r) { e.preventDefault(); r.click(); }
    }
  });
  window.addEventListener('resize', fit);

  function applyTheme() {
    document.body.dataset.theme = S.theme;
    document.documentElement.dataset.theme = S.theme;
    document.documentElement.dataset.palette = S.palette;
    document.body.dataset.palette = S.palette;
  }

  /* live CPU (random walk): only on Performance and in the menu bar */
  setInterval(() => {
    if (frozen) return;
    S.cpu = Math.max(6, Math.min(78, S.cpu + Math.round((Math.random() - 0.5) * 10)));
    document.querySelectorAll('[data-live="cpu"]').forEach(x => { x.textContent = S.cpu; });
    document.querySelectorAll('[data-live="cpu-bar"]').forEach(x => { x.style.width = S.cpu + '%'; });
    const c = document.querySelector('#menubar .cpu'); if (c) c.textContent = `CPU ${S.cpu}%`;
  }, 2000);

  /* clock in the fake menu bar */
  const clock = () => { const el = document.querySelector('#menubar .clock'); if (el) el.textContent = 'Thu Nov 26  10:43'; };

  if (!S.chrome) document.body.classList.add('nochrome');
  if (q.get('devbar') === '0') document.body.classList.add('nodev');
  applyTheme(); clock();
  if ((S.state === 'scanning' || S.state === 'cleaning') && !frozen && q.get('run') === '1') run(S.state);
  render();
  window.SOS_STATE = S; window.SOS_render = render;
})();
