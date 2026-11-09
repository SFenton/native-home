/* Shared helpers for the settings-account batch (Settings tab, Home Assistant settings cover, Performance, feedback, App Icon, Your Summary).
 * Loaded with a <script src> after kit.js. Nothing here edits the kit: it adds a few local symbols to Mock.symbols and a small <style>, and exposes `SA`.
 *
 * Promote to kit (see each mockup's notes): SA.link (SettingsLinkRow), SA.section / SA.header / SA.footer (Settings list sections), SA.valueRow (LabeledContent),
 * SA.sliderRow (PercentSliderRow), SA.appIcon (AppIconPreview), SA.popover and SA.actionSheet (confirmationDialog), SA.cover (full-screen cover),
 * SA.contentUnavailable (ContentUnavailableView), and the symbols below (ladybug, app.fill, person.crop.circle, wifi.exclamationmark, square.and.arrow.up, paperclip,
 * folder, location.fill, square.and.pencil, circle, gauge.with.dots.needle.67percent, chevron.forward).
 *
 * Sources: apple/Sources/HassUI/Features/Settings/SettingsScreen.swift (SettingsLinkRow, SettingsScreen), SettingsSectionHeader.swift,
 * Appearance/AppearanceSettingsSection.swift, AppIcon/*, HassCore/Settings/AppIconChoice.swift, HassDesign/AppIconArtwork.swift.
 */
