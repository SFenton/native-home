/* StateTile: the state-styled tile. apple/Sources/HassDesign/TileActions/StateTileLook.swift (the four layers and their diff),
 * apple/Sources/HassUI/UIKitPort/Design/UKStateTileTransition.swift, UKTileActions.swift (the arc standing in for the disc). Used by
 * components/tiles/state-styled-tile, proposals/state-style-library and proposals/state-tile-indicator. Rule doc: .agents/design/state-styled-tile.md.
 *
 * One tile node whose four layers (icon, colour, indicator, text) are updated one by one: StateTile.apply() touches only a layer whose
 * resolved value changed, so the arc that turns through Opening and Closing is one element that is never restarted.
 *
 * look: { title, text, icon, cls: 'resting'|'in-progress'|'warning'|'error'|'unknown', active?, family?, indicator?: 'none'|'arc'|'pulse'|'breathe',
 *         action?: {symbol, verb} | null (null: taps are ignored), lockedOut?, behavior?: 'perform'|'navigate'|'inert' }
 * opts: { placement: 'swap' | 'slot' | 'inline' | 'ring' }
 *   swap (the default, the rule): while a tap does nothing the disc, fill and glyph, fades out and a 28 pt arc in the tile's ink stands in its
 *     44 pt slot; the disc fades back in when a tap works again. A tile with no disc swaps its glyph for a glyph-sized arc.
 *   slot, inline, ring: the rejected placements A, B and C, kept for proposals/state-tile-indicator.
 */
