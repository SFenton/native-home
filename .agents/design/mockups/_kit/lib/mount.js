/* Mock.mount: the mockup page furniture, plus Mock.lint and Mock.componentConfig.
 *
 * Order on the page: header (title, status, source and spec paths) -> warnings (Mock.lint) -> controls bar (device, state, appearance,
 * text size, Reduce Motion, Reduce Transparency, zoom, Play all) -> the device stage -> States gallery -> Motion -> Transitions ->
 * Accessibility -> Reviews (HIG and SwiftUI Pro) -> Source map -> Notes -> Change log.
 * Control values live in the URL hash (#d=duo-unfolded-landscape&p=part&s=offline&a=light&t=ax5&rm=1&rt=1&z=75) so a view can be linked or screenshotted.
 * Landscape surfaces get a kit-made "Reflow and hinge" section (split opens and closes; the Duo hinge fully open to slightly closed and back).
 */
(function () {
  var h = Mock.h;
  var KINDS = ['page', 'modal', 'component', 'flow', 'proposal'];
  var PAGE_STATES = ['default', 'loading', 'refreshing', 'empty', 'error', 'offline', 'reconnecting', 'long-text', 'ax5'];
  var MODAL_STATES = ['default', 'loading', 'error', 'offline', 'ax5', 'medium', 'large', 'fitted'];
  var VERDICTS = ['pass', 'fix', 'departure'];

  /**
   * Validate a mockup config. Returns a list of human-readable problems (empty when complete). Mock.mount shows them as a banner.
   * Missing source, spec, reviews, a11y or a state the AUTHORING.md list expects (without a note saying why) are all problems.
   */
  Mock.lint = function (cfg) {
    cfg = cfg || Mock.config || {};
    var w = [];
    function arr(a) { return Array.isArray(a) && a.length > 0; }
    ['id', 'title', 'kind', 'status'].forEach(function (k) { if (!cfg[k]) w.push('config.' + k + ' is missing'); });
    if (cfg.kind && KINDS.indexOf(cfg.kind) < 0) w.push('config.kind must be one of ' + KINDS.join(', '));
    if (cfg.status && !/^(shipped|proposed|in-flight:.+)$/.test(cfg.status)) w.push('config.status must be shipped, proposed or in-flight:<branch>');
    if (cfg.kind !== 'proposal' && !cfg.area) w.push('config.area is missing (the product area, e.g. home)');
    if (!arr(cfg.source)) w.push('config.source is missing: list the SwiftUI files this surface is drawn by');
    if (!arr(cfg.spec)) w.push('config.spec is missing: list .agents/pages/<id>/spec.md and ios.md (or the design doc)');
    var r = cfg.reviews;
    if (!r || !arr(r.hig) || !arr(r.swiftui)) w.push('config.reviews needs non-empty hig[] and swiftui[] ({rule, verdict, note}) and a date');
    else {
      if (!r.date) w.push('config.reviews.date is missing');
      r.hig.concat(r.swiftui).forEach(function (f, i) {
        if (!f.rule || VERDICTS.indexOf(f.verdict) < 0) w.push('review finding ' + (i + 1) + ' needs a rule and a verdict of pass, fix or departure');
        else if (f.verdict === 'departure' && !f.note) w.push('review departure "' + f.rule + '" needs a note citing the owner decision or direction-g paragraph');
      });
    }
    if (!arr(cfg.a11y)) w.push('config.a11y is missing: name, role, state, reading order, 44 pt targets, AX5 behaviour');
    var keys = cfg.states ? Object.keys(cfg.states) : [];
    if (!keys.length) w.push('config.states is empty');
    keys.forEach(function (k) { if (typeof cfg.states[k].render !== 'function') w.push('state "' + k + '" has no render(ctx)'); });
    var notes = (cfg.notes || []).join(' ').toLowerCase();
    var want = cfg.kind === 'page' ? PAGE_STATES : (cfg.kind === 'modal' ? MODAL_STATES : []);
    want.forEach(function (k) { if (keys.indexOf(k) < 0 && notes.indexOf(k) < 0) w.push('state "' + k + '" is missing: add it, or say in notes why this surface has none'); });
    (cfg.devices || []).forEach(function (k) { if (!Mock.devices[k]) w.push('unknown device "' + k + '"'); });
    if (!cfg.devices || !cfg.devices.length) w.push('config.devices is missing');
    if (cfg.kind !== 'component' && cfg.kind !== 'proposal' && !Array.isArray(cfg.motion)) w.push('config.motion is missing (use [] and a note when the surface has no motion)');
    (cfg.motion || []).forEach(function (m) {
      if (!m.id || !m.what || !m.token) w.push('motion item "' + (m.id || '?') + '" needs id, what and token (cite motion.md)');
      if (typeof m.play !== 'function') w.push('motion item "' + m.id + '" has no play(stage)');
      if (!m.reduce) w.push('motion item "' + m.id + '" needs a reduce field (what Reduce Motion does)');
    });
    (Mock.loadErrors || []).forEach(function (f) { w.push('kit file ' + f + ' did not load (network); reload the page'); });
    Object.keys(Mock.missingIcons).forEach(function (n) { w.push('icon "' + n + '" is not in the symbol map (add it to lib/symbols.js)'); });
    return w;
  };

  var NAV = [['stage', 'Stage'], ['states', 'States'], ['motion', 'Motion'], ['transitions', 'Transitions'], ['reflow', 'Reflow and hinge'], ['a11y', 'Accessibility'], ['reviews', 'Reviews'], ['source', 'Source map'], ['log', 'Change log']];

  /** Where the repo root is, when the page is opened from a checkout (file://), so source and spec paths can link. */
  function repoBase() {
    var m = /^(file:\/\/.*?\/)\.agents\/design\/mockups\//.exec(location.href);
    return m ? m[1] : null;
  }
  function pathNode(p, base) {
    var label = typeof p === 'string' ? p : p.path, note = typeof p === 'string' ? '' : p.note;
    var code = h('code', label);
    var node = base ? h('a', { href: base + label.replace(/^\//, '') }, code) : code;
    return note ? h('span', node, ' ', h('span', { style: { color: 'var(--k-fg2)' } }, note)) : node;
  }
  function hashGet() {
    var o = {}; (location.hash || '').replace(/^#/, '').split('&').forEach(function (kv) { var p = kv.split('='); if (p[0]) o[p[0]] = decodeURIComponent(p[1] || ''); });
    return o;
  }
  function renderState(st, ctx) {
    try {
      var out = st.render(ctx);
      if (typeof out === 'string') out = Mock.html(out);
      return out;
    } catch (e) {
      if (window.console) console.error(e);
      return h('div', { style: { padding: '60px 20px', color: '#ff6961', background: '#200', height: '100%', font: '14px monospace', whiteSpace: 'pre-wrap' } }, 'render() threw: ' + e.message + '\n' + (e.stack || '').split('\n').slice(0, 4).join('\n'));
    }
  }
  function sec(id, title, kids) {
    var s = h('section', { id: id }, h('h2', title));
    Mock.append(s, kids); return s;
  }
  function table(head, rows) {
    return h('div.k-table-wrap', h('table', h('thead', h('tr', head.map(function (t) { return h('th', t); }))), h('tbody', rows.map(function (r) { return h('tr', r.map(function (c) { return h('td', c); })); }))));
  }
  function ctlSelect(label, id, opts, value, onchange) {
    var sel = h('select.k-select', { id: id }, opts.map(function (o) { return h('option', { value: o[0], selected: o[0] === value }, o[1]); }));
    sel.value = value; sel.addEventListener('change', function () { onchange(sel.value); });
    return h('label.k-ctl', { for: id }, h('span', label), sel);
  }
  function ctlSwitch(label, value, onchange) {
    var b = h('button.k-switch', { type: 'button', role: 'switch', 'aria-checked': String(!!value) }, h('i'), label);
    b.addEventListener('click', function () { var on = b.getAttribute('aria-checked') !== 'true'; b.setAttribute('aria-checked', String(on)); onchange(on); });
    return b;
  }

  /**
   * Render the mockup page. See AUTHORING.md for the config shape. Required: kind, id, title, area, status, source, spec, devices, states,
   * motion, a11y, reviews. Optional: patterns, hig, entities, transitions, notes, changelog, frame:false (component pages: no device frame),
   * alwaysDark:true (sheets that are dark by design).
   */
  Mock.mount = function (cfg) {
    Mock.config = cfg;
    var H = hashGet();
    var nav = NAV.slice(); (cfg.sections || []).forEach(function (x) { nav.splice(Math.max(1, nav.map(function (n) { return n[0]; }).indexOf(x.after || 'states') + 1), 0, [x.id, x.title]); });
    /* cfg.scrollFit: measure every vertical scroller (Mock.scrollFit) and print its fit under each device; a state may set its own `scrollFit` (e.g. {always: true}). */
    function sfOpts(st) { return cfg.scrollFit ? Object.assign({}, cfg.scrollFit === true ? {} : cfg.scrollFit, st && st.scrollFit) : null; }
    var devices = (cfg.devices && cfg.devices.length ? cfg.devices : ['iphone']).filter(function (k) { return Mock.devices[k]; });
    var stateKeys = Object.keys(cfg.states || {});
    var S = {
      device: devices.indexOf(H.d) >= 0 ? H.d : devices[0],
      state: stateKeys.indexOf(H.s) >= 0 ? H.s : stateKeys[0],
      appearance: H.a === 'light' ? 'light' : 'dark', ts: Mock.textSizes[H.t] ? H.t : 'default',
      rm: H.rm != null && H.rm !== '' ? H.rm === '1' : !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches), rt: H.rt === '1', posture: H.p === 'part' ? 'part' : 'open', zoom: H.z || 'fit', scroll: ['top', 'mid', 'end'].indexOf(H.sc) >= 0 ? H.sc : 'top',
    };
    var base = repoBase(); var stageCtx = null;
    var lint = Mock.lint(cfg);
    var root = h('div.k-wrap', { id: 'mock-root' });
    document.body.innerHTML = '';
    document.body.appendChild(root);

    // ---- header
    var theme = h('button.k-btn.small', { type: 'button', title: 'Page theme: follows the system, or force light or dark' }, 'Theme: auto');
    theme.addEventListener('click', function () {
      var cur = document.documentElement.getAttribute('data-theme'), next = cur === 'light' ? 'dark' : (cur === 'dark' ? null : 'light');
      if (next) document.documentElement.setAttribute('data-theme', next); else document.documentElement.removeAttribute('data-theme');
      theme.textContent = 'Theme: ' + (next || 'auto');
    });
    var statusCls = /^in-flight/.test(cfg.status || '') ? 'inflight' : (cfg.status || 'proposed');
    var nLinks = (cfg.source || []).length + (cfg.spec || []).length + (cfg.patterns || []).length;
    var links = h('details.k-links', { open: window.matchMedia && matchMedia('(min-width: 760px)').matches }, h('summary', 'Source, spec and patterns (' + nLinks + ')'),
      cfg.source && cfg.source.length ? h('div', h('b', 'Source '), cfg.source.map(function (p, i) { return [i ? ' · ' : '', pathNode(p, base)]; })) : null,
      cfg.spec && cfg.spec.length ? h('div', h('b', 'Spec '), cfg.spec.map(function (p, i) { return [i ? ' · ' : '', pathNode(p, base)]; })) : null,
      cfg.patterns && cfg.patterns.length ? h('div', h('b', 'Patterns '), cfg.patterns.map(function (p, i) { return [i ? ' · ' : '', pathNode('.agents/patterns/' + p + '.md', base)]; })) : null);
    root.appendChild(h('header', h('p.k-eyebrow', (cfg.kind || 'mockup') + (cfg.area ? ' · ' + cfg.area : '') + ' · S+H mockup atlas'),
      h('div.k-head', h('div', h('h1', cfg.title || cfg.id || 'Untitled mockup'),
        h('div.k-badges', h('span.k-tag.' + statusCls, cfg.status || 'status?'), (cfg.devices || []).length ? h('span.k-tag', (cfg.devices || []).length + ' devices') : null, stateKeys.length ? h('span.k-tag', stateKeys.length + ' states') : null)), theme),
      links, cfg.summary ? h('p', { style: { marginTop: '10px', color: 'var(--k-fg2)' } }, cfg.summary) : null,
      h('p', { style: { fontSize: '13px', color: 'var(--k-fg2)', margin: '10px 0 0' } }, 'Jump: ', nav.map(function (n, i) { return [i ? ' · ' : '', h('a', { href: '#' + n[0], onclick: function (e) { e.preventDefault(); var el = document.getElementById(n[0]); if (el) el.scrollIntoView({ behavior: 'smooth' }); } }, n[1])]; }))));
    if (lint.length) root.appendChild(h('div.k-warnbox', { role: 'alert' }, h('b', 'Incomplete mockup (' + lint.length + ')'), h('ul', lint.map(function (m) { return h('li', m); }))));

    // ---- controls
    var stageInner = h('div.k-stage-inner'), stageBox = h('div.k-stage', { id: 'stage' }, stageInner);
    var gallery = h('div.k-gallery');
    var controls = h('div.k-controls', { role: 'group', 'aria-label': 'Mockup controls' });
    function sync() {
      var q = 'd=' + S.device + '&s=' + S.state + '&a=' + S.appearance + '&t=' + S.ts + '&rm=' + (S.rm ? 1 : 0) + '&rt=' + (S.rt ? 1 : 0) + '&p=' + S.posture + '&z=' + S.zoom + '&sc=' + S.scroll;
      try { history.replaceState(null, '', '#' + q); } catch (e) { /* file:// in some browsers */ }
    }
    function ctxFor(deviceKey, st, extra) {
      var ov = Object.assign({}, st && st.override, extra);
      var c = Mock.ctx(ov.device || deviceKey, { appearance: ov.appearance || S.appearance, ts: ov.ts || S.ts, reduceMotion: ov.reduceMotion != null ? ov.reduceMotion : S.rm, reduceTransparency: ov.reduceTransparency != null ? ov.reduceTransparency : S.rt, posture: ov.posture || S.posture });
      c.stateKey = st && st.key; return c;
    }
    function renderStage() {
      var st = cfg.states[S.state]; if (!st) return;
      st.key = S.state;
      var ctx = ctxFor(S.device, st);
      Mock.settings.reduceMotion = ctx.reduceMotion; Mock.settings.reduceTransparency = ctx.reduceTransparency;
      Mock.current = stageCtx = ctx;
      var node = renderState(st, ctx), el;
      if (cfg.frame === false) {
        var ts = Mock.textSizes[ctx.ts];
        // A component page has no window, but it lays out at the width the device gives content (window minus the rail), and on an unfolded Duo it
        // carries the hinge, so a grid rounds to even columns exactly as it does in a screen (the band is drawn over it).
        el = h('div.k-plain.ui-root.g-dark' + (ts.cls ? '.' + ts.cls : '') + (ctx.reduceMotion ? '.k-reduce-motion' : '') + (ctx.reduceTransparency ? '.k-reduce-transparency' : ''),
          { dataset: { device: ctx.key }, style: { width: ctx.contentW + 'px', maxWidth: '100%', minWidth: Math.min(320, ctx.contentW) + 'px', position: 'relative' } }, node);
        if (ctx.hingeAny) {
          el.dataset.hinge = ctx.hingeAny.axis; el.dataset.posture = ctx.posture;
          if (ctx.hinge) { var band = h('div.k-hinge.v', { 'aria-hidden': 'true', dataset: { posture: ctx.posture }, title: 'Hinge band ' + ctx.hinge.x + ' to ' + (ctx.hinge.x + ctx.hinge.w).toFixed(1) + ' pt. ' + Mock.postures[ctx.posture].label, style: { left: ctx.hinge.x + 'px', width: ctx.hinge.w + 'px', top: 0, bottom: 0 } }, h('span.k-hinge-label', Mock.postures[ctx.posture].short)); el.appendChild(band); }
        }
      } else el = Mock.frame(ctx, node);
      stageInner.innerHTML = '';
      stageInner.classList.toggle('plain', cfg.frame === false);
      stageInner.appendChild(el);
      applyScroll(stageInner);
      stageInner.appendChild(h('p.k-device-caption', ctx.device.label + (ctx.posture ? ' · ' + Mock.postures[ctx.posture].short : '') + ' · ' + (st.title || S.state) + (st.note ? ' · ' + st.note : '')));
      if (sfOpts(st)) stageInner.appendChild(Mock.scrollFit.badge(el, sfOpts(st)));
      applyZoom();
    }
    /** Page scroll position control: the page scrolls inside the device; Middle and End let a reviewer see the lower sections. */
    function applyScroll(rootEl) {
      var f = { top: 0, mid: .5, end: 1 }[S.scroll] || 0;
      requestAnimationFrame(function () { requestAnimationFrame(function () { rootEl.querySelectorAll('.ui-scroll').forEach(function (sc) { if (f === 0 && sc.dataset.scrollPinned) return; sc.scrollTop = f * Math.max(0, sc.scrollHeight - sc.clientHeight); sc.dispatchEvent(new Event('scroll')); }); }); });
    }
    function applyZoom() {
      var z = 1;
      if (cfg.frame === false) z = 1;
      else if (S.zoom === 'fit') {
        var d = Mock.devices[S.device], avail = Math.max(240, stageBox.clientWidth - 40);
        var availH = Math.max(320, window.innerHeight - 110);
        z = Math.min(1, avail / (d.w + 2 * d.bezel + 4), availH / (d.h + 2 * d.bezel + 40));
      } else z = (parseInt(S.zoom, 10) || 100) / 100;
      stageInner.style.setProperty('--zoom', z.toFixed(3));
    }
    var galleryGen = 0;
    /** Builds the States gallery one figure per timer tick (so the controls stay responsive), newest request wins. */
    function renderGallery() {
      var gen = ++galleryGen; gallery.innerHTML = '';
      var d = Mock.devices[S.device], gz = Math.max(.22, Math.min(.7, 330 / (d.w + 2 * d.bezel)));
      if (cfg.frame === false) { gallery.hidden = true; return; }
      var both = cfg.kind === 'modal' && !cfg.alwaysDark, jobs = [];
      stateKeys.forEach(function (k) {
        (both ? ['dark', 'light'] : [null]).forEach(function (ap) {
          var fig = h('figure', h('div.k-gz', { style: { '--gz': gz.toFixed(3), width: (d.w + 2 * d.bezel) + 'px', height: (d.h + 2 * d.bezel) + 'px' } }),
            h('figcaption', h('b', (cfg.states[k].title || k)), h('code', k + (ap ? ' · ' + ap : '')), ' ', h('button.k-btn.small', { type: 'button', onclick: function () { S.state = k; if (ap) S.appearance = ap; sync(); refresh(); document.getElementById('stage').scrollIntoView({ behavior: 'smooth' }); } }, 'Open in stage')));
          gallery.appendChild(fig);
          jobs.push(function () {
            var st = cfg.states[k]; st.key = k;
            var ctx = ctxFor(S.device, st, ap ? { appearance: ap } : null);
            Mock.settings.reduceMotion = ctx.reduceMotion; Mock.settings.reduceTransparency = ctx.reduceTransparency; Mock.current = ctx;
            var box = fig.firstChild; box.appendChild(Mock.frame(ctx, renderState(st, ctx))); applyScroll(fig);
            if (sfOpts(st)) fig.appendChild(Mock.scrollFit.badge(box, sfOpts(st)));
          });
        });
      });
      (function next() {
        if (gen !== galleryGen) return;
        var job = jobs.shift();
        if (!job) { Mock.settings.reduceMotion = S.rm; Mock.settings.reduceTransparency = S.rt; if (stageCtx) Mock.current = stageCtx; return; }
        job(); setTimeout(next, 0);
      })();
    }
    function buildControls() {
      controls.innerHTML = '';
      var postureCtl = ctlSelect('Hinge', 'c-posture', Object.keys(Mock.postures).map(function (k) { return [k, Mock.postures[k].label]; }), S.posture, function (v) { S.posture = v; sync(); refresh(); });
      var showPosture = function () { postureCtl.hidden = !(Mock.devices[S.device] && Mock.devices[S.device].hinge); };
      controls.appendChild(ctlSelect(cfg.frame === false ? 'Window (device)' : 'Device', 'c-device', devices.map(function (k) { return [k, Mock.devices[k].label]; }), S.device, function (v) { S.device = v; showPosture(); sync(); refresh(); }));
      controls.appendChild(postureCtl); showPosture();
      controls.appendChild(ctlSelect('State', 'c-state', stateKeys.map(function (k) { return [k, k + (cfg.states[k].title ? ' · ' + cfg.states[k].title : '')]; }), S.state, function (v) { S.state = v; sync(); refresh(true); }));
      controls.appendChild(ctlSelect('Sheet appearance', 'c-appearance', [['dark', 'Dark'], ['light', 'Light']], S.appearance, function (v) { S.appearance = v; sync(); refresh(); }));
      if (cfg.frame !== false) controls.appendChild(ctlSelect('Page scroll', 'c-scroll', [['top', 'Top'], ['mid', 'Middle'], ['end', 'End']], S.scroll, function (v) { S.scroll = v; sync(); refresh(); }));
      controls.appendChild(ctlSelect('Text size', 'c-text', Object.keys(Mock.textSizes).map(function (k) { return [k, Mock.textSizes[k].label]; }), S.ts, function (v) { S.ts = v; sync(); refresh(); }));
      controls.appendChild(h('div.k-ctl', h('span', 'Accessibility'), h('div', { style: { display: 'flex', gap: '14px', flexWrap: 'wrap' } },
        ctlSwitch('Reduce Motion', S.rm, function (v) { S.rm = v; sync(); refresh(); }), ctlSwitch('Reduce Transparency', S.rt, function (v) { S.rt = v; sync(); refresh(); }))));
      if (cfg.frame !== false) controls.appendChild(ctlSelect('Zoom', 'c-zoom', [['fit', 'Fit window'], ['50', '50%'], ['75', '75%'], ['100', '100% (points)']], S.zoom, function (v) { S.zoom = v; sync(); applyZoom(); }));
      var play = h('button.k-btn.primary', { type: 'button', id: 'play-all', title: 'Play every motion and transition in order' }, 'Play all');
      play.addEventListener('click', function () { playAll(play); });
      controls.appendChild(h('div.k-ctl', h('span', 'Motion'), play));
    }
    function refresh(stateOnly) { renderStage(); if (!stateOnly) renderGallery(); }

    root.appendChild(controls);
    root.appendChild(stageBox);
    window.addEventListener('resize', applyZoom);

    // ---- sections
    root.appendChild(sec('states', 'States', [h('p', 'Every state for the selected device' + (cfg.kind === 'modal' && !cfg.alwaysDark ? ', in dark and light' : '') + '. Controls above (text size, Reduce Motion, Reduce Transparency) apply here too.'), gallery]));
    (cfg.sections || []).filter(function (x) { return (x.after || 'states') === 'states'; }).forEach(function (x) { root.appendChild(sec(x.id, x.title, x.build())); });   // cfg.sections: [{id, title, after?: 'states', build(): Node|Node[]}]

    function stageEl() { return stageInner.querySelector('.screen') || stageInner.firstElementChild; }
    function runItem(item, card) {
      var want = typeof item.state === 'function' ? item.state() : item.state, moved = false;
      if (item.device && devices.indexOf(item.device) >= 0 && item.device !== S.device) { S.device = item.device; moved = true; }
      if (item.posture && item.posture !== S.posture) { S.posture = item.posture; moved = true; }
      if (want && cfg.states[want] && want !== S.state) { S.state = want; moved = true; }
      if (moved) { sync(); buildControls(); renderGallery(); }
      renderStage();
      Mock.settings.reduceMotion = S.rm;
      if (card) card.classList.add('running');
      return Mock.sleep(40).then(function () { return item.play(stageEl(), stageInner); }).catch(function (e) { if (window.console) console.error(e); })
        .then(function () { if (card) card.classList.remove('running'); });
    }
    var items = [];
    function playBtn(item, card) {
      var b = h('button.k-btn.small', { type: 'button' }, 'Play');
      b.addEventListener('click', function () { b.disabled = true; runItem(item, card).then(function () { b.disabled = false; }); });
      return b;
    }
    var motion = cfg.motion || [];
    var mList = h('div.k-motion');
    motion.forEach(function (m) {
      var card = h('div.k-motion-item');
      Mock.append(card, [h('div.m', h('h3', m.what), h('p', h('code', m.id), ' · ', h('span.tok', m.token), m.source ? [' · ', h('code', m.source)] : null), h('p', h('b', 'Reduce Motion: '), m.reduce || '?'), m.note ? h('p', m.note) : null), typeof m.play === 'function' ? playBtn(m, card) : null]);
      mList.appendChild(card); items.push({ item: m, card: card });
    });
    var motionIntro = h('p');
    motionIntro.innerHTML = 'Durations and curves are the app\'s <code>MotionTokens</code> (<a href="' + (base ? base + '.agents/design/motion.md' : '#') + '">design/motion.md</a> section 7): quick 0.2 s, state 0.6 s (0.2 s reduced), standard 0.3 s. Each Play restages the selected state first; the Reduce Motion switch above applies.';
    root.appendChild(sec('motion', 'Motion', [motionIntro, motion.length ? mList : h('p', { style: { color: 'var(--k-fg2)' } }, 'This surface has no motion of its own (the system provides push, sheet and tab transitions).')]));

    var trans = cfg.transitions || [];
    var tList = h('div.k-motion');
    trans.forEach(function (t) {
      var card = h('div.k-motion-item');
      Mock.append(card, [h('div.m', h('div.k-trans', h('b', t.from), h('span.arrow', '→'), h('b', t.to), h('span.k-tag', t.kind || 'cut')), t.note ? h('p', t.note) : null), typeof t.play === 'function' ? playBtn(t, card) : null]);
      tList.appendChild(card); items.push({ item: t, card: card });
    });
    root.appendChild(sec('transitions', 'Transitions', trans.length ? [h('p', 'Navigation is the system\'s: a tab switch is a cut, a page pushes, a modal is a sheet, a tile that is the thing it opens zooms (iOS 18). Reduce Motion turns slides and zooms into cross-fades.'), tList] : h('p', { style: { color: 'var(--k-fg2)' } }, 'No transitions listed.')));

    // ---- Reflow and hinge (kit-made): the split opening and the Duo hinge posture, for every surface that has a landscape window
    var landscape = devices.filter(function (k) { var d = Mock.devices[k]; return d.regular && d.w > d.h; });
    var hingeDevs = landscape.filter(function (k) { return Mock.devices[k].hinge; });
    var rf = cfg.reflow || {}, splitInfo = h('p', { style: { color: 'var(--k-fg2)' } }, 'Checking which states split…');
    var scanned = {};
    /** The first state whose render has a split to animate on this device and posture (the selected state first), or null. Cached; renders offscreen. */
    function splitState(dev, posture) {
      var key = dev + '/' + posture;
      if (scanned[key] !== undefined) return scanned[key];
      if (rf.state && cfg.states[rf.state]) return (scanned[key] = rf.state);
      var keep = Mock.current, found = null;
      [S.state].concat(stateKeys.filter(function (k) { return k !== S.state; })).some(function (k) {
        var st = cfg.states[k]; st.key = k;
        var ctx = ctxFor(dev, st, { posture: posture });
        Mock.settings.reduceMotion = ctx.reduceMotion; Mock.current = ctx;
        try {
          var n = st.render(ctx);
          if (typeof n === 'string') n = Mock.html(n);
          var nodes = Array.isArray(n) ? n : [n];
          if (nodes.some(function (x) { return x && x.querySelector && (x.querySelector('.ui-split[data-split], [data-detail-pane]') || (x.matches && x.matches('.ui-split[data-split], [data-detail-pane]'))); })) { found = k; return true; }
        } catch (e) { /* a state that throws does not split */ }
        return false;
      });
      Mock.settings.reduceMotion = S.rm; Mock.current = keep || stageCtx;
      return (scanned[key] = found);
    }
    function pickLandscape() { return landscape.indexOf(S.device) >= 0 ? S.device : landscape[0]; }
    function flash(msg) { var c = stageInner.querySelector('.k-device-caption'); if (c) { var was = c.textContent; c.textContent = msg; return Mock.sleep(2200).then(function () { c.textContent = was; }); } return Mock.sleep(800); }
    function reflowSplit(dir) {
      return function (stage) {
        if (!Mock.reflow.has(stage)) return flash('This surface is a single page on ' + Mock.devices[S.device].short + ': there is no split to ' + dir + '.');
        return Mock.reflow.split(stage, stageCtx, dir).then(function () { return Mock.sleep(500); });
      };
    }
    function reflowPosture(from, to) {
      return function (stage) {
        var st = cfg.states[S.state], a = ctxFor(S.device, st, { posture: from }), b = ctxFor(S.device, st, { posture: to });
        return Mock.reflow.posture(stage, a, b).then(function () { S.posture = to; sync(); return Mock.sleep(350); }).then(function () { buildControls(); renderStage(); });
      };
    }
    var rList = h('div.k-motion');
    if (cfg.frame !== false && landscape.length) {
      var TOK = 'standard 0.3 s smooth (0.2 s reduced)', SRC = 'HassUI/App/Layout/OnDemandSplit.swift, SplitPolicy.swift', RED = 'no sliding: the panes cut to the end geometry and the page cross-fades in 0.2 s';
      var defs = [
        { id: 'split-open', what: 'Split opens: the page narrows to the leading pane and the detail slides in', device: function () { return pickLandscape(); }, posture: 'open', note: rf.open,
          play: reflowSplit('open') },
        { id: 'split-close', what: 'Split closes: the detail slides out and the page widens again', device: function () { return pickLandscape(); }, posture: 'open', note: rf.close,
          play: reflowSplit('close') }];
      if (hingeDevs.length) {
        defs.push({ id: 'hinge-open-to-part', what: 'Hinge: fully open, then slightly closed: the divider moves from the midpoint of the free space onto the hinge', device: function () { return hingeDevs[0]; }, posture: 'open', note: rf.posture,
          play: reflowPosture('open', 'part') });
        defs.push({ id: 'hinge-part-to-open', what: 'Hinge: slightly closed, then fully open: the divider moves from the hinge back to the midpoint of the free space', device: function () { return hingeDevs[0]; }, posture: 'part', note: rf.posture,
          play: reflowPosture('part', 'open') });
      }
      defs.forEach(function (m) {
        var dev = m.device;
        var item = { id: m.id, what: m.what, token: TOK, source: SRC, reduce: RED, note: m.note, posture: m.posture, play: m.play };
        Object.defineProperty(item, 'device', { get: function () { return dev(); } });
        Object.defineProperty(item, 'state', { get: function () { var d = dev(); return splitState(d, m.posture) || S.state; } });
        var card = h('div.k-motion-item');
        Mock.append(card, [h('div.m', h('h3', m.what), h('p', h('code', m.id), ' · ', h('span.tok', TOK), ' · ', h('code', SRC)), h('p', h('b', 'Reduce Motion: '), RED), m.note ? h('p', m.note) : null), playBtn(item, card)]);
        rList.appendChild(card); items.push({ item: item, card: card });
      });
      setTimeout(function () {
        var d = hingeDevs[0] || landscape[0], a = splitState(d, 'open');
        splitInfo.textContent = a ? 'This surface splits in landscape: the "' + (cfg.states[a].title || a) + '" state is the one the moves below play on. A fixed-width part (a carousel, the weather card) keeps its width while the panes move and settles when the move ends.'
          : 'This surface is a single page on every device (no split adopter), so nothing reflows when the split or the hinge changes: the page does not move, and the hinge moves below only change the band.';
      }, 0);
    }
    if (cfg.frame !== false && landscape.length) root.appendChild(sec('reflow', 'Reflow and hinge', [
      h('p', 'Landscape windows may split (SplitPolicy: regular width, wider than tall, each pane at least 360 pt). The iPad splits at the midpoint. The unfolded Duo splits at the midpoint of the free space, the window minus the trailing rail, while it is fully open, and on the hinge while it is slightly closed (owner rule, 2026-10-24; in flight, see split-view.md). Portrait never splits. Each Play restages the surface in a landscape window, then animates it; pick the hinge posture with the Hinge control.'),
      splitInfo, rList]));

    function playAll(btn) {
      btn.disabled = true; btn.textContent = 'Playing…';
      Mock.anim.series(items.map(function (it) { return function () { return runItem(it.item, it.card); }; })).then(function () { btn.disabled = false; btn.textContent = 'Play all'; });
    }

    root.appendChild(sec('a11y', 'Accessibility', [h('p', 'What VoiceOver, Switch Control and Dynamic Type see on this surface. Check at Large, xxxLarge and AX5 with the Text size control.'),
      h('ul', (cfg.a11y || []).map(function (a) { return h('li', typeof a === 'string' ? a : [h('b', a.rule + ': '), a.note]); }))]));

    var rv = cfg.reviews || {};
    function rtable(list) { return table(['Rule', 'Verdict', 'Note'], (list || []).map(function (f) { return [f.rule, h('span.k-verdict.' + f.verdict, f.verdict), f.note || '']; })); }
    root.appendChild(sec('reviews', 'Reviews', [h('p', 'Dated ' + (rv.date || '(no date)') + '. A departure cites the owner decision or the direction-g paragraph that overrides the HIG.'),
      h('h3', 'Apple HIG (apple-hig skill)'), rtable(rv.hig), h('h3', { style: { marginTop: '18px' } }, 'SwiftUI Pro, design lens'), rtable(rv.swiftui)]));

    var srcRows = [];
    (cfg.source || []).forEach(function (p) { srcRows.push(['source', pathNode(p, base)]); });
    (cfg.spec || []).forEach(function (p) { srcRows.push(['spec', pathNode(p, base)]); });
    (cfg.patterns || []).forEach(function (p) { srcRows.push(['pattern', pathNode('.agents/patterns/' + p + '.md', base)]); });
    (cfg.hig || []).forEach(function (p) { srcRows.push(['HIG', p]); });
    (cfg.entities || []).forEach(function (p) { srcRows.push(['entity', h('code', p)]); });
    (cfg.kitComponents || []).forEach(function (p) { srcRows.push(['kit component', h('code', 'Mock.components.' + p)]); });
    root.appendChild(sec('source', 'Source map', [srcRows.length ? table(['Kind', 'Reference'], srcRows) : h('p', 'No references listed.'), (cfg.notes || []).length ? [h('h3', { style: { marginTop: '18px' } }, 'Notes'), h('ul.k-notes', cfg.notes.map(function (n) { return h('li', n); }))] : null]));

    var log = cfg.changelog || [];
    root.appendChild(sec('log', 'Change log', log.length ? table(['Date', 'Change'], log.map(function (e) { return [e.date, e.note]; })) : h('p', 'No entries yet.')));

    buildControls(); refresh();
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(applyZoom);
    return root;
  };

  /**
   * A ready-made config for a component mockup: renders `variants` and `states` of Mock.components[name] in swatches on the page and
   * sheet surfaces. Merge your own fields over it: Mock.mount(Object.assign(Mock.componentConfig('GlassTile'), {...})).
   * @param {string} name key in Mock.components
   * @param {{surfaces?:Array<'page'|'sheet'>, props?:object}} [o] surfaces default to both; props is merged into every swatch
   */
  Mock.componentConfig = function (name, o) {
    o = o || {};
    var comp = Mock.components[name];
    var surfaces = o.surfaces || ['page', 'sheet'];
    function sw(list, title) {
      return function (ctx) {
        var out = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } });
        surfaces.forEach(function (surface) {
          var wrap = h('div.k-swatch-grid');
          (list.length ? list : [{ id: 'default', label: 'default', props: {} }]).forEach(function (v) {
            var box = h('div.k-swatch.' + (surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light')), { style: { width: o.swatchWidth || '', flex: o.swatchWidth ? 'none' : '1 1 260px', maxWidth: '100%' } },
              h('div.k-cap', surface + ' · ' + (v.label || v.id)), h('div.in', comp(Object.assign({ ctx: ctx }, v.props, o.props))), v.note ? h('div', { style: { font: '12px var(--font)', opacity: .7, marginTop: '8px' } }, v.note) : null);
            wrap.appendChild(box);
          });
          out.appendChild(wrap);
        });
        return out;
      };
    }
    var states = {};
    if (comp.variants.length) states.variants = { title: 'Variants', render: sw(comp.variants) };
    states.states = { title: 'States', render: sw(comp.states.length ? comp.states : [{ id: 'default', label: 'default', props: {} }]) };
    return Object.assign({ kind: 'component', id: name.replace(/([a-z])([A-Z])/g, '$1-$2').toLowerCase(), title: name, area: 'components', status: 'shipped', frame: false,
      source: comp.source ? [comp.source] : [], devices: Mock.deviceKeys.slice(), states: states, motion: [] }, o.config || {});
  };
})();
