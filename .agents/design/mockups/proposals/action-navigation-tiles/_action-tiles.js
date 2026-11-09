/* Action and navigation tiles: local helper, promote to kit.
 *
 * Draws the proposal's tiles over the kit's GlassTile (every face, colour and press state is the kit's; nothing of kit.css is copied) and adds what the kit lacks:
 *   - TileActionButton (.at-disc): the 44 pt round button (scales with text to 66 pt), spinner for in-flight, glyph replace, toggle / emphasised inks;
 *   - TileActionStrip: trailing slot (vertically centred, 12 pt in) or a below row (centred under the text) plus the volume slider;
 *   - content-aware spans (AT.grid): a tile that cannot fit text + discs takes more grid tracks (the web's `content-aware` sizing, not yet in DynamicGridLayout);
 *   - the read-only face (.ui-tile.readonly: flat, no sheen or rim, no press response);
 *   - AT.set: swaps a tile to a new state in place so colours cross-fade (state token) and glyphs replace (quick token).
 * Semantic spec S (what a tile is) is separate from its drawing: AT.render(S, opt) with opt 'today' | 'A' | 'B' | 'C'. Subjects (AT.S.*) are fixture names only.
 * Maps to apple/Sources/HassDesign/GlassTile.swift (TileBehavior, TileActionButton, TileActionStrip) and the pure TileActionPlacement in architecture.md.
 */