(function () {
  var h = Mock.h, K = Mock.components, I = Mock.icon;
  var css = [
    '.st-host { position: relative; display: grid; place-items: center; }',
    '.st-host .st-g { display: grid; place-items: center; transition: opacity var(--t-quick, .2s) ease-out; }',
    '.ui-tile .disc .st-g svg { width: 20px; height: 20px; }',
    '.st-host .st-arc, .st-host .st-ring { position: absolute; inset: 0; display: grid; place-items: center; opacity: 0; pointer-events: none; transition: opacity var(--t-quick, .2s) ease-out; }',
    '.st-host .st-arc.show, .st-host .st-ring.show, .st-inline.show { opacity: 1; }',
    '.st-host.arc-on .st-g { opacity: 0; }',
    /* swap: the disc's fill and glyph fade out on `quick` and the arc, 7/11 of the disc (28 pt in 44, 42 in 66), fades in over them */
    '.st-host .st-swap { position: absolute; inset: 0; display: grid; place-items: center; opacity: 0; pointer-events: none; color: var(--tile-ink, #fff); transition: opacity var(--t-quick, .2s) ease-out; }',
    '.st-host .st-swap .ui-arc { width: 63.64%; height: 63.64%; } .ui-tile .disc.st-host .st-swap .ui-arc svg { width: 100%; height: 100%; }',
    '.st-host.swap-on .st-swap { opacity: 1; } .st-host.swap-on .st-g { opacity: 0; }',
    '.ui-tile .disc.st-host.swap-on { background: transparent !important; }',
    '.ui-tile .disc.st-host.st-swapping { transition: background var(--t-quick, .2s) ease-out, color var(--t-state) var(--ease-state); }',
    '.ui-tile.st-locked .st-host.swap-on .st-g { opacity: 0; }',
    /* the app's disc is 44 pt scaled with the text and capped at 66 pt, which it reaches by Accessibility 1; the kit's stays 44 */
    '.ts-ax5 .ui-tile .disc.st-host { width: 66px; height: 66px; } .ts-ax5 .ui-tile .disc.st-host .st-g svg { width: 30px; height: 30px; }',
    '.st-host .st-ring { inset: -5px; color: var(--tile-ink, #fff); } .st-host .st-ring svg { width: 100%; height: 100%; animation: ui-spin .82s linear infinite; }',
    '.k-reduce-motion .st-host .st-ring svg { animation-duration: 1.64s; }',
    '.st-inline { display: inline-grid; vertical-align: -3px; width: 0; opacity: 0; overflow: hidden; transition: opacity var(--t-quick, .2s) ease-out; }',
    '.st-inline.show { width: 16px; margin-right: 6px; }',
    '.ui-tile.st-warning { --ul: var(--g-module-dense); --tile-ink-2: var(--st-warn); --tile-glyph: var(--st-warn); --st-warn: #FFB340; }',
    '.in-sheet.g-light .ui-tile.st-warning { --st-warn: #995400; }',
    '.ui-tile.st-warning .disc { color: var(--st-warn); } .ui-tile.error .disc { color: var(--g-red, #FF6961); }',
    '.ui-tile.st-locked .disc .st-g { opacity: .4; } .ui-tile.st-locked .st-host.arc-on .st-g { opacity: 0; }',
    '@keyframes st-breathe { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: .45; transform: scale(.9); } }',
    '.st-g.breathe { animation: st-breathe 1.8s ease-in-out infinite; } .st-g.pulse { animation: ui-pulse 1.4s ease-in-out infinite; }',
    '.k-reduce-motion .st-g.breathe, .k-reduce-motion .st-g.pulse { animation: none; }',
    '.st-film { display: grid; gap: 12px; } .st-film .cap { font: 600 12px var(--font); color: #fff; opacity: .8; margin: 0 0 6px 2px; }',
    '.st-note { font: 13px/1.4 var(--font); color: #fff; opacity: .78; margin: 2px 2px 0; }',
  ].join('\n');
  document.head.appendChild(h('style', { html: css }));

  function ring() {
    var d = 54, lw = 2.5, r = (d - lw) / 2, c = 2 * Math.PI * r, q = c / 4, m = d / 2;
    return '<svg viewBox="0 0 ' + d + ' ' + d + '" aria-hidden="true"><circle cx="' + m + '" cy="' + m + '" r="' + r + '" fill="none" stroke="currentColor" stroke-opacity=".22" stroke-width="' + lw + '"/>' +
      '<circle cx="' + m + '" cy="' + m + '" r="' + r + '" fill="none" stroke="currentColor" stroke-opacity=".96" stroke-width="' + lw + '" stroke-linecap="round" stroke-dasharray="' + q + ' ' + (c - q) + '"/></svg>';
  }
  /** The 28 pt arc with a 3 pt ring that stands in the disc's place (ArcSpinner's ring and quarters, a tile size). */
  function tileArc() {
    var d = 28, lw = 3, r = (d - lw) / 2, c = 2 * Math.PI * r, q = c / 4, m = d / 2;
    function circ(op, extra) { return '<circle cx="' + m + '" cy="' + m + '" r="' + r + '" fill="none" stroke="currentColor" stroke-opacity="' + op + '" stroke-width="' + lw + '"' + (extra || '') + '/>'; }
    return h('span.ui-arc', { 'aria-hidden': 'true', html: '<svg viewBox="0 0 ' + d + ' ' + d + '">' + circ('.22') + circ('.96', ' stroke-dasharray="' + q + ' ' + (c - q) + '" transform="rotate(-135 ' + m + ' ' + m + ')"') +
      circ('.72', ' stroke-dasharray="' + q + ' ' + (c - q) + '" transform="rotate(-45 ' + m + ' ' + m + ')"') + '</svg>' });
  }
  /** What GlassTile needs for a look: the face comes from the class and the active flag. */
  function props(l) {
    var un = l.cls === 'unknown', beh = l.behavior || 'perform', hasDisc = beh !== 'inert' && l.disc !== false;
    var p = { title: l.title, subtitle: l.text, symbol: l.icon, family: l.family || 'contact', isActive: !!l.active && !un && l.cls !== 'warning', isUnavailable: un, isError: l.cls === 'error',
      kind: beh === 'navigate' ? 'navigate' : 'command', behavior: beh };
    if (hasDisc) p.actions = [{ id: 'state', symbol: l.icon, label: (l.action ? l.action.verb + ' ' : '') + l.title, on: !!l.active && !un && l.cls !== 'warning' && l.cls !== 'error', dim: un }];
    return p;
  }
  function host(tile) { return tile.querySelector('.st-host'); }
  function spoken(l) {
    var v = l.text || '', add = { 'in-progress': 'in progress', warning: 'warning', error: 'error' }[l.cls];
    if (add && v.toLowerCase().indexOf(add) < 0) v += ', ' + add;
    return l.title + ', ' + v;
  }
  function paint(tile, l, o) {
    var fresh = K.GlassTile(props(l)), freshDisc = fresh.querySelector('.disc');
    tile.className = fresh.className + (l.cls === 'warning' ? ' st-warning' : '') + (!l.action && l.cls === 'in-progress' ? ' st-locked' : '');
    tile.setAttribute('style', fresh.getAttribute('style') || ''); tile.dataset.face = fresh.dataset.face;
    var d = tile.querySelector('.disc'); if (d && freshDisc) { d.className = freshDisc.className + ' st-host' + ['arc-on', 'swap-on', 'st-swapping'].map(function (c) { return d.classList.contains(c) ? ' ' + c : ''; }).join(''); }
    tile.setAttribute('aria-label', spoken(l));
    if (!l.action || l.cls === 'unknown') tile.setAttribute('aria-disabled', 'true'); else tile.removeAttribute('aria-disabled');
  }
  function setIndicator(tile, l, o) {
    var hs = host(tile), arc = l.indicator === 'arc', place = (o && o.placement) || 'swap', isDisc = hs.classList.contains('disc');
    /* The arc shows only while a tap does nothing: a state with an action (Stop, Reverse, Disarm) keeps its disc and has no arc. */
    var idle = arc && (!l.action || l.behavior === 'inert' || l.behavior === 'navigate' && !tile.querySelector('.disc'));
    /* slot (A): the arc takes the glyph's place inside the disc. A tile with no disc draws swap the same way, in the glyph's place. */
    var slot = idle && (place === 'slot' || place === 'swap' && !isDisc), swap = idle && place === 'swap' && isDisc;
    hs.querySelector('.st-arc').classList.toggle('show', slot); hs.classList.toggle('arc-on', slot);
    if (swap !== hs.classList.contains('swap-on')) { hs.classList.add('st-swapping'); clearTimeout(hs._swapT); hs._swapT = setTimeout(function () { hs.classList.remove('st-swapping'); }, 260); }
    hs.classList.toggle('swap-on', swap);
    hs.querySelector('.st-ring').classList.toggle('show', arc && place === 'ring');
    tile.querySelector('.st-inline').classList.toggle('show', arc && place === 'inline');
    var g = hs.querySelector('.st-g'); g.classList.toggle('breathe', l.indicator === 'breathe'); g.classList.toggle('pulse', l.indicator === 'pulse');
  }
  function glyphHTML(l, tile) { return I(l.icon, { fill: l.icon !== 'power' }); }

  var ST = window.StateTile = {};
  /** Builds the tile for a look. */
  ST.tile = function (l, o) {
    var tile = K.GlassTile(props(l)), slotEl = tile.querySelector('.disc') || tile.querySelector('.glyph');
    slotEl.classList.add('st-host'); slotEl.innerHTML = '';
    slotEl.appendChild(h('span.st-g', { html: glyphHTML(l) }));
    slotEl.appendChild(h('span.st-arc', K.ArcSpinner({ size: 'compact', label: 'In progress' })));
    slotEl.appendChild(h('span.st-ring', { html: ring() }));
    slotEl.appendChild(h('span.st-swap', tileArc()));
    var st = tile.querySelector('.st'); st.innerHTML = '';
    st.appendChild(h('span.st-inline', K.ArcSpinner({ size: 'inline', label: 'In progress' }))); st.appendChild(h('span.st-t', l.text));
    tile._look = l; tile._opts = o || {};
    paint(tile, l, o); setIndicator(tile, l, o);
    return tile;
  };
  /** The per-layer diff: each of icon, colour, indicator and text is compared with the look on screen and left alone when it did not change. */
  ST.apply = function (tile, l, o) {
    o = o || tile._opts; var was = tile._look, rm = !!Mock.settings.reduceMotion, hs = host(tile), g = hs.querySelector('.st-g'), jobs = [];
    function hidden() { return hs.classList.contains('swap-on') || hs.classList.contains('arc-on'); }
    var wasHidden = hidden(), iconChanged = was.icon !== l.icon;
    if (was.text !== l.text) tile.querySelector('.st-t').textContent = l.text;                                  // text: replaced at once
    if (was.cls !== l.cls || !!was.active !== !!l.active || !was.action !== !l.action) paint(tile, l, o);          // colour: the registered slots cross-fade on `state`
    else tile.setAttribute('aria-label', spoken(l));
    if (iconChanged && wasHidden) g.innerHTML = glyphHTML(l);                                                   // a hidden disc takes its next glyph with no effect, before it fades back in
    else if (iconChanged) {                                                                                     // icon: the symbol replace (down-up); a cut under Reduce Motion
      if (rm) g.innerHTML = glyphHTML(l);
      else if (o.placement !== 'slot' && o.placement !== 'inline' && o.placement !== 'ring' && l.indicator === 'arc' && !l.action) jobs.push(Mock.sleep(200).then(function () { if (tile._look === l) g.innerHTML = glyphHTML(l); })); // fading out: the glyph is replaced once it is hidden
      else jobs.push(g.animate([{ transform: 'scale(1)', opacity: 1 }, { transform: 'scale(.6)', opacity: 0 }], { duration: 130, easing: 'ease-in' }).finished.then(function () {
        g.innerHTML = glyphHTML(l); return g.animate([{ transform: 'scale(.6)', opacity: 0 }, { transform: 'scale(1)', opacity: 1 }], { duration: 170, easing: 'ease-out' }).finished; }));
    }
    if (was.indicator !== l.indicator || !was.action !== !l.action) setIndicator(tile, l, o);                      // indicator: fades on `quick`; untouched when it did not change
    if (wasHidden && !hidden()) jobs.push(Mock.sleep(200));                                                     // a one-shot entry effect waits for the disc's fade-in
    tile._look = l;
    return Promise.all(jobs);
  };
  /** One-shot entry effects on the glyph (the system times the real ones; these approximate them). Nothing under Reduce Motion. */
  ST.once = function (tile, effect) {
    if (Mock.settings.reduceMotion) return Promise.resolve();
    var g = host(tile).querySelector('.st-g'), frames = {
      pulse: [[{ opacity: 1 }, { opacity: .3 }, { opacity: 1 }], 900],
      bounce: [[{ transform: 'scale(1)' }, { transform: 'scale(1.28)' }, { transform: 'scale(.94)' }, { transform: 'scale(1)' }], 520],
      wiggle: [[{ transform: 'rotate(0)' }, { transform: 'rotate(-13deg)' }, { transform: 'rotate(11deg)' }, { transform: 'rotate(-7deg)' }, { transform: 'rotate(4deg)' }, { transform: 'rotate(0)' }], 620],
    }[effect];
    return g.animate(frames[0], { duration: frames[1], easing: 'ease-in-out' }).finished;
  };
  /** Runs looks in order: [[look, holdMs, onceEffect?], ...]. */
  ST.run = function (tile, steps, o) {
    return steps.reduce(function (p, s) {
      return p.then(function () { return ST.apply(tile, s[0], o); }).then(function () { return s[2] ? ST.once(tile, s[2]) : null; }).then(function () { return Mock.sleep(s[1]); });
    }, Promise.resolve());
  };
  ST.spoken = spoken;

  /* ---- the built-in styles (state -> look). Glyphs, words and colours are the shipped door, lock and alarm tiles' own. */
  var REV_D = { symbol: 'arrow.uturn.down', verb: 'Reverse' }, REV_U = { symbol: 'arrow.uturn.up', verb: 'Reverse' }, STOP = { symbol: 'stop.fill', verb: 'Stop' };
  function L(title, text, icon, cls, extra) { return Object.assign({ title: title, text: text, icon: icon, cls: cls, indicator: cls === 'in-progress' ? 'arc' : 'none', action: { verb: '' } }, extra || {}); }
  ST.garage = function (t) {
    t = t || 'Garage Door';
    return {
      closed: L(t, 'Closed', 'door.garage.closed', 'resting', { action: { verb: 'Open' } }),
      sendingOpen: L(t, 'Sending Open…', 'door.garage.open', 'in-progress', { active: true, action: null }),
      opening: L(t, 'Opening', 'arrow.uturn.down', 'in-progress', { active: true, action: REV_D }),
      sendingClose: L(t, 'Sending Close…', 'door.garage.open', 'in-progress', { active: true, action: null }),
      closing: L(t, 'Closing', 'arrow.uturn.up', 'in-progress', { active: true, action: REV_U }),
      open: L(t, 'Open', 'door.garage.open', 'resting', { active: true, action: { verb: 'Close' } }),
      error: L(t, 'Error', 'door.garage.closed', 'error', { action: { verb: 'Open' } }),
      unknown: L(t, 'Unavailable', 'door.garage.closed', 'unknown', { action: null }),
    };
  };
  ST.lock = function (t) {
    t = t || 'Front Door';
    return {
      locked: L(t, 'Locked', 'lock.fill', 'resting', { action: { verb: 'Unlock' } }),
      unlocking: L(t, 'Unlocking', 'lock.open', 'in-progress', { active: true, action: null }),
      unlocked: L(t, 'Unlocked', 'lock.open', 'resting', { active: true, action: { verb: 'Lock' } }),
      open: L(t, 'Open', 'lock.open', 'warning', { action: { verb: 'Lock' } }),
      locking: L(t, 'Locking', 'lock.fill', 'in-progress', { action: null }),
      jammed: L(t, 'Jammed', 'lock.trianglebadge.exclamationmark', 'error', { action: { verb: 'Lock' } }),
      unknown: L(t, 'Unavailable', 'lock.fill', 'unknown', { action: null }),
    };
  };
  ST.blind = function (t) {
    t = t || 'Office Blind';
    return {
      closed: L(t, 'Closed', 'blinds.horizontal.closed', 'resting', { family: 'lights', action: { verb: 'Open' } }),
      opening: L(t, 'Opening', 'stop.fill', 'in-progress', { active: true, action: STOP }),
      closing: L(t, 'Closing', 'stop.fill', 'in-progress', { active: true, action: STOP }),
      open: L(t, 'Open', 'blinds.horizontal.open', 'resting', { active: true, action: { verb: 'Close' } }),
    };
  };
  ST.alarm = function (t) {
    t = t || 'Security System';
    return {
      disarmed: L(t, 'Disarmed', 'shield.lefthalf.filled', 'resting', { family: 'sec-home', action: { verb: 'Arm Home' } }),
      arming: L(t, 'Arming', 'shield.slash', 'in-progress', { family: 'sec-home', active: true, action: { symbol: 'shield.slash', verb: 'Disarm' } }),
      armed: L(t, 'Armed Home', 'shield.slash', 'resting', { family: 'sec-home', active: true, action: { verb: 'Disarm' } }),
      pending: L(t, 'Pending', 'shield.slash', 'warning', { family: 'sec-home', action: { symbol: 'shield.slash', verb: 'Disarm' } }),
      disarming: L(t, 'Disarming', 'shield.lefthalf.filled', 'in-progress', { family: 'sec-home', action: null }),
      triggered: L(t, 'Triggered', 'shield.slash', 'error', { family: 'sec-home', action: { verb: 'Disarm' } }),
    };
  };
  ST.misc = {
    battery: L('Hall Sensor', 'Battery Low', 'battery.25percent', 'warning', { action: null, behavior: 'inert' }),
    batteryOk: L('Hall Sensor', 'Normal', 'battery.25percent', 'resting', { action: null, behavior: 'inert' }),
    leak: L('Laundry Leak Sensor', 'Wet', 'drop.fill', 'error', { action: null, behavior: 'inert', family: 'water' }),
    /* The built-in Robot style: the house while docked, the robot in every other state; the discs keep Start, Pause and Resume. */
    robotDocked: L('Robot Vacuum', 'Docked', 'house', 'resting', { family: 'cleaning', action: { symbol: 'play.fill', verb: 'Start' } }),
    robotCleaning: L('Robot Vacuum', 'Cleaning', 'robotic.vacuum', 'resting', { active: true, indicator: 'breathe', family: 'cleaning', action: { symbol: 'pause.fill', verb: 'Pause' } }),
    robotPaused: L('Robot Vacuum', 'Paused', 'robotic.vacuum', 'warning', { family: 'cleaning', action: { symbol: 'play.fill', verb: 'Resume' } }),
    robotReturning: L('Robot Vacuum', 'Returning', 'robotic.vacuum', 'in-progress', { active: true, family: 'cleaning', action: null }),
    sensorOpening: L('Side Gate', 'Opening', 'door.garage.open', 'in-progress', { active: true, behavior: 'inert', action: null }),
  };
})();
