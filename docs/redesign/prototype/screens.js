/* SOS Mac — screen views. Each view returns { title, subtitle, back, tools, solid, canvas, bottom, dialog }.
   Every number shown comes from data.js, and every field there exists in the engine (inventory §4.1). */
'use strict';
(function () {
  const { ic, fmt, fmtSplit, n, esc, plural, sum, tile, badge, btn, cb, cta, dock, meta, startView, scanView, resultsHead, rtile, doneView, emptyView, banner, alertBox, alist, reviewbar, selSum } = SOS;
  const M = SOS.MODS;
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));

  /* ======================================================================
     selection model
     ====================================================================== */
  const dupItems = similar => SOS.dupModel(similar ? SOS.SIMILAR : SOS.DUPS, similar).flatMap(s => s.items);
  const appById = id => SOS.APPS.find(a => a.id === id) || SOS.APPS[0];
  SOS.itemsFor = key => {
    if (key === 'junk') return SOS.JUNK.flatMap(r => r.items);
    if (key === 'smartcare') return [...SOS.JUNK.filter(r => !r.helper).flatMap(r => r.items), ...dupItems(false)];
    if (key === 'dup-exact') return dupItems(false);
    if (key === 'dup-similar') return dupItems(true);
    if (key === 'icloud') return SOS.dupModel(SOS.ICLOUD).flatMap(s => s.items);
    if (key === 'drive') return SOS.dupModel(SOS.DRIVE).flatMap(s => s.items);
    if (key === 'prot') return SOS.FINDINGS;
    if (key.startsWith('app:')) return SOS.appItems(appById(key.slice(4)));
    return [];
  };
  /* Pre-selection = today's behaviour (§4.2). Never widened. */
  SOS.defaultSel = key => {
    const items = SOS.itemsFor(key);
    if (key === 'drive' || key === 'prot') return [];
    if (key.startsWith('app:')) return items.map(i => i.id);
    return items.filter(i => (i.keep === undefined ? i.sev === 'safe' && !i.helper : !i.keep)).map(i => i.id);
  };
  SOS.selSet = (S, key) => S.sel[key] || (S.sel[key] = new Set(SOS.defaultSel(key)));
  SOS.keyFor = S => ({
    junk: 'junk', smartcare: 'smartcare', duplicates: 'dup-' + S.dupMode,
    cloud: S.state === 'drive' ? 'drive' : 'icloud', uninstaller: 'app:' + S.app, protection: 'prot',
  }[S.screen]);
  SOS.selected = (S, key) => {
    const set = SOS.selSet(S, key);
    return SOS.itemsFor(key).filter(i => !i.keep && set.has(i.id));
  };

  /* ======================================================================
     shared review frame (3 columns: groups · items · detail)
     ====================================================================== */
  const sevBadge = i => (i.sev === 'caution' ? badge('caution', 'Caution', 'warn') : i.sev === 'risky' ? badge('risky', 'Risky', 'warn') : i.sev === 'safe' ? badge('safe', 'Safe') : '');
  const irow = (i, sel, focused, o = {}) => `
    <div class="irow ${i.keep ? 'kept' : ''}" role="button" tabindex="0" data-act="focus" data-id="${i.id}" aria-current="${focused}">
      ${cb(i.keep ? false : sel.has(i.id), { act: 'sel', id: i.id, disabled: i.keep, label: (i.keep ? 'Kept: ' : 'Select ') + i.name })}
      <div style="min-width:0"><div class="nm">${esc(i.name)}</div><div class="pt">${esc(o.path ? o.path(i) : i.dir)}</div></div>
      <div class="bd">${o.badges ? o.badges(i) : ''}</div>
      <span class="sz">${fmt(i.size)}</span>
    </div>`;

  function reviewFrame(S, key, sections, o) {
    const sel = SOS.selSet(S, key);
    const groups = sections.flatMap(s => s.groups);
    const g = groups.find(x => x.id === S.group[S.screen]) || groups[0];
    const focus = g.items.find(i => i.id === S.focus[S.screen]) || g.items.find(i => !i.keep) || g.items[0];
    SOS.ctx = { key, groups, group: g };
    const left = sections.map(sec => `<div class="col-sub">${sec.title}</div>` + sec.groups.map(gr => {
      const elig = gr.items.filter(i => !i.keep);
      const k = elig.filter(i => sel.has(i.id)).length;
      return `<button class="grow" style="grid-template-columns:1fr auto" data-act="group" data-id="${gr.id}" aria-current="${gr === g}">
        <div style="min-width:0"><div class="gl">${esc(gr.label)}</div><div class="gs">${gr.sub}</div></div>
        <span class="gz">${k ? `${k} of ${elig.length}` : `0 of ${elig.length}`}</span></button>`;
    }).join('')).join('');
    const elig = g.items.filter(i => !i.keep);
    const mid = `
      <div class="list-head">
        <div style="min-width:0"><div class="lt">${esc(g.label)}</div><div class="ls">${g.head || esc(g.sub)}</div></div>
        <div class="tools">${btn('Select All', { cls: 'plain', act: 'selall', disabled: elig.every(i => sel.has(i.id)) })}${btn('Deselect All', { cls: 'plain', act: 'selnone', disabled: !elig.some(i => sel.has(i.id)) })}</div>
      </div>
      ${g.banner ? `<div class="inline-banner">${g.banner}</div>` : ''}
      <div class="list">${g.items.map(i => irow(i, sel, i === focus, o)).join('')}</div>`;
    const right = o.detail(focus, g);
    const picked = SOS.selected(S, key);
    return {
      canvas: `<div class="review"><section class="col-groups">${left}</section><section class="col-items">${mid}</section><section class="col-detail detail">${right}</section></div>`,
      bottom: reviewbar({
        left: o.barLeft || '',
        sum: selSum(picked.length, sum(picked), o.noun || 'item'),
        cta: btn(o.ctaLabel || 'Move to Trash…', { cls: o.ctaCls || 'prominent', act: 'clean', disabled: !picked.length }),
      }),
    };
  }
  const dl = (k, v, mono) => `<div class="dk">${k}</div><div class="dv ${mono ? 'mono' : ''}">${v}</div>`;
  const explain = html => `<div class="explain">${html}</div>`;

  /* group builders */
  const junkGroups = rules => rules.map(r => ({ id: r.id, label: r.short, sub: `${esc(r.root)} · ${plural(r.items.length, 'file')}`, items: r.items, helper: r.helper,
    banner: r.helper ? banner('info', 'key', 'Needs your approval', 'Moving these uses the SOS Mac helper. macOS asks for your password once.') : '' }));
  const setGroups = (sets, o = {}) => sets.map(s => ({
    id: s.id, label: s.title, isSet: true,
    sub: `${plural(s.items.length, 'copy', 'copies')} · ${fmt(s.items[0].size)}${s.similar ? '' : ' each'}`,
    head: s.similar ? 'Similar images. The newest is kept. Check each one before you move it.' : 'Identical copies. The newest by date modified is kept.',
    items: s.items, banner: o.banner || '',
  }));
  const junkDetail = i => `
    <div class="dt">${esc(i.name)}</div>
    ${dl('Rule', esc(i.rule))}
    ${dl('Location', esc(i.dir + '/' + i.name), true)}
    ${dl('Size', fmt(i.size))}
    ${dl('Safety', sevBadge(i) + (i.helper ? ' ' + badge('neutral', 'Needs approval', 'key') : ''))}
    ${explain(i.sev === 'caution'
      ? '<b>Caution:</b> the app that owns this file may rebuild it or lose a setting. Not selected for you; select it only if you know the app.'
      : '<b>Safe:</b> a cache the app rebuilds on its own. It goes to the Trash, so you can put it back.')}`;
  const keepDetail = (i, g) => `
    <div class="dt">${esc(i.name)}</div>
    ${i.keep ? `<div class="mt8">${badge('keep', 'Keep', 'lock')}</div>` : ''}
    ${i.dir ? dl('Location', esc(i.dir + '/' + i.name), true) : ''}
    ${dl('Size', fmt(i.size))}
    ${dl('Date modified', esc(i.mod))}
    ${explain(i.keep
      ? '<b>Kept automatically.</b> This is the newest copy by date modified, so it can\'t be selected.'
      : `<b>An extra copy.</b> The newest copy${g.items[0].dir ? ` in <span class="mono">${esc(g.items[0].dir)}</span>` : ''} stays where it is and can't be selected.`)}`;

  /* ======================================================================
     shared lifecycle pieces
     ====================================================================== */
  const pk = S => clamp(S.prog);
  const scanDock = (S, o = {}) => dock({
    left: o.left || '',
    cta: cta({ label: 'Stop', act: 'stop', stop: true, ring: o.ring === undefined ? 'indet' : o.ring, aria: 'Stop scan' }),
    right: o.right || '',
  });
  const cleaningView = (S, o) => ({
    canvas: scanView({ icon: 'trash', eyebrow: 'Moving to Trash', title: `Moving ${plural(o.count, o.noun || 'item', o.noun === 'copy' ? 'copies' : undefined)} to the Trash…`, lede: 'You can put items back from the Trash in Finder.',
      progress: [clamp(pk(S) * 0.9 + 0.08), `${n(Math.max(1, Math.round(o.count * clamp(pk(S) * 0.9 + 0.08))))} of ${n(o.count)} ${o.count === 1 ? o.noun || 'item' : o.noun === 'copy' ? 'copies' : (o.noun || 'item') + 's'}`, ''],
      path: o.path || '' }),
    bottom: dock({ cta: cta({ label: 'Moving', disabled: true, ring: 'indet', aria: 'Moving to Trash' }) }),
  });
  const doneActions = (extra = '') => `${btn('Open Trash', { act: 'open-trash', icon: 'trash' })}${btn('Scan Again', { act: 'scan-again', cls: 'prominent' })}${extra}`;
  const doneHint = 'Everything is in the Trash. To undo, open the Trash in Finder and choose Put Back.';
  const lastPicked = (S, key) => {
    if (S.last && S.last.key === key) return S.last;
    const items = key === 'lens' ? SOS.lensCartItems(S) : SOS.selected(S, key);
    return { count: items.length, bytes: sum(items) };
  };
  const resultsDock = (S, key, o = {}) => {
    const p = SOS.selected(S, key);
    return dock({
      left: btn(o.reviewLabel || 'Review Items…', { act: 'review', icon: 'list' }) + meta(p.length ? `<b>${fmt(sum(p))}</b> selected` : 'Nothing selected'),
      cta: cta({ label: o.label || 'Clean', act: 'clean', disabled: !p.length, aria: p.length ? `Clean ${fmt(sum(p))}` : 'Clean (nothing selected)' }),
      right: btn('Scan Again', { cls: 'plain', act: 'scan-again' }),
    });
  };

  const V = {};

  /* ======================================================================
     Dashboard
     ====================================================================== */
  V.dashboard = S => {
    const s = SOS.SYS, used = s.used / s.total;
    const modCard = id => {
      const m = M[id];
      const live = id === 'performance' ? `<div class="live"><i></i>Load ${s.load[0].toFixed(2)} · Memory ${Math.round(s.inUse / s.mem.total * 100)}%</div>` : '';
      return `<button class="mod" style="--h:${m.hue}" data-nav="${id}">${tile(m.hue, m.icon)}<div style="min-width:0"><div class="mt">${m.label}</div><div class="ms">${m.desc}</div>${live}</div>${ic('chevR', 'chev')}</button>`;
    };
    return {
      title: 'Dashboard', solid: false,
      canvas: `<div class="dash">
        <div class="dash-hero" style="--hue:${M.smartcare.hue}">
          <div class="l"><div class="orb"><div class="glyph">${ic('wand')}</div></div>
            <div><div class="eyebrow"><span class="dot"></span>Smart Care</div>
              <h1 class="display" style="margin:8px 0 6px">Clean up junk and duplicates in one pass</h1>
              <p class="lede" style="margin:0 0 16px">Smart Care finds caches, old logs and duplicate files, then shows you everything before anything moves.</p>
              ${btn('Run Smart Care', { cls: 'prominent large', act: 'run-smartcare', icon: 'wand' })}</div></div>
          <div class="r">
            <div class="row"><span style="font:var(--f-headline)">${s.volume}</span><span class="sp"></span><span class="muted" style="font:var(--f-callout)">${fmt(s.free)} free</span></div>
            <div class="meter" role="meter" aria-label="Storage used" aria-valuenow="${Math.round(used * 100)}"><i style="width:${(used * 100).toFixed(1)}%;background:var(--gradient-soft)"></i></div>
            <div class="kv"><span><b>${fmt(s.used)}</b> used</span><span>of ${fmt(s.total)}</span></div>
            <div>${btn('Open Space Lens', { cls: 'plain', go: 'spacelens', icon: 'grid' })}</div>
          </div>
        </div>
        <div class="snap">
          <div class="c"><div class="k">${ic('cpu')}Load average (1 min)</div><div class="v">${s.load[0].toFixed(2)}</div><div class="s">Read when this page opened</div></div>
          <div class="c"><div class="k">${ic('memory')}Memory in use</div><div class="v">${fmt(s.inUse)} <span class="muted" style="font:var(--f-callout)">of ${fmt(s.mem.total)}</span></div><div class="s">Read when this page opened</div></div>
          <div class="c"><div class="k">${ic('thermo')}Thermal state</div><div class="v">${s.thermal}</div><div class="s">Read when this page opened</div></div>
        </div>
        <div class="section-label">Clean</div>
        <div class="mods">${['junk', 'duplicates', 'spacelens', 'cloud'].map(modCard).join('')}</div>
        <div class="section-label">Manage · Speed · Protect</div>
        <div class="mods">${['uninstaller', 'updater', 'performance', 'protection'].map(modCard).join('')}</div>
      </div>`,
    };
  };

  /* ======================================================================
     Smart Care
     ====================================================================== */
  const scRules = () => SOS.JUNK.filter(r => !r.helper);
  const scSets = () => SOS.dupModel(SOS.DUPS);
  V.smartcare = S => {
    const st = S.state, hue = M.smartcare.hue;
    const junkItems = scRules().flatMap(r => r.items), sets = scSets();
    const healthTile = (err) => rtile({ cls: 'full', hue: M.performance.hue, icon: 'gauge', label: 'Health check · read-only', big: '', cap: '',
      body: `<div class="health"><div><div class="k">Load average (1 min)</div><div class="v">${SOS.SYS.load[0].toFixed(2)}</div></div><div><div class="k">Memory in use</div><div class="v">${fmt(SOS.SYS.inUse)} of ${fmt(SOS.SYS.mem.total)}</div></div><div><div class="k">Thermal state</div><div class="v">${SOS.SYS.thermal}</div></div></div>` });
    if (st === 'start') return {
      title: 'Smart Care',
      canvas: startView({ icon: 'wand', eyebrow: 'Smart Care', title: 'Junk and duplicates, in one pass',
        lede: 'Smart Care looks for files you can safely clear, then shows you the list. Nothing moves until you confirm.',
        bullets: [['trash', 'Junk & Cache', 'App caches, old logs and app support caches. 3 locations, no extra permission.'], ['docs', 'Duplicate files', 'Identical copies anywhere in your Home folder. The newest copy is always kept.'], ['gauge', 'Health check', 'Load, memory and thermal state. Read-only.']],
        note: 'The duplicate pass reads every file in your Home folder, so it can take a few minutes.' }),
      bottom: dock({ cta: cta({ label: 'Scan', act: 'scan' }) }),
    };
    if (st === 'scanning') {
      const p = pk(S), jd = p > 0.35;
      return {
        title: 'Smart Care', subtitle: 'Scanning',
        canvas: scanView({ icon: 'wand', title: 'Looking for junk and duplicates…',
          steps: [
            { label: 'Junk & Cache', st: jd ? 'done' : 'active', meta: jd ? `Found ${n(junkItems.length)}` : 'Scanning…' },
            { label: 'Duplicate files', st: jd ? 'active' : 'pending', meta: jd ? 'Scanning…' : 'Waiting…' },
            { label: 'Health check', st: 'done', meta: 'Read' },
          ],
          progress: [p, 'Scanning your Home folder', ''] }),
        bottom: scanDock(S),
      };
    }
    if (st === 'results' || st === 'error') {
      const jsel = SOS.selected(S, 'smartcare').filter(i => i.keep === undefined), dsel = SOS.selected(S, 'smartcare').filter(i => i.keep !== undefined);
      const [jn, ju] = fmtSplit(sum(jsel)), [dn, du] = fmtSplit(sum(dsel));
      const err = st === 'error';
      return {
        title: 'Smart Care', subtitle: 'Results',
        canvas: `<div class="results">
          ${resultsHead({ title: err ? 'Smart Care finished with a problem' : 'Here\'s what Smart Care found', sub: err ? 'Junk & Cache finished. Duplicate files stopped before the end.' : 'Selected items are ready for review. The newest copy of every duplicate is kept.' })}
          ${err ? `<div class="mt8" style="margin-bottom:14px">${banner('err', 'warn', 'Couldn\'t finish the duplicate scan', 'A folder in your Home folder couldn\'t be read. Junk results below are complete.', btn('Try Again', { act: 'scan-again' }))}</div>` : ''}
          <div class="tiles">
            ${rtile({ cls: 'wide', hue: M.junk.hue, icon: 'trash', label: 'Junk & Cache', check: !!jsel.length, big: jn, unit: ju, cap: `selected of ${fmt(sum(junkItems))} · ${plural(junkItems.length, 'file')} in 3 locations`,
              foot: `${badge('safe', `${jsel.length} safe selected`)}${junkItems.some(i => i.sev === 'caution') ? badge('caution', `${junkItems.filter(i => i.sev === 'caution').length} need a look`, 'warn') : ''}` })}
            ${err ? rtile({ cls: 'wide skipped', hue: M.duplicates.hue, icon: 'docs', label: 'Duplicate files', big: '—', cap: 'Scan stopped', foot: badge('risky', 'Failed', 'x') })
              : rtile({ cls: 'wide', hue: M.duplicates.hue, icon: 'docs', label: 'Duplicate files', check: !!dsel.length, big: dn, unit: du, cap: `selected · ${plural(sets.length, 'set')}, ${plural(dsel.length, 'extra copy', 'extra copies')}`, foot: badge('keep', 'Newest copy kept', 'lock') })}
            ${healthTile()}
          </div></div>`,
        bottom: resultsDock(S, 'smartcare'),
      };
    }
    if (st === 'review') {
      const r = reviewFrame(S, 'smartcare', [
        { title: 'Junk & Cache', groups: junkGroups(scRules()) },
        { title: 'Duplicate files', groups: setGroups(sets) },
      ], { badges: i => (i.keep ? badge('keep', 'Keep', 'lock') : i.sev ? sevBadge(i) : ''), path: i => (i.mod ? `${i.dir} · ${i.mod}` : i.dir), detail: (i, g) => (g.isSet ? keepDetail(i, g) : junkDetail(i)) });
      return { title: 'Smart Care', subtitle: 'Review', back: 'Results', ...r };
    }
    if (st === 'cleaning') return { title: 'Smart Care', subtitle: 'Cleaning', ...cleaningView(S, { count: lastPicked(S, 'smartcare').count, path: '~/Library/Caches/com.spotify.client/Data/Cache.db' }) };
    if (st === 'done') {
      const l = lastPicked(S, 'smartcare');
      return {
        title: 'Smart Care', subtitle: 'Done',
        canvas: doneView({ eyebrow: 'Smart Care complete', title: `${fmt(Math.max(0, l.bytes - 9620000))} moved to the Trash`, sub: 'One item couldn\'t be moved. It\'s still in its original place.',
          stats: [['Moved to Trash', fmt(Math.max(0, l.bytes - 9620000)), 'lime'], ['Items', n(Math.max(0, l.count - 1))], ['Couldn\'t move', '1']],
          actions: doneActions(), hint: doneHint,
          extra: banner('warn', 'warn', 'icons.cache couldn\'t be moved', 'Raycast had the file open. Quit Raycast, then run Smart Care again.') }),
      };
    }
    if (st === 'empty') return { title: 'Smart Care', canvas: emptyView({ kind: 'ok', icon: 'check', title: 'Nothing to clean', text: 'Smart Care found no junk and no duplicate files. The health check is below.', actions: btn('Scan Again', { act: 'scan-again' }) }).replace('</div></div>', `<div class="tiles" style="margin-top:24px;text-align:left;width:640px">${healthTile()}</div></div></div>`) };
  };

  /* ======================================================================
     Junk & Cache
     ====================================================================== */
  V.junk = S => {
    const st = S.state, all = SOS.JUNK.flatMap(r => r.items);
    if (st === 'start') return {
      title: 'Junk & Cache',
      canvas: startView({ icon: 'trash', eyebrow: 'Junk & Cache', title: 'Clear caches and old logs',
        lede: 'Apps rebuild these files on their own. You see every file before it moves, and everything goes to the Trash.',
        bullets: SOS.JUNK.map(r => [r.helper ? 'key' : 'folder', r.label, `<span class="mono">${r.root}</span>`]),
        note: 'System Caches need your approval. They\'re never selected for you.' }),
      bottom: dock({ cta: cta({ label: 'Scan', act: 'scan' }) }),
    };
    if (st === 'scanning') {
      const p = pk(S), k = Math.min(3, Math.floor(p * 4)), r = SOS.JUNK[k];
      return {
        title: 'Junk & Cache', subtitle: 'Scanning',
        canvas: scanView({ icon: 'trash', title: 'Looking for junk files…',
          steps: SOS.JUNK.map((x, i) => ({ label: x.short, st: i < k ? 'done' : i === k ? 'active' : 'pending', meta: i < k ? `Found ${n(x.items.length)}` : i === k ? 'Scanning…' : 'Waiting…' })),
          progress: [p, `${k} of 4 locations`, `${Math.round(p * 100)}%`], path: `${r.root}/${r.files[Math.floor(p * 37) % r.files.length][1]}` }),
        bottom: scanDock(S, { ring: p }),
      };
    }
    if (st === 'results') {
      const p = SOS.selected(S, 'junk');
      return {
        title: 'Junk & Cache', subtitle: 'Results',
        canvas: `<div class="results">${resultsHead({ title: `${fmt(sum(all))} of junk found`, sub: `${plural(all.length, 'file')} in 4 locations · ${fmt(sum(p))} selected (safe files only)` })}
          <div class="tiles">${SOS.JUNK.map(r => {
            const [a, u] = fmtSplit(sum(r.items)); const c = r.items.filter(i => i.sev === 'caution').length; const k = r.items.filter(i => p.includes(i)).length;
            return rtile({ cls: 'wide', hue: M.junk.hue, icon: r.helper ? 'key' : 'folder', label: r.short, check: !!k, big: a, unit: u, cap: `${plural(r.items.length, 'file')} · <span class="mono">${r.root}</span>`,
              foot: r.helper ? badge('neutral', 'Needs approval · not selected', 'key') : `${badge('safe', `${k} selected`)}${c ? badge('caution', `${c} caution`, 'warn') : ''}` });
          }).join('')}</div></div>`,
        bottom: resultsDock(S, 'junk'),
      };
    }
    if (st === 'review') {
      const r = reviewFrame(S, 'junk', [{ title: 'Locations', groups: junkGroups(SOS.JUNK) }], { badges: i => sevBadge(i) + (i.helper ? badge('neutral', 'Approval', 'key') : ''), detail: junkDetail });
      return { title: 'Junk & Cache', subtitle: 'Review', back: 'Results', ...r };
    }
    if (st === 'cleaning') return { title: 'Junk & Cache', subtitle: 'Cleaning', ...cleaningView(S, { count: lastPicked(S, 'junk').count, path: '~/Library/Caches/Google/Chrome/Default/Cache/Cache_Data/data_3' }) };
    if (st === 'done') {
      const l = lastPicked(S, 'junk');
      return { title: 'Junk & Cache', subtitle: 'Done', canvas: doneView({ title: `${fmt(l.bytes)} moved to the Trash`, sub: `${plural(l.count, 'file')} cleared from your caches and logs.`, stats: [['Moved to Trash', fmt(l.bytes), 'lime'], ['Files', n(l.count)], ['Couldn\'t move', '0']], actions: doneActions(), hint: doneHint }) };
    }
    if (st === 'empty') return { title: 'Junk & Cache', canvas: emptyView({ kind: 'ok', icon: 'check', title: 'No junk found', text: 'Your caches and logs are already clear in all 4 locations.', actions: btn('Scan Again', { act: 'scan-again' }) }) };
    if (st === 'error') return { title: 'Junk & Cache', canvas: emptyView({ kind: 'err', icon: 'warn', title: 'Couldn\'t scan System Caches', text: 'SOS Mac needs your approval to read /Library/Caches. The other 3 locations weren\'t affected.', actions: btn('Try Again', { act: 'scan-again', cls: 'prominent' }) + btn('Show Results for 3 Locations', { act: 'goto', id: 'results' }) }) };
  };

  /* ======================================================================
     Duplicate Finder
     ====================================================================== */
  const dupSeg = S => `<div class="seg" role="group" aria-label="Match type"><button data-act="mode" data-id="exact" aria-pressed="${S.dupMode === 'exact'}">Exact copies</button><button data-act="mode" data-id="similar" aria-pressed="${S.dupMode === 'similar'}">Similar images</button></div>`;
  const simBanner = banner('warn', 'warn', 'Similar isn\'t identical', 'There\'s no preview or similarity score yet, so check each image before you move it. Today every copy except the newest is selected.');
  V.duplicates = S => {
    const st = S.state, sim = S.dupMode === 'similar', key = 'dup-' + S.dupMode;
    const sets = SOS.dupModel(sim ? SOS.SIMILAR : SOS.DUPS, sim);
    const tools = ['start', 'results', 'review'].includes(st) ? dupSeg(S) : '';
    if (st === 'start') return {
      title: 'Duplicate Finder', tools,
      canvas: startView({ icon: 'docs', eyebrow: 'Duplicate Finder', title: sim ? 'Find similar images' : 'Find identical copies',
        lede: sim ? 'Looks for near-identical photos and screenshots in your Home folder.' : 'Compares file contents across your Home folder, so renamed copies are found too.',
        bullets: [['lock', 'The newest copy is kept', 'In every set, the copy with the latest date modified can\'t be selected.'], ['trash', 'Copies go to the Trash', 'Put anything back from the Trash in Finder.']],
        note: 'Hashing every file can take a few minutes on a large Home folder.', extra: sim ? `<div class="mt16">${simBanner}</div>` : '' }),
      bottom: dock({ cta: cta({ label: 'Scan', act: 'scan' }) }),
    };
    if (st === 'scanning') {
      const p = pk(S), hashing = p > 0.4, hp = clamp((p - 0.4) / 0.6);
      return {
        title: 'Duplicate Finder', subtitle: 'Scanning',
        canvas: scanView({ icon: 'docs', title: hashing ? 'Hashing files…' : 'Scanning for duplicates…',
          steps: [{ label: 'Find files with the same size', st: hashing ? 'done' : 'active', meta: hashing ? `${n(1284)} candidates` : `${n(Math.round(p * 2.5 * 48210))} files` }, { label: 'Compare contents', st: hashing ? 'active' : 'pending', meta: hashing ? '' : 'Waiting…' }],
          progress: hashing ? [hp, `${n(Math.round(hp * 1284))} of ${n(1284)} files`, `${Math.round(hp * 100)}%`] : [null, 'Counting files in your Home folder…', ''],
          path: hashing ? '~/Documents/Projects/Brand/design-assets-v4.zip' : '~/Pictures/2026-10' }),
        bottom: scanDock(S, { ring: hashing ? hp : 'indet' }),
      };
    }
    if (st === 'results') {
      const p = SOS.selected(S, key), [a, u] = fmtSplit(sum(p));
      return {
        title: 'Duplicate Finder', subtitle: 'Results', tools,
        canvas: `<div class="results">${resultsHead({ title: sim ? `${plural(sets.length, 'set')} of similar images` : `${plural(sets.length, 'set')} of identical files`, sub: 'The newest copy in each set is kept.' })}
          ${sim ? `<div style="margin-bottom:14px">${simBanner}</div>` : ''}
          <div class="tiles">
            ${rtile({ cls: 'wide', hue: M.duplicates.hue, icon: 'docs', label: 'Sets found', big: n(sets.length), unit: '', cap: `${plural(sum(sets, s => s.items.length), 'file')} in total` })}
            ${rtile({ cls: 'wide', hue: M.duplicates.hue, icon: 'trash', label: 'Selected', check: !!p.length, big: a, unit: u, cap: `${plural(p.length, 'extra copy', 'extra copies')}`, foot: badge('keep', `${sets.length} kept`, 'lock') })}
          </div>
          <div class="mt16">${banner('info', 'info', '14 files were skipped', 'They couldn\'t be read, usually because another app had them open.')}</div></div>`,
        bottom: resultsDock(S, key),
      };
    }
    if (st === 'review') {
      const r = reviewFrame(S, key, [{ title: sim ? 'Similar images' : 'Identical sets', groups: setGroups(sets, { banner: sim ? simBanner : '' }) }],
        { badges: i => (i.keep ? badge('keep', 'Keep', 'lock') : ''), path: i => `${i.dir} · ${i.mod}`, detail: keepDetail });
      return { title: 'Duplicate Finder', subtitle: 'Review', back: 'Results', tools, ...r };
    }
    if (st === 'cleaning') return { title: 'Duplicate Finder', subtitle: 'Cleaning', ...cleaningView(S, { count: lastPicked(S, key).count, noun: 'copy', path: '~/Downloads/onboarding-walkthrough.mov' }) };
    if (st === 'done') {
      const l = lastPicked(S, key);
      return { title: 'Duplicate Finder', subtitle: 'Done', canvas: doneView({ title: `${fmt(l.bytes)} moved to the Trash`, sub: `${plural(l.count, 'extra copy', 'extra copies')} moved. The newest copy of every file stayed.`, stats: [['Moved to Trash', fmt(l.bytes), 'lime'], ['Copies', n(l.count)], ['Kept', n(sets.length)]], actions: doneActions(), hint: doneHint }) };
    }
    if (st === 'empty') return { title: 'Duplicate Finder', tools, canvas: emptyView({ kind: 'ok', icon: 'check', title: 'No duplicates found', text: sim ? 'No similar images in your Home folder.' : 'Every file in your Home folder is unique.', actions: btn('Scan Again', { act: 'scan-again' }) }) };
    if (st === 'error') return { title: 'Duplicate Finder', canvas: emptyView({ kind: 'err', icon: 'warn', title: 'The scan stopped', text: 'SOS Mac couldn\'t read your Home folder. Check that it has Full Disk Access in System Settings › Privacy & Security.', actions: btn('Open System Settings', { act: 'toast', id: 'Opens Privacy & Security › Full Disk Access', icon: 'external' }) + btn('Try Again', { act: 'scan-again', cls: 'prominent' }) }) };
  };

  /* ======================================================================
     Uninstaller
     ====================================================================== */
  const appIc = (a, big) => `<span class="app-ic ${big ? 'app-big' : ''}" style="background:linear-gradient(160deg, color-mix(in srgb, ${a.c} 88%, white), color-mix(in srgb, ${a.c} 70%, black))">${esc(a.name[0].toUpperCase())}</span>`;
  const appRow = (a, o) => `<div class="app-row">${appIc(a)}<div style="min-width:0"><div class="an">${esc(a.name)}</div><div class="av">Version ${a.ver}</div></div>
      <span>${a.store ? badge('accent', 'App Store', 'bag') : ''}</span><span class="az">${o.size || '—'}</span><span>${o.action || ''}</span></div>${o.after || ''}`;
  V.uninstaller = S => {
    const st = S.state, a = appById(S.app), key = 'app:' + a.id;
    const search = `<div class="toolbar-search">${ic('search')}Search</div>`;
    if (st === 'start') return {
      title: 'Uninstaller', subtitle: `${plural(SOS.APPS.length, 'app')} in /Applications`, tools: search, solid: true,
      canvas: `<div class="pad" style="padding-top:16px">${banner('info', 'info', 'Pick an app to see what it left behind', 'Inspect looks for the app\'s caches, preferences and support files. Measure All inspects every app so you can see sizes.')}
        <div class="apps mt16">${SOS.APPS.map(x => appRow(x, { action: btn('Inspect', { act: 'app', id: x.id }) })).join('')}</div></div>`,
      bottom: dock({ left: meta('Sizes appear after an app is inspected'), cta: cta({ label: 'Measure All', act: 'scan', aria: 'Inspect all apps to measure their size' }) }),
    };
    if (st === 'scanning') {
      const p = pk(S), k = Math.min(SOS.APPS.length - 1, Math.floor(p * SOS.APPS.length));
      return {
        title: 'Uninstaller', subtitle: 'Measuring', solid: true,
        canvas: `<div class="pad" style="padding-top:16px"><div class="rtile" style="min-height:0;--h:${M.uninstaller.hue}"><div class="row"><span class="spinner"></span><b>Inspecting ${esc(SOS.APPS[k].name)}…</b></div>${SOS.progress(p, `${k} of ${SOS.APPS.length} apps`, `${Math.round(p * 100)}%`)}</div>
          <div class="apps mt16">${SOS.APPS.map((x, i) => appRow(x, { size: i < k ? fmt(SOS.appTotal(x)) : i === k ? '<span class="spinner" style="display:inline-block;vertical-align:middle"></span>' : '—' })).join('')}</div></div>`,
        bottom: scanDock(S, { ring: p }),
      };
    }
    if (st === 'results' || st === 'error') {
      const err = st === 'error';
      return {
        title: 'Uninstaller', subtitle: `${plural(SOS.APPS.length, 'app')} · measured`, tools: search, solid: true,
        canvas: `<div class="pad" style="padding-top:16px">
          <div class="row" style="margin-bottom:12px"><span class="tag-engine">${ic('warn')}Needs engine work · D1</span><span class="muted" style="font:var(--f-callout)">Sizes count the app and its files. Support and cache folders show no size until the folder-size fix lands.</span></div>
          <div class="apps">${SOS.APPS.map(x => {
            if (err && x.id === 'docker') return appRow(x, { size: '—', action: btn('Try Again', { act: 'scan-again' }), after: `<div class="row-error">${banner('err', 'warn', 'Couldn\'t inspect Docker', 'Some of its files in ~/Library/Containers couldn\'t be read.')}</div>` });
            return appRow(x, { size: fmt(SOS.appTotal(x)), action: btn('Review', { act: 'app-review', id: x.id }) });
          }).join('')}</div></div>`,
        bottom: dock({ left: meta('Choose an app to review what it left behind'), cta: cta({ label: 'Review', act: 'app-review', id: a.id, aria: `Review ${a.name}` }).replace('data-act', `data-id="${a.id}" data-act`), right: btn('Measure Again', { cls: 'plain', act: 'scan-again' }) }),
      };
    }
    if (st === 'review') {
      const items = SOS.appItems(a), sel = SOS.selSet(S, key), p = SOS.selected(S, key);
      SOS.ctx = { key, groups: [{ id: 'app', items }], group: { id: 'app', items } };
      return {
        title: 'Uninstaller', subtitle: a.name, back: 'Apps',
        canvas: `<div class="review two">
          <section class="col-groups" style="padding:22px 18px">
            ${appIc(a, true)}
            <div class="detail"><div class="dt mt12">${esc(a.name)}</div>
              ${a.store ? `<div class="mt8">${badge('accent', 'App Store', 'bag')}</div>` : ''}
              ${dl('Version', a.ver)}${dl('Bundle ID', a.bid, true)}${dl('Location', '/Applications/' + esc(a.name) + '.app', true)}${dl('Size', `At least ${fmt(SOS.appTotal(a))}`)}<div class="muted" style="font:var(--f-subhead);margin-top:2px">App and files. ${plural(SOS.appFolders(items), 'folder')} not measured yet.</div>
              ${explain(`<b>Quit ${esc(a.name)} first</b> if it's open. SOS Mac can't check yet whether it's running.`)}</div>
          </section>
          <section class="col-items">
            <div class="list-head"><div><div class="lt">${plural(items.length, 'item')} found</div><div class="ls">The app plus files whose name matches ${esc(a.bid)}</div></div>
              <div class="tools">${btn('Select All', { cls: 'plain', act: 'selall', disabled: p.length === items.length })}${btn('Deselect All', { cls: 'plain', act: 'selnone', disabled: !p.length })}</div></div>
            <div class="list">${items.map(i => `<div class="irow">${cb(sel.has(i.id), { act: 'sel', id: i.id, label: 'Select ' + i.name })}<div style="min-width:0"><div class="nm">${esc(i.name)}</div><div class="pt">${esc(i.dir)}</div></div><div class="bd">${badge('neutral', esc(i.src.startsWith('Associated') ? 'Associated' : 'App'))}</div><span class="sz">${i.folder ? '<span class="muted">Folder</span>' : fmt(i.size)}</span></div>`).join('')}</div>
          </section></div>`,
        bottom: reviewbar({ sum: p.length ? `<b>${plural(p.length, 'item')}</b> · <b>${SOS.appFolders(p) ? 'at least ' : ''}${fmt(sum(p))}</b> selected` : 'No items selected', cta: btn('Move to Trash…', { cls: 'prominent', act: 'clean', disabled: !p.length }) }),
      };
    }
    if (st === 'cleaning') return { title: 'Uninstaller', subtitle: a.name, ...cleaningView(S, { count: lastPicked(S, key).count, path: `/Applications/${a.name}.app` }) };
    if (st === 'done') {
      const l = lastPicked(S, key);
      return { title: 'Uninstaller', subtitle: a.name, canvas: doneView({ icon: 'check', title: `${esc(a.name)} moved to the Trash`, sub: `${plural(l.count, 'item')} moved, including the app.`, stats: [['Moved to Trash', 'At least ' + fmt(l.bytes), 'lime'], ['Items', n(l.count)]], actions: btn('Open Trash', { act: 'open-trash', icon: 'trash' }) + btn('Back to Apps', { act: 'goto', id: 'results', cls: 'prominent' }), hint: doneHint + (a.store ? ' You can also download it again from the App Store.' : '') }) };
    }
    if (st === 'empty') return { title: 'Uninstaller', canvas: emptyView({ icon: 'appx', title: 'No apps found', text: 'There are no apps in /Applications that SOS Mac can remove. Apps that came with macOS aren\'t listed.', actions: btn('Check Again', { act: 'scan-again' }) }) };
  };

  /* ======================================================================
     Updater — read-only (no Review / Done: nothing is installed)
     ====================================================================== */
  V.updater = S => {
    const st = S.state, A = id => appById(id);
    if (st === 'start') return {
      title: 'Updater',
      canvas: startView({ icon: 'updater', eyebrow: 'Updater', title: 'See which apps have updates',
        lede: 'Checks each app\'s own update feed and the App Store flag. SOS Mac doesn\'t install anything.',
        bullets: [['updater', 'Apps with an update feed', 'Shows the installed and the latest version.'], ['bag', 'App Store apps', 'Opens the App Store so you can update there.']] }),
      bottom: dock({ cta: cta({ label: 'Check', act: 'scan' }) }),
    };
    const all = SOS.APPS.length;
    if (st === 'scanning') {
      const p = pk(S), k = Math.min(all - 1, Math.floor(p * all));
      return {
        title: 'Updater', subtitle: 'Checking', solid: true,
        canvas: `<div class="pad" style="padding-top:16px"><div class="rtile" style="min-height:0;--h:${M.updater.hue}"><div class="row"><span class="spinner"></span><b>Checking ${esc(SOS.APPS[k].name)}…</b></div>${SOS.progress(p, `${k} of ${all} apps`, `${Math.round(p * 100)}%`)}</div>
          <div class="apps mt16">${SOS.APPS.map((x, i) => appRow(x, { size: i < k ? '<span class="muted">Checked</span>' : i === k ? '<span class="spinner" style="display:inline-block;vertical-align:middle"></span>' : '' })).join('')}</div></div>`,
        bottom: scanDock(S, { ring: p }),
      };
    }
    if (st === 'results') {
      const U = SOS.UPD, grp = (t, list, row) => `<div class="group-title">${t}<span class="c">${list.length}</span></div><div class="apps">${list.map(row).join('')}</div>`;
      return {
        title: 'Updater', subtitle: `${plural(U.updates.length, 'update')} available`, solid: true,
        canvas: `<div class="pad" style="padding-top:8px">
          ${grp('Updates available', U.updates, ([id, f, t]) => appRow(A(id), { size: `<span class="status-mono">${f} → ${t}</span>`, action: badge('caution', 'Update available') }))}
          ${grp('Update in the App Store', U.store, ([id]) => appRow(A(id), { size: '', action: btn('View in App Store', { act: 'toast', id: 'Opens an App Store search for ' + A(id).name, icon: 'external' }) }))}
          ${grp('Up to date', U.current, ([id, v]) => appRow(A(id), { size: `<span class="status-mono">${v}</span>`, action: badge('safe', 'Up to date', 'check') }))}
          ${grp('No update feed', U.nofeed, ([id]) => appRow(A(id), { size: '', action: badge('neutral', 'Can\'t check') }))}
          <p class="lens-note">${ic('info')} A failed check currently looks like "Up to date" (D3). The design for that state is on the Needs engine work board.</p>
        </div>`,
        bottom: dock({ left: meta(`<b>${all}</b> apps checked`), cta: cta({ label: 'Check Again', act: 'scan-again' }) }),
      };
    }
    if (st === 'empty') return { title: 'Updater', canvas: emptyView({ kind: 'ok', icon: 'check', title: 'All apps are up to date', text: `${all} apps checked. None has a newer version in its update feed.`, actions: btn('Check Again', { act: 'scan-again' }) }) };
  };

  /* ======================================================================
     Space Lens — squarified treemap
     ====================================================================== */
  const MAP_W = 660, MAP_H = 520;
  function squarify(nodes, W, H) {
    const total = sum(nodes, d => d.size), k = (W * H) / total, out = [];
    let rest = nodes.map(d => ({ ...d, a: d.size * k })), x = 0, y = 0, w = W, h = H;
    const worst = (row, len) => { const s = sum(row, r => r.a), mx = Math.max(...row.map(r => r.a)), mn = Math.min(...row.map(r => r.a)); return Math.max((len * len * mx) / (s * s), (s * s) / (len * len * mn)); };
    while (rest.length) {
      const len = Math.min(w, h); let row = [rest[0]], i = 1;
      while (i < rest.length && worst([...row, rest[i]], len) <= worst(row, len)) row.push(rest[i++]);
      rest = rest.slice(i);
      const s = sum(row, r => r.a);
      if (w >= h) { const cw = s / h; let cy = y; row.forEach(r => { const ch = r.a / cw; out.push({ ...r, x, y: cy, w: cw, h: ch }); cy += ch; }); x += cw; w -= cw; }
      else { const ch = s / w; let cx = x; row.forEach(r => { const cw = r.a / ch; out.push({ ...r, x: cx, y, w: cw, h: ch }); cx += cw; }); y += ch; h -= ch; }
    }
    return out;
  }
  const lensLevel = S => SOS.LENS[S.lens.path] || SOS.LENS.home;
  const lensNodes = S => {
    if (S.lens.view === 'type') return SOS.TYPES.map(([name, size, hue, icon]) => ({ name, size, hue, icon, type: true }));
    const L = lensLevel(S);
    return L.children.map(([name, size, count, modified, drill, flag]) => ({ name, size, count, modified, drill, flag, path: L.path + '/' + name }));
  };
  const lensKey = d => d.path || d.name;
  SOS.lensFind = (S, k) => lensNodes(S).find(d => lensKey(d) === k) || SOS.lensCartItems(S).find(d => lensKey(d) === k);
  SOS.lensCartItems = S => {
    const all = Object.values(SOS.LENS).flatMap(L => L.children.map(([name, size, count, modified, drill, flag]) => ({ name, size, count, modified, drill, flag, path: L.path + '/' + name })));
    return [...S.lens.cart].map(k => all.find(d => d.path === k)).filter(Boolean);
  };
  const crumbs = S => {
    const trail = S.lens.path === 'home' ? ['home'] : ['home', S.lens.path];
    return `<nav class="crumbs" aria-label="Folder path">${trail.map((p, i) => `${i ? ic('chevR') : ''}<button data-act="lens-crumb" data-id="${p}" ${i === trail.length - 1 ? 'aria-current="page"' : ''}>${i === 0 ? ic('house') + ' ' : ''}${SOS.LENS[p].label}</button>`).join('')}</nav>`;
  };
  function treemap(S) {
    const nodes = lensNodes(S).sort((a, b) => b.size - a.size), total = sum(nodes);
    const big = nodes.filter(d => d.size / total >= 0.004), small = nodes.filter(d => d.size / total < 0.004);
    const list = small.length ? [...big, { name: `${plural(small.length, 'smaller item')}`, size: sum(small), rest: true }] : big;
    const cells = squarify(list, MAP_W, MAP_H);
    return cells.map((c, i) => {
      const bg = c.rest ? 'var(--tm-8)' : c.type ? `color-mix(in srgb, ${c.hue} var(--tm-mix-pct), var(--tm-mix))` : `var(--tm-${(i % 8) + 1})`;
      const label = c.w >= 90 && c.h >= 40 ? `<span class="cn">${esc(c.name)}</span><span class="cz">${fmt(c.size)}</span>` : c.w >= 60 && c.h >= 22 ? `<span class="cn">${esc(c.name)}</span>` : '';
      const k = lensKey(c);
      const attrs = c.rest || c.type ? `data-act="lens-sel" data-id="${esc(k)}"` : `data-act="lens-sel" data-id="${esc(k)}"`;
      return `<button class="cell ${S.lens.cart.has(k) ? 'incart' : ''}" ${attrs} aria-selected="${S.lens.sel === k}" aria-label="${esc(c.name)}, ${fmt(c.size)}" style="left:${(c.x / MAP_W * 100).toFixed(3)}%;top:${(c.y / MAP_H * 100).toFixed(3)}%;width:${(c.w / MAP_W * 100).toFixed(3)}%;height:${(c.h / MAP_H * 100).toFixed(3)}%;background:${bg}">${label}</button>`;
    }).join('');
  }
  function inspector(S) {
    const L = lensLevel(S), nodes = lensNodes(S), d = S.lens.sel && nodes.find(x => lensKey(x) === S.lens.sel);
    const cartItems = SOS.lensCartItems(S);
    const cart = `<div class="cart"><div class="dk" style="margin-top:0">Cleanup list</div>${cartItems.length ? cartItems.map(c => `<div class="row" style="justify-content:space-between;margin-top:6px;font:var(--f-callout)"><span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(c.name)}</span><span class="muted">${fmt(c.size)}</span></div>`).join('') : '<div class="muted mt8" style="font:var(--f-callout)">Nothing added yet. Select a file or folder, then Add to Cleanup.</div>'}</div>`;
    if (S.lens.view === 'type') {
      const t = d || nodes[0];
      return `<div class="detail"><div class="dt">${esc(t.name)}</div>${dl('Size', fmt(t.size))}${dl('Share of scanned', `${Math.round(t.size / sum(nodes) * 100)}%`)}${explain('By Type shows totals only. Switch to By Folder to pick files to clean.')}</div>${cart}`;
    }
    if (!d) return `<div class="detail"><div class="dt">${esc(L.label)}</div>${dl('Size', fmt(sum(nodes)))}${dl('Items', n(nodes.length))}${dl('Path', esc(L.path), true)}${explain('Select a rectangle to see what it is. Double-click a folder to open it.')}</div>${cart}`;
    if (d.rest) return `<div class="detail"><div class="dt">${esc(d.name)}</div>${dl('Size', fmt(d.size))}${explain('Too small to draw. Open the folder in Finder to see them.')}</div>${cart}`;
    const inCart = S.lens.cart.has(d.path), prot = d.flag === 'protected';
    return `<div class="detail"><div class="dt">${esc(d.name)}</div>
      ${dl('Size', fmt(d.size))}${dl('Kind', d.flag === 'file' ? 'File' : 'Folder')}${d.count != null ? dl('Contains', plural(d.count, 'item')) : ''}${dl('Modified', esc(d.modified))}${dl('Path', esc(d.path), true)}
      <div class="row mt16" style="flex-wrap:wrap">
        ${d.drill ? btn('Show Contents', { act: 'lens-open', id: d.drill, icon: 'folder' }) : ''}
        ${prot ? '' : btn(inCart ? 'Remove from Cleanup' : 'Add to Cleanup', { act: 'lens-cart', id: d.path, cls: inCart ? '' : 'prominent', icon: inCart ? 'minus' : 'plus' })}
      </div>
      ${prot ? explain('<b>Can\'t be cleaned here.</b> Library holds settings and data that apps need. Use Junk & Cache or Uninstaller for files inside it.') : ''}
    </div>${cart}`;
  }
  const lensSeg = S => `<div class="seg" role="group" aria-label="Group by"><button data-act="lens-view" data-id="folder" aria-pressed="${S.lens.view === 'folder'}">By Folder</button><button data-act="lens-view" data-id="type" aria-pressed="${S.lens.view === 'type'}">By Type</button></div>`;
  const lensResults = S => {
    const L = lensLevel(S), cartItems = SOS.lensCartItems(S);
    const legend = S.lens.view === 'type'
      ? `<div class="legend">${SOS.TYPES.map(t => `<span><i style="background:color-mix(in srgb, ${t[2]} var(--tm-mix-pct), var(--tm-mix));border:1px solid ${t[2]}"></i>${t[0]} ${fmt(t[1])}</span>`).join('')}</div>`
      : `<div class="legend"><span>${ic('info')} Area is size. Shades only tell neighbours apart.</span><span><i style="background:var(--neon-magenta);border-radius:50%"></i>In cleanup list</span></div>`;
    return {
      canvas: `<div class="lens"><div class="map-col">${S.lens.view === 'type' ? '<div class="crumbs"><button aria-current="page">All file types</button></div>' : crumbs(S)}<div class="map" role="group" aria-label="${esc(L.label)} treemap">${treemap(S)}</div>${legend}</div><aside class="inspector">${inspector(S)}</aside></div>`,
      bottom: reviewbar({ left: meta(`Scanned <b>${n(842193)}</b> items in Home`), sum: selSum(cartItems.length, sum(cartItems)), cta: btn('Review…', { cls: 'prominent', act: 'lens-review', disabled: !cartItems.length }) }),
    };
  };
  V.spacelens = S => {
    const st = S.state, tools = ['results', 'review'].includes(st) ? lensSeg(S) : '';
    if (st === 'start') return {
      title: 'Space Lens',
      canvas: startView({ icon: 'grid', eyebrow: 'Space Lens', title: 'See what fills your disk',
        lede: 'Space Lens maps a folder by size, so the biggest things are the easiest to spot. Nothing is selected for you.',
        extra: `<div class="source-list mt16">
          <button class="source" style="--hue:${M.spacelens.hue}" data-act="scan">${tile(M.spacelens.hue, 'house')}<div><div class="st">Home</div><div class="ss mono">~ · recommended</div></div>${ic('chevR')}</button>
          <button class="source" style="--hue:${M.spacelens.hue}" data-act="toast" data-id="Opens a folder picker">${tile('#6366F1', 'folder')}<div><div class="st">Choose Folder…</div><div class="ss">Any folder you can open</div></div>${ic('chevR')}</button>
          <button class="source" style="--hue:${M.spacelens.hue}" data-act="toast" data-id="Scans the external volume">${tile('#38BDF8', 'drive')}<div><div class="st">Backup SSD</div><div class="ss mono">/Volumes/Backup SSD</div></div>${ic('chevR')}</button></div>` }),
      bottom: dock({ cta: cta({ label: 'Scan', act: 'scan', aria: 'Scan Home' }) }),
    };
    if (st === 'scanning') return {
      title: 'Space Lens', subtitle: 'Scanning Home',
      canvas: scanView({ icon: 'grid', title: 'Mapping your Home folder…', lede: 'The total isn\'t known until the scan ends, so there\'s no percentage.', progress: [null, `Scanned ${n(Math.round(120000 + pk(S) * 722193))} items…`, ''], path: '~/Library/Developer/Xcode/DerivedData' }),
      bottom: scanDock(S),
    };
    if (st === 'results' || st === 'review') {
      const r = lensResults(S);
      let dialog = '';
      if (st === 'review') {
        const items = SOS.lensCartItems(S);
        dialog = alertBox({ wide: true, hue: M.spacelens.hue, icon: 'trash', style: 'width:480px', title: `Move ${plural(items.length, 'item')} to the Trash?`,
          body: `<p>Uncheck anything you want to keep. You can put items back from the Trash in Finder.</p>
            <div class="sheet-list">${items.map(d => `<div class="sheet-row">${cb(true, { act: 'lens-cart', id: d.path, label: 'Keep in list: ' + d.name })}<div style="min-width:0"><div class="nm">${esc(d.name)}</div><div class="pt">${esc(d.path)}</div></div><span class="sz">${fmt(d.size)}</span></div>`).join('') || '<div class="sheet-row"><span></span><span class="muted">Nothing left in the list</span><span></span></div>'}</div>
            <div class="row" style="justify-content:space-between;font:var(--f-callout)"><span class="muted">Total</span><b>${fmt(sum(items))}</b></div>`,
          buttons: btn('Cancel', { act: 'lens-cancel' }) + btn('Move to Trash', { cls: 'prominent', act: 'confirm', disabled: !items.length }) });
      }
      return { title: 'Space Lens', subtitle: lensLevel(S).path, tools, solid: true, ...r, dialog };
    }
    if (st === 'cleaning') return { title: 'Space Lens', subtitle: 'Cleaning', ...cleaningView(S, { count: lastPicked(S, 'lens').count, path: '~/Downloads/raw-footage-2026-09.zip' }) };
    if (st === 'done') {
      const l = lastPicked(S, 'lens');
      return { title: 'Space Lens', subtitle: 'Done', canvas: doneView({ title: `${fmt(l.bytes)} moved to the Trash`, sub: `${plural(l.count, 'item')} from your cleanup list.`, stats: [['Moved to Trash', fmt(l.bytes), 'lime'], ['Items', n(l.count)]], actions: btn('Back to Map', { act: 'goto', id: 'results', cls: 'prominent' }) + btn('Open Trash', { act: 'open-trash', icon: 'trash' }) + btn('Scan Again', { act: 'scan-again', cls: 'plain' }), hint: doneHint }) };
    }
    if (st === 'empty') return { title: 'Space Lens', canvas: emptyView({ icon: 'folder', title: 'This folder is empty', text: '~/Desktop/Old has no files in it. Choose another folder to map.', actions: btn('Choose Folder…', { act: 'goto', id: 'start', cls: 'prominent' }) }) };
    if (st === 'error') return { title: 'Space Lens', canvas: emptyView({ kind: 'err', icon: 'drive', title: 'Couldn\'t read Backup SSD', text: 'The volume was disconnected during the scan. Connect it again, then scan once more.', actions: btn('Scan Again', { act: 'scan-again', cls: 'prominent' }) + btn('Choose Another Folder', { act: 'goto', id: 'start' }) }) };
  };

  /* ======================================================================
     Performance
     ====================================================================== */
  V.performance = S => {
    const st = S.state, s = SOS.SYS, na = st === 'unavailable', m = s.mem;
    const memParts = [['Wired', m.wired, '#6D28D9'], ['Active', m.active, '#8B5CF6'], ['Compressed', m.compressed, '#A78BFA'], ['Inactive', m.inactive, 'color-mix(in srgb, #A78BFA 40%, transparent)'], ['Free', m.free, 'transparent']];
    const action = (id, icon, t, sub) => {
      const running = st === 'running' && id === 'ram', appr = st === 'approval' && id === 'ram', ok = st === 'actiondone' && id === 'ram', bad = st === 'actionerror' && id === 'dns';
      const inline = appr ? banner('info', 'key', 'Approve the SOS Mac helper', 'The first run installs a small helper. Turn it on in System Settings › General › Login Items & Extensions, then run again.', btn('Open System Settings', { act: 'toast', id: 'Opens Login Items & Extensions', icon: 'external' }))
        : ok ? banner('ok', 'check', 'Free up RAM finished', 'macOS released inactive memory.')
        : bad ? banner('err', 'warn', 'Couldn\'t flush the DNS cache', 'The helper didn\'t respond.', btn('Try Again', { act: 'perf-run', id: 'dns' })) : '';
      return `<div class="mrow">${tile(M.performance.hue, icon)}<div><div class="mt">${t}</div><div class="ms">${sub}</div></div>${btn(running ? 'Running…' : 'Run', { act: 'perf-run', id, spin: running, disabled: running || na })}${inline ? `<div class="inline">${inline}</div>` : ''}</div>`;
    };
    const dash = '—';
    return {
      title: 'Performance', subtitle: na ? 'No data' : 'Live',
      canvas: `<div class="perf">
        ${na ? `<div style="margin:8px 0 14px">${banner('err', 'warn', 'Couldn\'t read system metrics', 'macOS didn\'t return CPU or memory data. Values show "—" until the next read.', btn('Try Again', { act: 'goto', id: 'live' }))}</div>` : ''}
        <div class="perf-grid">
          <div class="mcard"><div class="k">${ic('cpu')}CPU</div><div class="v">${na ? dash : `<span data-live="cpu">${S.cpu}</span><small>%</small>`}</div><div class="meter sm"><i data-live="cpu-bar" style="width:${na ? 0 : S.cpu}%;background:var(--gradient-soft)"></i></div><div class="s">Updates while this screen is open</div></div>
          <div class="mcard span2"><div class="k">${ic('memory')}Memory</div><div class="v">${na ? dash : `${fmtSplit(s.inUse)[0]}<small>GB in use</small>`}<span class="muted" style="font:var(--f-callout);margin-left:8px">of ${fmt(m.total)}</span></div>
            <div class="meter">${na ? '' : memParts.map(([, v, c]) => `<i style="width:${(v / m.total * 100).toFixed(2)}%;background:${c}"></i>`).join('')}</div>
            <div class="mem-legend">${memParts.map(([k, v, c]) => `<span><i style="background:${c};${k === 'Free' ? 'border:1px solid var(--hairline-strong)' : ''}"></i>${k} ${na ? dash : fmt(v)}</span>`).join('')}</div></div>
          <div class="mcard"><div class="k">${ic('thermo')}Thermal state</div><div class="v" style="font-size:22px;display:flex;align-items:center;gap:8px">${na ? dash : `<i style="width:9px;height:9px;border-radius:50%;background:var(--success)"></i>${s.thermal}`}</div><div class="s">As reported by macOS</div></div>
          <div class="mcard span2"><div class="k">${ic('gauge')}Load average</div><div class="row" style="gap:28px;margin-top:8px">${['1 min', '5 min', '15 min'].map((t, i) => `<div><div style="font:var(--f-numeral-l);font-size:24px" class="num">${na ? dash : s.load[i].toFixed(2)}</div><div class="s" style="margin-top:2px">${t}</div></div>`).join('')}</div></div>
          <div class="mcard span2" style="padding:0"><div class="kvrow"><span>Swap used</span><span>${na ? dash : `${fmt(s.swap.used)} of ${fmt(s.swap.total)}`}</span></div><div class="kvrow"><span>Architecture</span><span>${s.arch}</span></div><div class="kvrow"><span>Running since</span><span>${s.bootTime}</span></div></div>
        </div>
        <div class="section-label">Maintenance</div>
        <div class="rows-card">${action('ram', 'memory', 'Free up RAM', 'Asks macOS to release inactive memory. Needs the SOS Mac helper.')}${action('dns', 'network', 'Flush DNS Cache', 'Clears saved name lookups. Useful when a site won\'t load.')}</div>
        <div class="two-col mt16">
          <div class="rows-card"><div class="mrow">${tile(M.performance.hue, 'gauge')}<div><div class="mt">Menu bar widget</div><div class="ms">CPU and memory in the menu bar.</div></div>${btn(S.pop ? 'Hide Widget' : 'Open Menu Bar Widget', { act: 'pop' })}</div></div>
          <div class="rows-card"><div class="mrow">${tile(M.performance.hue, 'power')}<div><div class="mt">Open at login</div><div class="ms">Start the menu bar widget when you log in.</div></div><button class="toggle" role="switch" aria-checked="${S.login}" aria-label="Open at login" data-act="login"></button></div>
            ${s.agents.map(([f, d]) => `<div class="kvrow"><span class="mono">${f}</span><span class="mono">${d}</span></div>`).join('')}</div>
        </div>
      </div>`,
    };
  };

  /* ======================================================================
     Cloud Cleanup
     ====================================================================== */
  const PROVS = [['icloud', 'iCloud Drive', 'Local scan', 'cloud'], ['gdrive', 'Google Drive', 'Not set up in this build', 'drive'], ['dropbox', 'Dropbox', 'Not set up in this build', 'box'], ['onedrive', 'OneDrive', 'Not set up in this build', 'cloud']];
  V.cloud = S => {
    const st = S.state, drive = st === 'drive', prov = drive ? 'gdrive' : S.cloud;
    const left = `<aside class="providers"><div class="col-sub">Providers</div>${PROVS.map(([id, nm, sub, icn]) => `<button class="prov" data-act="prov" data-id="${id}" aria-current="${prov === id}"><span class="pi">${ic(icn)}</span><div><div class="pn">${nm}</div><div class="ps">${id === 'gdrive' && drive ? 'Design target' : sub}</div></div></button>`).join('')}</aside>`;
    const wrap = (main, o = {}) => ({ title: 'Cloud Cleanup', subtitle: o.sub || '', canvas: `<div class="cloud">${left}<div class="cloud-main">${main}</div></div>`, bottom: o.bottom || '', dialog: o.dialog || '' });
    if (prov !== 'icloud' && !drive) {
      const p = PROVS.find(x => x[0] === prov);
      return wrap(emptyView({ icon: p[3], title: `${p[1]} isn't set up in this build`, text: `Connecting ${p[1]} needs a registered sign-in app, which this build doesn't have yet. iCloud Drive works now with a local scan.`, actions: btn(`Connect ${p[1]}`, { disabled: true }) + btn('Use iCloud Drive', { act: 'prov', id: 'icloud', cls: 'prominent' }) }));
    }
    if (drive) {
      const sets = SOS.dupModel(SOS.DRIVE), key = 'drive', sel = SOS.selSet(S, key), p = SOS.selected(S, key);
      SOS.ctx = { key, groups: sets.map(s => ({ id: s.id, items: s.items })), group: null };
      return wrap(`<div class="cloud-pad"><div class="row"><span class="ribbon">${ic('warn')}Design target · needs a registered sign-in app</span></div>
          ${resultsHead({ eyebrow: 'Google Drive', title: `${plural(sets.length, 'set')} of duplicate files`, sub: `${n(2318)} files listed. Nothing is selected: deleting on Drive happens on Google's servers.` })}
          ${banner('warn', 'warn', 'Deleting here is not Move to Trash', 'Files go to Google Drive\'s own trash, on Google\'s servers. SOS Mac can\'t undo it.')}</div>
          ${sets.map(s => `<div class="set-head"><div><div class="lt">${esc(s.title)}</div><div class="ls">${plural(s.items.length, 'copy', 'copies')} · ${fmt(s.items[0].size)} each</div></div></div>${s.items.map(i => irow(i, sel, false, { badges: x => (x.keep ? badge('keep', 'Keep', 'lock') : ''), path: x => `Modified ${x.mod}` })).join('')}`).join('')}`,
        { sub: 'Google Drive', bottom: reviewbar({ sum: selSum(p.length, sum(p), 'file'), cta: btn('Delete from Google Drive…', { cls: 'danger', act: 'clean', disabled: !p.length }) }) });
    }
    const sets = SOS.dupModel(SOS.ICLOUD), key = 'icloud';
    if (st === 'start') return wrap(`<div class="cloud-pad">${banner('info', 'info', 'Local scan', 'Reads iCloud Drive files that are already downloaded to this Mac. Files only in the cloud aren\'t checked.')}</div>` +
      startView({ icon: 'cloud', eyebrow: 'iCloud Drive', title: 'Find duplicates in iCloud Drive', lede: 'Compares files by content. The newest copy is always kept, and the rest go to the Trash on this Mac.' }).replace('class="start"', 'class="start" style="min-height:0;padding-top:0;grid-template-columns:240px 1fr;gap:32px"').replace('class="orb"', 'class="orb" style="width:220px;height:220px"'),
    { bottom: dock({ cta: cta({ label: 'Scan', act: 'scan' }) }) });
    if (st === 'scanning') return wrap(scanView({ icon: 'cloud', title: 'Checking iCloud Drive…', progress: [null, `${n(Math.round(300 + pk(S) * 1820))} files listed`, ''], path: 'iCloud Drive/Documents/Brand' }).replace('class="scan"', 'class="scan" style="grid-template-columns:240px 1fr;gap:32px"').replace('class="orb scanning"', 'class="orb scanning" style="width:220px;height:220px"'), { sub: 'Scanning', bottom: scanDock(S) });
    if (st === 'results') {
      const p = SOS.selected(S, key), [a, u] = fmtSplit(sum(p));
      return wrap(`<div class="results" style="padding:16px 24px">${resultsHead({ eyebrow: 'iCloud Drive', title: `${plural(sets.length, 'set')} of duplicate files`, sub: `${n(2118)} files listed · newest copy kept in each set` })}
        <div class="tiles">${rtile({ cls: 'wide', hue: M.cloud.hue, icon: 'docs', label: 'Sets found', big: n(sets.length), cap: `${plural(sum(sets, s => s.items.length), 'file')}` })}${rtile({ cls: 'wide', hue: M.cloud.hue, icon: 'trash', label: 'Selected', check: !!p.length, big: a, unit: u, cap: `${plural(p.length, 'extra copy', 'extra copies')} · go to the Trash on this Mac` })}</div></div>`,
      { sub: 'Results', bottom: resultsDock(S, key) });
    }
    if (st === 'review') {
      const sel = SOS.selSet(S, key), p = SOS.selected(S, key);
      SOS.ctx = { key, groups: sets.map(s => ({ id: s.id, items: s.items })), group: null };
      return { ...wrap(`<div class="list-head"><div><div class="lt">iCloud Drive · ${plural(sets.length, 'set')}</div><div class="ls">The newest copy by date modified is kept.</div></div><div class="tools">${btn('Select All', { cls: 'plain', act: 'selall' })}${btn('Deselect All', { cls: 'plain', act: 'selnone' })}</div></div>` +
        sets.map(s => `<div class="set-head"><div><div class="lt">${esc(s.title)}</div><div class="ls">${plural(s.items.length, 'copy', 'copies')} · ${fmt(s.items[0].size)} each</div></div></div>${s.items.map(i => irow(i, sel, false, { badges: x => (x.keep ? badge('keep', 'Keep', 'lock') : ''), path: x => `${x.dir} · ${x.mod}` })).join('')}`).join(''),
      { sub: 'Review', bottom: reviewbar({ sum: selSum(p.length, sum(p)), cta: btn('Move to Trash…', { cls: 'prominent', act: 'clean', disabled: !p.length }) }) }), back: 'Results' };
    }
    if (st === 'cleaning') return wrap(cleaningView(S, { count: lastPicked(S, key).count, path: 'iCloud Drive/Downloads/Team-offsite-photos.zip' }).canvas, { sub: 'Cleaning', bottom: cleaningView(S, { count: 1 }).bottom });
    if (st === 'done') {
      const l = lastPicked(S, key);
      return wrap(doneView({ title: `${fmt(l.bytes)} moved to the Trash`, sub: 'iCloud removes these copies from your other devices once you empty the Trash.', stats: [['Moved to Trash', fmt(l.bytes), 'lime'], ['Copies', n(l.count)]], actions: doneActions(), hint: doneHint }), { sub: 'Done' });
    }
    if (st === 'empty') return wrap(emptyView({ kind: 'ok', icon: 'check', title: 'No duplicates in iCloud Drive', text: `${n(2118)} files listed. Every file that's on this Mac is unique.`, actions: btn('Scan Again', { act: 'scan-again' }) }));
    if (st === 'error') return wrap(emptyView({ kind: 'err', icon: 'cloud', title: 'iCloud Drive isn\'t available', text: 'Sign in to iCloud in System Settings and turn on iCloud Drive, then scan again.', actions: btn('Open System Settings', { act: 'toast', id: 'Opens Apple Account › iCloud', icon: 'external' }) + btn('Try Again', { act: 'scan-again', cls: 'prominent' }) }));
  };

  /* ======================================================================
     Protection
     ====================================================================== */
  const disclaimer = `<div class="disclaimer">${ic('info')}<span>Protection checks files against known malware signatures when you run a scan. It isn't real-time antivirus.</span></div>`;
  const extraQ = [['invoice_0923.pdf.app', '~/Downloads', 'Nov 20, 2026 at 09:14'], ['Flash_Update.pkg', '~/Downloads', 'Nov 12, 2026 at 18:30'], ['com.search.helper.plist', '~/Library/LaunchAgents', 'Nov 9, 2026 at 11:02'], ['player_setup.dmg', '~/Downloads/old', 'Oct 31, 2026 at 15:47'], ['ext_8f2c.crx', '~/Library/Application Support/Google/Chrome', 'Oct 18, 2026 at 20:11'], ['codec-pack.zip', '~/Downloads', 'Oct 2, 2026 at 13:05'], ['update_helper', '/Library/LaunchDaemons', 'Sep 21, 2026 at 08:40']];
  const qpanel = (recs, o = {}) => `<div class="qpanel"><div class="qh">${ic('lock')}<span class="lt">Quarantine</span><span class="ls">${plural(recs.length, 'item')} · restorable</span></div><div class="qbody" ${o.tall ? 'style="max-height:none"' : ''}>${recs.map((r, i) => `<div class="qrow"><div style="min-width:0"><div class="nm">${esc(r.name)}</div><div class="pt">From ${esc(r.from)}</div></div><span class="dt">${r.date}</span>${btn('Restore', { act: 'restore', id: r.id || 'x' + i, icon: 'restore' })}</div>`).join('')}</div></div>`;
  V.protection = S => {
    const st = S.state, q = SOS.QUAR.filter(r => !S.restored.has(r.id));
    const pad = html => `<div class="pad" style="padding-top:16px">${disclaimer}<div class="mt16">${html}</div></div>`;
    if (st === 'start') return {
      title: 'Protection',
      canvas: `<div style="padding:12px 32px 0">${disclaimer}</div>` + startView({ icon: 'shield', eyebrow: 'Protection', title: 'Check for known malware', lede: 'Scans 6 places where unwanted software usually hides. Anything found is quarantined, never deleted, so you can restore it.',
        extra: `<div class="locs mt16">${SOS.LOCATIONS.map(l => `<div class="loc">${ic('folder')}${l}</div>`).join('')}</div>${q.length ? qpanel(q) : ''}` }).replace('min-height:100%', ''),
      bottom: dock({ cta: cta({ label: 'Scan', act: 'scan' }) }),
    };
    if (st === 'scanning') {
      const p = pk(S), done = Math.round(p * 19388);
      return {
        title: 'Protection', subtitle: 'Scanning',
        canvas: `<div style="padding:12px 32px 0">${disclaimer}</div>` + scanView({ icon: 'shield', title: 'Checking files…', progress: [p, `${n(done)} of ${n(19388)} files`, done >= 20 ? `About ${Math.max(1, Math.round((1 - p) * 5.5))} minute${Math.round((1 - p) * 5.5) > 1 ? 's' : ''} remaining` : ''], path: '~/Downloads/' + ['eicar_test.com', 'Figma-Installer.dmg', 'node-v24.11.0.pkg'][Math.floor(p * 9) % 3],
          steps: SOS.LOCATIONS.map((l, i) => ({ label: l, st: i < Math.floor(p * 6) ? 'done' : i === Math.floor(p * 6) ? 'active' : 'pending', meta: '' })).slice(0, 6) }),
        bottom: scanDock(S, { ring: p }),
      };
    }
    if (st === 'results') {
      const f = SOS.FINDINGS;
      return {
        title: 'Protection', subtitle: 'Results',
        canvas: `<div class="results">${disclaimer}${resultsHead({ title: `${plural(f.length, 'threat')} found`, sub: `${n(19388)} files checked in 6 locations. Nothing is selected for you.` })}
          <div class="tiles">${rtile({ cls: 'wide', hue: '#F87171', icon: 'warn', label: 'Known threats', big: n(f.length), cap: `${esc(f[0].name)} in ${esc(f[0].dir)}`, foot: badge('threat', f[0].method, 'shieldplain') })}
          ${rtile({ cls: 'wide', hue: M.protection.hue, icon: 'lock', label: 'Already in quarantine', big: n(q.length), cap: 'Restorable at any time' })}</div></div>`,
        bottom: dock({ left: meta('Review the finding, then quarantine it'), cta: cta({ label: 'Review', act: 'review' }), right: btn('Scan Again', { cls: 'plain', act: 'scan-again' }) }),
      };
    }
    if (st === 'review') {
      const r = reviewFrame(S, 'prot', [{ title: 'Findings', groups: [{ id: 'dl', label: 'Downloads', sub: plural(SOS.FINDINGS.length, 'finding'), items: SOS.FINDINGS }] }], {
        badges: i => badge('threat', i.method, 'shieldplain'), ctaLabel: 'Quarantine…',
        detail: i => `<div class="dt">${esc(i.name)}</div>${dl('Detection', esc(i.method))}${dl('Identifier', esc(i.ident), true)}${dl('Found', esc(i.date))}${dl('Path', esc(i.dir + '/' + i.name), true)}${dl('Size', fmt(i.size))}${explain('<b>Quarantine is reversible.</b> The file moves to a folder only SOS Mac uses. Restore puts it back where it was.')}`,
      });
      return { title: 'Protection', subtitle: 'Review', back: 'Results', ...r };
    }
    if (st === 'cleaning') return { title: 'Protection', subtitle: 'Quarantining', ...cleaningView(S, { count: 1, path: '~/Downloads/eicar_test.com' }), canvas: scanView({ icon: 'shield', eyebrow: 'Quarantining', title: 'Moving 1 item to quarantine…', progress: [null, 'eicar_test.com', ''] }) };
    if (st === 'done') return {
      title: 'Protection', subtitle: 'Done',
      canvas: doneView({ icon: 'shield', title: '1 item quarantined', sub: 'It can\'t run from quarantine. Restore it if it was a mistake.', stats: [['Quarantined', '1', 'lime'], ['In quarantine', n(q.length + 1)]], actions: btn('Scan Again', { act: 'scan-again', cls: 'prominent' }),
        extra: qpanel([{ id: 'f1', name: 'eicar_test.com', from: '~/Downloads', date: 'Nov 26, 2026 at 10:43' }, ...q]) }),
    };
    if (st === 'quarantine') {
      const recs = [...q, ...extraQ.map(([name, from, date], i) => ({ id: 'e' + i, name, from, date }))].filter(r => !S.restored.has(r.id));
      return { title: 'Protection', subtitle: 'Quarantine', back: 'Protection', canvas: pad(qpanel(recs, { tall: true })) };
    }
    if (st === 'empty') return { title: 'Protection', canvas: `<div style="padding:12px 32px 0">${disclaimer}</div>` + emptyView({ kind: 'ok', icon: 'shield', title: 'No known threats found', text: `${n(19388)} files checked in 6 locations.`, actions: btn('Scan Again', { act: 'scan-again' }) }).replace('min-height:100%', '') };
    if (st === 'error') return { title: 'Protection', canvas: `<div style="padding:12px 32px 0">${disclaimer}</div>` + emptyView({ kind: 'err', icon: 'warn', title: 'The scan stopped', text: 'SOS Mac couldn\'t read System Daemons. 4 of 6 locations were checked and nothing was found there.', actions: btn('Try Again', { act: 'scan-again', cls: 'prominent' }) }) };
  };

  /* ======================================================================
     dialogs (confirmation before anything leaves its place)
     ====================================================================== */
  SOS.dialogFor = S => {
    if (!S.dialog) return '';
    const key = SOS.keyFor(S);
    if (S.dialog === 'trash') {
      const items = SOS.selected(S, key), helper = items.some(i => i.helper);
      return alertBox({ hue: M[S.screen].hue, icon: 'trash', title: `Move ${plural(items.length, 'item')} (${fmt(sum(items))}) to the Trash?`,
        body: `<p>You can put them back from the Trash in Finder until you empty it.</p>${helper ? '<p>System Caches are included: macOS will ask for your password once.</p>' : ''}${alist(items)}`,
        buttons: btn('Move to Trash', { cls: 'prominent', act: 'confirm' }) + (S.state !== 'review' ? btn('Review Items…', { act: 'review' }) : '') + btn('Cancel', { act: 'cancel-dialog' }) });
    }
    if (S.dialog === 'cloud') {
      const items = SOS.selected(S, 'drive');
      return alertBox({ wide: true, warn: true, icon: 'warn', title: `Delete ${plural(items.length, 'file')} from Google Drive?`,
        body: `<p>These files are deleted on Google Drive's servers, not moved to the Trash on this Mac. You can restore them only from Google Drive's own trash, and SOS Mac can't undo this.</p>${alist(items)}
          <label class="chk"><input type="checkbox" data-act="ack" ${S.ack ? 'checked' : ''}> I understand these files are deleted on Google Drive.</label>`,
        buttons: btn('Delete from Google Drive', { cls: 'danger', act: 'confirm', disabled: !S.ack }) + btn('Cancel', { cls: 'prominent', act: 'cancel-dialog' }) });
    }
    if (S.dialog === 'uninstall') {
      const a = appById(S.app), items = SOS.selected(S, 'app:' + a.id), others = items.filter(i => !i.id.endsWith('-app')).length;
      const hasApp = items.some(i => i.id.endsWith('-app'));
      return alertBox({ hue: M.uninstaller.hue, icon: 'appx', title: hasApp ? `Move ${esc(a.name)} and ${plural(others, 'related item')} to the Trash?` : `Move ${plural(items.length, 'item')} to the Trash?`,
        body: `<p>Quit ${esc(a.name)} first if it's open. You can put everything back from the Trash in Finder.</p>${a.store && hasApp ? '<p>You can download it again from the App Store.</p>' : ''}${alist(items)}`,
        buttons: btn('Move to Trash', { cls: 'prominent', act: 'confirm' }) + btn('Cancel', { act: 'cancel-dialog' }) });
    }
    if (S.dialog === 'quarantine') {
      const items = SOS.selected(S, 'prot');
      return alertBox({ hue: M.protection.hue, icon: 'shield', title: `Quarantine ${plural(items.length, 'item')}?`,
        body: `<p>SOS Mac moves it to a folder where it can't run. You can restore it from the Quarantine list at any time.</p>${alist(items)}`,
        buttons: btn('Quarantine', { cls: 'prominent', act: 'confirm' }) + btn('Cancel', { act: 'cancel-dialog' }) });
    }
    return '';
  };
  SOS.dialogKind = S => (S.screen === 'cloud' && S.state === 'drive' ? 'cloud' : S.screen === 'uninstaller' ? 'uninstall' : S.screen === 'protection' ? 'quarantine' : 'trash');

  /* deep-link seeding: give each state the data it needs */
  SOS.onEnter = S => {
    if (S.screen === 'spacelens') {
      if (['review', 'cleaning', 'done'].includes(S.state) && !S.lens.cart.size && !(S.last && S.last.key === 'lens')) { S.lens.path = 'downloads'; ['~/Downloads/raw-footage-2026-09.zip', '~/Downloads/conference-talk.mov'].forEach(k => S.lens.cart.add(k)); }
      if (S.state === 'results' && S.lens.path === 'home' && !S.lens.sel) S.lens.sel = '~/Developer';
    }
    if (S.screen === 'performance' && S.state === 'approval') S.pop = false;
    if (S.dialog === 'cloud') { if (S.screen === 'cloud') S.state = 'drive'; if (!S.sel.drive) S.sel.drive = new Set(['g1-1', 'g2-1']); }
  };

  SOS.views = V;
})();