(function () {
  'use strict';
  var h = Mock.h, I = Mock.icon, K = Mock.components;
  var SA = window.SA = window.SA || {};

  /* ---- local symbols (SF Symbol look-alikes, same 24 x 24 outline style as _kit/lib/symbols.js) ---- */
  var S = Mock.symbols;
  function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
  function p(d) { return '<path d="' + d + '"/>'; }
  function rc(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
  var add = {
    'ladybug': ['<ellipse cx="12" cy="13.6" rx="5.6" ry="6.4"/>' + p('M12 7.2v12.8M8.4 7.2a3.6 3.6 0 0 1 7.2 0M6.4 11H3.2M17.6 11h3.2M6.6 15.8H3.6M17.4 15.8h3M9.6 4.6 8 2.8M14.4 4.6 16 2.8')],
    'app.fill': [rc(4.5, 4.5, 15, 15, 4), rc(4, 4, 16, 16, 4.4)],
    'person.crop.circle': [c(12, 12, 9.2) + c(12, 9.6, 3) + p('M6.2 18.2c1-2.3 3.2-3.6 5.8-3.6s4.8 1.3 5.8 3.6')],
    'wifi.exclamationmark': [p('M3 9.4a13 13 0 0 1 14-2.6M5.8 12.7a9 9 0 0 1 6.2-2.6M8.8 15.8a4.6 4.6 0 0 1 3.2-1.1') + c(10, 19, .7) + p('M18.5 10.5v5M18.5 18.8v.2')],
    'square.and.arrow.up': [p('M12 15V3.5M8 7l4-3.8L16 7M7.5 10.5H6a1.5 1.5 0 0 0-1.5 1.5v7.5A1.5 1.5 0 0 0 6 21h12a1.5 1.5 0 0 0 1.5-1.5V12a1.5 1.5 0 0 0-1.5-1.5h-1.5')],
    'paperclip': [p('M20 11.4 12.2 19.2a5 5 0 0 1-7-7l8-8a3.3 3.3 0 0 1 4.7 4.7L10 16.8a1.7 1.7 0 0 1-2.4-2.4l7.1-7.1')],
    'folder': [p('M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2.2h8a1.5 1.5 0 0 1 1.5 1.5v8.8a1.5 1.5 0 0 1-1.5 1.5H5a1.5 1.5 0 0 1-1.5-1.5z')],
    'location.fill': [p('M20.4 3.6 3.8 10.6l6.4 2.4 2.4 6.4z'), '<path d="M20.4 3.6 3.8 10.6l6.4 2.4 2.4 6.4z"/>'],
    'square.and.pencil': [p('M11 5H6a1.5 1.5 0 0 0-1.5 1.5v11A1.5 1.5 0 0 0 6 19h11a1.5 1.5 0 0 0 1.5-1.5V13M17.8 3.7a1.8 1.8 0 0 1 2.5 2.5L12 14.5l-3.3.8.8-3.3z')],
    'circle': [c(12, 12, 8.5)],
  };
  Object.keys(add).forEach(function (k) { if (!S[k]) S[k] = add[k]; });
  if (S['person.crop.circle.fill'] && S['person.crop.circle'].length < 2) S['person.crop.circle'] = [S['person.crop.circle'][0], S['person.crop.circle.fill'][1]];
  if (!S['chevron.forward']) S['chevron.forward'] = S['chevron.right'];
  if (!S['gauge.with.dots.needle.67percent']) S['gauge.with.dots.needle.67percent'] = S['gauge.with.dots.needle.50percent'];

  /* ---- fixture data (gallery fixtures: no real server, token or name beyond the household's fixture names) ---- */
  SA.fx = {
    server: 'homeassistant.local:8123', version: '2026.10.2', build: '2610.26.01 (57) · 42edc57', name: 'Alex Morgan', sam: 'Sam Morgan',
    people: [
      { name: 'Alex Morgan', state: 'home', resident: 'alex', photo: 'a' },
      { name: 'Guest', state: 'home', resident: null },
      { name: 'Sam Morgan', state: 'not_home', resident: 'sam', photo: 'b' },
    ],
  };

  /* ---- CSS (tokens only through var(--...); everything text uses --fs-* so Dynamic Type applies) ---- */
  var css = [
    '.sa-wrap{display:flex;flex-direction:column;gap:24px;min-width:0}',
    '.sa-wrap.reg{max-width:704px;margin-left:auto;margin-right:auto}',
    '.ui-body > .sa-wrap.reg{width:calc(100% - 32px)}',
    '.sa-sec{display:flex;flex-direction:column;position:relative;min-width:0}',
    '.sa-hd{margin:0 0 6px 16px;font:600 var(--fs-sub)/1.25 var(--font);color:rgba(255,255,255,.85)}',
    '.in-sheet .sa-hd{color:var(--ink-sheet-2)}',
    '.sa-hd.sys{font-weight:400;font-size:var(--fs-foot);text-transform:uppercase;letter-spacing:.01em;color:rgba(255,255,255,.72)}',
    '.in-sheet .sa-hd.sys{color:var(--ink-sheet-2)}',
    '.sa-hd.field{color:var(--ink);font-weight:600;display:flex;flex-direction:column;gap:2px;margin-bottom:8px}',
    '.sa-hd.field span{font-weight:400;font-size:var(--fs-foot);color:var(--ink-sheet-2)}',
    '.sa-ft{margin:6px 16px 0;font-size:var(--fs-foot);line-height:1.3;color:rgba(255,255,255,.85)}',
    '.sa-ft.sys{color:rgba(255,255,255,.72)}',
    '.in-sheet .sa-ft{color:var(--ink-sheet-2)}',
    '.sa-solid{background:#1C1C1E!important}',
    '.in-sheet .sa-solid{background:var(--sheet-cell)!important}',
    '.sa-link .su{font-size:var(--fs-sub);white-space:normal}',
    '.sa-link .ti{white-space:normal}',
    '.sa-ico{width:34px;flex:none;display:grid;place-items:center;font-size:var(--fs-t3);color:var(--g-secondary-on-module)}',
    '.in-sheet .sa-ico{color:var(--ink-sheet-2)}',
    '.sa-ico.app{border-radius:7px}',
    '.sa-appicon{display:block;border-radius:22.37%;overflow:hidden;box-shadow:inset 0 0 0 .5px rgba(255,255,255,.14);flex:none}',
    '.g-light .sa-appicon,.g-light.sa-appicon{box-shadow:0 0 0 .5px rgba(0,0,0,.14)}',
    '.sa-appicon svg{display:block;width:100%;height:100%}',
    '.sa-val .ti{flex:1;min-width:0}',
    '.ts-ax5 .sa-val{flex-direction:column;align-items:flex-start;gap:6px}',
    '.ts-ax5 .sa-val .va{text-align:left}',
    '.ts-ax5 .sa-val .tx{width:100%}',
    '.sa-val .va{color:rgba(255,255,255,.72);font-size:var(--fs-body);text-align:right;min-width:0;overflow-wrap:anywhere}',
    '.in-sheet .sa-val .va{color:rgba(235,235,245,.72)}',
    '.g-light .sa-val .va{color:rgba(60,60,67,.72)}',
    '.sa-col{flex-direction:column;align-items:stretch!important;gap:8px!important;padding-top:10px!important;padding-bottom:10px!important}',
    '.sa-col .l1{display:flex;justify-content:space-between;align-items:baseline;gap:8px;font-size:var(--fs-body)}',
    '.sa-col .l1 .v{color:var(--g-secondary-on-module);font-variant-numeric:tabular-nums;font-weight:400}',
    '.sa-col.disabled{opacity:.5}',
    '.sa-btnrow{justify-content:flex-start}',
    '.sa-btnrow.center{justify-content:center}',
    '.sa-btnrow .bt{font-size:var(--fs-body);color:var(--ink-action,#409CFF);background:none;border:0;font-family:inherit;padding:0;min-height:44px;text-align:left;cursor:pointer}',
    '.sa-btnrow.center .bt{text-align:center;width:100%}',
    '.sa-btnrow .bt.danger{color:var(--ink-danger,#FF6961)}',
    '.sa-btnrow .bt[disabled]{opacity:.4;cursor:default}',
    '.sa-cover{position:absolute;inset:0;z-index:50;display:flex;flex-direction:column}',
    '.sa-under{position:absolute;inset:0}',
    '.sa-scroll{flex:1 1 auto;min-height:0;overflow-y:auto;scrollbar-width:none;padding:8px 16px 28px;position:relative}',
    '.sa-scroll::-webkit-scrollbar{display:none}',
    '.sa-pop{position:absolute;z-index:70;width:min(270px,calc(100% - 32px));border-radius:22px;background:rgba(44,44,46,.94);backdrop-filter:blur(30px);-webkit-backdrop-filter:blur(30px);color:#fff;box-shadow:0 12px 40px rgba(0,0,0,.45);overflow:hidden;text-align:center;font-family:var(--font)}',
    '.g-light .sa-pop{background:rgba(250,250,252,.95);color:#000;box-shadow:0 12px 40px rgba(0,0,0,.22)}',
    '.sa-pop .bd{padding:14px 16px 10px}.sa-pop .ti{font:600 var(--fs-foot)/1.25 var(--font);color:var(--ink-sheet-2,rgba(235,235,245,.6))}',
    '.sa-pop .ms{font-size:var(--fs-foot);margin-top:4px;color:var(--ink-sheet-2,rgba(235,235,245,.6))}',
    '.sa-pop button{display:block;width:100%;min-height:44px;border:0;border-top:.5px solid rgba(128,128,128,.4);background:none;color:var(--ink-action,#0A84FF);font:400 var(--fs-body)/1.2 var(--font);padding:8px 12px;cursor:pointer}',
    '.sa-pop button.destructive{color:var(--ink-danger,#FF6961)}',
    '.sa-sheetact{position:absolute;left:8px;right:8px;bottom:calc(var(--safe-bottom,20px) + 4px);z-index:95;display:flex;flex-direction:column;gap:8px;font-family:var(--font)}',
    '.sa-sheetact .card{border-radius:26px;background:rgba(44,44,46,.94);backdrop-filter:blur(30px);-webkit-backdrop-filter:blur(30px);color:#fff;overflow:hidden;text-align:center}',
    '.g-light .sa-sheetact .card{background:rgba(250,250,252,.95);color:#000}',
    '.sa-sheetact .bd{padding:14px 16px 10px;font-size:var(--fs-foot);color:var(--ink-sheet-2,rgba(235,235,245,.6))}',
    '.sa-sheetact .bd b{display:block;font-weight:600;margin-bottom:2px}',
    '.sa-sheetact button{display:block;width:100%;min-height:56px;border:0;border-top:.5px solid rgba(128,128,128,.4);background:none;color:var(--ink-action,#0A84FF);font:400 var(--fs-hd)/1.2 var(--font);cursor:pointer}',
    '.sa-sheetact button.destructive{color:var(--ink-danger,#FF6961)}',
    '.sa-sheetact .cancel button{border-top:0;font-weight:600}',
    '.sa-cu{display:flex;flex-direction:column;align-items:center;text-align:center;gap:8px;padding:32px 24px;color:var(--ink)}',
    '.sa-cu .gl{font-size:calc(var(--fs-t1)*1.5);color:var(--ink-sheet-2)}',
    '.sa-cu .t{font:600 var(--fs-t3)/1.2 var(--font-d)}',
    '.sa-cu .d{font-size:var(--fs-sub);color:var(--ink-sheet-2);max-width:32ch}',
    '.sa-cu button{margin-top:6px;min-height:44px;padding:0 20px;border:0;border-radius:999px;background:var(--fill-tertiary);color:var(--ink-action);font:600 var(--fs-body)/1.2 var(--font);cursor:pointer}',
    '.sa-slot{display:flex;align-items:center;gap:8px}',
    '.sa-tight{gap:12px}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'sa-style'; st.textContent = css; document.head.appendChild(st);

  /* ---- rows ---- */

  /** SettingsLinkRow: glyph (or app icon preview), 17 pt title, 15 pt wrapping subtitle, trailing chevron. At AX sizes the icon sits above the text.
   *  props: {title, subtitle, symbol, appIcon?:choice key, chevron?:boolean (default true), ctx?} */
  SA.link = function (o) {
    var ctx = o.ctx || Mock.current || {}, ax = !!ctx.axSize;
    var icon = o.appIcon ? h('span.sa-ico.app', SA.appIcon(o.appIcon, 30)) : h('span.sa-ico', { html: I(o.symbol) });
    var chev = o.chevron === false ? null : h('span.chev', { html: I('chevron.right', { weight: 2.4 }), 'aria-hidden': 'true' });
    var label = o.title + '. ' + o.subtitle;
    return h('button.ui-mrow.sub.press.sa-link', { type: 'button', 'aria-label': label, style: { '--sep-inset': 'calc(16px + 34px + 12px)' } },
      ax ? null : icon, h('span.tx', ax ? icon : null, h('span.ti', o.title), h('span.su', o.subtitle)), chev);
  };
  /** LabeledContent: label left in the primary ink, value right in the secondary ink. */
  SA.valueRow = function (label, value, o) {
    o = o || {};
    return h('div.ui-mrow.sa-val', { role: 'group', 'aria-label': label + ', ' + (typeof value === 'string' ? value : (o.valueLabel || '')) }, h('span.ti', label), h('span.va', value));
  };
  /** The About section's Version row (AboutSettingsSection / VersionRow): glyph, title and the build text trailing, or under the title
   *  once it no longer fits (Accessibility sizes: the glyph is dropped, the text wraps). One button that copies the build. */
  SA.versionRow = function (value, o) {
    var ctx = (o && o.ctx) || Mock.current || {}, ax = !!ctx.axSize;
    return h('button.ui-mrow.press.sa-val.sa-ver', { type: 'button', 'aria-label': 'Version, ' + value.replace(' · ', ', commit ').replace(/ \((\d+)\)/, ', build $1'), 'data-testid': 'settings.version' },
      ax ? null : h('span.sa-ico', { html: I('info.circle') }), h('span.tx', h('span.ti', 'Version'), ax ? h('span.su', value) : null), ax ? null : h('span.va', value));
  };
  /** A Toggle row in a list. */
  SA.toggleRow = function (title, on) { return h('div.ui-mrow', h('span.tx', h('span.ti', title)), h('span.acc', K.Toggle({ on: on, label: title }))); };
  /** PercentSliderRow: title and value on one line, the system slider under it (0 to 100 in steps of 5). */
  SA.sliderRow = function (title, pct, o) {
    o = o || {};
    return h('div.ui-mrow.sa-col' + (o.disabled ? '.disabled' : ''), h('div.l1', h('span', title), h('span.v', pct + '%')), K.Slider({ value: pct / 100, label: title }));
  };
  /** A plain button row (tint text, or red for destructive; centred for Sign Out). */
  SA.buttonRow = function (title, o) {
    o = o || {};
    var b = h('button.bt' + (o.danger ? '.danger' : ''), { type: 'button' }, title); if (o.disabled) b.disabled = true;
    return h('div.ui-mrow.sa-btnrow' + (o.center ? '.center' : ''), b);
  };
  /** A menu or picker row with a leading symbol: Attach Media. */
  SA.labelRow = function (symbol, title, o) {
    o = o || {};
    var b = h('button.ui-mrow.press', { type: 'button', style: { opacity: o.disabled ? .4 : 1 } }, h('span.rg', { style: { color: 'var(--ink-action)' }, html: I(symbol) }), h('span.tx', h('span.ti', { style: { color: 'var(--ink-action)' } }, title)));
    if (o.disabled) b.disabled = true; return b;
  };

  /* ---- sections ---- */

  /** SettingsSectionHeader (15 Semibold, Title Case) or, with `sys`, the system's own grouped header (what FormHeader and Section("...") keep). */
  SA.header = function (t, o) { return h('div.sa-hd' + (o && o.sys ? '.sys' : ''), { role: 'heading', 'aria-level': '2' }, t); };
  SA.footer = function (t, o) { return h('div.sa-ft' + (o && o.sys ? '.sys' : ''), t); };
  /** props: {header?, footer?, rows:[Node], sys?:boolean (system header/footer style), noglyph?:boolean, solid?:boolean (system cell, not the module), dense?} */
  SA.section = function (o) {
    var list = K.ModuleList({ rows: o.rows, hasGlyphs: !o.noglyph, density: o.dense ? 'dense' : 'thin' });
    if (o.solid) list.classList.add('sa-solid');
    return h('section.sa-sec', (o.headerNode || o.header) ? (o.headerNode || SA.header(o.header, o)) : null, list, o.footerNode || (o.footer ? SA.footer(o.footer, o) : null));
  };
  /** The column of sections; centred at 704 pt on regular width (an inset-grouped list on iPad uses the readable width). */
  SA.wrap = function (ctx, kids) { return h('div.sa-wrap' + (ctx.regular ? '.reg' : ''), kids); };

  /* ---- ContentUnavailableView ---- */
  SA.contentUnavailable = function (o) {
    return h('div.sa-cu', { role: 'group', 'aria-label': o.title + '. ' + o.description }, h('span.gl', { html: I(o.symbol) }), h('div.t', o.title), h('div.d', o.description), o.action ? h('button', { type: 'button' }, o.action) : null);
  };

  /* ---- App icon art (HassDesign/AppIconArtwork.swift: dusk glass, tint at 0.86, house and heart; 100-unit coordinates, glyph 80% of the width) ---- */
  SA.icons = [
    { id: 'navySky', name: 'Navy + Sky', tint: '#0E1E46', glyph: '#7CC4FF' }, { id: 'tealMint', name: 'Teal + Mint', tint: '#063A3E', glyph: '#6EE7C8' },
    { id: 'plumLilac', name: 'Plum + Lilac', tint: '#3A1648', glyph: '#D3A8FF' }, { id: 'forestGreen', name: 'Forest + Green', tint: '#10301E', glyph: '#9BE29B' },
    { id: 'burgundyRose', name: 'Burgundy + Rose', tint: '#48101E', glyph: '#FF9EB0' }, { id: 'indigoPeriwinkle', name: 'Indigo + Periwinkle', tint: '#221C5A', glyph: '#A8B4FF' },
    { id: 'espressoAmber', name: 'Espresso + Amber', tint: '#342014', glyph: '#FFB35C' }, { id: 'midnightGold', name: 'Midnight + Gold', tint: '#101630', glyph: '#FFD36B' },
  ];
  SA.iconById = function (id) { return SA.icons.filter(function (i) { return i.id === id; })[0] || SA.icons[0]; };
  var uid = 0;
  /** An app icon preview of `side` pt (decorative), clipped to the system corner (22.37%). */
  SA.appIcon = function (id, side) {
    var ic = SA.iconById(id), n = 'sai' + (++uid);
    var HOUSE = 'M50 12 90 44Q92 46 89 47L82 47 82 84Q82 88 78 88L22 88Q18 88 18 84L18 47 11 47Q8 46 10 44Z';
    var WIN = [[25, 59], [37, 59], [25, 71], [37, 71]].map(function (w) { return 'M' + w[0] + ' ' + w[1] + 'h9.5v9.5h-9.5z'; }).join('');
    var HEART = 'M50 88C20 66 8 50 8 34C8 20 19 10 32 10C40 10 46 14 50 21C54 14 60 10 68 10C81 10 92 20 92 34C92 50 80 66 50 88Z';
    var svg = '<svg viewBox="0 0 100 100" aria-hidden="true" xmlns="http://www.w3.org/2000/svg"><defs>' +
      '<linearGradient id="' + n + 'b" gradientUnits="userSpaceOnUse" x1="34.2" y1="-9.1" x2="65.8" y2="109.1"><stop offset="0" stop-color="#23324D"/><stop offset=".48" stop-color="#4B4A52"/><stop offset="1" stop-color="#7A5E3A"/></linearGradient>' +
      '<radialGradient id="' + n + 'g1" gradientUnits="userSpaceOnUse" cx="74" cy="80" r="45.8"><stop offset="0" stop-color="#FFB866" stop-opacity=".55"/><stop offset="1" stop-color="#FFB866" stop-opacity="0"/></radialGradient>' +
      '<radialGradient id="' + n + 'g2" gradientUnits="userSpaceOnUse" cx="22" cy="72" r="38.2"><stop offset="0" stop-color="#FFD696" stop-opacity=".32"/><stop offset="1" stop-color="#FFD696" stop-opacity="0"/></radialGradient>' +
      '<linearGradient id="' + n + 'l" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".18"/><stop offset=".46" stop-color="#fff" stop-opacity="0"/></linearGradient>' +
      '<mask id="' + n + 'm" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100"><rect width="100" height="100" fill="#fff"/><g transform="translate(55 60) scale(.4)"><path d="' + HEART + '" fill="#000" stroke="#000" stroke-width="16" stroke-linejoin="round"/></g></mask></defs>' +
      '<rect width="100" height="100" fill="url(#' + n + 'b)"/><rect width="100" height="100" fill="url(#' + n + 'g1)"/><rect width="100" height="100" fill="url(#' + n + 'g2)"/>' +
      '<rect width="100" height="100" fill="' + ic.tint + '" fill-opacity=".86"/><rect width="100" height="100" fill="url(#' + n + 'l)"/>' +
      '<g transform="translate(10 10) scale(.8)"><g mask="url(#' + n + 'm)"><path d="' + HOUSE + WIN + '" fill="' + ic.glyph + '" fill-rule="evenodd"/></g><g transform="translate(55 60) scale(.4)"><path d="' + HEART + '" fill="' + ic.glyph + '"/></g></g></svg>';
    return h('span.sa-appicon', { style: { width: side + 'px', height: side + 'px' }, html: svg });
  };

  /* ---- confirmation dialogs (system UI) ---- */

  /** iOS 26 and later: the confirmationDialog is a popover anchored to its source, with no Cancel button (an outside tap cancels). Position it with
   *  `top`/`bottom`/`left`/`right` in the style, inside a position:relative parent. props: {title?, message?, buttons:[{title, role}], style} */
  SA.popover = function (o) {
    var bs = (o.buttons || []).filter(function (b) { return b.role !== 'cancel'; });
    var el = h('div.sa-pop', { role: 'dialog', 'aria-label': o.title || 'Confirm', style: o.style || null }, h('div.bd', o.title ? h('div.ti', o.title) : null, o.message ? h('div.ms', o.message) : null),
      bs.map(function (b) { return h('button' + (b.role === 'destructive' ? '.destructive' : ''), { type: 'button' }, b.title); }));
    return el;
  };
  /** iOS 17 to 25 on a compact window: the action sheet from the bottom with a separate Cancel card. props: {title, message, buttons} (a cancel-role button is the Cancel card) */
  SA.actionSheet = function (o) {
    var bs = o.buttons || [], cancel = bs.filter(function (b) { return b.role === 'cancel'; })[0];
    return h('div.ui-alert-scrim', { style: { placeItems: 'end stretch' } }, h('div.sa-sheetact', { role: 'dialog', 'aria-label': o.title },
      h('div.card', h('div.bd', h('b', o.title), o.message || null), bs.filter(function (b) { return b.role !== 'cancel'; }).map(function (b) { return h('button' + (b.role === 'destructive' ? '.destructive' : ''), { type: 'button' }, b.title); })),
      cancel ? h('div.card.cancel', h('button', { type: 'button' }, cancel.title)) : null));
  };
  /** A scrim over a host that holds an alert node (the kit's Alert), in the sheet's appearance. */
  SA.alertScrim = function (ctx, alert, dark) { return h('div.ui-alert-scrim.' + ((dark || ctx.appearance === 'dark') ? 'g-dark' : 'g-light'), alert); };

  /* ---- a full-screen cover (fullScreenCover: no grabber, no detents, nothing scales back) ---- */
  /** props: {title, leading?:'none'|'back', trailing?:Node|'close', content:Node, presenter?:Node, ground?:css, cell?:css, overlay?:Node|Node[], scrollEnd?:boolean}
   *  The cover inherits the shell's dark scheme (MainTabView preferredColorScheme(.dark)); a full-screen cover is the base elevation level, so the grouped
   *  ground is systemGroupedBackground dark (#000) and the cells secondarySystemGroupedBackground (#1C1C1E). */
  SA.cover = function (ctx, o) {
    var d = ctx.device;
    var host = h('div.ui-host', { dataset: { indicator: 'light' }, style: { background: '#000' } });
    if (o.presenter) host.appendChild(h('div.sa-under', o.presenter));
    var sheet = h('div.ui-sheet.in-sheet.g-dark.sa-cover', { role: 'dialog', aria: { modal: 'true', label: o.title }, style: { '--sheet-ground': o.ground || '#000', '--sheet-cell': o.cell || '#1C1C1E', paddingTop: d.safeTop + 'px', paddingBottom: Math.max(0, d.safeBottom - 10) + 'px' } });
    var modal = K.HassModal({ title: o.title, leading: o.leading || 'none', trailing: o.trailing === undefined ? 'close' : o.trailing, content: o.content });
    var scroll = modal.querySelector('.ui-mscroll'); if (scroll && o.scrollEnd) requestAnimationFrame(function () { requestAnimationFrame(function () { scroll.scrollTop = scroll.scrollHeight; }); });
    if (scroll && o.bleed) { scroll.style.padding = '0'; scroll.style.overflow = 'hidden'; }
    sheet.appendChild(modal);
    host.appendChild(sheet);
    Mock.append(host, o.overlay || null);
    return host;
  };

  /* ---- people, monograms ---- */
  /** The initials disc; `photo` ('a'..'d', Mock.portrait) draws the person's Home Assistant photo over it with a 0.5 pt hairline (AvatarView). */
  SA.monogram = function (name, side, fill, photo) {
    var ini = name ? name.split(/\s+/).map(function (w) { return w[0]; }).join('').slice(0, 2).toUpperCase() : '';
    var m = h('span', { 'aria-hidden': 'true', style: { width: side + 'px', height: side + 'px', borderRadius: '50%', background: fill || '#0071E3', color: '#fff', display: 'grid', placeItems: 'center', flex: 'none', position: 'relative', font: '600 ' + Math.round(side * .4) + 'px var(--font)' } }, ini || (name === '' ? null : '?'));
    if (photo) { m.appendChild(Mock.portraitLayer(photo)); m.appendChild(h('span.ui-photo-hair')); }
    return m;
  };

  /** Swatches for component mockups: the builder drawn on the page surface (module over a gradient, always dark) and on the sheet surface (follows Sheet appearance). */
  SA.surfaces = function (ctx, build, which) {
    var out = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } });
    (which || ['page', 'sheet']).forEach(function (surface) {
      var box = h('div.k-swatch.' + (surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light')), { style: { maxWidth: '640px' } },
        h('div.k-cap', surface === 'page' ? 'page surface (always dark, on the wallpaper)' : 'sheet surface (' + ctx.appearance + ')'), build(surface, ctx));
      out.appendChild(box);
    });
    return out;
  };
})();