(function () {
  var h = Mock.h, I = Mock.icon, AT = Mock.at = Mock.at || {};
  function K() { return Mock.components; }

  /* ---------------------------------------------------------------- styles */
  var css = [
    '.at-disc { --d: calc(44px * min(var(--sc, 1), 1.5)); width: var(--d); height: var(--d); border-radius: 50%; border: 0; padding: 0; flex: none; display: grid; place-items: center; cursor: pointer; position: relative; overflow: hidden; color: #fff; background: rgba(255, 255, 255, .12); font: inherit;',
    '  transition: background var(--t-state) var(--ease-state), color var(--t-state) var(--ease-state), opacity var(--t-quick) var(--ease-quick); }',
    '.at-disc .g { grid-area: 1 / 1; display: grid; place-items: center; }',
    '.at-disc .g svg { width: calc(var(--d) * .43); height: calc(var(--d) * .43); grid-area: 1 / 1; }',
    '.at-disc:active { opacity: .7; }',
    '.ui-tile.on .at-disc, .ui-tile.colored .at-disc, .ui-tile.error .at-disc { background: rgba(0, 0, 0, .18); }',
    '.ui-tile.lit .at-disc, .ui-tile.power .at-disc { background: var(--lit-ink); color: #fff; }',
    '.ui-tile .at-disc.is-on, .ui-tile .at-disc.emph { background: #fff; color: var(--fill, #333); }',
    '.ui-tile.lit .at-disc.is-on, .ui-tile.power .at-disc.is-on { background: var(--lit-ink); color: #fff; }',
    '.ui-tile.at-b:not(.on):not(.colored):not(.lit):not(.power):not(.error) .at-disc:not(.is-on):not(.emph) { background: rgba(255, 255, 255, .16); }',   /* option B resting disc on a dark tile: white 16% */
    '.ui-tile.at-carry .at-disc.pri { background: rgba(255, 255, 255, .16); color: var(--tile-glyph); }',   /* the disc carries the glyph in the off-glyph colour: measured 5.2:1 (contact) and 4.9:1 (air) against the disc, so no lift toward white is needed (>= 3:1) */
    '.ui-tile.at-carry.on .at-disc.pri, .ui-tile.at-carry.colored .at-disc.pri { background: #fff; color: var(--fill, #333); }',
    '.ui-tile.at-carry.error .at-disc.pri { background: rgba(0, 0, 0, .18); color: var(--tile-glyph); }',
    '.ui-tile.at-carry.lit .at-disc.pri, .ui-tile.at-carry.power .at-disc.pri { background: var(--lit-ink); color: #fff; }',
    '.ui-tile.at-b.unavail .at-disc.pri { background: transparent; color: var(--tile-glyph); } .ui-tile.at-b.unavail .at-disc:disabled { opacity: .5; }',   /* unavailable: glyph at 50%, no fill */
    '.ui-tile.at-b .at-disc:disabled:not([data-phase="inflight"]) { opacity: .5; }',   /* one action unavailable: the disc dims in place (glyph 50%), never disappears, nothing moves */
    '.at-disc:disabled { cursor: default; } .at-disc:disabled:not([data-phase="inflight"]) { opacity: .4; }',
    '.at-disc[data-phase="inflight"] { opacity: 1; }',
    '.at-spin { animation: at-rot .9s linear infinite; transform-origin: 50% 50%; } @keyframes at-rot { to { transform: rotate(360deg); } }',
    '.at-strip { display: flex; gap: 12px; align-items: center; }',
    '.at-wrap { flex-wrap: wrap; row-gap: 8px; }',
    '.at-below { flex: none; width: 100%; display: flex; flex-direction: column; gap: 8px; align-items: stretch; }',
    '.at-below .row { display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; }',
    '.at-b .at-vol .ico { font-size: var(--fs-body); }',
    '.at-vol { color: var(--tile-ink-2); } .at-vol .ui-sliderrow { gap: 8px; } .at-vol .ico { color: var(--tile-ink-2); font-size: var(--fs-foot); display: grid; } .at-vol .ico .ui-sym { width: 1em; height: 1em; }',
    '.at-vol .ui-slider { min-width: 0; touch-action: pan-y; cursor: ew-resize; } .at-vol .ui-slider .tr { background: rgba(255, 255, 255, .28); } .at-vol .ui-slider .fi { background: #fff; } .at-vol .ui-slider .kn { width: 22px; height: 22px; }',
    '.ui-tile.readonly::before, .ui-tile.readonly::after { display: none; } .ui-tile.readonly { cursor: default; } .ui-tile.readonly:active { opacity: 1; }',   /* option B read-only face: flat */
    '.ts-ax5 .ui-tile .acc.at-acc { align-self: flex-start; }',
    '.at-grid > * { min-width: 0; }',
    '.ui-tile.at-b .ti, .ui-tile.at-b .st { white-space: nowrap; overflow: hidden; }',   /* option B: title and state on one line at their natural width; overflow becomes a ticker */
    '.at-wrapx .ui-tile.at-b .ti, .at-wrapx .ui-tile.at-b .st { white-space: normal; overflow: visible; }',   /* Reduce Motion and accessibility sizes: no ticker, the text wraps */
    '.at-tick { display: block; overflow: hidden; white-space: nowrap; } .at-tick .tk { display: inline-block; will-change: transform; }',
    '.at-tick.over { -webkit-mask-image: linear-gradient(90deg, #000 calc(100% - 12px), transparent); mask-image: linear-gradient(90deg, #000 calc(100% - 12px), transparent); }',
    '.at-tick.over.moving { -webkit-mask-image: linear-gradient(90deg, transparent, #000 12px, #000 calc(100% - 12px), transparent); mask-image: linear-gradient(90deg, transparent, #000 12px, #000 calc(100% - 12px), transparent); }',   /* the leading fade only once the text has moved */
    '.at-cells { display: flex; flex-wrap: wrap; gap: 16px; align-items: flex-start; }',
    '.at-cell { flex: 0 1 398px; max-width: 100%; min-width: 0; }',
    '.at-sub { font: 600 12px var(--mono); opacity: .7; margin: 14px 0 6px; }',
    '.at-note { font-size: var(--fs-foot); color: var(--g-secondary-on-wallpaper, rgba(255, 255, 255, .85)); }',
    '.at-ruler { display: flex; align-items: center; gap: 8px; font: 11px var(--mono); }',
    '.at-arch pre { overflow: auto; padding: 12px 14px; border-radius: 10px; background: var(--k-code); font-size: 12.5px; line-height: 1.45; }',
    '.at-arch pre code { background: none; padding: 0; } .at-arch .at-lede { font-size: 15px; color: var(--k-fg2); }',
    '.at-rec { border-left: 4px solid var(--k-accent); background: var(--k-accent-soft); padding: 12px 16px; border-radius: 8px; }',
    '.at-q { padding: 10px 14px; border: 1px solid var(--k-line); border-radius: 10px; background: var(--k-surface); margin-bottom: 8px; }',
    '.at-cmp td.b, .at-cmp th.b { background: color-mix(in srgb, var(--k-accent) 8%, transparent); }',
  ].join('\n');
  var st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);

  var SPIN = '<svg class="ui-sym at-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="8.5" stroke-dasharray="38 16"/></svg>';

  /* ---------------------------------------------------------------- glyph replace */
  /** Replaces the single svg inside `el` (a .glyph or a disc's .g): old scales .5 and fades out while the new scales in and fades up, the system symbol replace.
   *  motion.md section 6 "Symbols" + section 7 `quick` 0.2 s; Reduce Motion keeps only the cross-fade (no scale). */
  function morph(el, html) {
    var tmp = document.createElement('span'); tmp.innerHTML = html; var nw = tmp.firstElementChild, old = el.firstElementChild;
    if (!nw) return Promise.resolve();
    if (!old) { el.appendChild(nw); return Promise.resolve(); }
    if (old.outerHTML === nw.outerHTML) return Promise.resolve();
    var rm = Mock.settings.reduceMotion, ms = Mock.anim.ms.quick();
    old.style.gridArea = nw.style.gridArea = '1 / 1'; el.appendChild(nw);
    if (!old.animate) { old.remove(); return Promise.resolve(); }
    var sc = rm ? '' : ' scale(.5)';
    old.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: sc ? 'scale(.5)' : 'none' }], { duration: ms, easing: Mock.anim.easing.quick, fill: 'forwards' });
    var a = nw.animate([{ opacity: 0, transform: sc ? 'scale(.5)' : 'none' }, { opacity: 1, transform: 'none' }], { duration: ms, easing: Mock.anim.easing.quick });
    return a.finished.then(function () { old.remove(); }, function () { old.remove(); });
  }
  AT.morph = morph;

  /* ---------------------------------------------------------------- TileActionButton */
  /** a: {id, label, symbol, tog?, on?, emph?, phase?: 'ready'|'inflight'|'disabled', onlyB?}. o: {spinner, hidden, disabled}. A toggle-styled disc shows state (solid white when on); a momentary one shows the action. */
  AT.disc = function (a, o) {
    o = o || {};
    var inflight = a.phase === 'inflight', spin = inflight && o.spinner, still = spin && Mock.settings.reduceMotion;   // Reduce Motion: a static ellipsis glyph instead of the turning spinner
    var cls = 'at-disc' + (a.tog && a.on && o.refine ? ' is-on' : '') + (a.emph ? ' emph' : '') + (a.pri ? ' pri' : '');
    var label = a.label + (a.tog ? ', ' + (a.on ? 'On' : 'Off') : '');
    var b = h('button', { type: 'button', 'aria-label': label, dataset: { id: a.id, sym: spin ? (still ? 'ellipsis-still' : 'spinner') : a.symbol, phase: a.phase || 'ready' } }, h('span.g', { html: spin ? (still ? I('ellipsis', { weight: 2.4 }) : SPIN) : I(a.symbol, { weight: 2.4 }) }));
    b.className = cls;
    if (a.phase === 'disabled' || inflight || o.disabled) b.disabled = true;
    if (a.value) b.setAttribute('aria-description', a.value);   // the label names the role (Open, Stop, Reverse), the value the state; a spinning disc keeps its label and reads "Stopping"
    if (o.hidden) { b.setAttribute('aria-hidden', 'true'); b.tabIndex = -1; }
    return b;
  };

  /** Volume row (TileVolumeSlider): speaker.fill, the kit Slider, speaker.wave.3.fill. Drag writes visually here; in the app it commits on release and uses the horizontal-pan
   *  gesture BrightnessTile uses so a vertical scroll that starts on it still scrolls the page. */
  AT.volume = function (v) {
    var row = K().Slider({ value: v == null ? .35 : v, icons: ['speaker.fill', 'speaker.wave.3.fill'], label: 'Volume' });
    var wrap = h('div.at-vol', row), s = row.querySelector('.ui-slider');
    function set(f) { f = Math.max(0, Math.min(1, f)); var p = Math.round(f * 100); s.querySelector('.fi').style.width = p + '%'; s.querySelector('.kn').style.left = p + '%'; s.setAttribute('aria-valuenow', p); }
    function at(e) { var r = s.getBoundingClientRect(); set((e.clientX - r.left) / r.width); }
    s.addEventListener('pointerdown', function (e) { e.stopPropagation(); s.setPointerCapture(e.pointerId); at(e); s.onpointermove = at; });
    s.addEventListener('pointerup', function () { s.onpointermove = null; });
    s.addEventListener('click', function (e) { e.stopPropagation(); });
    s.addEventListener('keydown', function (e) { var n = +s.getAttribute('aria-valuenow'); if (e.key === 'ArrowRight') set((n + 5) / 100); if (e.key === 'ArrowLeft') set((n - 5) / 100); });
    wrap.setVolume = set;
    return wrap;
  };

  /* ---------------------------------------------------------------- semantic specs (fixture names only) */
  function act(id, label, symbol, x) { return Object.assign({ id: id, label: label, symbol: symbol }, x || {}); }
  var S = AT.S = {};
  /** The longest fixed state text each tile can show: spans come from the title plus this, not the current state, so a live update never reflows the grid. */
  AT.MAX = { lock: "Didn't Respond", garage: 'Sending Close…', power: 'Turning On…', light: 'On at 70%', guest: 'Guests staying', fan: 'Off in 1:00:00', purifier: 'Auto • On', vacuum: 'Cleaning · 40%', remote: 'Paused · Netflix', washer: 'Running · 42 min' };
  /** A lock (Front Door, car Doors). state: locked | unlocking | unlocked | locking | jammed | noresp | unavailable. */
  S.lock = function (state, title, symbol) {
    var lockedDisc = act('lock', 'Unlock', 'lock.fill', { tog: true, on: true }), unlockedDisc = act('lock', 'Lock', 'lock.open', { tog: true, on: false });
    var m = {
      locked: { sub: 'Locked', active: false, sym: 'lock', a: lockedDisc },
      unlocking: { sub: 'Unlocking…', active: true, sym: 'lock.open', a: act('lock', 'Unlocking', 'lock.open', { tog: true, on: false, phase: 'inflight' }) },
      unlocked: { sub: 'Unlocked', active: true, sym: 'lock.open', a: unlockedDisc },
      locking: { sub: 'Locking…', active: false, sym: 'lock', a: act('lock', 'Locking', 'lock.fill', { tog: true, on: true, phase: 'inflight' }) },
      jammed: { sub: 'Jammed', error: true, sym: 'lock.open', a: Object.assign({}, unlockedDisc, { bSymbol: 'lock.trianglebadge.exclamationmark' }) },   // B: a different shape, not only red
      noresp: { sub: "Didn't Respond", error: true, sym: 'lock.open', a: unlockedDisc },
      unavailable: { sub: 'Unavailable', unavail: true, sym: 'lock', a: act('lock', 'Unlock', 'lock', { tog: true, on: false, phase: 'disabled' }) },
    }[state];
    return { id: 'lock', title: title || 'Front Door', subtitle: m.sub, symbol: symbol || m.sym, family: 'contact', active: !!m.active, error: !!m.error, unavail: !!m.unavail, kind: 'action', actions: [m.a] };
  };
  /** A garage door (Aladdin Connect, supported_features 3: open and close only, no stop, no position; live check 2026-10-26). Option B (owner 2026-10-26): ONE morphing disc, the
   *  tile body does what the disc shows. state: closed | sendingOpen | opening | open | sendingClose | closing, plus stopping | partly for an opener that supports Stop.
   *  variant: 'reverse' (default, ours: a tap while moving sends the opposite command, web garageDoorCommandForState) | 'stop' (if an opener supports Stop, not ours today).
   *  A and C keep the literal two actions (Open or Close, Stop). */
  S.garage = function (state, title, sub, variant) {
    title = title || 'Left Door'; variant = variant || 'reverse';
    var subs = { closed: 'Closed', sendingOpen: 'Sending Open…', opening: 'Opening…', stopping: 'Stopping…', open: 'Open', partly: 'Partly Open', sendingClose: 'Sending Close…', closing: 'Closing…' };
    var vals = { sendingOpen: 'Sending Open', sendingClose: 'Sending Close', stopping: 'Stopping' };
    var active = state !== 'closed';   // today's rule (SecurityTiles.swift: isActive = displayState != "closed"): filled while sending, moving or open
    var doorGlyph = (state === 'closed' || state === 'sendingOpen') ? 'door.garage.closed' : 'door.garage.open';
    var d;
    if (state === 'closed' || state === 'sendingOpen') d = act('door', 'Open ' + title, 'door.garage.closed');
    else if (state === 'open' || state === 'partly' || state === 'sendingClose') d = act('door', 'Close ' + title, 'door.garage.open');
    else if (state === 'stopping') d = act('door', 'Stop ' + title, 'stop.fill');
    else if (variant === 'stop') d = act('door', 'Stop ' + title, 'stop.fill');
    else d = act('door', 'Reverse ' + title, state === 'opening' ? 'arrow.uturn.down' : 'arrow.uturn.up');
    if (state === 'sendingOpen' || state === 'sendingClose' || state === 'stopping') d.phase = 'inflight';
    d.value = vals[state] || subs[state];
    var base = { sendingOpen: 'opening', stopping: 'opening', sendingClose: 'closing' }[state] || state, moving = base === 'opening' || base === 'closing';
    var primary = base === 'open' || state === 'partly' ? act('close', 'Close', 'arrow.down.to.line') : act('open', 'Open', 'arrow.up.to.line');
    if (moving) primary = Object.assign(act(base === 'opening' ? 'open' : 'close', base === 'opening' ? 'Opening' : 'Closing', base === 'opening' ? 'arrow.up.to.line' : 'arrow.down.to.line'), { phase: 'inflight' });
    primary.stateSymbol = doorGlyph;
    var stop = act('stop', 'Stop', 'stop.fill', moving ? {} : { phase: 'disabled' });
    return { id: 'garage', title: title, subtitle: sub || subs[state], symbol: doorGlyph, family: 'contact', active: active, kind: 'action', actions: [primary, stop], bActions: [d] };
  };
  /** HYPOTHETICAL: no two-action action tile exists in the app today; a sprinkler zone with Run and Skip stands in for the class. */
  S.sprinkler = function () {
    return { id: 'sprinkler', title: 'Front Lawn Zone', subtitle: 'Idle · next 6:00 AM', symbol: 'drop', family: 'water', active: false, kind: 'action', actions: [act('run', 'Run', 'play.fill'), act('skip', 'Skip', 'forward.fill')] };
  };
  /** A power-family toggle (Alex's PC, Towel Rack). state: off | on | turningOn. */
  S.power = function (state, title, symbol, sub) {
    var on = state === 'on' || state === 'turningOn';
    var d = act('power', on ? 'Turn Off' : 'Turn On', 'power', { tog: true, on: state === 'on', phase: state === 'turningOn' ? 'inflight' : undefined });
    return { id: 'power', title: title, subtitle: sub || { off: 'Off', on: 'On', turningOn: 'Turning On…' }[state], symbol: symbol, family: 'power', active: on, kind: 'action', actions: [d] };
  };
  /** A light with a power toggle (lit face). */
  S.light = function (on, title) {
    return { id: 'light', title: title, subtitle: on ? 'On at 70%' : 'Off', symbol: 'lightbulb', family: 'lights', active: on, progress: on ? .7 : undefined, kind: 'action', actions: [act('power', on ? 'Turn Off' : 'Turn On', 'power', { tog: true, on: on })] };
  };
  S.guest = function (on, title, symbol) {
    return { id: 'guest', title: title, subtitle: on ? 'Guests staying' : 'No guests', symbol: symbol || 'bed.double', family: 'occupancy', active: on, kind: 'action', actions: [act('guest', on ? 'Clear guests' : 'Guests staying', 'person', { tog: true, on: on })] };
  };
  /** Three custom actions (the 3+ class): a shade with Open, Stop, Close. */
  S.shade = function () {
    return { id: 'shade', title: 'Living Room Shade', subtitle: 'Open 40%', symbol: 'arrow.up.to.line', family: 'contact', active: true, kind: 'action',
      actions: [act('open', 'Open', 'arrow.up.to.line'), act('stop', 'Stop', 'stop.fill'), act('close', 'Close', 'arrow.down.to.line')] };
  };
  S.vents = function (title) { return { id: 'vents', title: title || 'Vents', subtitle: 'Open', symbol: 'aqi.medium', family: 'vents', active: true, kind: 'nav' }; };
  S.purifier = function (on) {
    return { id: 'purifier', title: 'Air Purifier', subtitle: on === false ? 'Off' : 'Auto • On', symbol: 'fan', family: 'air', active: on !== false, kind: 'nav', actions: [act('power', on === false ? 'Turn On' : 'Turn Off', 'power', { tog: true, on: on !== false })] };
  };
  /** The bathroom fan: Lock + Power. today() draws the shipped tile with its trailing rail. */
  S.fan = function (o) {
    o = o || {};
    var on = o.on !== false, locked = o.locked !== false;
    return { id: 'fan', title: o.title || 'Bathroom Fan', subtitle: o.status || (on ? 'On' : 'Off'), symbol: 'fan', family: 'air', active: on, kind: 'nav', singleLine: true,
      actions: [act('lock', 'Lock', locked ? 'lock.fill' : 'lock.open', { tog: true, on: locked }), act('power', on ? 'Turn Off' : 'Turn On', 'power', { tog: true, on: on })],
      today: function () { return Mock.dv.fanTile({ title: o.title || 'Bathroom Fan', on: on, locked: locked, status: o.status }); } };
  };
  /** A robot vacuum: Start or Pause, Dock, Locate. state: cleaning | docked */
  S.vacuum = function (state) {
    var c = state !== 'docked';
    return { id: 'vacuum', title: 'Main Floor', subtitle: c ? 'Cleaning · 40%' : 'Docked', symbol: 'robotic.vacuum', family: 'cleaning', active: c, progress: c ? .4 : undefined, kind: 'nav',
      actions: [act('startpause', c ? 'Pause' : 'Start', c ? 'pause.fill' : 'play.fill'), act('dock', 'Dock', 'house.fill', c ? {} : { phase: 'disabled' }), act('locate', 'Locate', 'location.fill')] };
  };
  /** A TV remote. state: playing | paused | off. Playing and paused show the transport and volume; off shows a Power disc in B only. */
  S.remote = function (state, title, sub, o) {
    o = o || {};
    var off = state === 'off', play = state === 'playing';
    return { id: 'remote', title: title || 'Living Room Remote', subtitle: sub || { playing: 'Playing · Streaming C', paused: 'Paused · Streaming C', off: 'Off' }[state], symbol: 'appletvremote.gen4', family: 'media', active: !off, kind: 'nav', volume: off ? null : .35,
      actions: off ? [act('power', 'Turn On', 'power', { onlyB: true })] : [act('prev', 'Previous', 'backward.fill'), act('playpause', play ? 'Pause' : 'Play', play ? 'pause.fill' : 'play.fill', { emph: true }), act('next', 'Next', 'forward.fill', o.nextDisabled ? { phase: 'disabled' } : {})], reshapes: true };
  };
  S.projector = function (on, title) {
    return { id: 'projector', title: title || 'Media Room', subtitle: on ? 'On' : 'Off', symbol: 'videoprojector', family: 'media', active: on, kind: 'nav', actions: [act('power', on ? 'Turn Off' : 'Turn On', 'power', { tog: true, on: on })] };
  };
  S.state = function (title, sub, symbol, family, active, progress) { return { id: 'state', title: title, subtitle: sub, symbol: symbol, family: family, active: !!active, progress: progress, kind: 'state' }; };
  S.washer = function (st) { return S.state('Washing Machine', st === 'off' ? 'Off' : 'Running · 42 min', 'washer', 'cleaning', st !== 'off', st === 'off' ? undefined : .55); };
  S.dryer = function () { return S.state('Dryer', 'Off', 'dryer', 'cleaning', false); };
  S.airQuality = function () { return S.state('Air Quality', 'Good · 12 µg/m³', 'aqi.medium', 'air', true); };
  S.ventSensor = function (title, sub) { return S.state(title, sub || '72° · Open 50%', 'aqi.medium', 'vents', true); };

  /* ---------------------------------------------------------------- render */
  function todayNode(S) {
    if (S.today && Mock.dv) return S.today();
    return K().GlassTile({ title: S.title, subtitle: S.subtitle, symbol: S.symbol, family: S.family, isActive: S.active, isError: S.error, isUnavailable: S.unavail, progress: S.progress,
      kind: S.kind === 'nav' ? 'navigate' : (S.kind === 'state' ? 'state' : 'command'), singleLine: S.singleLine });
  }
  /**
   * One tile for option opt ('today' | 'A' | 'B' | 'C'). o: {offline}. Rules: action tile (>= 1 action, no destination): 1 or 2 actions trail (vertically centred), 3+ go below;
   * a navigation tile keeps its chevron and any actions go below, centred. B adds the spinner, toggle-styled discs, the off-remote Power disc and the flat read-only face.
   * C draws only the single-action tile new; everything else is today's tile.
   */
  AT.render = function (S, opt, o) {
    o = o || {};
    if (opt === 'today') return todayNode(S);
    var one = S.kind === 'action' && (S.actions || []).length === 1;   // C: only the literal single-action tiles
    if (opt === 'C' && !one) return todayNode(S);
    var refine = opt !== 'A';
    var acts = ((opt === 'B' && S.bActions) ? S.bActions : (S.actions || [])).filter(function (a) { return !(a.onlyB && !refine); });
    // A: a navigation tile's actions go below. B (owner 2026-10-26): up to two actions trail beside the chevron (today's fan rail geometry); 3+ and custom controls (transport, volume) go below.
    var slot = !acts.length ? 'none' : (S.kind === 'nav' ? (opt === 'B' && acts.length <= 2 && S.volume == null ? 'trailing' : 'below') : (acts.length > 2 ? 'below' : 'trailing'));
    var carry = opt === 'B' && S.kind === 'action' && acts.length > 0;   // B: an action tile never draws a leading glyph; a trailing first disc carries the state glyph
    if (opt === 'B') acts = acts.map(function (a, i) { var m = Object.assign({}, a); if (a.bSymbol) m.symbol = a.bSymbol; if (carry && slot === 'trailing') { if (a.stateSymbol) m.symbol = a.stateSymbol; if (i === 0) m.pri = true; } return m; });
    var discOpt = { spinner: refine, refine: refine, disabled: !!o.offline };
    var props = { title: S.title, subtitle: S.subtitle, symbol: S.symbol, family: S.family, isActive: S.active, isError: S.error, isUnavailable: S.unavail, progress: S.progress, progressTint: S.progressTint,
      kind: S.kind === 'nav' ? 'navigate' : (S.kind === 'state' ? 'state' : 'command'), singleLine: S.singleLine };
    var hidden = slot === 'trailing' && acts.length === 1 && S.kind === 'action';      // single action: the tile is the one VoiceOver element, the disc repeats it
    var strip = null, below = null;
    if (slot === 'trailing') {
      strip = h('div.at-strip', acts.map(function (a) { return AT.disc(a, Object.assign({ hidden: hidden }, discOpt)); }));
      props.accessory = strip; props.accessoryWidth = 64;
    }
    var t = K().GlassTile(props);
    if (opt === 'B') t.classList.add('at-b');
    if (carry) { var gl = t.querySelector(':scope > .glyph'); if (gl) gl.remove(); t.classList.add('at-carry'); t.dataset.carry = '1'; }
    if (slot === 'trailing') {
      var n = acts.length;
      var navT = S.kind === 'nav';   // beside the chevron: the rail sits one chevron reserve (20 pt) in from the tile padding, as the fan rail does today
      t.style.setProperty('--acc-w', 'calc(' + n + ' * 44px * min(var(--sc, 1), 1.5) + ' + (n - 1) * 12 + 'px + 8px' + (navT ? ' + 20px' : '') + ')');   // the text stops 8 pt short of the discs
      t.querySelector('.acc').classList.add('at-acc'); if (navT) t.querySelector('.acc').style.right = '32px';
    }
    if (slot === 'below') {
      below = h('div.at-below', h('div.row', acts.map(function (a) { return AT.disc(a, discOpt); })), S.volume != null ? AT.volume(S.volume) : null);
      t.appendChild(below); t.classList.add('at-wrap');
    } else if (S.volume != null) { /* no volume without a below row */ }
    if (refine && S.kind === 'state') { t.classList.add('readonly'); }
    if (S.reshapes) t.dataset.reshape = '1';   // its action set changes shape (Off: Power beside the chevron; Playing: transport and volume below): only a tile that spans its whole row may do that
    t.dataset.maxState = S.maxState || AT.MAX[S.id] || '';
    if (S.singleLine && opt !== 'B') { var stEl = t.querySelector('.st'); if (stEl) { stEl.style.textOverflow = 'ellipsis'; if (stEl.textContent.length > 9) stEl.style.fontSize = 'calc(var(--fs-foot) * .85)'; } }   // tileSingleLineSubtitle: 85% before it truncates
    if (hidden) t.setAttribute('aria-description', acts[0].label);
    if (slot === 'trailing' && S.kind === 'nav') t.dataset.nav = '1';
    t.dataset.opt = opt; t.dataset.n = slot === 'trailing' ? acts.length : 0; t.dataset.bn = slot === 'below' ? acts.length : 0; t.dataset.vol = S.volume != null && slot === 'below' ? '1' : '0';
    return t;
  };

  /* ---------------------------------------------------------------- in-place update */
  /** Swaps `tile` to the fresh render of S in place: the class change cross-fades the fill (state token via the kit's registered colour slots), the glyphs replace, the text updates. Resolves after the colour settles. */
  AT.set = function (tile, S, opt, o) {
    var f = AT.render(S, opt, o), gc = tile.style.gridColumn, gr = tile.style.gridRow;
    tile.className = f.className; tile.setAttribute('style', f.getAttribute('style') || ''); tile.style.gridColumn = gc; tile.style.gridRow = gr; tile.setAttribute('aria-label', f.getAttribute('aria-label'));
    ['face', 'family'].forEach(function (k) { tile.dataset[k] = f.dataset[k]; });
    ['n', 'bn', 'vol', 'carry', 'nav', 'maxState', 'reshape'].forEach(function (k) { if (f.dataset[k] != null) tile.dataset[k] = f.dataset[k]; else delete tile.dataset[k]; });
    var a = tile.querySelector('.ti'), b = f.querySelector('.ti'); if (a && b) { a.textContent = b.textContent; delete a.dataset.full; delete a.dataset.tk; }
    a = tile.querySelector('.st'); b = f.querySelector('.st'); if (a && b) { a.textContent = b.textContent; delete a.dataset.full; delete a.dataset.tk; }
    var g = tile.querySelector(':scope > .glyph'), fg = f.querySelector(':scope > .glyph'); if (g && fg) morph(g, fg.innerHTML);
    var old = Array.prototype.slice.call(tile.querySelectorAll('.at-disc')), fresh = Array.prototype.slice.call(f.querySelectorAll('.at-disc'));
    var same = old.length === fresh.length && old.every(function (d, i) { return d.dataset.id === fresh[i].dataset.id; });
    if (same) {
      old.forEach(function (d, i) {
        var x = fresh[i]; d.className = x.className; d.disabled = x.disabled; d.setAttribute('aria-label', x.getAttribute('aria-label')); d.dataset.phase = x.dataset.phase;
        if (d.dataset.sym !== x.dataset.sym) { d.dataset.sym = x.dataset.sym; morph(d.querySelector('.g'), x.querySelector('.g').innerHTML); }
      });
      var v = f.querySelector('.at-vol'), tv = tile.querySelector('.at-vol');
      if (v && tv) { tv.querySelector('.ui-slider .fi').style.width = v.querySelector('.ui-slider .fi').style.width; }
    } else {
      ['.acc', '.at-below'].forEach(function (sel) { var o1 = tile.querySelector(':scope > ' + sel), n1 = f.querySelector(':scope > ' + sel); if (o1 && n1) o1.replaceWith(n1); else if (o1) o1.remove(); else if (n1) tile.appendChild(n1); });
    }
    AT.fit(tile);
    return Mock.sleep(Mock.anim.ms.state() + 30);
  };
  /** True while the page is scrolling (a layout change waits for it to stop). */
  function scrolling(tile) { var sc = tile.closest('.ui-scroll'); if (!sc) return false; if (!sc._atScr) { sc._atScr = { on: false, t: 0 }; sc.addEventListener('scroll', function () { sc._atScr.on = true; clearTimeout(sc._atScr.t); sc._atScr.t = setTimeout(function () { sc._atScr.on = false; }, 150); }); } return sc._atScr.on; }
  function fadeIn(el, ms) { if (!el || !el.animate) return Promise.resolve(); el.style.opacity = ''; return el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: ms, easing: Mock.anim.easing.quick }).finished.catch(function () {}); }
  /** The action SET changes shape (owner-approved exception to motion.md section 6, 2026-10-26; guard rails: only a tile already spanning its full row, so content below shifts down and nothing
   *  reflows sideways; a change arriving while the page scrolls waits; o.instant (reconnect, cold launch from the snapshot) applies with no animation). Collapse: departing discs fade (quick 0.2 s),
   *  then the height animates (standard 0.3 s, no bounce), the arriving disc fades in. Expand: swap, height animates, arriving discs fade in after. Reduce Motion: no height animation, a 0.2 s cross-fade. */
  AT.reshape = function (tile, S, opt, o) {
    o = o || {};
    if (o.instant) return AT.set(tile, S, opt, o);
    var rm = !!Mock.settings.reduceMotion;
    function go() {
      var H0 = tile.offsetHeight, oldBelow = tile.querySelector(':scope > .at-below'), pre = Promise.resolve();
      if (oldBelow && !rm && oldBelow.animate) pre = oldBelow.animate([{ opacity: 1 }, { opacity: 0 }], { duration: Mock.anim.ms.quick(), easing: Mock.anim.easing.quick, fill: 'forwards' }).finished.catch(function () {});
      return pre.then(function () {
        tile.style.height = ''; var done = AT.set(tile, S, opt, o);
        var nb = tile.querySelector(':scope > .at-below'), na = tile.querySelector(':scope > .acc'), arrive = nb || na;
        if (arrive) arrive.style.opacity = 0;
        var H1 = tile.offsetHeight;
        var grow = Promise.resolve();
        if (!rm && tile.animate && H1 !== H0) grow = tile.animate([{ height: H0 + 'px' }, { height: H1 + 'px' }], { duration: Mock.anim.ms.standard(), easing: Mock.anim.easing.standard }).finished.catch(function () {});
        return grow.then(function () { return fadeIn(arrive, rm ? Mock.anim.ms.quick() : Mock.anim.ms.quick()); }).then(function () { return done; });
      });
    }
    return new Promise(function (res) { (function wait() { if (scrolling(tile)) setTimeout(wait, 100); else go().then(res); })(); });
  };
  /** The tile titled `title` inside a device stage. */
  AT.find = function (stage, title) {
    return Array.prototype.slice.call(stage.querySelectorAll('.ui-tile')).filter(function (x) { var t = x.querySelector('.ti'); return t && t.textContent === title; })[0];
  };

  /* ---------------------------------------------------------------- content-aware grid */
  /* ---------------------------------------------------------------- ticker (TickerLabel stand-in) */
  /** One overflowing line becomes a ticker (patterns/ticker.md, motion.md section 9 exception): hold 1.5 s, travel 30 pt/s, hold 1.5 s, return 0.3 s, three passes, 12 pt soft edge fades
   *  (the leading one only once the text has moved); hidden from VoiceOver (the tile's label speaks the full text); pauses while the page scrolls. Kit A.ticker is the weather card's
   *  (16 pt inset, no pause), so this tile version is local. */
  function fitText(el, wrap) {
    if (!el) return;
    if (el.dataset.full == null) el.dataset.full = el.textContent;
    var full = el.dataset.full, key = full + '|' + Math.round(el.clientWidth) + '|' + (wrap ? 1 : 0);
    if (el.dataset.tk === key) return;
    var old = el.querySelector('.at-tick'); if (old) { if (old._a) old._a.cancel(); el.textContent = full; }
    el.dataset.tk = key;
    if (wrap) return;
    if (el.scrollWidth - el.clientWidth <= 1) return;
    var tk = h('span.tk', full), box = h('span.at-tick', { 'aria-hidden': 'true' }, tk);
    el.textContent = ''; el.appendChild(box);
    var over = tk.offsetWidth - box.clientWidth; if (over <= 1 || !tk.animate) { el.textContent = full; return; }
    box.classList.add('over'); el.dataset.tk = key;
    var shift = over + 12, hold = 1500, rt = shift / 30 * 1000, ret = 300, total = 2 * hold + rt + ret;
    box._a = tk.animate([{ transform: 'translateX(0)', offset: 0 }, { transform: 'translateX(0)', offset: hold / total }, { transform: 'translateX(' + (-shift) + 'px)', offset: (hold + rt) / total },
      { transform: 'translateX(' + (-shift) + 'px)', offset: (2 * hold + rt) / total }, { transform: 'translateX(0)', offset: 1 }], { duration: total, iterations: 3, easing: 'linear' });
    setTimeout(function () { box.classList.add('moving'); }, hold);
    box._a.onfinish = function () { box.classList.remove('moving'); };
    var sc = box.closest('.ui-scroll');
    if (sc && !sc._atTick) { sc._atTick = 1; sc.addEventListener('scroll', function () { var bs = sc.querySelectorAll('.at-tick.over'); bs.forEach(function (b) { if (b._a) b._a.pause(); }); clearTimeout(sc._atT); sc._atT = setTimeout(function () { bs.forEach(function (b) { if (b._a) b._a.play(); }); }, 180); }); }
  }
  /** Title and state of a B tile: ticker when the line overflows (and the tile cannot widen), wrap under Reduce Motion or accessibility sizes. */
  AT.fit = function (tile, wrap) {
    if (tile.dataset.opt !== 'B') return;
    if (wrap == null) wrap = !!Mock.settings.reduceMotion || (parseFloat(getComputedStyle(tile).getPropertyValue('--sc')) || 1) > 1.5;
    fitText(tile.querySelector('.ti'), wrap); fitText(tile.querySelector('.st'), wrap);
  };
  /** Restart every ticker in a stage (for a motion Play). Resolves after the first pass of the longest one. */
  AT.replayTickers = function (stage) {
    var boxes = Array.prototype.slice.call(stage.querySelectorAll('.at-tick.over')), ms = 0;
    boxes.forEach(function (b) { if (b._a) { b._a.currentTime = 0; b._a.play(); ms = Math.max(ms, b._a.effect.getTiming().duration); } });
    return Mock.sleep(Math.min(ms, 9000));
  };

  /* ---------------------------------------------------------------- content-aware grid */
  /** TileGrid whose children take as many tracks as they need (the web's content-aware sizing; DynamicGridLayout has none yet, see architecture.md "Grid").
   *  Option B measures each tile on ONE line at the natural width of its title and of the longest state it can show (AT.MAX, not the current state, so a live update never
   *  reflows the grid): need = padding + glyph column (none on an action tile) + text + 8 + trailing discs + chevron reserve; tracks = ceil(need / track), capped at the row (or, with
   *  a hinge, at that side of the fold). Rows are packed first-fit like the web's fillRows (a widened tile may move a later short tile up into a gap; otherwise page order); a span
   *  never crosses the hinge band. A and C keep the earlier fixed estimate (96 pt text minimum) and CSS auto placement.
   *  o: {compact?: boolean (default from ctx), max} */
  AT.grid = function (nodes, ctx, o) {
    o = o || {};
    var g = K().TileGrid({ items: nodes, min: 150, max: o.max || 6, equal: false });
    g.classList.add('at-grid');
    function natural(t, el, text) {
      if (!el) return 0;
      var m = document.createElement('span'); m.className = el.className; m.textContent = text; m.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap;overflow:visible;font-size:' + (el.style.fontSize || '');
      t.querySelector('.tx').appendChild(m); var w = m.offsetWidth; m.remove(); return w;
    }
    function spans() {
      var w = g.clientWidth; if (!w) return;
      var gap = 12, sc = parseFloat(getComputedStyle(g).getPropertyValue('--sc')) || 1;
      var cols = Math.max(1, Math.min(o.max || 6, Math.floor((w + gap) / (Math.min(w, 150 * sc) + gap))));
      var screen = g.closest('.screen'), hinge = !!(screen && screen.dataset.hinge);
      if (hinge && cols >= 2 && cols % 2) cols -= 1;
      var seg = hinge && cols >= 2 ? cols / 2 : cols;   // tracks on one side of the fold
      var track = (w - gap * (cols - 1)) / cols;
      var compact = o.compact != null ? o.compact : !!(ctx || Mock.current || {}).compact;
      var D = 44 * Math.min(sc, 1.5), wrap = !!Mock.settings.reduceMotion || sc > 1.5;
      g.classList.toggle('at-wrapx', wrap);
      var kids = Array.prototype.slice.call(g.children), anyB = kids.some(function (t) { return t.dataset.opt === 'B'; }), ks = [];
      kids.forEach(function (t) {
        if (!t.dataset.opt) { ks.push(1); return; }   // today's tiles keep their own placement
        var n = +t.dataset.n || 0, bn = +t.dataset.bn || 0, need = 0, k;
        if (t.dataset.opt === 'B') {
          var ti = t.querySelector('.ti'), st = t.querySelector('.st'), tw = natural(t, ti, ti.dataset.full != null ? ti.dataset.full : ti.textContent);
          if (st) tw = Math.max(tw, natural(t, st, st.dataset.full != null ? st.dataset.full : st.textContent), t.dataset.maxState ? natural(t, st, t.dataset.maxState) : 0);
          var nav = t.classList.contains('navigate'), lead = 24 + (t.classList.contains('at-carry') ? 0 : 42);
          var disc = n ? n * D + (n - 1) * 12 : 0, trail = n ? 8 + disc + (nav ? 20 : 0) : (nav ? 20 : 0);
          need = lead + tw + trail;
          var bw = bn ? bn * D + (bn - 1) * 12 : 0; if (t.dataset.vol === '1') bw = Math.max(bw, 120 + 2 * (17 * sc + 8));
          if (bw) need = Math.max(need, 24 + bw);
          k = Math.min(seg, Math.max(1, Math.ceil((need + gap) / (track + gap))));
          if ((compact && bn) || t.dataset.reshape) k = seg;
          t.dataset.need = Math.round(need); t.dataset.span = k;
        } else {
          if (n) need = (t.dataset.carry ? 24 + 8 : (t.dataset.nav ? 94 : 74)) + 96 * sc + n * D + (n - 1) * 12;
          var bw2 = bn ? bn * D + (bn - 1) * 12 : 0; if (t.dataset.vol === '1') bw2 = Math.max(bw2, 120 + 2 * (17 * sc + 8));
          if (bw2) need = Math.max(need, 24 + bw2, 66 + 96 * sc + 20);
          k = need ? Math.min(cols, Math.max(1, Math.ceil((need + gap) / (track + gap)))) : 1;
          if (compact && t.dataset.opt === 'B' && bn) k = cols;
        }
        ks.push(k);
      });
      if (anyB) {
        var occ = []; function free(r, c) { return !(occ[r] && occ[r][c]); }
        kids.forEach(function (t, i) {
          if (!t.dataset.opt) return;
          var k = ks[i], placed = false;
          for (var r = 0; !placed; r++) for (var c = 0; c + k <= cols && !placed; c++) {
            if (hinge && Math.floor(c / seg) !== Math.floor((c + k - 1) / seg)) continue;   // never across the band
            var ok = true; for (var x = c; x < c + k; x++) if (!free(r, x)) ok = false;
            if (!ok) continue;
            for (x = c; x < c + k; x++) { (occ[r] = occ[r] || [])[x] = 1; }
            t.style.gridColumn = (c + 1) + ' / span ' + k; t.style.gridRow = String(r + 1); placed = true;
          }
        });
      } else {
        kids.forEach(function (t, i) { if (t.dataset.opt) t.style.gridColumn = ks[i] > 1 ? 'span ' + ks[i] : ''; });
      }
      kids.forEach(function (t) { AT.fit(t, wrap); });
    }
    AT.refit = spans;
    [60, 400, 1200].forEach(function (ms) { setTimeout(spans, ms); });   // first layout (a page built off screen or in a hidden pane may not deliver an observation)
    if (window.ResizeObserver) new ResizeObserver(function () { setTimeout(spans, 0); }).observe(g);   // after the observer callback, so writing spans never feeds the observer in the same frame
    return g;
  };

  /* ---------------------------------------------------------------- page helpers */
  AT.sec = function (title, node, detail) { return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '12px', minWidth: 0 } }, K().PageSectionHeader({ title: title, detail: detail }), node); };
  /** A page of sections: secs = [[title, [S...] , {detail}]] drawn for option opt. */
  AT.tiles = function (ctx, list, opt, o) { return AT.grid(list.map(function (s) { return AT.render(s, opt, o); }), ctx); };
  AT.page = function (ctx, o) {
    // Regular width lays sections side by side as room pages do (patterns/dynamic-grid.md "Sections side by side count as columns": 340 pt columns, max 2, Media 3).
    var cols = o.cols || 2, wrap = ctx.regular && o.split !== false && o.sections.length > 1
      ? h('div', { style: { display: 'grid', gap: '24px', alignItems: 'start', gridTemplateColumns: 'repeat(auto-fill, minmax(max(340px, calc((100% - ' + 24 * (cols - 1) + 'px) / ' + cols + ')), 1fr))' } }, o.sections)
      : h('div', { style: { display: 'flex', flexDirection: 'column', gap: '24px' } }, o.sections);
    return Mock.page(ctx, Object.assign({ title: o.title, section: o.section || 'home', back: o.back, badge: 3, choresBadge: 2, body: [wrap], bottomPad: 32 }, o.page));
  };
  AT.note = function (text) { return h('p.at-note', text); };
  /** Today | A | B | C cells for the options section: each is a dark page swatch holding the same tiles at phone width in a two-column grid. */
  AT.cells = function (label, build) {
    var wrap = h('div.at-cells');
    [['today', 'Today'], ['A', 'A · Owner\'s rules'], ['B', 'B · Rules + refinements (recommended)'], ['C', 'C · Minimal']].forEach(function (c) {
      var box = h('div.k-swatch.page.g-dark.at-cell', { style: { '--sc': 1 } }, h('div.k-cap', c[1]), h('div.in', build(c[0])));
      wrap.appendChild(box);
    });
    return h('div', h('h3', label), wrap);
  };
})();
