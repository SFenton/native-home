/* Local helper for the devices-vacuums batch: the room-device sheets (bathroom fan, air quality, grill, humidifier) and the pieces the
 * Vacuums mockups share (action sheet, swatches, extra glyphs). Loaded with <script src> after kit.js; defines Mock.dv.
 * Everything here is a STAND-IN for a SwiftUI view in apple/Sources/HassUI/Features/RoomDevices (named in each header).
 * Promote to kit: dv.section (DeviceSection), dv.lengthRow (FanTimerLengthRow), dv.timerRunning (FanTimerRunning), dv.tintedCapsule
 * (TintedCapsuleButtonStyle), dv.dial (single-value ThermostatDial with DialValueStyle trails), dv.statusPill (DeviceStatusPill), dv.stepper,
 * dv.actionSheet (confirmationDialog), dv.swatches (component mockups without a registered kit component).
 */
(function () {
  var h = Mock.h, I = Mock.icon, K = function () { return Mock.components; };
  var dv = Mock.dv = Mock.dv || {};

  /* ---------------------------------------------------------------- extra glyphs (kit symbols.js lacks them; added to Mock.symbols locally) */
  (function () {
    function p(d) { return '<path d="' + d + '"/>'; }
    function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
    function rc(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
    var S = Mock.symbols;
    function add(name, outline, filled) { if (!S[name]) S[name] = filled ? [outline, filled] : [outline]; }
    function battery(level) { return rc(2.5, 7.5, 17, 9, 2.5) + p('M21.5 10.5v3') + (level ? '<rect x="4.5" y="9.5" width="' + (level * 11 / 100) + '" height="5" rx="1" fill="currentColor" stroke="none"/>' : ''); }
    add('battery.0percent', battery(0)); add('battery.25percent', battery(28)); add('battery.50percent', battery(55)); add('battery.100percent', battery(100));
    add('ev.charger', rc(5, 4.5, 9, 15.5, 1.8) + p('M3.5 20.5h12M14 9h2.2a1.8 1.8 0 0 1 1.8 1.8v4.4a1.5 1.5 0 0 0 3 0V9l-2.2-2.2M8.2 8.5 7 12.2h2.8L8.6 16'));
    add('clock.arrow.circlepath', c(12, 12, 8.4) + p('M12 7.6V12l3 1.8M3.6 4.8v3.4H7'), c(12, 12, 8.4) + p('M12 7.6V12l3 1.8M3.6 4.8v3.4H7'));
    add('scope', c(12, 12, 6.2) + c(12, 12, 1.6) + p('M12 2.8v3M12 18.2v3M2.8 12h3M18.2 12h3'));
    add('arrow.up.left.and.arrow.down.right', p('M14.5 3.5h6v6M20.5 3.5l-7 7M9.5 20.5h-6v-6M3.5 20.5l7-7'));
    add('trash.circle', c(12, 12, 8.8) + p('M8.6 9.4h6.8M10.2 9.4V8.2h3.6v1.2M9.4 9.4l.5 6.2h4.2l.5-6.2'));
    add('pause.circle', c(12, 12, 8.8) + p('M10 8.8v6.4M14 8.8v6.4'));
    add('drop.triangle', p('M12 3.6c3.4 4.1 5.6 7 5.6 10.1a5.6 5.6 0 0 1-11.2 0c0-3.1 2.2-6 5.6-10.1z') + p('M12 12.2v3M12 17.5v.1'));
    add('paintbrush.pointed', p('M19.5 4.5 11 13M8.5 14a3 3 0 0 0-3 3c0 1.5-.8 2.5-2 3 3.5.8 7-1 7-4.2z'));
    add('circle.circle', c(12, 12, 8.6) + c(12, 12, 3.4));
    add('dot.radiowaves.left.and.right', c(12, 12, 1.8) + p('M8.4 8.4a5 5 0 0 0 0 7.2M15.6 8.4a5 5 0 0 1 0 7.2M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8'));
    function gauge(frac) { var a = (135 + frac * 270) * Math.PI / 180; return p('M5.6 18.4A9 9 0 1 1 18.4 18.4') + p('M12 12 L' + (12 + 5.6 * Math.cos(a)).toFixed(2) + ' ' + (12 + 5.6 * Math.sin(a)).toFixed(2)) + c(12, 12, 1); }
    add('gauge.with.dots.needle.33percent', gauge(.33)); add('gauge.with.dots.needle.67percent', gauge(.67)); add('gauge.with.dots.needle.100percent', gauge(1));
    add('minus', p('M5.5 12h13')); add('plus', p('M12 5.5v13M5.5 12h13'));
    add('thermometer.high', p('M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z') + p('M12 6.5v9'));
    add('xmark.circle', c(12, 12, 8.8) + p('M9 9l6 6M15 9l-6 6'));
    add('stop.fill', '<rect x="6" y="6" width="12" height="12" rx="2.4"/>');
    add('speaker.slash', p('M4 9.5h3.2L12 5.5v13l-4.8-4H4zM15.5 9.5l5 5M20.5 9.5l-5 5'));
    add('testtube.2', p('M9 3.5h4M10 3.5V16a3 3 0 1 0 6 0V3.5M6 8l-1.5 8.5a3 3 0 0 0 5 2'));
  })();

  /* ---------------------------------------------------------------- styles (.dv-*), tokens only through the kit's custom properties */
  var css = [
    '.in-sheet.g-dark { --dv-sel: #fff; --dv-sel-ink: #000; --ink-timer: #FF9F0A; --dv-blue: #0071E3; }',
    '.in-sheet.g-light { --dv-sel: #1C1C1E; --dv-sel-ink: #fff; --ink-timer: #B35C00; --dv-blue: #0071E3; }',
    '.dv-stack { display: flex; flex-direction: column; gap: 24px; min-width: 0; }',
    '.dv-col { width: 100%; margin: 0 auto; min-width: 0; }',
    '.dv-sec { display: flex; flex-direction: column; gap: 12px; min-width: 0; }',
    '.dv-foot { margin: 0; font-size: var(--fs-foot); color: var(--ink-sheet-2); }',
    '.dv-sub { font-size: var(--fs-sub); color: var(--ink-sheet-2); margin: 0; }',
    /* FanTimerLengthRow */
    '.dv-lenrow { display: flex; gap: 2px; padding: 2px; border-radius: 12px; background: var(--sheet-cell); }',
    '.dv-lenrow button { flex: 1; min-width: 0; min-height: 44px; border: 0; border-radius: 10px; background: none; color: var(--ink); font: 400 var(--fs-sub)/1.2 var(--font); font-variant-numeric: tabular-nums; white-space: nowrap; cursor: pointer; }',
    '.dv-lenrow button.sel { background: var(--dv-sel); color: var(--dv-sel-ink); font-weight: 600; }',
    '.ts-ax5 .dv-lenrow, .ts-ax5 .k-swatch .dv-lenrow { display: grid; grid-template-columns: repeat(3, 1fr); }',
    /* FanTimerRunning */
    '.dv-run { --k: 1; display: flex; flex-direction: column; gap: 12px; }',
    '.ts-xxxl .dv-run { --k: 1.18; } .ts-ax5 .dv-run { --k: 1.76; }',
    '.dv-run .cd { display: flex; align-items: center; gap: 12px; color: var(--ink-timer); min-width: 0; }',
    '.dv-run .cd svg { width: calc(40px * var(--k)); height: calc(40px * var(--k)); flex: none; }',
    '.dv-run { container-type: inline-size; }',
    /* minimumScaleFactor 0.5: shrink to fit the row, never below half */
    '.dv-run .cd .t { font: 600 max(calc(20px * var(--k)), min(calc(40px * var(--k)), calc((100cqw - 40px * var(--k) - 12px) / var(--ch, 3))))/1.3 ui-monospace, "SF Mono", Menlo, monospace; white-space: nowrap; min-width: 0; overflow: hidden; font-variant-numeric: tabular-nums; }',
    '.dv-bar { height: 6px; border-radius: 3px; background: color-mix(in srgb, var(--ink-timer) 22%, transparent); overflow: hidden; }',
    '.dv-bar i { display: block; height: 100%; border-radius: 3px; background: var(--ink-timer); }',
    /* TintedCapsuleButtonStyle */
    '.dv-tint { display: flex; align-items: center; justify-content: center; width: 100%; min-height: 44px; padding: 8px 24px; border: 0; border-radius: 999px; font: 600 var(--fs-body)/1.25 var(--font); text-align: center; cursor: pointer;',
    '  color: var(--ink-danger); background: color-mix(in srgb, var(--ink-danger) 16%, transparent); }',
    '.g-light .dv-tint { background: color-mix(in srgb, var(--ink-danger) 8%, transparent); }',
    '.dv-tint[disabled] { opacity: .4; cursor: default; }',
    /* grey bordered capsule (humidifier power) and bordered destructive button */
    '.dv-bordered { display: inline-flex; align-items: center; justify-content: center; gap: 8px; min-width: 140px; min-height: 44px; padding: 8px 24px; border: 0; border-radius: 999px; background: var(--fill-tertiary); color: var(--ink); font: 600 var(--fs-body)/1.25 var(--font); cursor: pointer; }',
    '.dv-bordered[disabled] { opacity: .4; cursor: default; }',
    '.dv-bordered.block { display: flex; width: 100%; border-radius: 12px; }',
    '.dv-bordered.danger { color: var(--ink-danger); }',
    /* sheet cell cards, rows, pills */
    '.dv-card { background: var(--sheet-cell); border-radius: var(--radius-tile); padding: 12px; min-width: 0; }',
    '.dv-switchrow { display: flex; align-items: center; gap: 12px; min-height: 44px; color: var(--ink); font-size: var(--fs-body); }',
    '.dv-switchrow .lb { flex: 1; min-width: 0; display: flex; align-items: center; gap: 10px; } .dv-switchrow .lb svg { color: var(--ink-sheet-2); width: 1.1em; height: 1.1em; flex: none; }',
    '.dv-switchrow .tt { font-weight: 600; } .dv-switchrow .sb { display: block; font-size: var(--fs-foot); color: var(--ink-sheet-2); font-weight: 400; }',
    '.dv-switchrow .ui-toggle[disabled] { opacity: .4; }',
    '.dv-act { display: flex; align-items: center; gap: 12px; width: 100%; min-height: 44px; padding: 12px; border: 0; border-radius: var(--radius-tile); background: var(--sheet-cell); color: var(--ink); font: inherit; text-align: left; cursor: pointer; }',
    '.dv-act.run { box-shadow: inset 0 0 0 1px var(--fam-water-glyph); }',
    '.dv-act .tx { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; } .dv-act .a { font-size: var(--fs-body); font-weight: 600; } .dv-act .b { font-size: var(--fs-sub); color: var(--ink-sheet-2); } .dv-act .c { font-size: var(--fs-foot); color: var(--ink-sheet-2); } .dv-act.run .c { color: var(--fam-water-glyph); } .g-light .dv-act.run .c { color: var(--fam-water-glyph-light); }',
    '.dv-act .chev { color: var(--ink-sheet-2); opacity: .7; font-size: var(--fs-foot); } .dv-act[disabled] { cursor: default; }',
    '.dv-pill { display: flex; align-items: center; gap: 8px; padding: 12px; min-height: 44px; border-radius: var(--radius-tile); background: var(--sheet-cell); color: var(--ink); min-width: 0; }',
    '.dv-pill .ico { width: 24px; flex: none; display: grid; place-items: center; color: var(--pt, var(--ink-sheet-2)); transition: color var(--t-state) var(--ease-state); }',
    '.dv-pill .tx { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; } .dv-pill .la { font-size: var(--fs-c1); color: var(--ink-sheet-2); } .dv-pill .va { font-size: var(--fs-sub); font-weight: 600; font-variant-numeric: tabular-nums; }',
    '.ts-ax5 .dv-pill { flex-direction: column; align-items: flex-start; }',
    '.dv-pills { display: grid; gap: 12px; grid-template-columns: repeat(auto-fill, minmax(calc(150px * var(--sc)), 1fr)); }',
    '.dv-pills.two { grid-template-columns: repeat(2, minmax(0, 1fr)); } .ts-ax5 .dv-pills.two { grid-template-columns: 1fr; }',
    '.dv-days { display: grid; gap: 8px; grid-template-columns: repeat(7, minmax(0, 1fr)); } .ts-ax5 .dv-days, .ts-xxxl .dv-days { grid-template-columns: repeat(2, minmax(0, 1fr)); }',
    '.dv-days button { min-height: 44px; border: 0; border-radius: 10px; background: var(--fill-tertiary); color: var(--ink); font: 500 var(--fs-sub)/1.2 var(--font); cursor: pointer; }',
    '.dv-days button.sel { background: var(--dv-blue); color: #fff; font-weight: 600; }',
    '.dv-field { min-height: 44px; display: flex; align-items: center; padding: 8px 12px; border-radius: 10px; background: var(--sheet-cell); color: var(--ink); font-size: var(--fs-body); box-shadow: inset 0 0 0 .5px var(--sep); }',
    '.dv-pickrow { display: flex; align-items: center; justify-content: space-between; gap: 12px; min-height: 44px; color: var(--ink); font-size: var(--fs-body); flex-wrap: wrap; }',
    '.dv-pickrow .v { background: var(--fill-tertiary); border-radius: 8px; padding: 6px 12px; font-variant-numeric: tabular-nums; }',
    '.dv-menu { display: inline-flex; align-items: center; gap: 6px; color: var(--ink-action); }',
    '.dv-stepper { display: flex; align-items: center; gap: 12px; min-height: 44px; color: var(--ink); font-size: var(--fs-body); flex-wrap: wrap; }',
    '.dv-stepper .lb { flex: 1; min-width: 0; display: flex; justify-content: space-between; gap: 12px; } .dv-stepper .lb .v { color: var(--ink-sheet-2); font-variant-numeric: tabular-nums; }',
    '.dv-stepper .pm { display: flex; border-radius: 9px; background: var(--fill-tertiary); overflow: hidden; } .dv-stepper .pm button { width: 47px; min-height: 44px; border: 0; background: none; color: var(--ink); display: grid; place-items: center; cursor: pointer; } .dv-stepper .pm button + button { border-left: .5px solid var(--sep); }',
    '.dv-stepper .pm button[disabled] { opacity: .35; }',
    /* the dial */
    '.dv-dialwrap { display: flex; justify-content: center; }',
    '.dv-dial { position: relative; display: block; flex: none; } .dv-dial svg { display: block; width: 100%; height: 100%; overflow: visible; }',
    '.dv-dial .mid { position: absolute; left: 19%; right: 19%; top: 19%; bottom: 19%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; text-align: center; pointer-events: none; }',
    '.dv-dial .act { font-size: var(--fs-sub); font-weight: 700; color: var(--ink-sheet-2); line-height: 1.15; }',
    '.dv-dial .big { font: 300 calc(var(--d, 300px) * .22)/1.05 var(--font-d); font-variant-numeric: tabular-nums; color: var(--ink); white-space: nowrap; } .dv-dial .big sup { font-size: .32em; font-weight: 700; vertical-align: top; position: relative; top: .35em; margin-left: 2px; }',
    '.dv-dial .cap { font-size: var(--fs-foot); font-weight: 700; color: var(--ink-sheet-2); font-variant-numeric: tabular-nums; line-height: 1.2; }',
    '.dv-dial.inactive svg { opacity: .45; filter: saturate(0); }',
    '.ts-ax5 .dv-dial .act, .ts-ax5 .dv-dial .cap { font-size: calc(var(--d, 300px) * .075); } .ts-ax5 .dv-dial .big { font-size: calc(var(--d, 300px) * .2); }',
    /* hero and two columns */
    '.dv-hero { display: flex; flex-direction: column; align-items: center; gap: 16px; min-width: 0; } .dv-hero .hint { margin: 0; text-align: center; font-size: var(--fs-foot); color: var(--ink-sheet-2); }',
    '.dv-two { display: flex; align-items: flex-start; } .dv-two > div { flex: 1 1 0; min-width: 0; padding: 0 16px; }',
    /* the grill header */
    '.dv-grillhead { display: flex; align-items: center; gap: 12px; } .dv-grillhead .c { width: 44px; height: 44px; border-radius: 50%; display: grid; place-items: center; flex: none; font-size: 1.35em; background: var(--sheet-cell); color: var(--ink-sheet-2); transition: background-color var(--t-state) var(--ease-state), color var(--t-state) var(--ease-state); }',
    '.dv-grillhead .c.on { background: var(--fam-cooking-fill); color: #fff; } .dv-grillhead .ti { font: 600 var(--fs-hd)/1.2 var(--font); color: var(--ink); display: block; } .dv-grillhead .su { font-size: var(--fs-sub); color: var(--ink-sheet-2); display: block; }',
    /* FanRailButton */
    '.dv-rail { display: flex; gap: 8px; } .dv-rail button { width: calc(44px * min(var(--sc), 1.5)); height: calc(44px * min(var(--sc), 1.5)); border-radius: 50%; border: 0; padding: 0; display: grid; place-items: center; cursor: pointer; flex: none;',
    '  background: rgba(255, 255, 255, .12); color: #fff; transition: background-color var(--t-state) var(--ease-state), color var(--t-state) var(--ease-state); }',
    '.dv-rail button svg { width: calc(18px * min(var(--sc), 1.2)); height: calc(18px * min(var(--sc), 1.2)); }',
    '.dv-rail.lit button { background: rgba(0, 0, 0, .18); } .dv-rail button.on { background: #fff; color: #006E62; }',
    /* confirmationDialog drawn as the iPhone action sheet */
    '.dv-asheet { align-self: end; justify-self: center; width: calc(100% - 16px); margin-bottom: 12px; display: flex; flex-direction: column; gap: 8px; }',
    '.dv-asheet .g { border-radius: 26px; overflow: hidden; background: rgba(44, 44, 46, .96); color: #fff; text-align: center; } .g-light .dv-asheet .g { background: rgba(250, 250, 252, .96); color: #000; }',
    '.dv-asheet .hd { padding: 14px 16px; font-size: var(--fs-foot); color: rgba(235, 235, 245, .6); } .g-light .dv-asheet .hd { color: rgba(60, 60, 67, .76); }',
    '.dv-asheet .hd b { display: block; font-weight: 600; font-size: var(--fs-sub); color: inherit; } .dv-asheet .hd span { display: block; margin-top: 4px; }',
    '.dv-asheet button { display: block; width: 100%; min-height: 56px; border: 0; border-top: .5px solid rgba(128, 128, 128, .4); background: none; font: 400 var(--fs-hd)/1.2 var(--font); color: #0A84FF; cursor: pointer; padding: 8px; }',
    '.g-light .dv-asheet button { color: #0066CC; } .dv-asheet button.destructive { color: #FF6961; } .g-light .dv-asheet button.destructive { color: #C21717; } .dv-asheet .cancel { font-weight: 600; border-radius: 26px; border: 0; background: rgba(44, 44, 46, .96); } .g-light .dv-asheet .cancel { background: rgba(250, 250, 252, .96); }',
    '.regular .dv-asheet { align-self: center; width: 270px; margin: 0; } ',
    /* trimmed presenter page tile groups */
    '.dv-foot, .dv-sub, .dv-switchrow, .dv-act, .dv-pill, .dv-hero .hint, .in-sheet .ui-inline-alert { overflow-wrap: anywhere; min-width: 0; }',
    '.dv-switchrow { min-width: 0; } .dv-switchrow .lb > span:last-child { min-width: 0; }',
    '.ui-tile .ti, .ui-tile .st { overflow-wrap: anywhere; }',
    '.dv-note { font: 12px var(--font); opacity: .72; margin: 8px 0 0; }',
  ].join('\n');
  var st = document.getElementById('dv-style');
  if (!st) { st = document.createElement('style'); st.id = 'dv-style'; document.head.appendChild(st); }
  st.textContent = css;

  /* ---------------------------------------------------------------- small builders */
  /** Flip a kit GlassTile between its off and on faces (the state colour cross-fades in kit.css), and change its subtitle. */
  dv.setTile = function (tile, on, subtitle, symbol) {
    tile.classList.toggle('on', !!on); tile.classList.toggle('off', !on); tile.dataset.face = on ? 'on' : 'off';
    if (tile.hasAttribute('aria-pressed')) tile.setAttribute('aria-pressed', on ? 'true' : 'false');
    var st = tile.querySelector('.st'); if (st && subtitle != null) st.textContent = subtitle;
    if (symbol) { var g = tile.querySelector('.glyph'); if (g) g.innerHTML = I(symbol, { fill: !!on }); }
  };
  /** DeviceSection: RoomSectionHeader(inSheet) + optional footnote + content. */
  dv.section = function (title, o, kids) {
    if (o && (o.nodeType || Array.isArray(o) || typeof o === 'string')) { kids = o; o = {}; }
    o = o || {};
    return h('section.dv-sec', { role: 'group', 'aria-label': title }, K().PageSectionHeader({ title: title }), o.footnote ? h('p.dv-foot', o.footnote) : null, kids);
  };
  /** DeviceTileGrid. The kit grid's minimum (132 pt x Dynamic Type) can exceed a narrow sheet at AX5 and overflow it; DynamicGridLayout clamps a
   *  track to the proposed width, so the track minimum is capped at 100% here (promote to kit: TileGrid). */
  dv.fitGrid = function (g) { g.style.gridTemplateColumns = 'repeat(auto-fill, minmax(min(100%, max(calc(var(--min, 150px) * var(--sc)), calc((100% - (var(--max, 6) - 1) * var(--gap, 12px)) / var(--max, 6)))), 1fr))'; return g; };
  dv.tileGrid = function (items, max) { return dv.fitGrid(K().TileGrid({ items: items, min: 132, max: max || 4, equal: true })); };
  dv.tintedCapsule = function (title, o) { o = o || {}; var b = h('button.dv-tint', { type: 'button' }, title); if (o.disabled) b.disabled = true; return b; };
  dv.bordered = function (title, o) {
    o = o || {}; var b = h('button.dv-bordered' + (o.block ? '.block' : '') + (o.danger ? '.danger' : ''), { type: 'button' }, o.symbol ? h('span', { html: I(o.symbol), style: { display: 'inline-flex' } }) : null, title);
    if (o.disabled) b.disabled = true; return b;
  };
  dv.switchRow = function (label, o) {
    o = o || {};
    var tg = K().Toggle({ on: !!o.on, label: label }); if (o.disabled) tg.disabled = true;
    return h('div.dv-switchrow', { role: 'group', 'aria-label': label }, h('span.lb', o.symbol ? h('span', { html: I(o.symbol), style: { display: 'inline-flex' } }) : null, o.sub ? h('span', h('span.tt', label), h('span.sb', o.sub)) : h('span', label)), tg);
  };
  dv.stepper = function (label, value, o) {
    o = o || {};
    return h('div.dv-stepper', { role: 'group', 'aria-label': label + ', ' + value }, h('div.lb', h('span', label), h('span.v', value)),
      h('div.pm', h('button', { type: 'button', 'aria-label': 'Decrement', html: I('minus', { weight: 2.2 }), disabled: !!o.minDisabled }), h('button', { type: 'button', 'aria-label': 'Increment', html: I('plus', { weight: 2.2 }) })));
  };
  /** DeviceStatusPill. tone: neutral|ok|active|warning|danger|unavailable. */
  dv.statusPill = function (p) {
    var tone = { ok: 'var(--fam-occupancy-glyph)', active: 'var(--fam-water-glyph)', warning: 'var(--ink-warning)', danger: 'var(--ink-danger)', neutral: 'var(--ink-sheet-2)', unavailable: 'var(--ink-sheet-2)' }[p.tone || 'neutral'];
    return h('div.dv-pill', { role: 'group', 'aria-label': p.title + ': ' + p.value, style: { '--pt': tone } }, h('span.ico', { html: I(p.symbol) }), h('span.tx', h('span.la', p.title), h('span.va', p.value)));
  };
  dv.pills = function (items, cls) { return h('div.dv-pills' + (cls ? '.' + cls : ''), items.map(dv.statusPill)); };

  /** A confirmationDialog as the iPhone action sheet (a popover on iPad, drawn as a small card). */
  dv.actionSheet = function (o) {
    return h('div.dv-asheet', { role: 'alertdialog', 'aria-label': o.title },
      h('div.g', h('div.hd', h('b', o.title), o.message ? h('span', o.message) : null),
        (o.actions || []).map(function (a) { return h('button' + (a.role === 'destructive' ? '.destructive' : ''), { type: 'button' }, a.title); })),
      h('button.cancel', { type: 'button' }, o.cancel || 'Cancel'));
  };

  /* ---------------------------------------------------------------- component swatches (page and sheet surfaces) for mockups without a kit component */
  dv.swatches = function (ctx, list, surfaces) {
    surfaces = surfaces || ['page', 'sheet'];
    var out = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } });
    surfaces.forEach(function (surface) {
      var wrap = h('div.k-swatch-grid');
      list.forEach(function (v) {
        if (v.surface && v.surface !== surface) return;
        var box = h('div.k-swatch.' + (surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light')), { style: { flex: '1 1 ' + (v.w || 300) + 'px', maxWidth: '100%', minWidth: 0 } },
          h('div.k-cap', surface + ' · ' + v.label), h('div.in', v.build(ctx)), v.note ? h('div.dv-note', v.note) : null);
        wrap.appendChild(box);
      });
      if (wrap.childNodes.length) out.appendChild(wrap);
    });
    return out;
  };

  /* ---------------------------------------------------------------- dial (ThermostatDial with DialValueStyle: one handle, optional trails) */
  function pt(cx, cy, r, deg) { var a = deg * Math.PI / 180; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; }
  function arc(cx, cy, r, d0, d1) { var a = pt(cx, cy, r, d0), b = pt(cx, cy, r, d1); return 'M' + a[0].toFixed(2) + ' ' + a[1].toFixed(2) + ' A' + r + ' ' + r + ' 0 ' + (d1 - d0 > 180 ? 1 : 0) + ' 1 ' + b[0].toFixed(2) + ' ' + b[1].toFixed(2); }
  /** o: {min,max,value,current?,tint,trails?:[{from,to,tint}],action,big,unit?,caption?,inactive?,size?,label}  tint is a css colour. */
  dv.dial = function (o) {
    var size = o.size || 300, min = o.min, max = o.max;
    function deg(v) { return 135 + Math.min(Math.max((v - min) / (max - min), 0), 1) * 270; }
    var cx = 160, cy = 160, r = 145, lw = 24, svg = '<svg viewBox="0 0 320 320" aria-hidden="true">';
    svg += '<path d="' + arc(cx, cy, r, 135, 405) + '" fill="none" stroke-width="' + lw + '" stroke-linecap="round" style="stroke:color-mix(in srgb, var(--ink) 16%, transparent)"/>';
    (o.trails || []).forEach(function (t) { svg += '<path d="' + arc(cx, cy, r, deg(t.from), deg(t.to)) + '" fill="none" stroke="' + t.tint + '" stroke-width="' + lw + '" stroke-linecap="round"/>'; });
    if (o.current != null) { var d = pt(cx, cy, r, deg(o.current)); svg += '<circle cx="' + d[0] + '" cy="' + d[1] + '" r="9" fill="' + o.tint + '" stroke="#141414" stroke-width="3"/>'; }
    var k = pt(cx, cy, r, deg(o.value));
    svg += '<circle class="hd" cx="' + k[0] + '" cy="' + k[1] + '" r="14" fill="#fff" stroke="' + o.tint + '" stroke-width="4" style="filter:drop-shadow(0 3px 5px rgba(0,0,0,.3))"/></svg>';
    var label = o.label || (o.action + ' ' + o.big + (o.unit || ''));
    return h('div.dv-dial' + (o.inactive ? '.inactive' : ''), { role: 'slider', 'aria-label': o.action, 'aria-valuetext': label + (o.caption ? ', ' + o.caption : ''), style: { width: size + 'px', height: size + 'px', '--d': size + 'px', maxWidth: '100%' } },
      h('div', { html: svg, style: { position: 'absolute', inset: 0 } }),
      h('div.mid', h('span.act', o.action), h('span.big', o.big, o.unit ? h('sup', o.unit) : null), o.caption ? h('span.cap', o.caption) : null));
  };
  /** Move a dial's handle and current dot to a new value along the arc: `quick` 0.2 s easeOut, none under Reduce Motion (ThermostatDial .animation(quick, value: displayed)). */
  dv.moveHandle = function (dialEl, min, max, from, to) {
    var hd = dialEl.querySelector('.hd'); if (!hd) return Promise.resolve();
    var d = (to - from) / (max - min) * 270;
    hd.style.transformBox = 'view-box'; hd.style.transformOrigin = '160px 160px';
    if (Mock.settings.reduceMotion) { hd.style.transform = 'rotate(' + d + 'deg)'; return Promise.resolve(); }
    return hd.animate([{ transform: 'rotate(0deg)' }, { transform: 'rotate(' + d + 'deg)' }], { duration: 200, easing: 'cubic-bezier(0,0,.2,1)', fill: 'forwards' }).finished.catch(function () {});
  };
  var WATER = '#30B4DC', COMFORT = 'rgba(67,160,71,.92)', HIGH = 'rgba(251,140,0,.9)';
  dv.dials = {
    mist: function (H, size) {
      var off = !H.power, sleep = H.mode === 'Sleep', current = !off && !H.blocked ? H.currentMist : null;
      return dv.dial({ min: 0, max: 9, value: off ? 0 : H.mist, current: current, tint: WATER, action: 'Mist Level', size: size || 300, inactive: off || sleep || H.unavailable,
        big: H.unavailable ? 'Off' : sleep ? 'Sleep' : off ? 'Off' : String(H.mist), caption: off ? null : (current != null ? 'Level ' + current + ' • ' : '') + H.humidity + '% current',
        label: 'Humidifier mist level ' + (sleep ? 'Sleep' : off ? 'Off' : H.mist) });
    },
    target: function (v, o) {
      o = o || {};
      return dv.dial({ min: 40, max: 80, value: v, current: o.current == null ? null : o.current, tint: WATER, action: o.action || 'Target Humidity', size: o.size || 250, big: String(v), unit: '%',
        trails: [{ from: 40, to: 50, tint: COMFORT }, { from: 60, to: 80, tint: HIGH }], caption: o.caption, label: (o.action || 'Target humidity') + ' ' + v + ' percent' });
    },
    scheduledMist: function (v) { return dv.dial({ min: 1, max: 9, value: v, tint: WATER, action: 'Mist Level', size: 250, big: String(v), label: 'Scheduled mist level ' + v }); },
  };

  /* ---------------------------------------------------------------- fan ---------------------------------------------------------------- */
  /** FanTimerLengthRow: six lengths, 44 pt tall, the chosen one the label's opposite. */
  dv.lengthRow = function (sel) {
    var L = [5, 10, 15, 20, 30, 60];
    return h('div.dv-lenrow', { role: 'radiogroup', 'aria-label': 'Timer length' }, L.map(function (m) {
      return h('button' + (m === sel ? '.sel' : ''), { type: 'button', role: 'radio', 'aria-checked': m === sel ? 'true' : 'false', 'aria-label': m === 60 ? '1 hour' : m + ' minutes' }, m === 60 ? '1h' : m + 'm');
    }));
  };
  dv.startTitle = function (m) { return m === 60 ? 'Turn Off in 1 Hour' : 'Turn Off in ' + m + ' Minutes'; };
  dv.timerPicker = function (o) {
    o = o || {}; var m = o.minutes || 30;
    return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '12px' } }, dv.lengthRow(m), K().PrimaryButton({ title: dv.startTitle(m), disabled: !!o.disabled }),
      h('p.dv-foot', 'The fan runs, then turns itself off. Starting a timer turns it on if it\'s off.'));
  };
  /** FanTimerRunning: orange countdown, progress bar, Clear Timer. */
  dv.timerRunning = function (o) {
    o = o || {};
    var txt = o.text || '12:34';
    return h('div.dv-run', h('div.cd', { style: { '--ch': (txt.length * 0.62).toFixed(2) }, role: 'timer', 'aria-label': 'Timer, ' + (o.spoken || '12 minutes 34 seconds'), html: I('timer', { weight: 1.8 }) + '<span class="t">' + txt + '</span>' }),
      h('div.dv-bar', { 'aria-hidden': 'true' }, h('i', { style: { width: Math.round((o.fraction == null ? .84 : o.fraction) * 100) + '%' } })), dv.tintedCapsule('Clear Timer', { disabled: o.disabled }));
  };
  /** The fan's controls. o: {power:'on'|'off'|'unavailable', locked, lockAvail, timer:'idle'|'running'|'unavailable', minutes, text, fraction} */
  dv.fanControls = function (o) {
    o = o || {};
    var unavailable = o.power === 'unavailable';
    /* Rollout R (item 14): Power and Lock are action tiles (text . disc, FanRailActions): the disc carries the state glyph and the body does what it shows. */
    var pw = K().GlassTile({ title: 'Power', subtitle: unavailable ? 'Unavailable' : (o.power === 'on' ? 'On' : 'Off'), symbol: 'power', family: 'air', isActive: o.power === 'on', isUnavailable: unavailable, kind: 'toggle',
      behavior: 'perform', actions: [{ id: 'power', symbol: 'power', label: (o.power === 'on' ? 'Turn Off' : 'Turn On') + ' Power', on: o.power === 'on', dim: unavailable }] });
    var lockUn = unavailable || o.lockAvail === false;
    var lk = K().GlassTile({ title: 'Lock', subtitle: lockUn ? 'Unavailable' : (o.locked ? 'Locked' : 'Unlocked'), symbol: o.locked ? 'lock.fill' : 'lock.open', family: 'sec-home', isActive: !!o.locked, isUnavailable: lockUn, kind: 'toggle',
      behavior: 'perform', actions: [{ id: 'lock', symbol: o.locked ? 'lock.fill' : 'lock.open', label: (o.locked ? 'Unlock' : 'Lock') + ' Lock', on: !!o.locked, dim: lockUn }] });
    var timer = o.timer === 'running' ? dv.timerRunning({ text: o.text, fraction: o.fraction }) : dv.timerPicker({ minutes: o.minutes, disabled: o.timer === 'unavailable' || unavailable });
    return h('div.dv-stack', dv.tileGrid([pw, lk], 2), dv.section('Timer', timer));
  };
  /** FanRailButton rail on the room tile. */
  dv.fanRail = function (o) {
    var lit = o.on;
    var bs = [];
    if (o.lockAvail !== false) bs.push(h('button' + (o.locked ? '.on' : ''), { type: 'button', 'aria-label': 'Lock', 'aria-pressed': o.locked ? 'true' : 'false', title: 'Lock, ' + (o.locked ? 'On' : 'Off'), html: I(o.locked ? 'lock.fill' : 'lock.open', { weight: 2.2 }) }));
    bs.push(h('button' + (o.on ? '.on' : ''), { type: 'button', 'aria-label': 'Power', 'aria-pressed': o.on ? 'true' : 'false', title: 'Power, ' + (o.on ? 'On' : 'Off'), html: I('power', { weight: 2.4 }) }));
    return h('div.dv-rail' + (lit ? '.lit' : ''), bs);
  };
  /** BathroomFanRoomTile: the air-family navigate tile with the Lock and Power rail. o: {title, on, locked, status, unavailable} */
  dv.fanTile = function (o) {
    o = o || {};
    var unav = o.unavailable;
    var t = K().GlassTile({ title: o.title || 'Bathroom Fan', subtitle: unav ? 'Unavailable' : (o.status || (o.on ? 'On' : 'Off')), symbol: 'fan', family: 'air', isActive: !!o.on && !unav, isUnavailable: unav, kind: 'navigate', singleLine: true,
      accessory: unav ? null : dv.fanRail({ on: o.on, locked: o.locked }), accessoryWidth: 124 });
    var st = t.querySelector('.st'); if (st) { st.style.textOverflow = 'ellipsis'; if (st.textContent.length > 9) st.style.fontSize = 'calc(var(--fs-foot) * .85)'; }   /* tileSingleLineSubtitle: one line, 85% before it truncates */
    t.style.setProperty('--acc-w', 'calc(28px + 96px * min(var(--sc), 1.5))');   /* the rail's measured width (two circles that scale up to 1.5x) plus 8 pt */
    var acc = t.querySelector('.acc'); if (acc) acc.style.right = '32px';   /* the rail sits one chevron slot in (tile padding 12 + GlassTileFace.chevronReserve 20), never over the chevron */
    return t;
  };

  /** The built fan tile (action-tiles.md): a navigation tile with Lock then Power as action discs left of the chevron. o: {title, on, locked, status, unavailable, lockAvail}. dv.fanTile stays as the "today" of the proposal. */
  dv.fanActionTile = function (o) {
    o = o || {};
    var unav = o.unavailable;
    var t = K().GlassTile({ title: o.title || 'Bathroom Fan', subtitle: unav ? 'Unavailable' : (o.status || (o.on ? 'On' : 'Off')), symbol: 'fan', family: 'air', isActive: !!o.on && !unav, isUnavailable: unav, kind: 'navigate', singleLine: true,
      behavior: 'navigate', actions: unav ? [] : [{ id: 'lock', symbol: o.locked ? 'lock.fill' : 'lock.open', label: (o.locked ? 'Unlock ' : 'Lock ') + (o.title || 'Bathroom Fan'), on: !!o.locked, dim: o.lockAvail === false }, { id: 'power', symbol: 'power', label: (o.on ? 'Turn Off ' : 'Turn On ') + (o.title || 'Bathroom Fan'), on: !!o.on }] });
    var st = t.querySelector('.st'); if (st) { st.style.textOverflow = 'ellipsis'; if (st.textContent.length > 9) st.style.fontSize = 'calc(var(--fs-foot) * .85)'; }
    return t;
  };

  /* ---------------------------------------------------------------- air quality ---------------------------------------------------------------- */
  /** o: {mode:'Manual'|'Sleep'|'Auto', auto:'Default', speed:'Low', unavailable:{mode,auto,fan}, ctx} */
  dv.purifierControls = function (o) {
    o = o || {};
    var Sc = K().SegmentedChoice, dis = o.unavailable || {};
    function seg(title, options, selected, off) {
      var n = Sc({ options: options, selected: selected, label: title, ctx: o.ctx });
      if (off) { n.style.opacity = .4; n.querySelectorAll('button').forEach(function (b) { b.disabled = true; }); n.setAttribute('aria-disabled', 'true'); }
      return dv.section(title, n);
    }
    var kids = [seg('Fan Mode', ['Manual', 'Sleep', 'Auto'], o.mode || 'Auto', dis.mode)];
    if ((o.mode || 'Auto') === 'Auto') kids.push(seg('Auto Mode', ['Default', 'Quiet', 'Efficient'], o.auto || 'Default', dis.auto));
    if (o.mode === 'Manual') kids.push(seg('Fan Speed', ['Off', 'Low', 'Medium', 'High'], o.speed || 'Low', dis.fan));
    return h('div.dv-stack', { role: 'group', 'aria-label': (o.room || 'Office') + ' air purifier controls' }, kids);
  };

  /* ---------------------------------------------------------------- grill ---------------------------------------------------------------- */
  /** o: {state:'Cooking'|'Idle'|'Off'|'Unavailable', probe:'165 °F', pellet:'72%', warm:false, smoke:true, unavailable:{}} */
  dv.grillControls = function (o) {
    o = o || {};
    var off = o.state === 'Off' || o.state === 'Unavailable', un = o.state === 'Unavailable';
    var head = h('div.dv-grillhead', { role: 'group', 'aria-label': 'Grill Probe, ' + (o.state || 'Cooking') }, h('span.c' + (off ? '' : '.on'), { html: I('flame', { fill: true }) }), h('span', h('span.ti', 'Grill Probe'), h('span.su', o.state || 'Cooking')));
    var T = K().GlassTile;
    var sensor = function (title, value, sym, uns) { return T({ title: title, subtitle: uns ? 'Unavailable' : value, symbol: sym, family: 'cooking', isActive: false, isUnavailable: !!uns, kind: 'state' }); };   /* EntityState.isActive is only true for on/open/unlocked/...: a numeric reading never fills */
    /* Rollout R (item 15): Keep Warm and Super Smoke are action tiles with a Power disc (PowerToggleActions); the readings above stay flat. */
    var sw = function (title, on, sym, uns) { return T({ title: title, subtitle: uns ? 'Unavailable' : (on ? 'On' : 'Off'), symbol: sym, family: 'cooking', isActive: !!on && !uns, isUnavailable: !!uns, kind: 'toggle',
      behavior: 'perform', actions: [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + title, on: !!on && !uns, dim: !!uns }] }); };
    return h('div.dv-stack', head, dv.tileGrid([sensor('Probe 1', o.probe || '165 °F', 'thermometer.medium', un), sensor('Pellet Level', o.pellet || '72%', 'percent', un), sw('Keep Warm', o.warm, 'flame', un), sw('Super Smoke', o.smoke == null ? true : o.smoke, 'smoke', un)], 2));
  };

  /* ---------------------------------------------------------------- humidifier ---------------------------------------------------------------- */
  dv.H = function (o) {
    return Object.assign({ power: true, mode: 'Target Humidity', mist: 5, currentMist: 5, target: 50, warm: 1, timer: 60, remaining: 3000, display: true, humidity: 41, temp: '70°F', humidifying: true, fault: null, unavailable: false, vacation: false }, o || {});
  };
  dv.Hsub = function (H) { return H.unavailable ? 'Unavailable' : !H.power ? 'Off' : H.fault === 'tank' ? 'Tank Removed' : H.fault === 'water' ? 'Water Low' : (H.humidifying ? 'Humidifying' : 'On') + ' • ' + H.humidity + '%'; };
  function Hhint(H) {
    if (H.unavailable) return 'Humidifier controls are unavailable.';
    if (H.fault === 'tank') return 'Reinsert the water tank to restore controls.';
    if (H.fault === 'water') return 'Refill the tank to restore output controls.';
    if (H.mode === 'Sleep') return 'Sleep mode controls output automatically.';
    return H.power ? 'Drag the dial to adjust mist output.' : null;
  }
  function minutes(m) { if (m <= 0) return 'Off'; if (m < 60) return m + 'm'; var hr = Math.floor(m / 60), r = m % 60; return r === 0 ? hr + 'h' : hr + 'h ' + r + 'm'; }
  dv.minutes = minutes;
  dv.humHero = function (H) {
    var blocked = H.unavailable || !!H.fault;
    var fault = H.fault === 'tank' ? 'Tank removed. Reinsert it before turning the humidifier on.' : H.fault === 'water' ? 'Water is low. Refill the tank before turning the humidifier on.' : null;
    var canToggle = !H.unavailable && (H.power || !H.fault);
    return h('div.dv-hero', h('div.dv-dialwrap', dv.dials.mist(Object.assign({}, H, { blocked: blocked }))), dv.bordered(H.power ? 'Turn Off' : 'Turn On', { symbol: 'power', disabled: !canToggle }),
      Hhint(H) ? h('p.hint', Hhint(H)) : null, fault ? K().InlineAlert({ message: fault }) : null,
      dv.pills([{ title: 'Current Humidity', symbol: 'humidity', value: H.humidity + '%' }, { title: 'Temperature', symbol: 'thermometer.medium', value: H.temp }], 'two'));
  };
  dv.humControls = function (H, o) {
    o = o || {};
    var blocked = H.unavailable || !!H.fault, sleep = H.mode === 'Sleep', ctx = o.ctx, Sc = K().SegmentedChoice;
    function seg(label, options, sel, off) { var n = Sc({ options: options, selected: sel, label: label, ctx: ctx }); if (off) { n.style.opacity = .4; n.querySelectorAll('button').forEach(function (b) { b.disabled = true; }); } return n; }
    var modeLbl = { 'Manual': 'Manual', 'Target Humidity': 'Auto Humidity', 'Sleep': 'Sleep' }[H.mode];
    var presets = ['Low', 'Medium', 'High', 'Max'], pv = { 2: 'Low', 5: 'Medium', 8: 'High', 9: 'Max' }[H.mist];
    var kids = [dv.section('Mode', seg('Mode', ['Manual', 'Auto Humidity', 'Sleep'], modeLbl, blocked)),
      dv.section('Mist Output', { footnote: 'Use the dial for exact levels, or choose a quick preset.' }, seg('Mist output', presets, H.power ? pv : null, blocked || sleep))];
    if (H.mode === 'Target Humidity') {
      kids.push(dv.section('Target Humidity', [H.targetInvalid ? K().InlineAlert({ message: 'Choose a target before relying on Auto Humidity.' }) : null,
        h('div.dv-dialwrap', dv.dials.target(H.target, { current: blocked ? null : H.humidity, caption: H.humidity + '% current' })),
        H.target > 60 ? K().InlineAlert({ message: 'Targets above 60% can encourage condensation and mold.' }) : h('p.dv-foot', '40–50% is the recommended comfort range for most homes.')]));
    }
    kids.push(dv.section('Warm Mist', seg('Warm mist', ['Off', 'Low', 'Medium', 'High'], ['Off', 'Low', 'Medium', 'High'][H.warm], blocked || sleep)));
    if (H.power) {
      kids.push(dv.section('Device Timer', { footnote: 'This one-shot timer turns the humidifier off. Recurring activities live in Schedules.' }, [dv.stepper('Turn Off In', minutes(H.timer)),
        H.remaining > 0 ? dv.bordered('Cancel Timer · ' + minutes(Math.max(1, Math.ceil(H.remaining / 60))) + ' Remaining', { block: true, danger: true, symbol: 'xmark' }) : null]));
      kids.push(dv.section('Display', dv.switchRow('Display', { symbol: 'display', on: H.display, disabled: blocked || sleep })));
    }
    return h('div.dv-stack', kids);
  };
  dv.RULES = [
    { id: 'night', label: 'Night', days: 'Sun, Mon, Tue, Wed, Thu', time: '10:00 PM–7:00 AM', summary: 'Sleep', running: false },
    { id: 'evening', label: 'Evening', days: 'Every day', time: '6:00 PM–9:30 PM', summary: 'Auto 45% • Mist 6', running: false },
  ];
  /** Schedules tab. o: {rules, enabled, title, sub, loading, error, canEdit, toggleDisabled} */
  dv.humSchedules = function (o) {
    o = o || {}; var rules = o.rules || dv.RULES, canEdit = o.canEdit !== false;
    var tg = K().Toggle({ on: o.enabled !== false, label: o.title || 'Scheduling On' }); if (o.toggleDisabled) tg.disabled = true;
    var head = h('div.dv-sec', { style: { gap: '8px' } }, h('div.dv-card', { style: { display: 'flex', alignItems: 'center', gap: '12px' } },
      h('div.dv-switchrow', { style: { flex: 1 } }, h('span.lb', h('span', { html: I('calendar') }), h('span', h('span.tt', o.title || 'Scheduling On'), h('span.sb', o.sub || (rules.length + ' activities configured')))), tg)),
      h('p.dv-foot', 'Schedules run on Home Assistant. Manual changes last until the next activity or restart/reconnect recovery.'));
    var list;
    if (o.loading) list = h('div', { style: { display: 'flex', alignItems: 'center', gap: '10px', color: 'var(--ink-sheet-2)', fontSize: 'var(--fs-body)' } }, K().ArcSpinner({ size: 'compact' }), 'Loading scheduled activities…');
    else if (!rules.length) list = h('p.dv-sub', 'No activities yet. Add morning, evening, or overnight profiles.');
    else list = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px' } }, rules.map(function (r) {
      var b = h('button.dv-act' + (r.running ? '.run' : ''), { type: 'button', 'aria-label': r.label + ', ' + r.days + ', ' + r.time + ', ' + r.summary + (r.running ? ', Active now' : '') }, h('span.tx', h('span.a', r.label), h('span.b', r.days + ' · ' + r.time), h('span.c', r.summary + (r.running ? ' • Active now' : ''))), h('span.chev', { html: I('chevron.right', { weight: 2.4 }) }));
      if (!canEdit) b.disabled = true; return b;
    }));
    return h('div.dv-stack', head, o.error ? K().InlineAlert({ message: o.error }) : null, dv.section('Activities', list),
      canEdit ? K().PrimaryButton({ title: 'Add Scheduled Activity', symbol: 'plus', disabled: !!o.loading }) : h('p.dv-foot', 'Only Home Assistant administrators can edit scheduled activities.'));
  };
  /** Info tab. */
  dv.humInfo = function (H) {
    var blocked = H.unavailable || !!H.fault;
    var outTone = H.unavailable ? 'unavailable' : H.fault === 'tank' ? 'danger' : H.fault === 'water' ? 'warning' : H.humidifying ? 'active' : H.power ? 'ok' : 'neutral';
    var out = H.fault === 'tank' ? 'Tank Removed' : H.fault === 'water' ? 'Water Low' : H.humidifying ? 'Humidifying' : H.power ? 'Idle' : 'Off';
    var warm = ['Off', 'Low', 'Medium', 'High'][H.warm];
    var mist = H.power ? (H.currentMist == null ? 'Unavailable' : 'Level ' + H.currentMist) : 'Saved ' + H.mist;
    return h('div.dv-stack',
      dv.section('Device State', dv.pills([{ title: 'Output', symbol: 'humidifier', value: out, tone: outTone }, { title: 'Water', symbol: 'drop', value: H.fault ? 'Low' : 'OK', tone: H.fault ? 'warning' : 'ok' },
        { title: 'Tank', symbol: 'drop', value: H.fault === 'tank' ? 'Removed' : 'Installed', tone: H.fault === 'tank' ? 'danger' : 'ok' }, { title: 'Mode', symbol: 'a.circle', value: { 'Manual': 'Manual', 'Target Humidity': 'Auto Humidity', 'Sleep': 'Sleep' }[H.mode] },
        { title: 'Display', symbol: 'display', value: H.display ? 'On' : 'Off' }, { title: 'Warm Mist', symbol: 'flame', value: warm }])),
      dv.section('Environment', dv.pills([{ title: 'Humidity', symbol: 'humidity', value: H.humidity + '%' }, { title: 'Temperature', symbol: 'thermometer.medium', value: H.temp },
        { title: 'Mist Level', symbol: 'humidifier', value: mist }, { title: 'Timer', symbol: 'clock', value: H.remaining > 0 && H.power ? minutes(Math.max(1, Math.ceil(H.remaining / 60))) : 'Off' }])));
  };
  /** The pushed activity editor. o: {isNew, rule:{label,days:[0..6 selected],start,end,mode,mist,target,warm,display}, error, saving, ctx} */
  dv.activityEditor = function (o) {
    o = o || {};
    var R = Object.assign({ label: 'Night', days: [0, 1, 1, 1, 1, 1, 0], start: '10:00 PM', end: '7:00 AM', mode: 'Sleep', mist: 4, target: 50, warm: 0, display: false }, o.rule || {});
    var names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'], full = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    var Sc = K().SegmentedChoice, kids = [];
    kids.push(dv.section('Name', h('div.dv-field', { role: 'textbox', 'aria-label': 'Name' }, R.label)));
    kids.push(dv.section('Days', h('div.dv-days', { role: 'group', 'aria-label': 'Days' }, names.map(function (n, i) { return h('button' + (R.days[i] ? '.sel' : ''), { type: 'button', 'aria-label': full[i], 'aria-pressed': R.days[i] ? 'true' : 'false' }, n); }))));
    kids.push(dv.section('Time', [h('div.dv-pickrow', h('span', 'Start'), h('span.v', R.start)), h('div.dv-pickrow', h('span', 'End'), h('span.v', R.end))]));
    kids.push(dv.section('Mode', h('div.dv-pickrow', { role: 'button', 'aria-haspopup': 'menu', 'aria-label': 'Mode, ' + R.mode }, h('span', 'Mode'), h('span.dv-menu', R.mode, h('span', { html: I('chevron.down', { size: '.8em' }) })))));
    if (R.mode !== 'Sleep') {
      var cols = [dv.section('Mist Level', h('div.dv-dialwrap', dv.dials.scheduledMist(R.mist)))];
      if (R.mode === 'Auto Humidity') cols.push(dv.section('Target Humidity', h('div.dv-dialwrap', dv.dials.target(R.target, { action: 'Target Humidity' }))));
      kids.push(h('div', { style: { display: 'grid', gridTemplateColumns: o.ctx && o.ctx.regular ? 'repeat(2, minmax(0, 1fr))' : '1fr', gap: '24px' } }, cols));
      kids.push(dv.section('Warm Mist', Sc({ options: ['Off', 'Low', 'Medium', 'High'], selected: ['Off', 'Low', 'Medium', 'High'][R.warm], label: 'Warm mist', ctx: o.ctx })));
      kids.push(dv.section('Display', dv.switchRow('Display', { symbol: 'display', on: R.display })));
    }
    if (!R.days.some(Boolean)) kids.push(K().InlineAlert({ message: 'Select at least one day.' }));
    if (o.error) kids.push(K().InlineAlert({ message: o.error }));
    if (!o.isNew) kids.push(dv.bordered('Delete Activity', { block: true, danger: true, symbol: 'trash' }));
    return h('div.dv-col.dv-stack', { style: { maxWidth: '640px' } }, kids);
  };
  /** The Save button of the pushed editor: a confirmationAction text button. */
  dv.saveButton = function (o) {
    o = o || {};
    var b = h('button.ui-glass', { type: 'button', style: { minHeight: '44px', padding: '0 18px', borderRadius: '999px', font: '600 var(--fs-body)/1 var(--font)', color: 'var(--ink-action)', cursor: 'pointer' } }, o.saving ? 'Saving…' : 'Save');
    if (o.disabled) b.disabled = true; if (o.disabled) b.style.opacity = '.4';
    return b;
  };

  /* ---------------------------------------------------------------- presenters and the sheet wrapper ---------------------------------------------------------------- */
  /** A trimmed room page (the sheets open from a room card). o: {room, tiles:[Node], connection} */
  dv.roomPage = function (ctx, o) {
    return Mock.page(ctx, { title: o.room, section: 'home', back: 'Rooms', badge: 3, choresBadge: 2, connection: o.connection || 'live',
      body: [K().PageSectionHeader({ title: o.section || 'Devices' }),
        o.lead && !ctx.regular ? o.lead : null,   /* a phone gives a lead row the full width; regular width joins the two-column grid (RoomSectionView.leadJoinsGrid) */
        dv.fitGrid(K().TileGrid({ items: (o.lead && ctx.regular ? [o.lead] : []).concat(o.tiles), min: 150, max: 2 }))] });
  };
  var PRES = {
    fan: function (ctx, c, st) { return dv.roomPage(ctx, { room: 'Bathroom 1', section: 'Fan', connection: c, lead: dv.fanTile({ title: 'Bathroom Fan', on: st && st.on, locked: st && st.locked, status: st && st.status, unavailable: st && st.status === 'Unavailable' }), tiles: [{ title: 'Vanity Light', subtitle: 'Off', symbol: 'lightbulb', family: 'lights' }] }); },
    purifier: function (ctx, c) { return dv.roomPage(ctx, { room: 'Office', section: 'Air', connection: c, tiles: [{ title: 'Air Quality', subtitle: '12 AQI • 3 µg/m³', symbol: 'aqi.medium', family: 'air', isActive: true, kind: 'navigate' }, { title: 'Office Light', subtitle: 'On at 70%', symbol: 'lightbulb', family: 'lights', isActive: true, progress: .7 }] }); },
    humidifier: function (ctx, c) { return dv.roomPage(ctx, { room: 'Bedroom 1', section: 'Climate', connection: c, tiles: [{ title: 'Humidifier', subtitle: 'Humidifying • 41%', symbol: 'humidifier', family: 'water', isActive: true, kind: 'navigate' }, { title: 'Bedside Lamp', subtitle: 'Off', symbol: 'lightbulb', family: 'lights' }] }); },
    grill: function (ctx, c) { return dv.roomPage(ctx, { room: 'Back Deck', section: 'Cooking', connection: c, tiles: [{ title: 'Grill Probe', subtitle: 'Cooking', symbol: 'flame', family: 'cooking', isActive: true, kind: 'navigate' }, { title: 'Deck Light', subtitle: 'On at 40%', symbol: 'lightbulb', family: 'lights', isActive: true, progress: .4 }] }); },
  };
  dv.presenter = function (kind, ctx, connection, st) { return PRES[kind](ctx, connection, st); };
  /** A device sheet over its room page. o: {kind:'fan'|'purifier'|'humidifier'|'grill', title, subtitle, content, size, detent, connection, tabs, leading, trailing, alert, noPresenter, tileState} */
  dv.sheet = function (ctx, o) {
    return Mock.sheet(ctx, { title: o.title, subtitle: o.subtitle, detent: o.detent || 'fitted', size: o.size || 'form', leading: o.leading, trailing: o.trailing === undefined ? 'close' : o.trailing, content: o.content,
      tabs: o.tabs, alert: o.alert, presenter: o.noPresenter ? null : dv.presenter(o.kind, ctx, o.connection, o.tileState) });
  };
  /** Humidifier tabs (Controls, Schedules, Info). */
  dv.humTabs = function (sel, ctx) {
    return K().ModalTabBar({ ctx: ctx, selected: sel, tabs: [{ id: 'controls', title: 'Controls', symbol: 'humidifier' }, { id: 'schedules', title: 'Schedules', symbol: 'calendar' }, { id: 'info', title: 'Info', symbol: 'info.circle' }] });
  };
})();
