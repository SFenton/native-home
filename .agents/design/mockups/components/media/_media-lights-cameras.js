/* Shared helpers for the media-lights-cameras batch (Media, Custom Lights, Cameras): `window.MLC`.
 *
 * Loaded by every mockup in the batch with a relative <script src> (after kit.js). Nothing here edits _kit/: the extra symbols are added to
 * Mock.symbols at run time, the extra CSS is one injected <style id="mlc-style">, and the builders return plain DOM nodes.
 *
 * PROMOTE TO KIT (see each README "Open notes"): the remote pad / volume card / transport keys / app tile (MediaRemote), the camera viewer controls,
 * BrightnessTile's real copy ("70%", not "On at 70%") and chevron, the symbols below, a CameraTile without the "Last live" pill (the app's tile never draws it).
 *
 * Sources it mirrors (apple/Sources): HassUI/Features/{Media,MediaRemote,CustomLights,Cameras}, HassDesign/{BrightnessTile,OptionPickerSheet}.swift,
 * HassCore/Config/{MediaPageConfig,MediaRemotes,CustomLightsConfig}.swift. Entity states are the gallery fixtures (MediaRemoteFixtures, HomePagesFixtures).
 */
(function () {
  'use strict';
  var h = Mock.h, I = Mock.icon, K = Mock.components;
  var MLC = window.MLC = {};
  function ts(ctx, d, x, a) { return ctx && ctx.ts === 'ax5' ? a : (ctx && ctx.ts === 'xxxl' ? x : d); }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
  function rm() { return !!Mock.settings.reduceMotion; }
  /** A grid's minimum cell width, never wider than the container at this text size (the app's DynamicGridLayout clamps to one column; the kit's CSS does not). */
  MLC.fitMin = function (ctx, min, pad) { var sc = (ctx && ctx.scale) || 1; return Math.floor(Math.min(min, ((ctx ? ctx.contentW : 400) - (pad == null ? 32 : pad)) / sc)); };

  /* ------------------------------------------------------------------ 1. symbols the kit lacks (SF Symbol look-alikes, run-time additions) */
  (function () {
    var S = Mock.symbols;
    function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
    function p(d) { return '<path d="' + d + '"/>'; }
    function rc(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
    var tv = S.tv; tv = Array.isArray(tv) ? tv[0] : tv;
    var add = {
      'circle.fill': [c(12, 12, 7.5), '<circle cx="12" cy="12" r="8"/>'],
      'arrowtriangle.down.fill': [p('M5.5 8h13L12 18.5z'), p('M4.5 7.5h15L12 19z')],
      'keyboard': [rc(2.5, 6.5, 19, 11, 2.5) + p('M6 10h.01M9 10h.01M12 10h.01M15 10h.01M18 10h.01M6 13.5h.01M18 13.5h.01M9.5 14h5')],
      'speaker.minus.fill': [p('M3.5 9.5H7l4.5-3.7v12.4L7 14.5H3.5z') + p('M15 12h5'), p('M3 9.3h4l4.8-3.9v13.2L7 14.7H3z') + '<rect x="14.5" y="11.2" width="6" height="1.7" rx=".85"/>'],
      'speaker.plus.fill': [p('M3.5 9.5H7l4.5-3.7v12.4L7 14.5H3.5z') + p('M15 12h5M17.5 9.5v5'), p('M3 9.3h4l4.8-3.9v13.2L7 14.7H3z') + '<rect x="14.5" y="11.2" width="6" height="1.7" rx=".85"/><rect x="16.65" y="9.05" width="1.7" height="6" rx=".85"/>'],
      'appletvremote.gen4': [rc(7, 2.5, 10, 19, 3) + c(12, 8.5, 2.7) + p('M10 14.2h4M10.5 17.8h.01M13.5 17.8h.01'), '<path fill-rule="evenodd" d="M10 2h4a3 3 0 0 1 3 3v14a3 3 0 0 1-3 3h-4a3 3 0 0 1-3-3V5a3 3 0 0 1 3-3zm2 3.6a2.9 2.9 0 1 0 0 5.8 2.9 2.9 0 0 0 0-5.8zM10 13.6h4v1.5h-4zM10 17h1.6v1.6H10zm2.4 0H14v1.6h-1.6z"/>'],
      'hifireceiver': [rc(2.5, 7.5, 19, 9.5, 2) + c(7.5, 12.2, 2.2) + p('M13 10.8h5.5M13 13.6h4')],
      'tv.slash': [tv + p('M3.5 3.5l17 17')],
      'tv.and.mediabox': [rc(2.5, 4, 19, 11, 2) + rc(7, 17.5, 10, 3, 1)],
      'server.rack': [rc(3.5, 4, 17, 6, 1.6) + rc(3.5, 14, 17, 6, 1.6) + p('M7 7h.01M7 17h.01M12 7h5M12 17h5')],
      'arrow.counterclockwise': [p('M4.5 12a7.5 7.5 0 1 0 2.4-5.5') + p('M4.5 4.5v4h4')],
      'chevron.up.chevron.down': [p('M8 9.5 12 5.5l4 4M8 14.5l4 4 4-4')],
    };
    Object.keys(add).forEach(function (k) { if (!S[k]) S[k] = add[k]; });
  })();

  /* ------------------------------------------------------------------ 2. styles (local; promote to kit.css) */
  var css = [
    '.g-dark{--mg:var(--fam-media-glyph);--mg-off:color-mix(in srgb,var(--fam-media-glyph) 88%,var(--off-grey-dark));--lg:var(--fam-lights-glyph);--lg-off:color-mix(in srgb,var(--fam-lights-glyph) 88%,var(--off-grey-dark))}',
    '.g-light{--mg:var(--fam-media-glyph-light);--mg-off:color-mix(in srgb,var(--fam-media-glyph-light) 88%,var(--off-grey-light));--lg:var(--fam-lights-glyph-light);--lg-off:color-mix(in srgb,var(--fam-lights-glyph-light) 88%,var(--off-grey-light))}',
    /* remote pad, keys, transport */
    '.mlc-col{display:flex;flex-direction:column;gap:24px;max-width:640px;margin:0 auto;width:100%}',
    '.mlc-two{display:grid;grid-template-columns:1fr 1fr;margin:0 -16px;align-items:start}.mlc-two>.l,.mlc-two>.r{padding:16px;min-width:0}.mlc-two>.l{display:flex;justify-content:center}',
    '.mlc-pad{display:grid;grid-template-columns:repeat(3,var(--d));gap:12px;justify-content:center}',
    '.mlc-key{width:var(--d);height:var(--d);border-radius:50%;background:var(--sheet-cell);color:var(--ink);border:0;padding:0;display:grid;place-items:center;font-size:var(--fs-t1);font-weight:600;cursor:pointer;flex:none;transition:transform var(--t-quick) var(--ease-quick),opacity var(--t-quick) var(--ease-quick)}',
    '.mlc-key .g{display:grid;place-items:center;transition:color var(--t-state) var(--ease-state)}.mlc-key .ui-sym{width:1em;height:1em}',
    '.mlc-key.small{font-size:var(--fs-foot)}.mlc-key.t2{font-size:var(--fs-t2)}.mlc-key.mini{width:44px;height:44px;background:transparent;font-size:var(--fs-body)}',
    '.mlc-key.pwr .g{width:46px;height:46px;border-radius:50%;background:var(--ink-success);color:var(--ink-on-success)}.mlc-key.pwr.off .g{background:transparent;box-shadow:inset 0 0 0 2px var(--ink-2);color:var(--ink-2)}',
    '.mlc-key[disabled]{opacity:.4;cursor:default}.mlc-key.gap{visibility:hidden}',
    '.mlc-key.pressed{transform:scale(.94)}.k-reduce-motion .mlc-key.pressed{transform:none;opacity:.7}',
    '.mlc-trans{display:flex}.mlc-trans>div{flex:1;display:grid;place-items:center}',
    '.mlc-vol{background:var(--sheet-cell);border-radius:var(--radius-module);padding:12px 16px;display:flex;flex-direction:column;gap:8px}',
    '.mlc-vol .r1{display:flex;align-items:center;gap:12px}.mlc-vol .nm{flex:1;font:600 var(--fs-hd)/1.25 var(--font);color:var(--ink)}',
    '.mlc-vol .pc{font:400 var(--fs-hd)/1.25 var(--font);font-variant-numeric:tabular-nums;color:var(--ink-sheet-2)}',
    '.mlc-vol .r2{display:flex;align-items:center;gap:4px}.mlc-vol[data-off] .mlc-key,.mlc-vol[data-off] .ui-slider{opacity:.4}',
    '.mlc-kbd{display:flex;flex-direction:column;gap:8px}.mlc-kbd .lb{font-size:var(--fs-sub);color:var(--ink-sheet-2)}',
    '.mlc-kbd .row{display:flex;gap:8px;align-items:center}.mlc-kbd.ax .row{flex-direction:column;align-items:stretch}',
    '.mlc-kbd .fld{flex:1;min-height:44px;display:flex;align-items:center;padding:0 10px;border-radius:8px;background:var(--fill-tertiary);box-shadow:inset 0 0 0 .5px var(--sep);color:var(--ink-sheet-2);font-size:var(--fs-body)}.mlc-kbd .fld.typed{color:var(--ink)}',
    '.mlc-kbd .btns{display:flex;gap:8px}.mlc-kbd .btn{min-height:50px;padding:0 22px;border-radius:25px;border:0;font:600 var(--fs-body)/1 var(--font);cursor:pointer}',
    '.mlc-kbd .btn.send{background:#0071E3;color:#fff}.mlc-kbd .btn.send[disabled]{opacity:.4;cursor:default}.mlc-kbd .btn.cancel{background:var(--fill-tertiary);color:var(--ink-action);font-weight:400}',
    /* app tiles, device rows, hue sync */
    '.mlc-app{display:flex;flex-direction:column;align-items:center;gap:4px;background:none;border:0;padding:0;color:var(--ink);font:inherit;cursor:pointer;width:100%;min-width:0}',
    '.mlc-app .art{position:relative;width:100%;max-width:168px;aspect-ratio:1;border-radius:var(--radius-chip);overflow:hidden;display:grid;place-items:center;background:var(--sheet-cell);box-shadow:inset 0 0 0 1px var(--sep);transition:box-shadow var(--t-state) var(--ease-state)}',
    '.mlc-app.on .art{box-shadow:inset 0 0 0 3px var(--mg)}.mlc-app.un .art{opacity:.4}.mlc-app[disabled]{cursor:default}',
    '.mlc-app .art.white{background:#fff}.mlc-app .art .ini{font:700 calc(var(--fs-t1)*1.7)/1 var(--font-d);color:#fff;text-shadow:0 1px 2px rgba(0,0,0,.3)}.mlc-app .art.white .ini{color:#d93025;text-shadow:none}',
    '.mlc-app .art .fb{font-size:calc(var(--fs-lt)*1);color:var(--mg-off)}.mlc-app.on .art .fb{color:var(--mg)}.mlc-app .art.white .fb{color:#000}',
    '.mlc-app .nm{font-size:var(--fs-sub);text-align:center;color:var(--ink)}.mlc-app .pl{font-size:var(--fs-foot);color:var(--ink-sheet-2)}',
    '.mlc-app.page .art{background:var(--g-module-thin);box-shadow:inset 0 0 0 1px rgba(255,255,255,.14)}.mlc-app.page.on .art{box-shadow:inset 0 0 0 3px var(--mg)}',
    '.mlc-app.page .nm{color:#fff}.mlc-app.page .pl{color:var(--g-secondary-on-module)}',
    '.mlc-hue{display:flex;flex-direction:column;gap:20px}.mlc-hue section>.ui-formhead{margin-left:16px}',
    '.mlc-ctlrow{padding-top:6px;padding-bottom:6px}.mlc-ctlrow .ui-seg,.mlc-ctlrow .ui-menu-tabs{flex:1}.mlc-ctlrow .ui-seg button{min-height:36px}',
    '.mlc-brow{display:flex;flex-direction:column;align-items:stretch;gap:4px;padding:8px 16px}.mlc-brow .t{display:flex;justify-content:space-between;color:var(--ink);font-size:var(--fs-body)}.mlc-brow .t span+span{color:var(--ink-sheet-2);font-variant-numeric:tabular-nums}',
    '.mlc-brow .ui-slider .fi{background:var(--lg)}',
    '.mlc-dis .acc,.mlc-dis .rg{opacity:.4}.mlc-dis .acc{pointer-events:none}',
    '.mlc-un{font-size:var(--fs-body);color:var(--ink-2)}',
    /* custom lights */
    '.mlc-cl{display:flex;flex-direction:column;gap:12px;width:min(960px,calc(100% - 32px));margin-left:auto!important;margin-right:auto!important}',
    '.mlc-modeacc{display:inline-flex;align-items:center;gap:8px;color:var(--ink-action);font-size:var(--fs-body);min-width:0}.mlc-modeacc .ui-sym{font-size:var(--fs-foot)}',
    '.mlc-modeacc .ui-swatch{transition:opacity var(--t-state) var(--ease-state)}',
    '.mlc-ls{display:flex;flex-direction:column;gap:24px;max-width:640px;margin:0 auto;width:100%}',
    '.mlc-row{display:flex;align-items:center;gap:12px;min-height:52px;padding:8px 16px;width:100%;background:none;border:0;font:inherit;font-size:var(--fs-body);color:var(--ink);text-align:left;position:relative;cursor:pointer}',
    '.mlc-row+.mlc-row::before{content:"";position:absolute;top:0;right:0;left:16px;height:.5px;background:var(--sep)}',
    '.mlc-row.act{color:var(--ink-action)}.mlc-row.act[disabled]{color:var(--ink-sheet-2);cursor:default}.mlc-row .i{display:grid;place-items:center}.mlc-row .t{flex:1;min-width:0}',
    '.mlc-well{width:30px;height:30px;border-radius:50%;background:conic-gradient(#ff3b30,#ffcc00,#34c759,#00c7be,#007aff,#af52de,#ff3b30);position:relative;flex:none}',
    '.mlc-well::after{content:"";position:absolute;inset:5px;border-radius:50%;background:var(--wc,#fff);box-shadow:0 0 0 1px rgba(0,0,0,.18)}',
    '.mlc-others{background:var(--sheet-cell);border-radius:var(--radius-module);padding:12px}',
    '.mlc-others .g{display:grid;gap:8px;grid-auto-rows:1fr;grid-template-columns:repeat(auto-fill,minmax(max(calc(76px*var(--sc)),calc((100% - 24px)/4)),1fr))}',
    '.mlc-sw{display:flex;flex-direction:column;align-items:center;justify-content:flex-start;gap:4px;background:none;border:0;padding:0;color:var(--ink-2);font:inherit;cursor:pointer}',
    '.mlc-sw .d{width:clamp(44px,calc(48px*var(--sc)),100px);height:clamp(44px,calc(48px*var(--sc)),100px);border-radius:50%;background:var(--dc,transparent);transition:background-color var(--t-state) var(--ease-state)}',
    '.mlc-sw .d.empty{box-shadow:inset 0 0 0 1.5px var(--ink-sheet-2)}.mlc-sw .n{font-size:var(--fs-foot);text-align:center;color:var(--ink-2)}',
    /* cameras */
    '.mlc-view{display:flex;flex-direction:column;gap:24px;max-width:720px;margin:0 auto;width:100%}.mlc-view.split{flex-direction:row;gap:16px;max-width:none;align-items:flex-start}.mlc-view.split>*{flex:1;min-width:0}',
    '.mlc-video{position:relative;border-radius:var(--radius-tile);overflow:hidden;background:#000;width:100%}',
    '.mlc-video .live,.mlc-video .snap{position:absolute;inset:0}.mlc-video .snap{transition:opacity var(--t-quick) var(--ease-quick);filter:saturate(.78) brightness(.9)}.mlc-video[data-live] .snap{opacity:0}',
    '.mlc-badge{position:absolute;left:8px;top:8px;display:inline-flex;align-items:center;gap:4px;padding:4px 8px;border-radius:99px;background:rgba(0,0,0,.75);color:#fff;font:600 var(--fs-c1)/1.25 var(--font);max-width:calc(100% - 16px)}',
    '.mlc-badge .dot{width:8px;height:8px;border-radius:50%;background:#FF3B30;flex:none}.mlc-badge .ui-sym{font-size:var(--fs-c1)}',
    '.mlc-retry{position:absolute;left:50%;transform:translateX(-50%);bottom:8px;min-height:44px;padding:0 20px;border-radius:99px;border:0;background:#0071E3;color:#fff;font:600 var(--fs-sub)/1.2 var(--font);display:inline-flex;align-items:center;gap:8px;cursor:pointer;white-space:nowrap}',
    '.mlc-ctls{display:flex;gap:12px;align-items:flex-start}.mlc-ctls.v{flex-direction:column;align-items:stretch}',
    '.mlc-ctl{flex:1;display:flex;flex-direction:column;align-items:center;gap:8px;background:none;border:0;color:var(--ink);cursor:pointer;min-height:44px;font:inherit;width:100%;min-width:0}',
    '.mlc-ctl .c{width:var(--cd);height:var(--cd);border-radius:50%;background:var(--sheet-cell);display:grid;place-items:center;font-size:var(--fs-t2);color:var(--ink);position:relative;overflow:hidden;transition:color var(--t-state) var(--ease-state)}',
    '.mlc-ctl .c::before{content:"";position:absolute;inset:0;border-radius:50%;background:var(--tint);opacity:0;transition:opacity var(--t-state) var(--ease-state)}',
    '.mlc-ctl.on .c::before{opacity:.22}.mlc-ctl.on .c{color:var(--tint)}.mlc-ctl .c .g{position:relative;z-index:1;display:grid}',
    '.mlc-ctl .lb{font:600 var(--fs-foot)/1.25 var(--font);text-align:center}',
    '.mlc-pulse .g{animation:mlc-pulse 1s ease-in-out infinite}@keyframes mlc-pulse{50%{opacity:.35}}.k-reduce-motion .mlc-pulse .g{animation:none}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'mlc-style'; st.textContent = css; document.head.appendChild(st);

  /* ------------------------------------------------------------------ 3. fixtures (gallery fixture values; no real names) */
  var SHIELD_APPS = [
    { t: 'Plex', c: ['#E5A00D', '#7A4E00'], l: 'P' }, { t: 'Streaming B', white: true, l: 'Y' }, { t: 'Streaming C', c: ['#B3121C', '#450A0E'], l: 'N' },
    { t: 'Prime Video', c: ['#1B77C9', '#0A3560'], l: 'P' }, { t: 'Streaming E', c: ['#2E5BFF', '#10236B'], l: 'P' }, { t: 'Streaming F', c: ['#2C3F9E', '#0F1744'], l: 'D' },
  ];
  /** The four remotes (MediaRemotes.swift): title, pad kind, tabs (only those with content), volume card, apps, devices. */
  MLC.remotes = {
    'living-room-shield': { id: 'living-room-shield', title: 'Living Room Streaming Box', kind: 'shield', keyboard: true, sub: 'Plex · Playing', vol: { title: 'Speaker Volume', pct: 32 },
      appsTitle: 'Media', apps: SHIELD_APPS, tabs: ['controls', 'apps'], media: 'media_player.demo_living_room_1' },
    'master-bedroom-apple-tv': { id: 'master-bedroom-apple-tv', title: 'Streamer', kind: 'appletv', keyboard: false, sub: 'Plex · Paused', vol: { title: 'Volume', pct: 24 },
      appsTitle: 'Media', apps: [SHIELD_APPS[0]], tabs: ['controls', 'apps'], media: 'media_player.demo_bedroom_1_1' },
    'theater-room-shield': { id: 'theater-room-shield', title: 'Media Room Streaming Box', kind: 'shield', keyboard: true, sub: 'On', vol: { title: 'Receiver Volume', pct: 45, showWhenOff: true },
      appsTitle: 'Media', apps: SHIELD_APPS, devices: 'theater', tabs: ['controls', 'apps', 'devices'], media: 'media_player.demo_media_room_1' },
    'music-room-remote': { id: 'music-room-remote', title: 'Studio Remote', kind: 'shield', keyboard: false, powerSwitch: true, sub: 'On', vol: { title: 'Soundbar Volume', pct: 30, showWhenOff: true },
      appsTitle: 'Quick App Launch', apps: [{ t: 'Game', icon: 'gamecontroller' }], devices: 'music', hue: true, tabs: ['controls', 'apps', 'devices', 'hue'], media: 'media_player.demo_media_room_1' },
  };
  var TAB = { controls: ['Remote', 'appletvremote.gen4'], apps: ['Apps', 'play.rectangle'], devices: ['Devices', 'videoprojector'], hue: ['Hue Sync', 'lightbulb.2'] };
  MLC.tabTitle = function (t) { return TAB[t][0]; };
  var DEVICES = {
    theater: [
      { t: 'Projector', sym: 'videoprojector', kind: 'toggle', on: true, sub: 'On' }, { t: 'Receiver', sym: 'hifireceiver', kind: 'toggle', on: true, sub: 'On' },
      { t: 'Media Room Streaming Box', sym: 'tv.and.mediabox', kind: 'toggle', on: true, sub: 'On' }, { t: 'Media Room Computer', sym: 'videoprojector', kind: 'toggle', on: false, sub: 'Off' }],
    music: [
      { t: 'TV', sym: 'tv', kind: 'toggle', on: true, sub: 'On' }, { t: 'Game Console', sym: 'gamecontroller', kind: 'toggle', on: true, sub: 'On' },
      { t: 'Server', sym: 'server.rack', kind: 'select', on: false, sub: 'Off' }, { t: 'Computer', sym: 'pc', kind: 'select', on: false, sub: 'Off' },
      { t: 'Soundbar', sym: 'hifispeaker', kind: 'state', on: true, sub: 'On' }],
  };
  MLC.devices = DEVICES;

  var LIGHTS = [['Left Door Light', 100, [0, 255, 0]], ['Right Door Light', 90, [0, 0, 255]], ['Bollard 1', 80, [255, 0, 234]], ['Bollard 2', 71, [255, 0, 0]],
    ['Bollard 3', 61, [0, 255, 0]], ['Bollard 4', 51, [255, 137, 14]], ['Bollard 5', 41, [0, 0, 255]], ['Bollard 6', 0, null]];
  MLC.lights = LIGHTS;
  function rgbCss(c) { return c ? 'rgb(' + c.join(',') + ')' : null; }
  MLC.rgbCss = rgbCss;
  MLC.MODES = ["Default", "Custom", "Team Colors", "Holiday Mode"];
  /** CustomLightsConfig.swatch: Seahawks green and blue, Valentine's red and pink, Custom the lights' colours (unique, darkest first), Default none. */
  MLC.swatch = function (mode) {
    if (mode === 'Team Colors') return ['rgb(0,255,0)', 'rgb(0,0,255)'];
    if (mode === "Holiday Mode") return ['rgb(255,0,0)', 'rgb(255,0,234)'];
    if (mode !== 'Custom') return [];
    var seen = {}, u = [];
    LIGHTS.forEach(function (l) { if (l[2] && !seen[l[2]]) { seen[l[2]] = 1; u.push(l[2]); } });
    function lum(c) { return .299 * c[0] + .587 * c[1] + .114 * c[2]; }
    return u.map(function (c, i) { return [c, i]; }).sort(function (a, b) { return lum(a[0]) === lum(b[0]) ? a[1] - b[1] : lum(a[0]) - lum(b[0]); }).map(function (x) { return rgbCss(x[0]); });
  };
  function swatchEl(cols) { return cols.length ? h('span.ui-swatch', { 'aria-hidden': 'true', style: { background: 'linear-gradient(90deg,' + cols.join(',') + ')' } }) : null; }
  MLC.swatchEl = swatchEl;

  var CAMS = [['Front Door', 'front-door', 4 / 3, '4:3'], ['Driveway', 'driveway', 10 / 3, '10:3'], ['Upper Deck', 'upper-deck', 16 / 9, '16:9'], ['Lower Deck', 'lower-deck', 16 / 9, '16:9']];
  MLC.cams = CAMS;

  /* ------------------------------------------------------------------ 4. media remote */
  function padKeys(r) {
    var atv = r.kind === 'appletv';
    return [
      atv ? { l: 'Menu', s: 'chevron.left' } : { l: 'Back', s: 'arrowtriangle.down.fill', rot: 90 }, { l: 'Up', s: 'chevron.up' }, { l: 'Power', s: 'power', power: true },
      { l: 'Left', s: 'chevron.left' }, atv ? { l: 'Select', s: 'circle.fill', small: true } : { l: 'Select' }, { l: 'Right', s: 'chevron.right' },
      atv ? { l: 'Home', s: 'house' } : { l: 'Home', s: 'circle.fill', small: true }, { l: 'Down', s: 'chevron.down' }, r.keyboard ? { l: 'Keyboard', s: 'keyboard', kbd: true } : { gap: true },
    ];
  }
  /** DirectionalPad.diameter: 64 to 104 with Dynamic Type, never wider than three keys fit in maxWidth, never under 44. */
  MLC.padDiameter = function (ctx, maxWidth) {
    var size = clamp(ts(ctx, 76, 88, 104), 64, 104);
    return maxWidth ? Math.max(44, Math.min(size, (maxWidth - 24) / 3)) : size;
  };
  function keyBtn(k, d, o) {
    if (k.gap) return h('span.mlc-key.gap', { 'aria-hidden': 'true' });
    var cls = 'button.mlc-key' + (k.small ? '.small' : '') + (k.power ? '.pwr' + (o.power === 'off' || o.power === 'unavailable' ? '.off' : '') : '') + (o.pressed === k.l ? '.pressed' : '');
    var a = { type: 'button', 'aria-label': k.l, title: k.l };
    if (!k.power && o.disabled) a.disabled = true;
    if (k.kbd) a['aria-expanded'] = o.keyboard ? 'true' : 'false';
    if (k.power && o.powerSwitch) { a.role = 'switch'; a['aria-checked'] = o.power === 'on' ? 'true' : 'false'; }
    var kids = k.s ? h('span.g', { style: k.rot ? { transform: 'rotate(' + k.rot + 'deg)' } : null, html: I(k.s) }) : null;
    return h(cls, a, kids);
  }
  /**
   * The 3 x 3 pad (DirectionalPad): Back, Up, Power; Left, Select, Right; Home, Down, Keyboard.
   * @param {object} ctx @param {object} r a MLC.remotes entry
   * @param {{power?:'on'|'off'|'unavailable', disabled?:boolean, keyboard?:boolean, pressed?:string, maxWidth?:number}} [o]
   */
  MLC.pad = function (ctx, r, o) {
    o = o || {}; var d = MLC.padDiameter(ctx, o.maxWidth);
    var p = { power: o.power || 'on', disabled: o.disabled != null ? o.disabled : (o.power === 'off' || o.power === 'unavailable'), keyboard: o.keyboard, pressed: o.pressed, powerSwitch: r.powerSwitch };
    return h('div.mlc-pad', { role: 'group', 'aria-label': r.title + ' remote controls', style: { '--d': d + 'px' } }, padKeys(r).map(function (k) { return keyBtn(k, d, p); }));
  };
  function miniKey(sym, label, extra) { return h('button.mlc-key.mini' + (extra && extra.disabled ? '' : ''), { type: 'button', 'aria-label': label, title: label, disabled: extra && extra.disabled ? true : null }, h('span.g', { html: I(sym) })); }
  /** The speaker card: name, level, Mute; the slider between Volume Down and Volume Up (RemoteControlsTab.volumeCard). */
  MLC.volumeCard = function (r, o) {
    o = o || {}; var off = !!o.off, pct = o.pct != null ? o.pct : r.vol.pct;
    var card = h('div.mlc-vol', { role: 'group', 'aria-label': r.vol.title },
      h('div.r1', h('span.nm', r.vol.title), h('span.pc', pct + '%'), miniKey('speaker.slash.fill', 'Mute', { disabled: off })),
      h('div.r2', miniKey('speaker.minus.fill', 'Volume Down', { disabled: off }), K.Slider({ value: pct / 100, label: r.vol.title + ' volume' }), miniKey('speaker.plus.fill', 'Volume Up', { disabled: off })));
    if (off) card.setAttribute('data-off', '');
    return card;
  };
  MLC.transport = function (ctx, o) {
    o = o || {}; var d = clamp(ts(ctx, 56, 66, 88), 44, 88), dis = !!o.disabled;
    function key(s, label) { return h('button.mlc-key.t2' + (o.pressed === label ? '.pressed' : ''), { type: 'button', 'aria-label': label, title: label, disabled: dis ? true : null, style: { '--d': d + 'px' } }, h('span.g', { html: I(s) })); }
    return h('div.mlc-trans', { role: 'group', 'aria-label': 'Playback' }, h('div', key('pause.fill', 'Pause')), h('div', h('span', { style: { width: d + 'px', height: d + 'px' }, 'aria-hidden': 'true' })), h('div', key('play.fill', 'Play')));
  };
  MLC.keyboardForm = function (ctx, o) {
    o = o || {}; var typed = !!o.text;
    return h('div.mlc-kbd' + (ctx.axSize ? '.ax' : ''), { role: 'group', 'aria-label': 'Text to send' }, h('span.lb', 'Text to send'),
      h('div.row', h('div.fld' + (typed ? '.typed' : ''), { role: 'textbox', 'aria-label': 'Text to send' }, o.text || 'Enter text'),
        h('div.btns', h('button.btn.send', { type: 'button', disabled: typed ? null : true }, 'Send'), h('button.btn.cancel', { type: 'button' }, 'Cancel'))));
  };
  /** The Remote section under the pad: the inline keyboard while open, the volume card, the transport keys. */
  MLC.controlsTab = function (ctx, r, o) {
    o = o || {}; var kids = [];
    if (o.keyboard) kids.push(MLC.keyboardForm(ctx, { text: o.text }));
    var volOn = r.vol && (r.vol.showWhenOff || !o.volumeOff);
    if (volOn) kids.push(MLC.volumeCard(r, { off: !!o.volumeOff, pct: o.pct }));
    kids.push(MLC.transport(ctx, { disabled: o.controlsOff, pressed: o.pressed }));
    return h('div.mlc-controls', { style: { display: 'flex', flexDirection: 'column', gap: '24px' } }, kids);
  };

  /** One app tile (AppTile): artwork square, name under it, "Playing" and a pink ring while it runs. art: 'loaded'|'loading'; surface: 'sheet'|'page'. */
  MLC.appTile = function (a, o) {
    o = o || {}; var art = o.art || (a.icon ? 'loading' : 'loaded');
    var inner;
    if (art === 'loading' || a.icon) inner = h('span.fb', { html: I(a.icon || 'play.rectangle') });
    else inner = h('span.ini', a.l || a.t[0]);
    var artEl = h('span.art' + (a.white ? '.white' : ''), { style: !a.white && art === 'loaded' && a.c ? { background: 'linear-gradient(135deg,' + a.c[0] + ',' + a.c[1] + ')' } : null, 'aria-hidden': 'true' }, a.white && art === 'loaded' ? h('span.ini', a.l || 'Y') : inner);
    var cls = 'button.mlc-app' + (o.active ? '.on' : '') + (o.unavailable ? '.un' : '') + (o.surface === 'page' ? '.page' : '');
    return h(cls, { type: 'button', 'aria-label': a.t, 'aria-pressed': o.active ? 'true' : null, disabled: o.unavailable ? true : null }, artEl, h('span.nm', a.t), o.active ? h('span.pl', 'Playing') : null);
  };
  MLC.appsTab = function (ctx, r, o) {
    o = o || {};
    var tiles = r.apps.map(function (a) { return MLC.appTile(a, { active: o.active === a.t, unavailable: o.unavailable, art: o.art }); });
    return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '12px' } }, K.PageSectionHeader({ title: r.appsTitle }), K.TileGrid({ items: tiles, min: MLC.fitMin(ctx, 100), max: 4, gap: 12, fill: 'none' /* aspect artwork: never fills (duo-widths rule 4) */ }));
  };
  /** A device row (RemoteDeviceRow): glyph in the media colour while on, name and state, then a switch, a checkmark or nothing. */
  MLC.deviceRow = function (d, o) {
    o = o || {}; var un = !!o.unavailable, on = d.on && !un, sub = un ? 'Unavailable' : d.sub, acc = null, disabled = un && d.kind !== 'state';
    if (d.kind === 'toggle') acc = K.Toggle({ on: on, label: d.t });
    else if (d.kind === 'select') acc = h('span', { html: I('checkmark', { weight: 2.4 }), style: { color: 'var(--ink-action)', opacity: o.selected ? 1 : 0 } });
    var row = K.ModuleRow({ title: d.t, subtitle: sub, symbol: d.sym, glyph: on || (o.selected && !un) ? 'var(--mg)' : 'var(--mg-off)', accessory: acc, press: d.kind === 'select' });
    if (disabled) { row.classList.add('mlc-dis'); var t = row.querySelector('.ui-toggle'); if (t) t.disabled = true; row.setAttribute('aria-disabled', 'true'); }
    return row;
  };
  function formSection(head, list, foot) { return h('section', head ? h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, head) : null, list, foot ? h('p.ui-formfoot', foot) : null); }
  MLC.devicesTab = function (ctx, r, o) {
    o = o || {}; var rows = DEVICES[r.devices].map(function (d) { return MLC.deviceRow(d, o); });
    return h('div.mlc-hue', formSection('Devices', K.ModuleList({ rows: rows })));
  };
  /** The Hue Sync section: power and sync switches, sync mode and intensity segments, brightness, HDMI inputs (HueSyncTab). */
  MLC.hueTab = function (ctx, o) {
    o = o || {}; var un = !!o.unavailable;
    function sw(title, sym, on) { var row = K.ModuleRow({ title: title, symbol: sym, glyph: on && !un ? 'var(--lg)' : 'var(--lg-off)', accessory: K.Toggle({ on: on && !un, label: title }) }); if (un) { row.classList.add('mlc-dis'); row.querySelector('.ui-toggle').disabled = true; } return row; }
    function choice(label, options, sel) {
      if (un) return h('div.ui-mrow.mlc-ctlrow', h('span.mlc-un', { role: 'text', 'aria-label': label + ', Unavailable' }, 'Unavailable'));
      return h('div.ui-mrow.mlc-ctlrow', K.SegmentedChoice({ options: options, selected: sel, label: label, large: true, ctx: ctx }));
    }
    var powerOn = o.power != null ? o.power : true, sync = !!o.sync;
    var hdmi = [['HDMI 1', 'Linked'], ['HDMI 2', 'Connected'], ['HDMI 3', 'Plugged'], ['HDMI 4', 'Unplugged']];
    var sel = o.hdmi || 'HDMI 1';
    var hdmiRows = hdmi.map(function (x) {
      var disc = un || x[1] === 'Unplugged', isSel = sel === x[0], row = K.ModuleRow({ title: x[0], subtitle: un ? 'Unavailable' : (isSel ? 'Selected • ' + x[1] : x[1]), symbol: disc ? 'tv.slash' : 'tv', glyph: isSel && !disc ? 'var(--mg)' : 'var(--mg-off)', press: !disc,
        accessory: h('span', { html: I('checkmark', { weight: 2.4 }), style: { color: 'var(--ink-action)', opacity: isSel && !un ? 1 : 0 } }) });
      if (disc) { row.classList.add('mlc-dis'); row.setAttribute('aria-disabled', 'true'); }
      return row;
    });
    var bright = o.brightness != null ? o.brightness : 50;
    var brow = h('div.mlc-brow', un ? { 'aria-label': 'Brightness, Unavailable' } : null, h('div.t', { 'aria-hidden': 'true' }, h('span', 'Brightness'), h('span', un ? 'Unavailable' : String(bright))),
      K.Slider({ value: bright / 100, label: 'Brightness' }));
    if (un) brow.style.opacity = .4;
    return h('div.mlc-hue',
      formSection('Power and Sync', K.ModuleList({ rows: [sw('Sync Box Power', 'power', powerOn), sw('Light Sync', 'lightbulb.2', sync)] }), 'Light Sync turns on the Sync Box and starts syncing. Choosing a mode does the same. Presence lighting pauses until syncing stops.'),
      formSection('Sync Mode', K.ModuleList({ hasGlyphs: false, rows: [choice('Sync Mode', ['Music', 'Video', 'Game'], o.mode || 'Video')] })),
      formSection('Intensity', K.ModuleList({ hasGlyphs: false, rows: [choice('Intensity', ['Subtle', 'Moderate', 'High', 'Intense'], o.intensity || 'Moderate'), brow] })),
      formSection('HDMI Input', K.ModuleList({ rows: hdmiRows })));
  };

  /**
   * The remote's sections as MediaRemoteSheet lays them out. One column (compact, or a window that may not split): the pad only in Remote.
   * Two columns (SplitPolicy allows a split AND the sheet is at least 640 pt wide): the pad leads for every section, the section trails.
   * @param {object} ctx @param {object} r @param {{tab?, power?, keyboard?, pressed?, text?, volumeOff?, unavailable?, active?, art?}} [o]
   */
  MLC.remoteBody = function (ctx, r, o) {
    o = o || {}; var tab = o.tab || 'controls';
    var power = o.unavailable ? 'unavailable' : (o.power || 'on'), off = power !== 'on';
    var two = ctx.canSplit && !ctx.compact;
    var padOpts = { power: power, keyboard: o.keyboard, pressed: o.pressed, maxWidth: two ? Math.min(704, ctx.w - 64) / 2 - 32 : null };
    function section(withPad) {
      if (tab === 'controls') {
        var kids = []; if (withPad) kids.push(h('div', { style: { display: 'flex', justifyContent: 'center' } }, MLC.pad(ctx, r, padOpts)));
        kids.push(MLC.controlsTab(ctx, r, { keyboard: o.keyboard, text: o.text, volumeOff: o.volumeOff || (o.unavailable && !r.vol.showWhenOff), controlsOff: off, pressed: o.pressed, pct: o.unavailable ? 0 : undefined }));
        return h('div.mlc-col', kids);
      }
      if (tab === 'apps') return h('div.mlc-col', MLC.appsTab(ctx, r, { unavailable: o.unavailable && r.id === 'music-room-remote', active: o.active, art: o.art }));
      if (tab === 'devices') return h('div.mlc-col', MLC.devicesTab(ctx, r, { unavailable: o.unavailable }));
      return h('div.mlc-col', MLC.hueTab(ctx, { unavailable: o.unavailable }));
    }
    if (two) return h('div.mlc-two', h('div.l', MLC.pad(ctx, r, padOpts)), h('div.r', section(false)));
    return section(true);
  };
  /** The glass section bar (ModalTabBar) for a remote, or null when it has one section. */
  MLC.remoteTabs = function (ctx, r, selected) {
    if (r.tabs.length < 2) return null;
    return K.ModalTabBar({ ctx: ctx, selected: selected || 'controls', tabs: r.tabs.map(function (t) { return { id: t, title: TAB[t][0], symbol: TAB[t][1] }; }) });
  };

  /* ------------------------------------------------------------------ 5. Media page */
  /**
   * The Media page cards by mode. Cards: {t, sym, offSym?, sub, on, lead?}. Modes: default (streaming box playing, Studio on, projector on), alloff, xbox (game console is the
   * active source), unavailable, pending (first sign-in). Source tiles read "On" for the active source and "Off" for every other (MediaPageConfig.sourceLabels).
   */
  MLC.mediaSections = function (mode) {
    var un = mode === 'unavailable', alloff = mode === 'alloff', xbox = mode === 'Game Console' || mode === 'Game', fortnite = mode === 'Game';
    function sub(on, word) { return un ? 'Unavailable' : (on ? word || 'On' : 'Off'); }
    var living = { t: 'Living Room Streaming Box', sym: 'tv', offSym: 'tv.slash', lead: true, on: !un && !alloff, sub: un ? 'Unavailable' : (alloff ? 'Off' : 'Playing'), transport: !un && !alloff, vol: 40, un: un };
    var musicLead = { t: 'Studio Remote', sym: 'appletvremote.gen4', lead: true, on: !un && !alloff, sub: sub(!alloff) };
    /* Rollout R: a source chooses (selection face, check disc); the state line is "On the TV" while chosen and nothing otherwise. With Game active, game console and game both read chosen. */
    function src(t, sym, on) { return { t: t, sym: sym, on: !un && on, sub: un ? 'Unavailable' : (on ? 'On the TV' : null), un: un, source: true }; }
    var theaterLead = { t: 'Media Room', sym: 'videoprojector', lead: true, on: !un && !alloff, sub: sub(!alloff) };
    return [
      { title: 'Living Room', cards: [living] },
      { title: 'Studio', cards: [musicLead, src('Game Console', 'gamecontroller', xbox || fortnite), src('Server', 'server.rack', false), src('Computer', 'pc', false), src('Game', 'gamecontroller', fortnite)] },
      /* Switch and streaming box: action tiles with a toggle-styled power disc tracked through the tile's script (ScriptPowerActions). */
      { title: 'Media Room', cards: [theaterLead, { t: 'Handheld Console', sym: 'gamecontroller', on: false, sub: un ? 'Unavailable' : (mode === 'switch-flight' ? 'Turning On…' : 'Off'), un: un, script: true, flight: mode === 'switch-flight' }, { t: 'Media Room Streaming Box', sym: 'tv', on: !un && !alloff, sub: sub(!alloff), un: un, script: true }] },
    ];
  };
  MLC.mediaTile = function (c, o) {
    o = o || {};
    var off = !c.on;
    var p = { title: c.t, subtitle: c.sub, symbol: off && c.offSym ? c.offSym : c.sym, family: 'media', isActive: !!c.on, isUnavailable: !c.lead && !!c.un, kind: c.lead ? 'navigate' : 'toggle', pending: !!o.pending };
    if (c.lead) {
      /* action-tiles.md: a remote tile is navigation (glyph . text . chevron). Off, on or unavailable: Power beside the chevron. Playing, paused or buffering: previous,
         play/pause and next below the text, and the volume slider while the volume entity is on (writes on release). */
      p.behavior = 'navigate';
      if (c.transport) {
        p.actions = [{ id: 'previous', symbol: 'backward.fill', label: 'Previous ' + c.t }, { id: 'play_pause', symbol: c.paused ? 'play.fill' : 'pause.fill', label: (c.paused ? 'Play ' : 'Pause ') + c.t, on: true }, { id: 'next', symbol: 'forward.fill', label: 'Next ' + c.t }];
        if (c.vol != null) p.under = Mock.tileVolume(c.vol, c.t + ' volume');
      } else p.actions = [{ id: 'power', symbol: 'power', label: (c.on ? 'Turn Off ' : 'Turn On ') + c.t, on: !!c.on, dim: !!c.un }];
    }
    if (c.source) {
      p.kind = 'selection'; p.selected = !!c.on; p.behavior = 'perform';
      p.actions = [{ id: 'source', symbol: c.on ? 'checkmark' : 'circle', label: c.on && c.t !== 'Game' ? 'Turn Off TV' : 'Select ' + c.t, on: !!c.on, dim: !!c.un }];
    } else if (c.script) {
      p.kind = 'toggle'; p.behavior = 'perform';
      p.actions = [{ id: 'power', symbol: 'power', label: (c.on ? 'Turn Off ' : 'Turn On ') + c.t, on: !!c.on, dim: !!c.un, busy: !!c.flight }];
    }
    return K.GlassTile(p);
  };
  MLC.mediaBody = function (ctx, o) {
    o = o || {};
    var secs = MLC.mediaSections(o.mode).map(function (s) {
      var lead = MLC.mediaTile(s.cards[0], o), rest = s.cards.slice(1).map(function (c) { return MLC.mediaTile(c, o); });
      return h('div.ui-section', { style: { gap: '12px', minWidth: 0 } }, K.PageSectionHeader({ title: s.title }), lead, rest.length ? K.TileGrid({ items: rest, min: MLC.fitMin(ctx, 140, 64), max: 4 }) : null);
    });
    /* Partly folded Duo (section-sides.md, claude/section-sides): fold columns by configured order (Living Room and Media Room lead, Studio trails),
       the sides today's grid gives; each side stacks (no row holes) at every text size (no 340 pt fall-back across the band). */
    var fold = Mock.foldColumns(ctx, { leading: secs.filter(function (_, i) { return i % 2 === 0; }), trailing: secs.filter(function (_, i) { return i % 2 === 1; }) });
    if (fold) return fold;
    return [K.TileGrid({ items: secs, min: MLC.fitMin(ctx, 340), max: 3, gap: 24, equal: false })];
  };
  /** The Media page (pushed under Home): also the trimmed presenter behind the remote sheet. */
  MLC.mediaPage = function (ctx, o) {
    o = o || {};
    return Mock.page(ctx, Object.assign({ title: 'Media', section: 'home', back: 'Home', badge: 3, choresBadge: 2, connection: o.connection, body: MLC.mediaBody(ctx, o) }, o.page));
  };
  /** Flip a GlassTile between its off and on faces in place (the colour slots cross-fade for `state`). */
  MLC.flip = function (tile, on, sub) {
    var st = tile.querySelector('.st'), sym = tile.dataset.sym;
    tile.classList.toggle('off', !on); tile.classList.toggle('on', on);
    if (st && sub) st.textContent = sub;
    tile.setAttribute('aria-pressed', on ? 'true' : 'false');
    return Mock.sleep(Mock.anim.ms.state() + 80);
  };
  MLC.press = function (btn) { btn.classList.add('pressed'); return Mock.sleep(Mock.anim.ms.quick() + 120).then(function () { btn.classList.remove('pressed'); return Mock.sleep(Mock.anim.ms.quick()); }); };

  /* ------------------------------------------------------------------ 6. Custom Lights */
  /**
   * A light tile (CustomLightTile -> BrightnessTile): the lit tile whose bright band is the brightness, status "71%" / "Off" / "Unavailable".
   * open: tap opens the sheet (chevron). dragging: lifted, "30%" bubble.
   */
  MLC.lightTile = function (p) {
    var pct = p.percent || 0, un = !!p.unavailable;
    /* Rollout L: BrightnessTile is a GlassTile with its drag over the body. A tile whose tap opens details is a navigation tile (glyph, text, the power disc left of the chevron, two tracks wide);
       one that flips power is an action tile (text . power disc). An unavailable navigation tile has no disc. */
    var tile = Mock.components.BrightnessTile({ title: p.title, percent: pct, unavailable: un, tint: p.rgb ? rgbCss(p.rgb) : undefined, chevron: !!p.open });
    tile.dataset.anim = 'brightness'; tile.setAttribute('role', 'slider'); tile.setAttribute('aria-valuenow', pct); tile.setAttribute('aria-valuemin', 0); tile.setAttribute('aria-valuemax', 100);
    tile.setAttribute('aria-valuetext', un ? 'Unavailable' : (pct > 0 ? pct + '%' : 'Off'));
    if (p.dragging) MLC.lift(tile, pct);
    return tile;
  };
  MLC.lift = function (tile, pct) {
    tile.style.transform = 'scale(1.03)'; tile.style.boxShadow = '0 10px 24px rgba(0,0,0,.4)'; tile.style.overflow = 'visible'; tile.style.zIndex = 3;
    var b = h('span.ui-bubble', { 'aria-hidden': 'true', style: { position: 'absolute', top: '-28px', zIndex: 5, left: 'calc(' + pct + '% - 30px)', width: '60px', height: '32px', display: 'grid', placeItems: 'center', background: '#2C2C2E', color: '#fff', font: '600 var(--fs-sub) var(--font)', borderRadius: '99px', fontVariantNumeric: 'tabular-nums', boxShadow: '0 2px 6px rgba(0,0,0,.3)', transition: 'left var(--t-quick) var(--ease-quick)' } }, pct + '%');
    tile.appendChild(b); return b;
  };
  /** Play a brightness drag on a lit tile: lift, the band and bubble follow the finger on `quick`, release. Reduce Motion: no lift, the band jumps. */
  MLC.drag = function (tile, steps) {
    var band = tile.querySelector('.band'), st = tile.querySelector('.st'), bubble = null, reduced = rm();
    if (!band) return Promise.resolve();
    band.style.transition = reduced ? 'none' : '';
    if (!reduced) { tile.style.transition = 'transform var(--t-quick) var(--ease-quick), box-shadow var(--t-quick) var(--ease-quick)'; tile.style.transform = 'scale(1.03)'; tile.style.boxShadow = '0 10px 24px rgba(0,0,0,.4)'; }
    else tile.style.boxShadow = '0 10px 24px rgba(0,0,0,.4)';
    tile.style.overflow = 'visible'; tile.style.zIndex = 3;
    bubble = MLC.lift(tile, steps[0]); bubble.style.transform = 'none';
    var chain = Promise.resolve();
    steps.forEach(function (v) { chain = chain.then(function () { band.style.width = v + '%'; bubble.style.left = 'calc(' + v + '% - 30px)'; bubble.textContent = v + '%'; if (st) st.textContent = v > 0 ? v + '%' : 'Off'; return Mock.sleep(Mock.anim.ms.quick() + 140); }); });
    return chain.then(function () { bubble.remove(); tile.style.transform = ''; tile.style.boxShadow = ''; return Mock.sleep(Mock.anim.ms.quick()); });
  };
  /**
   * The Custom Lights body. o.manual 'on'|'off'|'unavailable', o.mode, o.lights 'ok'|'unavailable'. Lights and Reset show only while manual control is on and the mode is Custom.
   */
  MLC.customLightsBody = function (ctx, o) {
    o = o || {}; var manual = o.manual || 'on', mode = o.mode || 'Custom', mon = manual === 'on', un = manual === 'unavailable';
    var title = 'Manually Control Front Yard Lights';
    var tg = K.Toggle({ on: mon, label: title }); if (un) tg.disabled = true;
    var rows = [K.ModuleRow({ title: title, symbol: 'lightbulb.2', glyph: mon ? 'var(--lg)' : 'var(--lg-off)', glyphOpacity: un ? .5 : undefined, accessory: tg })];
    if (mon) {
      var sw = swatchEl(MLC.swatch(mode));
      var row = K.ModuleRow({ title: 'Lighting Mode', symbol: 'paintpalette', press: true, accessory: h('span.mlc-modeacc', sw, h('span.mode', mode), h('span', { html: I('chevron.up.chevron.down', { weight: 2.4 }), 'aria-hidden': 'true' })) });
      row.setAttribute('aria-label', 'Lighting Mode, ' + mode); row.dataset.anim = 'mode-row'; rows.push(row);
    }
    var controls = [K.PageSectionHeader({ title: 'Front Yard' }), K.ModuleList({ rows: rows })], lights = [];
    if (mon && mode === 'Custom') {
      var un2 = o.lights === 'unavailable';
      lights.push(K.TileGrid({ items: LIGHTS.map(function (l) { return MLC.lightTile({ title: l[0], percent: un2 ? 0 : l[1], rgb: l[2], unavailable: un2, open: true }); }), min: MLC.fitMin(ctx, 150), max: 4 }));
      var reset = h('button.ui-mrow.press', { type: 'button', 'aria-label': 'Reset All Lights', style: { color: 'var(--ink-action)', minHeight: '52px' } }, h('span.rg', { style: { color: 'var(--ink-action)' }, html: I('arrow.counterclockwise') }), h('span.tx', h('span.ti', { style: { color: 'var(--ink-action)' } }, 'Reset All Lights')));
      lights.push(h('div.ui-mlist', reset));
    }
    /* Partly folded Duo (section-sides.md, claude/section-sides): the page's one section divides at its blocks. The header and the switch/mode card lead;
       the light tiles and Reset All Lights trail, level with the card. With no lights showing (manual off, a preset mode) the trailing side is empty. */
    if (ctx.splitAtHinge && ctx.splitGeometry) {
      var head = controls[0], card = controls[1];
      var fold = Mock.foldColumns(ctx, { leading: [h('div.mlc-cl', head, card)], trailing: lights.length ? [h('div.mlc-cl', { style: { paddingTop: 'calc(var(--fs-t3) * 1.2 + 12px)' } }, lights)] : [] });
      return fold;
    }
    return [h('div.mlc-cl', controls.concat(lights))];
  };
  MLC.customLightsPage = function (ctx, o) {
    o = o || {};
    return Mock.page(ctx, Object.assign({ title: 'Custom Lights', section: 'home', back: 'Home', badge: 3, choresBadge: 2, connection: o.connection, body: MLC.customLightsBody(ctx, o) }, o.page));
  };
  /**
   * The custom light sheet body. o.light index, o.kind 'color'|'white'|'off'|'unavailable'. Subtitle: "On · 71%", "Off" or "Unavailable".
   */
  MLC.lightSubtitle = function (kind, pct) { return kind === 'unavailable' ? 'Unavailable' : (kind === 'off' || !pct ? 'Off' : 'On · ' + pct + '%'); };
  MLC.lightSheetBody = function (ctx, o) {
    o = o || {}; var idx = o.light == null ? 3 : o.light, kind = o.kind || 'color', L = LIGHTS[idx];
    var un = kind === 'unavailable', off = kind === 'off', pct = off || un ? 0 : L[1];
    var rgb = off ? null : L[2];
    var tile = MLC.lightTile({ title: L[0], percent: pct, rgb: off || kind === 'white' ? null : L[2], unavailable: un });
    var kids = [tile];
    if (kind === 'color' || kind === 'off') {
      var well = h('span.mlc-well', { style: { '--wc': rgb ? rgbCss(rgb) : '#fff' }, 'aria-hidden': 'true' });
      var colorRow = h('div.mlc-row', { role: 'group', 'aria-label': 'Color' }, h('span.i', { style: { color: 'var(--ink-sheet-2)', width: 'calc(28px*var(--sc))' }, html: I('paintpalette') }), h('span.t', 'Color'), well);
      function act(t, sym, dis) { return h('button.mlc-row.act', { type: 'button', 'aria-label': t, disabled: dis ? true : null }, h('span.i', { style: { width: 'calc(28px*var(--sc))' }, html: I(sym) }), h('span.t', t)); }
      kids.push(h('div.ui-mlist', colorRow, act('Reset to Warm White', 'arrow.counterclockwise'), act('Apply to All Lights', 'lightbulb.2', !rgb)));
      var others = LIGHTS.filter(function (_, i) { return i !== idx; }).map(function (l) {
        return h('button.mlc-sw', { type: 'button', 'aria-label': 'Apply ' + l[0] + ' Color', 'aria-description': l[2] ? null : 'Off', style: l[2] ? null : { pointerEvents: 'none' } },
          h('span.d' + (l[2] ? '' : '.empty'), { style: l[2] ? { '--dc': rgbCss(l[2]) } : null }), h('span.n', l[0]), l[2] ? null : h('span.n', 'Off'));
      });
      kids.push(h('div', { style: { display: 'flex', flexDirection: 'column', gap: '12px' } }, K.PageSectionHeader({ title: 'Copy Color From' }), h('div.mlc-others', h('div.g', others))));
    }
    return h('div.mlc-ls', kids);
  };

  /* ------------------------------------------------------------------ 7. Cameras */
  /** A camera tile as the app draws it: name capsule (red dot only while live) over the picture, no pill (kit CameraTile adds one the app does not). */
  MLC.cameraTile = function (p) {
    var n = K.CameraTile(p), s = n.querySelector('.state'); if (s) s.remove();
    if (p.redacted) n.querySelector('.photo').style.filter = 'blur(14px)';
    return n;
  };
  MLC.homePresenter = function (ctx, o) {
    o = o || {};
    var chips = K.ChipRail({ chips: Mock.chips.home(), frame: { x: 0, w: ctx.contentW } });
    var s = o.cams || ['live', 'live', 'live', 'live'];
    var tiles = CAMS.map(function (c, i) { return MLC.cameraTile({ title: c[0], scene: c[1], state: s[i] }); });
    var cams = h('div.ui-section', K.PageSectionHeader({ title: 'Cameras' }), K.TileGrid({ min: MLC.fitMin(ctx, 160), max: 4, equal: false, items: tiles }));
    return Mock.page(ctx, { title: 'Home', section: 'home', badge: 3, choresBadge: 2, connection: o.connection, body: [chips, cams] });
  };
  /** The video: black frame at the camera's own aspect ratio, the live picture under the snapshot (which fades out when live), badge, Retry. */
  MLC.video = function (cam, o) {
    o = o || {}; var phase = o.phase || 'live';
    var v = h('div.mlc-video', { role: 'img', 'aria-label': cam[0] + ' camera', style: { aspectRatio: String(cam[2]) } },
      h('div.live', { style: { background: Mock.scene(cam[1]) } }), h('div.snap', { style: { background: Mock.scene(cam[1]) } }));
    if (phase === 'live' || phase === 'delayed') v.setAttribute('data-live', '');
    var value = { connecting: 'Connecting to live video', live: 'Live', delayed: 'Live, a few seconds behind', stalled: 'Connecting to live video', failed: 'Live video unavailable, showing the latest snapshot' }[phase];
    v.setAttribute('aria-roledescription', value);
    v.appendChild(MLC.badge(phase, o.since));
    if (phase === 'failed') v.appendChild(h('button.mlc-retry', { type: 'button' }, h('span', { html: I('arrow.clockwise') }), 'Retry Live Video'));
    return v;
  };
  MLC.badge = function (phase, since) {
    var kids;
    if (phase === 'connecting') kids = [K.ArcSpinner({ size: 'inline' }), 'Connecting'];
    else if (phase === 'stalled') kids = [K.ArcSpinner({ size: 'inline' }), 'Last live ' + (since || '6:51 PM')];
    else if (phase === 'failed') kids = [h('span', { html: I('photo') }), 'Snapshot'];
    else kids = [h('span.dot'), phase === 'delayed' ? 'Live · Delayed' : 'Live'];
    return h('span.mlc-badge', { 'aria-hidden': 'true' }, kids);
  };
  /** One control: a 56 pt circle over its label, the glyph tinted while on (CameraControlButton). */
  MLC.camControl = function (ctx, o) {
    var d = clamp(ts(ctx, 56, 66, 88), 44, 100);
    var cls = 'button.mlc-ctl' + (o.active ? '.on' : '') + (o.pulse && !Mock.settings.reduceMotion ? '.mlc-pulse' : '');
    var a = { type: 'button', 'aria-label': o.label, style: { '--cd': d + 'px', '--tint': o.tint || 'var(--ink-action)' } };
    if (o.toggle) a['aria-pressed'] = o.active ? 'true' : 'false';
    if (o.value) a['aria-description'] = o.value;
    if (o.disabled) a.disabled = true;
    return h(cls, a, h('span.c', h('span.g', { html: I(o.sym) })), h('span.lb', o.title));
  };
  /**
   * Snapshot, Sound, Record. o.snap 'idle'|'saving'|'saved'|'failed', o.muted (default true), o.recording, o.noRecord, o.axis 'h'|'v'.
   * Accessibility sizes stack the controls (three across break their labels mid-word at AX5).
   */
  MLC.camControls = function (ctx, o) {
    o = o || {}; var snap = o.snap || 'idle', muted = o.muted !== false, rec = !!o.recording;
    var S = { idle: ['Snapshot', 'camera.fill'], saving: ['Snapshot', 'camera.fill'], saved: ['Saved', 'checkmark.circle.fill'], failed: ['Not Saved', 'exclamationmark.triangle.fill'] }[snap];
    var kids = [
      MLC.camControl(ctx, { label: 'Snapshot', title: S[0], sym: S[1], active: snap !== 'idle', pulse: snap === 'saving', value: { idle: '', saving: 'Saving', saved: 'Saved to Photos', failed: "Couldn't save the snapshot" }[snap], disabled: snap === 'saving', tint: 'var(--ink-action)' }),
      MLC.camControl(ctx, { label: 'Sound', title: muted ? 'Muted' : 'Sound On', sym: muted ? 'speaker.slash.fill' : 'speaker.wave.2.fill', active: !muted, toggle: true, value: muted ? 'Off' : 'On', tint: 'var(--ink-action)' }),
    ];
    if (!o.noRecord) kids.push(MLC.camControl(ctx, { label: 'Record', title: rec ? 'Recording' : 'Record', sym: 'record.circle', active: rec, pulse: rec, toggle: true, value: rec ? 'Recording' : 'Not recording', tint: 'var(--ink-danger)' }));
    var vertical = o.axis === 'v' || ctx.axSize;
    return h('div.mlc-ctls' + (vertical ? '.v' : ''), { role: 'group', 'aria-label': (o.camera || 'Front Door') + ' camera controls' }, kids);
  };
  /**
   * The viewer page: the video and the controls in one page scroller. Stacked (video over a row of controls, 720 pt at most) unless the window may split and the
   * sheet is at least 640 pt wide (iPad and the unfolded Duo in landscape): then the video leads and the controls stack beside it.
   */
  MLC.viewerBody = function (ctx, o) {
    o = o || {}; var cam = CAMS[o.cam || 0], split = ctx.canSplit && !ctx.compact;
    var v = MLC.video(cam, { phase: o.phase || 'live', since: o.since });
    var c = MLC.camControls(ctx, { snap: o.snap, muted: o.muted, recording: o.recording, axis: split ? 'v' : 'h', camera: cam[0] });
    return h('div.mlc-view' + (split ? '.split' : ''), { 'data-layout': split ? 'split' : 'stacked' }, v, c);
  };
  /** The viewer sheet over Home. detent 'fitted' (in flight: hassSheet(.page, appearance: .dark)) or 'large' (main: height .full). */
  MLC.viewerSheet = function (ctx, o) {
    o = o || {}; var cam = CAMS[o.cam || 0];
    var host = Mock.sheet(ctx, { title: cam[0], detent: o.detent || 'fitted', size: 'page', trailing: 'close', appearance: 'dark', content: MLC.viewerBody(ctx, o), presenter: o.noPresenter ? null : MLC.homePresenter(ctx, { connection: o.connection }) });
    if (o.alert) host.appendChild(h('div.ui-alert-scrim.g-dark', MLC.photosAlert()));
    return host;
  };
  MLC.photosAlert = function () {
    return K.Alert({ title: 'Allow Photos Access', message: 'Snapshots are saved to your photo library. Allow S+H to add photos in Settings.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Open Settings' }] });
  };

  /* ------------------------------------------------------------------ 8. component page helpers */
  /** A swatch box as Mock.componentConfig draws them: surface 'page' (always dark, over a gradient) or 'sheet' (follows the appearance control; o.dark forces dark). */
  MLC.sw = function (ctx, surface, label, node, o) {
    o = o || {};
    var cls = surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + ((o.dark || ctx.appearance === 'dark') ? 'g-dark' : 'g-light');
    return h('div.k-swatch.' + cls, { style: { flex: o.flex || '1 1 300px', maxWidth: '100%', minWidth: 0, width: o.width || null } }, h('div.k-cap', surface + ' · ' + label), h('div.in', node), o.note ? h('div', { style: { font: '12px var(--font)', opacity: .7, marginTop: '8px' } }, o.note) : null);
  };
  MLC.grid = function (list) { return h('div.k-swatch-grid', list); };
  MLC.stack = function (list) { return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } }, list); };

  /** Shared review findings. */
  MLC.R = {
    sheetFit: { rule: 'Sheets: as tall as the content, grabber visible, close with a circle x', verdict: 'pass', note: 'hassSheet fitted detent (SheetFit), SheetCloseItem trailing; never a text "Done".' },
    sheetPage: { rule: 'Sheets: page or form sizing on iPad', verdict: 'pass', note: 'Page sheet (704 pt) on iPad and the unfolded Duo (modal-sheet.md iPad size).' },
    target44: { rule: 'Buttons: 44 pt minimum hit target', verdict: 'pass', note: 'HassTokens.minTarget (44 pt) is the floor for every round key, row and control; sizes scale with Dynamic Type.' },
    colorNotAlone: { rule: 'Color: never the only differentiator', verdict: 'pass', note: 'State is words and glyph as well as colour.' },
    darkModes: { rule: 'Dark Mode: support both appearances', verdict: 'pass', note: 'Sheets follow the system appearance while pages stay dark (owner 2026-10-15).' },
    glass: { rule: 'Materials: Liquid Glass on the navigation layer only', verdict: 'pass', note: 'Section bar and header circles are glass; keys, cards, rows and tiles use the sheet cell colour or the module material.' },
    scaled: { rule: 'Dynamic Type: scaled metrics, no truncation', verdict: 'pass', note: 'Round keys, circles and artwork use @ScaledMetric; labels wrap (fixedSize vertical) instead of truncating.' },
    motionTokens: { rule: 'Motion goes through MotionTokens and motionSafeAnimation', verdict: 'pass', note: 'Colour on state (0.6 s, 0.2 s reduced), level and press on quick (0.2 s).' },
  };
})();
