/* Inventory batch helper (author batch `inventory`). Loaded with <script src> after kit.js by every inventory mockup:
 *   pages/inventory/inventory-space, modals/inventory/*, components/inventory/*, and the design components that this batch owns.
 * Everything here is a LOCAL helper (AUTHORING.md: "if the kit lacks a component, add a local helper and list it in notes as promote to kit"):
 *   - SF Symbol stand-ins the kit lacks (basket, barcode.viewfinder, keyboard, chevron.forward ...): promote to kit/lib/symbols.js
 *   - Mock.inv.row / list / page / editor / scan builders for Features/Inventory (InventoryRow, InventoryScreen, InventoryItemEditor, ScanItemSheet)
 *   - Mock.inv.alertField (an alert with a text field), Mock.inv.askSheet (confirmationDialog), Mock.inv.swatch (component mockup swatch),
 *     Mock.inv.embed (a scaled device frame inside a component mockup)
 * Sources: apple/Sources/HassUI/Features/Inventory/*, apple/Sources/HassCore/Inventory/{InventoryCatalog,InventoryEditorModel,ScanItemModel}.swift.
 * Fixture data = EverShelfFixtureServer.sample (synthetic rows, dates relative to today = Fri Oct 23 2026, the kit's clock).
 */
(function () {
  var h = Mock.h, I = Mock.icon, K = function () { return Mock.components; };
  var Inv = Mock.inv = {};

  /* ------------------------------------------------------------------ symbols (promote to kit) */
  function p(d) { return '<path d="' + d + '"/>'; }
  var S = Mock.symbols;
  function add(name, outline, filled) { if (!S[name]) S[name] = filled ? [outline, filled] : [outline]; }
  function outline(n) { var v = S[n]; return Array.isArray(v) ? v[0] : v; }
  add('chevron.forward', outline('chevron.right'));
  add('chevron.backward', outline('chevron.left'));
  add('basket', p('M3.5 10h17l-1.6 9a1.5 1.5 0 0 1-1.5 1.2H6.6A1.5 1.5 0 0 1 5.100 19z') + p('M8 10 11 4M16 10l-3-6M9 13.5v3.5M12 13.5v3.5M15 13.5v3.5'));
  add('barcode.viewfinder', p('M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2') + p('M8 8.500v7M11 8.500v7M13.500 8.500v7M16 8.500v7'));
  add('barcode', p('M3.500 6v12M6.500 6v12M9.500 6v12M12.200 6v12M14.800 6v12M17.500 6v12M20.500 6v12'));
  add('keyboard', '<rect x="2.500" y="6" width="19" height="12" rx="2.500"/>' + p('M6.500 10h.01M9.500 10h.01M12.500 10h.01M15.500 10h.01M18 10h.01M7 14h10'));
  add('square.and.pencil', p('M11 5H6.500A2.500 2.500 0 0 0 4 7.500v10A2.500 2.500 0 0 0 6.500 20h10a2.500 2.500 0 0 0 2.500-2.500V13M18 3.500 20.500 6 12 14.500l-3.500 1 1-3.500z'));
  add('battery.100percent', '<rect x="2.500" y="8" width="17" height="8.500" rx="2.200"/>' + p('M21.500 11v2.500M5 10.300h12v3.900H5z'));
  add('calendar.badge.clock', '<rect x="3.500" y="5.500" width="15" height="14" rx="2.200"/>' + p('M3.500 10h15M8 3.500v3.500M14 3.500v3.500') + '<circle cx="18" cy="17" r="4" fill="var(--sheet-cell, #2C2C2E)"/>' + p('M18 15v2.200l1.300.8'));
  add('clock.arrow.circlepath', p('M4.200 12a7.800 7.800 0 1 0 2.300-5.500M4 4.500v3.500h3.500M12 8.500v3.800l2.500 1.500'));
  add('antenna.radiowaves.left.and.right', '<circle cx="12" cy="12" r="1.600"/>' + p('M8.500 8.500a5 5 0 0 0 0 7M15.500 8.500a5 5 0 0 1 0 7M5.800 5.800a9 9 0 0 0 0 12.400M18.200 5.800a9 9 0 0 1 0 12.400'));
  add('trash.fill', outline('trash'));
  S['clock.fill'] = ['', '<circle cx="12" cy="12" r="9.200"/><path d="M12 7v5.200l3 1.800" fill="none" stroke="#1C1C1E" stroke-width="1.900" stroke-linecap="round" stroke-linejoin="round"/>'];

  /* ------------------------------------------------------------------ local CSS (tokens only; promote to kit) */
  var css = [
    '.inv-list{border-radius:var(--radius-module);overflow:hidden;background:var(--g-module-dense);color:#fff}',
    '.in-sheet .inv-list{background:var(--sheet-cell);color:var(--ink)}',
    '.k-reduce-transparency .inv-list{background:#141416}.k-reduce-transparency.in-sheet .inv-list,.k-reduce-transparency .in-sheet .inv-list{background:var(--sheet-cell)}',
    '.inv-swipe{position:relative;overflow:hidden}',
    '.inv-swipe + .inv-swipe .inv-row::before{content:"";position:absolute;top:0;left:16px;right:0;height:.5px;background:var(--sep,rgba(255,255,255,.14))}',
    '.inv-row{position:relative;display:flex;align-items:center;gap:8px;min-height:64px;padding:8px 4px 8px 16px;background:transparent;transition:background-color var(--t-state) var(--ease-state)}',
    '.inv-row.sel{background:color-mix(in srgb,var(--ink-action,#409CFF) 18%,transparent)}',
    '.inv-row>.inv-copy{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}',
    '.inv-name{font-size:var(--fs-body);color:inherit;line-height:1.25}',
    '.inv-name.redact{color:transparent;background:color-mix(in srgb,currentColor 0%,rgba(255,255,255,.3));border-radius:5px;align-self:flex-start;user-select:none}',
    '.in-sheet .inv-name.redact{background:rgba(120,120,128,.3)}',
    '.inv-sub{display:flex;gap:4px;align-items:baseline;font-size:var(--fs-sub);color:var(--g-secondary-on-module);line-height:1.25}',
    '.in-sheet .inv-sub{color:var(--ink-sheet-2)}',
    '.inv-sub .ui-sym{width:.8em;height:.8em}',
    '.inv-sub.soon{color:var(--g-orange)}.inv-sub.expired{color:var(--g-red)}',
    '.in-sheet .inv-sub.soon{color:var(--ink-warning)}.in-sheet .inv-sub.expired{color:var(--ink-error)}',
    '.inv-err{font-size:var(--fs-foot);color:var(--g-red)}.in-sheet .inv-err{color:var(--ink-error)}',
    '.inv-tail{display:flex;align-items:center;gap:4px;flex:none}',
    '.inv-qty{font-size:var(--fs-body);font-variant-numeric:tabular-nums;color:var(--g-secondary-on-module);padding-right:4px}',
    '.in-sheet .inv-qty{color:var(--ink-sheet-2)}',
    '.inv-btn{width:calc(44px*var(--sc));height:calc(44px*var(--sc));min-width:44px;display:grid;place-items:center;background:none;border:0;padding:0;color:var(--g-secondary-on-module);cursor:pointer;font:inherit;font-size:var(--fs-body)}',
    '.in-sheet .inv-btn.chev{color:var(--ink-sheet-2)}',
    '.inv-btn.cart{color:var(--ink-action,#409CFF)}.inv-btn.cart.added{color:#30D158}.g-light .inv-btn.cart.added,.in-sheet.g-light .inv-btn.cart.added{color:#1E7B34}',
    '.inv-btn.chev{font-size:var(--fs-sub);font-weight:600;margin-left:4px}',
    '.inv-btn .ui-arc{color:var(--ink,#fff)}',
    '.ts-ax5 .inv-row{flex-direction:column;align-items:flex-start;gap:8px}.ts-ax5 .inv-tail{align-self:flex-start}',
    '.inv-act{border:0;position:absolute;top:0;bottom:0;display:flex;align-items:center;justify-content:center;flex-direction:column;gap:4px;color:#fff;font:600 var(--fs-foot)/1.15 var(--font);text-align:center;padding:0 12px;z-index:2}',
    '.inv-act.lead{left:0;background:#0071E3;width:112px}.inv-act.trail{right:0;background:#D70015;width:88px}',
    '.inv-act .ui-sym{width:22px;height:22px}',
    '.inv-face{position:relative;transition:transform var(--t-standard) var(--ease-standard);background:inherit;z-index:1}',
    /* page furniture inside the inventory page */
    '.inv-col{display:flex;flex-direction:column;gap:12px}.inv-col>*{margin-left:16px;margin-right:16px}',
    '.inv-col>.inv-summary{margin:0 16px;padding:0 16px;font-size:var(--fs-sub);color:var(--g-secondary-on-wallpaper)}',
    '.inv-search{align-self:center;display:flex;gap:8px;align-items:center;padding:8px;border-radius:999px;background:rgba(60,60,60,.55);backdrop-filter:blur(20px);color:#fff;font-size:var(--fs-sub)}',
    '.inv-sec{display:flex;flex-direction:column;gap:8px}.inv-sec+.inv-sec{margin-top:6px}',
    /* empty state */
    '.inv-empty{display:flex;flex-direction:column;align-items:center;gap:8px;text-align:center;padding:24px 32px;color:#fff}',
    '.inv-empty .ico{font-size:34px;color:var(--g-secondary-on-wallpaper);padding-bottom:4px}.inv-empty .ico .ui-sym{width:1.25em;height:1.25em}',
    '.inv-empty h2{margin:0;font:700 var(--fs-t2)/1.2 var(--font-d)}',
    '.inv-empty p{margin:0;font-size:var(--fs-body);color:var(--g-secondary-on-wallpaper)}',
    '.inv-empty .ui-primary{max-width:320px;margin-top:12px}',
    /* editor */
    '.inv-form{display:flex;flex-direction:column;gap:20px;padding-bottom:8px}',
    '.inv-form .ui-field{min-height:52px}',
    '.inv-form .ui-field .va{display:inline-flex;align-items:center;gap:10px}',
    '.inv-date{white-space:nowrap}.ts-ax5 .inv-form .ui-field.stack,.ts-ax5 .inv-scan .ui-field.stack{flex-wrap:wrap}.ts-ax5 .ui-field.stack .va{flex-basis:100%;justify-content:space-between}',
    '.va.ctl{display:inline-flex;align-items:center;gap:10px}.inv-scan .ui-field .val{min-width:20px;text-align:right}',
    '.inv-step{display:inline-flex;border-radius:9px;background:var(--fill-tertiary);overflow:hidden;flex:none}',
    '.inv-step button{width:calc(47px);height:32px;border:0;background:none;color:var(--ink);display:grid;place-items:center;cursor:pointer;padding:0}',
    '.inv-step button+button{border-left:.5px solid var(--sep)}.inv-step button[disabled]{opacity:.35}',
    '.inv-date{background:var(--fill-tertiary);color:var(--ink);padding:6px 11px;border-radius:8px;font-size:var(--fs-body);font-variant-numeric:tabular-nums}',
    '.inv-del{color:var(--ink-danger);justify-content:space-between}.inv-del .lb{color:var(--ink-danger)}',
    '.inv-link{color:var(--ink-action)}.inv-link .lb{color:var(--ink-action)}',
    '.inv-btnrow{width:100%;font:inherit;text-align:left;border:0;cursor:pointer}',
    '.inv-form .ui-field.busy{opacity:.55}',
    '.inv-pane{--sheet-ground:#000;--sheet-cell:#1C1C1E;background:#000;color:#fff;border-left:.5px solid rgba(255,255,255,.14);display:flex;flex-direction:column;flex:1;min-width:0}',
    '.inv-pane .hd{display:flex;align-items:center;gap:12px;padding:0 16px;min-height:56px;border-bottom:.5px solid var(--sep,rgba(255,255,255,.14))}',
    '.inv-pane .hd h2{flex:1;margin:0;font:600 var(--fs-hd)/1.25 var(--font)}',
    '.inv-pane .bd{padding:20px 16px 24px;overflow:hidden}',
    /* scan */
    '.inv-scan{display:flex;flex-direction:column;gap:20px}',
    '.inv-scan .lead{margin:0;padding:0 16px;font-size:var(--fs-sub);color:var(--ink-sheet-2)}',
    '.inv-cam{position:relative;aspect-ratio:4/5;max-width:400px;width:100%;margin:0 auto;border-radius:var(--radius-module);overflow:hidden;background:#000;color:#fff;display:flex;align-items:center;justify-content:center}',
    '.inv-cam.live::before{content:"";position:absolute;inset:0;background:radial-gradient(90% 70% at 50% 40%,#3a3d33,#15170f 70%,#080906)}',
    '.inv-cam .reticle{position:absolute;left:12%;right:12%;top:38%;height:24%;border:2px solid rgba(255,255,255,.55);border-radius:12px}',
    '.inv-cam .reticle::after{content:"";position:absolute;left:8%;right:8%;top:50%;height:1.5px;background:rgba(255,80,60,.8)}',
    '.inv-cam .msg{position:relative;display:flex;flex-direction:column;align-items:center;gap:8px;padding:16px;text-align:center;font-size:var(--fs-body)}',
    '.inv-cam .msg .ui-sym{width:42px;height:42px}',
    '.inv-cam .sim{display:flex;flex-direction:column;align-items:center;gap:12px;position:relative}',
    '.inv-cam .sim .ui-sym{width:56px;height:56px;opacity:.8}',
    '.inv-cam .sim button{background:#0071E3;color:#fff;border:0;border-radius:999px;padding:10px 20px;font:600 var(--fs-body)/1.2 var(--font)}',
    '.inv-pill{position:absolute;bottom:16px;left:12px;right:12px;margin:auto;width:max-content;max-width:calc(100% - 24px);display:flex;gap:8px;align-items:center;padding:8px 14px;border-radius:999px;background:rgba(60,60,60,.55);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);color:#fff;font:600 var(--fs-sub)/1.25 var(--font)}',
    '.inv-manual{display:flex;align-items:center;justify-content:center;gap:8px;min-height:44px;color:var(--ink-action);background:none;border:0;font:inherit;font-size:var(--fs-body);cursor:pointer;width:100%}',
    '.inv-foot{flex:none;display:flex;flex-direction:column;gap:8px;padding:8px 16px;background:var(--sheet-ground)}',
    '.inv-gray{display:flex;align-items:center;justify-content:center;width:100%;min-height:50px;border-radius:999px;border:0;background:color-mix(in srgb,var(--ink) 15%,transparent);color:var(--ink);font:600 var(--fs-hd)/1.2 var(--font);cursor:pointer;padding:8px 24px}',
    '.inv-gray[disabled]{opacity:.4}',
    '.inv-product{display:flex;align-items:center;gap:12px;padding:4px 0}',
    '.inv-product .tile{width:calc(56px*var(--sc));height:calc(56px*var(--sc));border-radius:var(--radius-chip);background:var(--fill-tertiary);display:grid;place-items:center;color:var(--ink-sheet-2);font-size:var(--fs-t2);flex:none}',
    '.inv-product .nm{font:600 var(--fs-hd)/1.25 var(--font)}.inv-product .bc{font-size:var(--fs-sub);color:var(--ink-sheet-2)}',
    '.inv-result{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;min-height:180px;font:600 var(--fs-hd)/1.25 var(--font);text-align:center}',
    '.inv-result .okc{color:var(--ink-success);font-size:64px}.inv-result .okc .ui-sym{width:1em;height:1em}',
    '.inv-proc{display:flex;gap:12px;align-items:center;justify-content:center;min-height:120px;font:600 var(--fs-hd)/1.25 var(--font)}',
    '.inv-qrow{display:flex;align-items:center;gap:12px}.inv-qrow .lb{flex:1}.inv-qrow .val{min-width:44px;max-width:80px;text-align:right;color:var(--ink)}',
    /* prompts */
    '.inv-field{margin:12px 16px 0;padding:8px 10px;border-radius:8px;background:rgba(255,255,255,.1);border:.5px solid rgba(255,255,255,.2);text-align:left;font-size:var(--fs-body);color:#fff}',
    '.g-light .inv-field{background:rgba(0,0,0,.05);border-color:rgba(0,0,0,.2);color:#000}',
    '.inv-ask{position:absolute;inset:0;z-index:90;background:rgba(0,0,0,.4);display:flex;align-items:flex-end;justify-content:center;padding:8px}',
    '.inv-ask .sheet{width:100%;max-width:420px;display:flex;flex-direction:column;gap:8px}',
    '.inv-ask .grp{border-radius:26px;background:rgba(44,44,46,.94);backdrop-filter:blur(30px);overflow:hidden;color:#fff;text-align:center}',
    '.g-light .inv-ask .grp{background:rgba(250,250,250,.94);color:#000}',
    '.inv-ask .ti{padding:14px 16px;font-size:var(--fs-foot);font-weight:600;color:rgba(235,235,245,.6);border-bottom:.5px solid rgba(128,128,128,.4)}',
    '.g-light .inv-ask .ti{color:rgba(60,60,67,.6)}',
    '.inv-ask button{display:block;width:100%;min-height:56px;border:0;background:none;font:400 calc(var(--fs-body) + 3px)/1.2 var(--font);color:#0A84FF;cursor:pointer;padding:8px 16px}',
    '.inv-ask button.destructive{color:#FF6961}.g-light .inv-ask button.destructive{color:#C21717}',
    '.inv-ask button.cancel{font-weight:600}',
    '.inv-pop{width:280px;border-radius:14px;background:rgba(44,44,46,.94);backdrop-filter:blur(30px);color:#fff;text-align:center;overflow:hidden;box-shadow:0 12px 40px rgba(0,0,0,.5)}',
    '.g-light .inv-pop{background:rgba(250,250,250,.94);color:#000}',
    '.inv-pop .ti{padding:12px 16px;font-size:var(--fs-foot);color:rgba(235,235,245,.6);border-bottom:.5px solid rgba(128,128,128,.4)}',
    '.inv-pop button{display:block;width:100%;min-height:44px;border:0;background:none;font:400 var(--fs-body)/1.2 var(--font);color:#FF6961;cursor:pointer}',
    '.inv-keys{position:absolute;left:0;right:0;bottom:0;background:#2b2b2d;padding:8px 4px 24px;display:grid;grid-template-columns:repeat(3,1fr);gap:6px;z-index:95}',
    '.inv-keys span{height:44px;border-radius:6px;background:#4a4a4c;color:#fff;display:grid;place-items:center;font:400 22px var(--font)}',
    '.inv-keys span.dim{background:#363638}',
    '.g-light .ui-alert{background:rgba(247,247,247,.94);color:#000}.g-light .ui-alert .btns{border-top-color:rgba(60,60,67,.29)}.g-light .ui-alert .btns button{color:#0066CC}.g-light .ui-alert .btns button + button{border-left-color:rgba(60,60,67,.29)}.g-light .ui-alert .btns button.destructive{color:#C21717}',
    '.ui-info p{white-space:pre-line}',
    /* kit bug workaround: `.k-wrap h2` (atlas section headings, margin 44px, 22px) also hits the app's h2s inside a mockup; restore the app's own rules (promote to kit) */
    '.k-wrap .ui-hdr h2{margin:0;font:700 var(--fs-t3)/1.2 var(--font-d);letter-spacing:0}.k-wrap .inv-empty h2{margin:0;font:700 var(--fs-t2)/1.2 var(--font-d);letter-spacing:0}.k-wrap .inv-pane .hd h2{margin:0;font:600 var(--fs-hd)/1.25 var(--font);letter-spacing:0}.k-wrap .ui-flyout h2{margin:0 12px 8px;font:700 var(--fs-t2)/1.2 var(--font-d);letter-spacing:0}',
    /* component swatch helpers */
    '.inv-embed{display:inline-block;vertical-align:top;margin:0 12px 12px 0;transform-origin:0 0}',
    '.inv-cap{display:inline-flex;align-items:center;gap:6px;padding:8px 14px;border-radius:999px;background:var(--g-module-thin);color:#fff;font-size:var(--fs-sub);min-height:44px}',
    '.in-sheet .inv-cap{background:var(--sheet-cell);color:var(--ink)}',
  ].join('\n');
  var style = document.createElement('style'); style.id = 'inv-css'; style.textContent = css; document.head.appendChild(style);

  /* ------------------------------------------------------------------ fixture data (EverShelfFixtureServer.sample) */
  var TODAY = new Date(2026, 9, 23);
  function day(n) { var d = new Date(TODAY.getFullYear(), TODAY.getMonth(), TODAY.getDate() + n); return d; }
  function disp(d) { return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }); }
  function qty(n) { return String(n); }
  Inv.day = day; Inv.disp = disp;
  var ROWS = [
    { id: 1, name: 'Black Beans', q: 2, loc: 'Pantry', exp: 240 }, { id: 2, name: 'Black Beans', q: 1, loc: 'Pantry', exp: 420 },
    { id: 3, name: 'Spaghetti', q: 1, loc: 'Pantry', exp: 300 }, { id: 4, name: 'Jasmine Rice', q: 1, loc: 'Pantry', exp: -3 },
    { id: 5, name: 'Honey', q: 1, loc: 'Pantry', exp: null }, { id: 6, name: 'Whole Milk', q: 1, loc: 'Fridge', exp: 3 },
    { id: 7, name: 'Eggs', q: 12, loc: 'Fridge', exp: 18 }, { id: 8, name: 'Chicken Soup', q: 2, loc: 'Fridge', exp: 4, prepared: true },
    { id: 9, name: 'Frozen Peas', q: 1, loc: 'Freezer', exp: 150 }, { id: 10, name: 'Smoked Paprika', q: 1, loc: 'Spice Rack', exp: 500 },
    { id: 11, name: 'Peanut Butter', q: 1, loc: 'Cabinet', exp: 60 },
  ];
  /** The six pages (InventorySpace): title, the location it lists (null = all), the "phrase" delete and restock copy uses. */
  Inv.spaces = {
    'all-food': { title: 'All Food', loc: null, phrase: 'library', fam: 'food', icon: 'carrot' }, pantry: { title: 'Pantry', loc: 'Pantry', phrase: 'pantry' }, fridge: { title: 'Fridge', loc: 'Fridge', phrase: 'fridge' },
    freezer: { title: 'Freezer', loc: 'Freezer', phrase: 'freezer' }, 'spice-rack': { title: 'Spice Rack', loc: 'Spice Rack', phrase: 'spice rack' }, cabinet: { title: 'Cabinet', loc: 'Cabinet', phrase: 'cabinet' },
  };
  /** InventoryCatalog.displayItems: rows grouped into cards by lowercased name; quantity summed; soonest expiry; batches by (location, expiry, prepared). */
  Inv.cards = function (space) {
    var sp = Inv.spaces[space || 'all-food'], map = {}, order = [];
    ROWS.filter(function (r) { return !sp.loc || r.loc === sp.loc; }).forEach(function (r) {
      var k = r.name.toLowerCase();
      if (!map[k]) { map[k] = { id: k, name: r.name, rows: [] }; order.push(k); }
      map[k].rows.push(r);
    });
    return order.map(function (k) {
      var c = map[k], batches = {}, bo = [];
      c.rows.forEach(function (r) { var bk = [r.loc, r.exp, r.prepared ? 1 : 0].join('|'); if (!batches[bk]) { batches[bk] = { loc: r.loc, exp: r.exp, prepared: !!r.prepared, q: 0 }; bo.push(bk); } batches[bk].q += r.q; });
      c.batches = bo.map(function (bk) { return batches[bk]; }).sort(function (a, b) { return (a.exp == null) - (b.exp == null) || (a.exp - b.exp) || a.loc.localeCompare(b.loc); });
      c.qty = c.rows.reduce(function (s, r) { return s + r.q; }, 0);
      var dated = c.rows.filter(function (r) { return r.exp != null; });
      c.soonest = dated.length ? Math.min.apply(null, dated.map(function (r) { return r.exp; })) : null;
      c.shown = c.qty > 1 ? c.qty : null;
      return c;
    });
  };
  /** ExpiryInfo: label and tone (soon is under 7 days, the same judgement as the section header). */
  Inv.expiry = function (days) {
    if (days == null) return { label: 'No Expiration Date', tone: null };
    if (days < 0) return { label: 'Expired ' + disp(day(days)), tone: 'expired' };
    return { label: 'Expires ' + disp(day(days)), tone: days < 7 ? 'soon' : null };
  };
  Inv.summary = function (cards) {
    var exp = cards.filter(function (c) { return Inv.expiry(c.soonest).tone === 'soon'; }).length;
    return cards.length + (cards.length === 1 ? ' Item' : ' Items') + ' • ' + exp + ' Expiring Soon';
  };
  Inv.sort = function (cards, mode, desc) {
    var a = cards.slice();
    a.sort(function (x, y) {
      if (mode === 'expiry') {
        if (x.soonest == null && y.soonest == null) return x.name.localeCompare(y.name);
        if (x.soonest == null) return 1; if (y.soonest == null) return -1;
        if (x.soonest !== y.soonest) return desc ? y.soonest - x.soonest : x.soonest - y.soonest;
      }
      return desc ? y.name.localeCompare(x.name) : x.name.localeCompare(y.name);
    });
    return a;
  };
  var FILTERS = { all: [null, null], expired: [-9999, -1], week: [0, 7], month: [0, 30], six: [0, 183], year: [0, 365], none: 'none' };
  Inv.filter = function (cards, f) {
    if (!f || f === 'all') return cards;
    return cards.filter(function (c) { var r = FILTERS[f]; if (r === 'none') return c.soonest == null; return c.soonest != null && c.soonest >= r[0] && c.soonest <= r[1]; });
  };
  /** InventorySections.make: under a title sort one headerless list, under an expiry sort Expired / Expiring Soon / Later / No Expiration Date. */
  Inv.sections = function (cards, mode) {
    if (mode !== 'expiry') return cards.length ? [{ id: 'all', title: null, items: cards }] : [];
    var names = { expired: 'Expired', soon: 'Expiring Soon', later: 'Later', undated: 'No Expiration Date' }, out = [];
    cards.forEach(function (c) {
      var t = Inv.expiry(c.soonest).tone, b = c.soonest == null ? 'undated' : (t === 'expired' ? 'expired' : (t === 'soon' ? 'soon' : 'later'));
      if (out.length && out[out.length - 1].id === b) out[out.length - 1].items.push(c); else out.push({ id: b, title: names[b], items: [c] });
    });
    return out;
  };

  /* ------------------------------------------------------------------ InventoryRow */
  /**
   * One card. o: {surface:'page'|'sheet' (class only: the host decides), selected, shopping:'idle'|'adding'|'added', error, redacted, swipe:'lead'|'trail', first, last}
   * The row is a .inv-row; wrap rows with Inv.list. Multi-batch cards show no tone (tone nil) and "Multiple Expiration Dates".
   */
  Inv.row = function (c, o) {
    o = o || {};
    var multi = c.batches.length > 1, ex = Inv.expiry(c.soonest), tone = multi ? null : ex.tone;
    var sub = multi ? 'Multiple Expiration Dates' : ex.label, shop = o.shopping || 'idle';
    var cartLabel = { idle: 'Add ' + c.name + ' to shopping list', adding: 'Adding ' + c.name + ' to shopping list', added: 'Added ' + c.name + ' to shopping list' }[shop];
    var cart = h('button.inv-btn.cart' + (shop === 'added' ? '.added' : ''), { type: 'button', 'aria-label': cartLabel, disabled: shop !== 'idle' ? '' : null,
      html: shop === 'adding' ? '' : I(shop === 'added' ? 'checkmark' : 'cart.badge.plus', { weight: shop === 'added' ? 2.4 : 1.8 }) });
    if (shop === 'adding') cart.appendChild(K().ArcSpinner({ size: 'compact', label: 'Adding to Groceries' }));
    var chev = h('button.inv-btn.chev', { type: 'button', 'aria-label': 'Edit ' + c.name, title: multi ? 'Opens each expiration batch' : 'Opens the item editor', html: I('chevron.forward', { weight: 2.4 }) });
    var label = [c.name].concat(c.shown ? ['Quantity ' + qty(c.shown)] : [], [sub], tone === 'soon' ? ['Expiring soon'] : [], o.error ? [o.error] : []).join(', ');
    var copy = h('div.inv-copy', { role: 'group', 'aria-label': label },
      h('span.inv-name' + (o.redacted ? '.redact' : ''), c.name),
      h('span.inv-sub' + (tone ? '.' + tone : ''), tone ? h('span', { html: I(tone === 'expired' ? 'exclamationmark.triangle.fill' : 'clock.fill') }) : null, h('span', sub)),
      o.error ? h('span.inv-err', o.error) : null);
    var tail = h('div.inv-tail', c.shown ? h('span.inv-qty', { 'aria-hidden': 'true' }, qty(c.shown)) : null, cart, chev);
    var row = h('div.inv-row' + (o.selected ? '.sel' : ''), { dataset: { item: c.id } }, copy, tail);
    var sw = h('div.inv-swipe', { dataset: { row: c.id } });
    var face = h('div.inv-face', row);
    if (o.swipe === 'lead') { sw.appendChild(h('button.inv-act.lead', { type: 'button' }, h('span', { html: I('cart.badge.plus') }), 'Add to Groceries')); face.style.transform = 'translateX(112px)'; }
    if (o.swipe === 'trail') { sw.appendChild(h('button.inv-act.trail', { type: 'button' }, h('span', { html: I('trash') }), 'Delete')); face.style.transform = 'translateX(-88px)'; }
    sw.appendChild(face);
    return sw;
  };
  /** The dense module (page) or sheet cell card for a run of rows. */
  Inv.list = function (rows, o) { return h('div.inv-list', { role: 'list' }, rows); };

  /* ------------------------------------------------------------------ the page */
  /** InventoryEmptyState (also the page's centred empty/error state). props: {title, description, error, kind} */
  Inv.empty = function (p) {
    return h('div.inv-empty', { role: 'group', 'aria-label': p.title }, h('div.ico', { html: I(p.error ? 'exclamationmark.triangle' : 'basket', { size: '1.25em' }) }),
      h('h2', { role: 'heading', 'aria-level': '2' }, p.title), h('p', p.description), p.error ? K().PrimaryButton({ title: 'Try Again' }) : null);
  };
  /** InventoryCatalog.emptyState copy. kind: 'empty' | 'error' | 'search' | 'search-filter' | 'filter'. */
  Inv.emptyCopy = function (space, kind) {
    var t = Inv.spaces[space].title, tl = t.toLowerCase();
    return {
      empty: ['No Items Found', 'Scan an item to add it to your ' + tl + '.'],
      error: ['Unable to Load ' + t, 'Try again in a moment, or scan an item while ' + tl + ' is unavailable.'],
      'error-detail': ['Unable to Load ' + t, t + ' is unavailable. Check the connection to Home Assistant and try again.'],
      search: ['No Matching Items', 'Try a different search or clear the search to show all items.'],
      'search-filter': ['No Matching Items', 'Try a different search, clear the selected filter, or clear the search to show all items.'],
      filter: ['No Matching Items', 'Try a different filter, or clear it to show all items.'],
    }[kind];
  };
  /** The floating action bar of an inventory page: Search, Sort, Filter and Scan Item (a titled capsule on an empty page). */
  Inv.fab = function (ctx, o) {
    o = o || {};
    var acts = [];
    if (!o.empty) acts.push({ id: 'sort', title: 'Sort', symbol: 'arrow.up.arrow.down', showsTitle: false, active: !!o.sortActive }, { id: 'filter', title: 'Filter', symbol: 'line.3.horizontal.decrease', showsTitle: false, active: !!o.filterActive });
    acts.push({ id: 'scan', title: 'Scan Item', symbol: 'barcode.viewfinder', showsTitle: !!o.empty, prominent: false });
    return K().FloatingActionBar({ actions: acts, search: o.empty ? null : { prompt: 'Search items', text: o.query || '' }, ctx: ctx });
  };
  /** The list column: summary line, sections of rows. */
  Inv.listColumn = function (ctx, o) {
    var all = Inv.cards(o.space).concat(o.extra || []);
    var cards = Inv.sort(Inv.filter(all, o.filter), o.sort, o.desc);
    if (o.query) cards = cards.filter(function (c) { return c.name.toLowerCase().indexOf(o.query.toLowerCase()) >= 0; });
    var kids = [], order = o.query ? 0 : 0;
    if (!o.query && !(o.filter && o.filter !== 'all' && false)) kids.push(h('p.inv-summary', Inv.summary(all)));
    Inv.sections(cards, o.sort).forEach(function (s) {
      var rows = s.items.map(function (c) {
        return Inv.row(c, { selected: o.selected === c.id, shopping: (o.shopping || {})[c.id], error: (o.errors || {})[c.id], redacted: o.redacted, swipe: (o.swipe || {})[c.id] });
      });
      kids.push(h('div.inv-sec', s.title ? K().PageSectionHeader({ title: s.title, detail: String(s.items.length) }) : null, Inv.list(rows)));
    });
    return [h('div.ui-bleed.inv-col', kids)];
  };
  /**
   * The inventory page. o: {space:'all-food', sort:'title'|'expiry', desc, filter, query, phase:'content'|'loading'|'spinner', empty:'empty'|'error'|..., selected, shopping:{id:state}, errors:{id:text},
   * swipe:{id:'lead'|'trail'}, redacted, searching, noFab (a sheet is up), connection, split:{editor:Node-fn(ctx)}, refreshing}
   */
  Inv.page = function (ctx, o) {
    o = o || {}; o.space = o.space || 'all-food';
    var sp = Inv.spaces[o.space], body, fab = null, hasRows = Inv.cards(o.space).length > 0 && !o.empty;
    var showFab = !o.noFab && (o.phase || 'content') === 'content';
    if (o.phase === 'loading' || o.phase === 'spinner') {
      body = [K().ContentGate({ phase: o.phase === 'loading' ? 'loading' : 'spinner', label: 'Loading ' + sp.title, minHeight: 360, content: Inv.listColumn(ctx, o) })];
      showFab = false; fab = Inv.fab(ctx, {}); fab.style.opacity = '0';   // the bar is inside the gate: it arrives with the rows
    } else if (o.empty) {
      var cp = Inv.emptyCopy(o.space, o.empty);
      body = [h('div', { style: { minHeight: '440px', display: 'flex', alignItems: 'center', justifyContent: 'center' } }, Inv.empty({ title: cp[0], description: cp[1], error: /^error/.test(o.empty) }))];
      if (o.empty === 'search' || o.empty === 'search-filter' || o.empty === 'filter') fab = Inv.fab(ctx, { query: o.query, filterActive: o.empty !== 'search', sortActive: false });
      else fab = Inv.fab(ctx, { empty: true });
    } else {
      body = Inv.listColumn(ctx, o);
      if (o.searching) body.unshift(h('div.inv-search', { role: 'status', 'aria-label': 'Searching inventory' }, K().ArcSpinner({ size: 'compact', label: 'Searching inventory' }), 'Searching Inventory'));
      fab = Inv.fab(ctx, { query: o.query, sortActive: o.sort === 'expiry' || !!o.desc, filterActive: !!o.filter && o.filter !== 'all' });
    }
    if (showFab && !fab) fab = Inv.fab(ctx, { empty: !hasRows });
    var paneNode = null, splitTop = 0;
    if (o.split && ctx.canSplit) {
      /* InventoryScreen is a plain HStack of two equal halves today (SplitPolicy.allowsSplit only; it does not read the hinge): list leads, the editor pane trails full height.
         Drawn with the owner's 2026-10-24 hinge rule (in flight): the divider is the hinge band while a Duo is slightly closed, else the midpoint of the free space.
         The page narrows to the leading pane (--split-inset), so the list and the floating bar need no width of their own. */
      var top = ctx.device.barTop + 44;
      body = [h('div.ui-bleed', { style: { display: 'flex', flexDirection: 'column', gap: '20px' } }, body)];
      if (showFab && fab) fab = h('div', { style: { marginRight: 'auto' } }, fab);
      paneNode = true; splitTop = top;
    }
    var gated = o.phase === 'loading' || o.phase === 'spinner';
    var page = Mock.page(ctx, { title: sp.title, section: 'home', back: 'Food', badge: 3, choresBadge: 2, connection: o.connection || 'live', body: body, floating: (showFab || gated) ? fab : null });
    if (paneNode) Mock.detailPane(ctx, page, o.split.editor, { top: splitTop });
    if (o.overlay) page.appendChild(o.overlay);
    return page;
  };

  /* ------------------------------------------------------------------ prompts: alert with a field, confirmation dialog */
  /** An alert with a text field (the quantity prompts). o: {title, message, value, buttons:[{title, role}], keyboard} */
  Inv.alertField = function (o) {
    var el = h('div.ui-alert', { role: 'alertdialog', 'aria-label': o.title, 'aria-modal': 'true' },
      h('div.bd', h('div.ti', o.title), o.message ? h('div.ms', o.message) : null, h('div.inv-field', { role: 'textbox', 'aria-label': 'Quantity', 'aria-description': 'Decimal pad' }, o.value == null ? '1' : o.value)),
      h('div.btns', (o.buttons || [{ title: 'Cancel', role: 'cancel' }, { title: 'Add' }]).map(function (b) { return h('button', { type: 'button', style: b.role === 'cancel' ? { fontWeight: 600 } : null }, b.title); })));
    return el;
  };
  /** A scrim over the page with an alert in the middle (and the decimal pad on compact widths). */
  Inv.alertOverlay = function (ctx, alert, o) {
    o = o || {};
    alert.style.maxHeight = ctx.compact ? 'min(500px, 56%)' : '80%'; alert.style.overflowY = 'auto';
    var scrim = h('div.ui-alert-scrim.g-dark', { style: { alignItems: 'start', paddingTop: ctx.compact ? '100px' : '' } }, alert);
    if (ctx.compact && o.keyboard !== false) {
      scrim.style.alignItems = 'start';
      var keys = h('div.inv-keys', '1 2 3 4 5 6 7 8 9 . 0 ⌫'.split(' ').map(function (k) { return h('span' + (k === '.' || k === '⌫' ? '.dim' : ''), k); }));
      scrim.appendChild(keys);
    }
    return scrim;
  };
  /** confirmationDialog(titleVisibility .visible): an action sheet on compact widths, a popover on regular (iPad, unfolded Duo). */
  Inv.askSheet = function (ctx, title, confirm) {
    var wrap = h('div.inv-ask.g-dark', { role: 'dialog', 'aria-label': title });
    if (ctx.compact) {
      wrap.appendChild(h('div.sheet', h('div.grp', h('div.ti', title), h('button.destructive', { type: 'button' }, confirm || 'Delete')), h('div.grp', h('button.cancel', { type: 'button' }, 'Cancel'))));
    } else {
      wrap.style.alignItems = 'center';
      wrap.appendChild(h('div.inv-pop', h('div.ti', title), h('button', { type: 'button' }, confirm || 'Delete')));
    }
    return wrap;
  };

  /* ------------------------------------------------------------------ item editor */
  var MODELS = {
    milk: { title: 'Whole Milk', place: 'Fridge', batches: [{ q: 1, exp: 3 }] },
    beans: { title: 'Black Beans', place: 'Pantry', batches: [{ q: 2, exp: 240 }, { q: 1, exp: 420 }] },
    soup: { title: 'Chicken Soup', place: 'Fridge', batches: [{ q: 2, exp: 4, prepared: true }] },
    eggs: { title: 'Eggs', place: 'Fridge', batches: [{ q: 12, exp: 18 }] },
    honey: { title: 'Honey', place: 'Pantry', batches: [{ q: 1, exp: null }] },
  };
  Inv.models = MODELS;
  /** InventoryEditorModel.summary: "Quantity 3 · In the Pantry". */
  Inv.editorSummary = function (m) { return 'Quantity ' + qty(m.batches.reduce(function (s, b) { return s + b.q; }, 0)) + ' · In the ' + m.place; };
  function stepper(label, draft, minimum) {
    return h('div.ui-field.stack', h('span.lb', label), h('span.va', h('span', { style: { color: 'var(--ink-sheet-2)' } }, qty(draft)),
      h('span.inv-step', h('button', { type: 'button', 'aria-label': 'Decrease ' + label, disabled: draft <= minimum ? '' : null, html: I('minus') }), h('button', { type: 'button', 'aria-label': 'Increase ' + label, html: I('plus') }))));
  }
  /** Form groups for an editor. o: {drafts:[{q?, exp?}], busy:'save'|'delete'|'prepared'|null, error, hint-from-drafts, pane (adds Save Changes)} */
  Inv.editorForm = function (m, o) {
    o = o || {}; var K_ = K(), multi = m.batches.length > 1, drafts = o.drafts || [], changed = false, nodes = [];
    var T = K_.Toggle;
    if (o.error) nodes.push(h('div', { style: { margin: '0 16px' } }, K_.InlineAlert({ message: o.error, severity: 'error' })));
    m.batches.forEach(function (b, i) {
      var d = drafts[i] || {}, q = d.q != null ? d.q : b.q, hasExp = d.exp !== undefined ? d.exp != null : b.exp != null, expv = d.exp !== undefined ? d.exp : b.exp;
      var delta = q - b.q, dirty = delta !== 0 || (d.exp !== undefined && d.exp !== b.exp); if (dirty) changed = true;
      var place = m.place, head = multi ? Inv.expiry(b.exp).label + ' · In the ' + place + (b.prepared ? ' · Prepared' : '') : 'In the ' + place + (b.prepared ? ' · Prepared' : '');
      var qual = multi ? (b.exp == null ? ' without an expiration date' : ' expiring ' + disp(day(b.exp))) + (b.prepared ? ' prepared' : '') : (b.prepared ? ' prepared' : '');
      var rows = [stepper('Quantity', q, Math.min(1, b.q))];
      rows.push(h('div.ui-field', h('span.lb', 'Expiration Date'), T({ on: hasExp, label: 'Expiration date for ' + m.title + qual })));
      if (hasExp) rows.push(h('div.ui-field.stack', h('span.lb', 'Expires'), h('span.inv-date', { role: 'button', 'aria-label': 'Expires, ' + m.title + qual }, disp(day(expv)))));
      rows.push(h('div.ui-field' + (o.busy === 'prepared' ? '.busy' : ''), h('span.lb', { style: { display: 'inline-flex', gap: '8px', alignItems: 'center' } }, 'Prepared Food', o.busy === 'prepared' ? K_.ArcSpinner({ size: 'inline', label: 'Updating prepared food' }) : null), T({ on: b.prepared, label: 'Prepared food, ' + m.title + qual })));
      var delRow = h('button.ui-field.inv-btnrow.inv-del', { type: 'button', 'aria-label': (o.busy === 'delete' ? 'Deleting ' : 'Delete ') + m.title + qual },
        h('span.lb', 'Delete'), o.busy === 'delete' ? K_.ArcSpinner({ size: 'inline', label: 'Deleting' }) : h('span', { html: I('trash') }));
      var foot = [];
      if (delta !== 0) foot.push('Saving ' + (delta > 0 ? 'adds ' : 'removes ') + qty(Math.abs(delta)) + (Math.abs(delta) === 1 ? ' item ' : ' items ') + (delta > 0 ? 'to' : 'from') + ' the ' + place.toLowerCase() + '.');
      if (i === 0) foot.push('Prepared Food marks an item that does not need classification.');
      // One commit model (owner, 2026-10-24): Prepared Food is a draft saved with Save; Delete sits in its own group and applies at once.
      nodes.push(h('section', h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, head), h('div.ui-form', o.disabled ? { style: { opacity: .55 } } : null, rows), foot.length ? h('p.ui-formfoot', foot.map(function (t, k) { return [k ? h('br') : null, t]; })) : null));
      nodes.push(h('section', h('div.ui-form', o.disabled ? { style: { opacity: .55 } } : null, delRow), h('p.ui-formfoot', 'Deleting asks first and applies at once. It is not part of Save.')));
    });
    if (changed) {
      var crow = [];
      if (o.pane) crow.push(h('button.ui-field.inv-btnrow.inv-link', { type: 'button', 'aria-label': (o.busy === 'save' ? 'Saving ' : 'Save ') + m.title }, h('span.lb', { style: { fontWeight: 700 } }, 'Save Changes'), o.busy === 'save' ? K_.ArcSpinner({ size: 'inline', label: 'Saving' }) : null));
      crow.push(h('button.ui-field.inv-btnrow.inv-link', { type: 'button', 'aria-label': 'Reset Changes to ' + m.title }, h('span.lb', 'Reset Changes')));
      nodes.push(h('div.ui-form', crow));
    }
    var el = h('div.inv-form', nodes); el.dataset.changed = changed ? '1' : '';
    return el;
  };
  /** The editor as the sheet's options (feed Mock.sheet / Mock.presentDemo). */
  Inv.editorSheet = function (ctx, m, o) {
    o = o || {};
    var form = Inv.editorForm(m, o), changed = !!form.dataset.changed;
    var busy = o.busy === 'save';
    return { title: m.title, subtitle: Inv.editorSummary(m), detent: o.detent || 'fitted', size: 'form', leading: 'cancel', trailing: 'confirm', confirm: { title: 'Save', enabled: changed && !o.busy, busy: busy, busyTitle: 'Saving' }, content: form, grabber: !o.busy };
  };
  /** The trailing pane (landscape split): its own header with the name and Close, then the form with Save Changes. */
  Inv.editorPane = function (m, o) {
    o = Object.assign({ pane: true }, o);
    return h('div.inv-pane.g-dark', { role: 'region', 'aria-label': m.title }, h('div.hd', h('h2', { role: 'heading', 'aria-level': '2' }, m.title), K().SheetCloseItem()), h('div.bd', Inv.editorForm(m, o)));
  };

  /* ------------------------------------------------------------------ filter and sort sheets (InventoryControlSheets) */
  Inv.SORT_BY = [['Title', 'Sort alphabetically by item name.'], ['Expiration Date', 'Sort by the item expiration date.']];
  Inv.DIRECTION = [['Ascending', 'A–Z, soonest first'], ['Descending', 'Z–A, latest first']];
  Inv.FILTER = [['All Items', 'Show everything in this location.', 'all'], ['Expired', 'Only items past their expiration date.', 'expired'], ['Expiring Within a Week', 'Items expiring in the next 7 days.', 'week'],
    ['Expiring Within a Month', 'Items expiring in the next 30 days.', 'month'], ['Expiring Within 6 Months', 'Items expiring in the next 6 months.', 'six'], ['Expiring Within a Year', 'Items expiring in the next year.', 'year'],
    ['No Expiration Date', 'Items without a usable expiration date.', 'none']];
  Inv.sortSheet = function (ctx, o) {
    o = o || {}; var mode = o.mode || 0, dir = o.dir || 0, canReset = mode !== 0 || dir !== 0;
    var content = K().FilterSheet({ canReset: canReset, sections: [
      { title: 'Sort By', options: Inv.SORT_BY.map(function (x, i) { return { title: x[0], subtitle: x[1], selected: i === mode }; }) },
      { title: 'Sort Direction', options: Inv.DIRECTION.map(function (x, i) { return { title: x[0], subtitle: x[1], selected: i === dir }; }) }] });
    return { title: 'Sort Inventory', detent: o.detent || 'fitted', size: 'form', leading: 'cancel', trailing: 'confirm', confirm: { title: 'Apply', enabled: canReset }, content: content };
  };
  Inv.filterSheet = function (ctx, o) {
    o = o || {}; var sel = o.sel || 'all', cards = Inv.cards(o.space || 'all-food'), shown = Inv.filter(cards, sel).length;
    var content = K().FilterSheet({ canReset: sel !== 'all', sections: [{ title: 'Show', options: Inv.FILTER.map(function (x) { return { title: x[0], subtitle: x[1], selected: x[2] === sel }; }) }] });
    return { title: 'Filter Inventory', subtitle: shown + ' of ' + cards.length + (cards.length === 1 ? ' Item' : ' Items'), detent: o.detent || 'fitted', size: 'form', leading: 'cancel', trailing: 'confirm', confirm: { title: 'Apply', enabled: sel !== 'all' }, content: content };
  };

  /* ------------------------------------------------------------------ Add Item (ScanItemSheet) */
  var QUICK = ['In 3 Days', 'In 1 Week', 'In 1 Month', 'In 6 Months', 'In 1 Year'];
  var LOCS = ['Pantry', 'Fridge', 'Freezer', 'Spice Rack', 'Cabinet', 'Library'];
  function optRows(titles, sel) { return h('div.ui-form', { style: { background: 'var(--sheet-cell)' } }, titles.map(function (t) { return h('button.ui-optrow' + (t === sel ? '.sel' : ''), { type: 'button', 'aria-pressed': t === sel ? 'true' : 'false', style: { minHeight: '52px' } }, h('span.tx', h('span', t)), h('span.ck', { html: I('checkmark', { weight: 2.4 }) })); })); }
  function sect(head, body, foot) { return h('section', head ? h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, head) : null, body, foot ? (foot.nodeType ? foot : h('p.ui-formfoot', foot)) : null); }
  function nameRow(v) { return h('div.ui-field', h('span.lb', 'Name'), h('span.va', { role: 'textbox', 'aria-label': 'Product name', style: { flex: 1, textAlign: 'right', opacity: v ? 1 : .6 } }, v || 'Product Name')); }
  function fieldBtn(txt, cls) { return h('button.ui-field.inv-btnrow' + (cls ? '.' + cls : ''), { type: 'button' }, h('span.lb', txt)); }
  function expiryRows(date, read) {
    var rows = [h('div.ui-field', h('span.lb', 'Expiration Date'), K().Toggle({ on: !!date, label: 'Expiration Date' }))];
    if (date) rows.push(h('div.ui-field.stack', h('span.lb', h('span', 'Expires'), read ? h('span', { style: { display: 'block', fontSize: 'var(--fs-sub)', color: 'var(--ink-sheet-2)' } }, 'Read from the package') : null), h('span.inv-date', { role: 'button', 'aria-label': 'Expiration date' }, disp(day(date)))));
    return rows;
  }
  /**
   * The scan sheet. o.step: 'barcode-camera' | 'barcode-processing' | 'barcode-found' | 'barcode-notfound' | 'barcode-failed' | 'expiry-camera' | 'expiry-manual' | 'expiry-read' | 'expiry-notfound' | 'expiry-failed'
   *   | 'review' | 'review-qty-error' | 'review-add-error' | 'adding' | 'added'; o.camera: 'live'|'starting'|'unavailable'|'denied'|'simulated'; o.location: 'Pantry'; o.ax (footer inside the form)
   */
  Inv.scanSheet = function (ctx, o) {
    o = o || {}; var step = o.step || 'barcode-camera', loc = o.location || 'Pantry', K_ = K(), cam = o.camera || 'live';
    var sub, lead, body = [], footer = [], toolbar = { leading: 'cancel', trailing: 'none' }, ax = !!ctx.axSize;
    function camera(symbol, label, manual, activity) {
      var inner;
      if (cam === 'starting') inner = h('div.msg', K_.ArcSpinner({ size: 'page' }), 'Starting camera…');
      else if (cam === 'unavailable') inner = h('div.msg', h('span', { html: I('exclamationmark.circle') }), 'Camera unavailable. Enter the details manually.');
      else if (cam === 'denied') inner = h('div.msg', h('span', { html: I('exclamationmark.circle') }), 'Camera access is off. Allow it in Settings, or enter the details manually.');
      else if (cam === 'simulated') inner = h('div.sim', h('span', { html: I(symbol) }), h('button', { type: 'button' }, symbol === 'camera' ? 'Simulate Photo' : 'Simulate Scan'));
      else inner = symbol === 'barcode.viewfinder' ? h('div.reticle') : null;
      var cardEl = h('div.inv-cam' + (cam === 'live' ? '.live' : ''), { role: 'img', 'aria-label': label }, inner, cam === 'live' && activity ? h('div.inv-pill', { role: 'status', 'aria-label': activity }, K_.ArcSpinner({ size: 'compact', label: activity }), activity) : null);
      return [cardEl, h('button.inv-manual', { type: 'button' }, h('span', { html: I('keyboard') }), manual)];
    }
    function productHeader(name, code) { return h('div.ui-form', { style: { padding: '8px 16px', background: 'transparent' } }, h('div.inv-product', { role: 'group', 'aria-label': (name || 'New Item') + (code ? ', Barcode ' + code : '') }, h('div.tile', { html: I(code ? 'barcode' : 'square.and.pencil') }), h('div', h('div.nm', name || 'New Item'), code ? h('div.bc', 'Barcode ' + code) : null))); }
    var BC = '0123456789012';
    switch (step) {
      case 'barcode-camera':
        sub = 'Scan Barcode · Step 1 of 3'; lead = 'Use the product barcode to look up item details. Center the barcode inside the camera window and hold steady.';
        body = camera('barcode.viewfinder', 'Live item scan camera feed', 'Manually Enter Name', 'Looking for a Barcode'); footer = [{ t: 'Skip Barcode' }]; break;
      case 'barcode-processing': sub = 'Scan Barcode · Step 1 of 3'; lead = ''; body = [h('div.ui-form', h('div.inv-proc', { role: 'status' }, K_.ArcSpinner({ size: 'compact' }), 'Processing…'))]; break;
      case 'barcode-found': case 'barcode-notfound': case 'barcode-failed': {
        sub = 'Enter Product Name · Step 1 of 3'; lead = 'Review or enter the product name before continuing.';
        var found = step === 'barcode-found';
        if (step === 'barcode-notfound') body.push(K_.InlineAlert({ message: 'No barcode match found for ' + BC + '.', severity: 'warning' }));
        if (step === 'barcode-failed') body.push(K_.InlineAlert({ message: 'Unable to resolve barcode.', severity: 'error' }));
        body.push(sect('What item are you adding?', h('div.ui-form', nameRow(found ? 'Greek Yogurt' : ''), fieldBtn('Scan Barcode Again', 'inv-link'))));
        footer = [{ t: 'Next', primary: found || step === 'barcode-notfound', disabled: !found }]; break; }
      case 'expiry-camera':
        sub = 'Expiration Date · Step 2 of 3'; lead = 'Take a clear photo of the printed expiration date. Center it inside the camera window and keep the label flat.'; toolbar.leading = 'back'; toolbar.backLabel = 'Back to Barcode Scan';
        body = camera('camera', 'Live expiration date camera feed', 'Manually Enter Expiration Date', null); footer = [{ t: 'Read Expiration Date', primary: true }, { t: 'Skip Expiration' }]; break;
      case 'expiry-manual': case 'expiry-read': case 'expiry-notfound': case 'expiry-failed': {
        sub = 'Expiration Date · Step 2 of 3'; toolbar.leading = 'back'; toolbar.backLabel = 'Back to Barcode Scan';
        var read = step === 'expiry-read', date = read ? 365 : (o.date == null ? null : o.date);
        lead = read ? 'Review or adjust the expiration date before continuing.' : 'Enter the expiration date manually, or read it from the camera.';
        if (step === 'expiry-notfound') body.push(K_.InlineAlert({ message: 'No expiration date found in that image.', severity: 'warning' }));
        if (step === 'expiry-failed') body.push(K_.InlineAlert({ message: 'AI-based expiration date parsing is unavailable. Please enter the expiration date manually or try again later.', severity: 'error' }));
        body.push(sect('When does it expire?', h('div.ui-form', expiryRows(date, read))));
        body.push(sect('Quick Expiration Dates', optRows(QUICK, o.quick || null)));
        body.push(h('div.ui-form', fieldBtn(read ? 'Read Expiration Date Again' : 'Read Expiration Date', 'inv-link')));
        footer = [{ t: 'Next', primary: !!date, disabled: !date }]; break; }
      case 'review': case 'review-qty-error': case 'review-add-error': {
        sub = 'Review Item · Step 3 of 3'; lead = 'Confirm the item details before adding it to your ' + loc.toLowerCase() + '.'; toolbar.leading = 'back'; toolbar.backLabel = 'Back to Expiration Date';
        toolbar.trailing = 'confirm'; toolbar.confirm = { title: 'Add to ' + loc, enabled: true };
        var qerr = step === 'review-qty-error';
        body.push(sect(null, productHeader('Greek Yogurt', BC)));
        var detail = [nameRow('Greek Yogurt'), h('div.ui-field.stack', h('span.lb', 'How Many'), h('span.va.ctl', h('span.val', { role: 'textbox', 'aria-label': 'Quantity', style: qerr ? { color: 'var(--ink-error)' } : null }, qerr ? '0' : '1'),
          h('span.inv-step', h('button', { type: 'button', 'aria-label': 'Decrease', disabled: '', html: I('minus') }), h('button', { type: 'button', 'aria-label': 'Increase', html: I('plus') })))), ].concat(expiryRows(o.date == null ? 7 : o.date, false), [h('div.ui-field', h('span.lb', 'Prepared Food'), K_.Toggle({ on: false, label: 'Prepared Food' }))]);
        body.push(sect('What item are you adding?', h('div.ui-form', detail), h('div', qerr ? h('p.ui-formfoot', { style: { color: 'var(--ink-error)' } }, 'Quantity must be at least 1.') : null, h('p.ui-formfoot', 'Prepared Food marks an item that does not need classification.'))));
        body.push(sect('Where should it be stored?', optRows(LOCS, loc), o.hint || 'Suggested for this product by Pantryhub.'));
        if (step === 'review-add-error') body.push(K_.InlineAlert({ message: 'Unable to add this item to ' + loc + '.', severity: 'error' }));
        break; }
      case 'adding': sub = 'Adding Item'; lead = ''; toolbar = { leading: 'none', trailing: 'none' };
        body = [h('div.ui-form', h('div.inv-result', { role: 'status' }, K_.ArcSpinner({ size: 'compact' }), 'Adding to ' + loc + '…'))]; break;
      case 'added': sub = 'Item Added'; lead = ''; toolbar = { leading: 'none', trailing: 'close' };
        body = [h('div.ui-form', h('div.inv-result', { role: 'status' }, h('span.okc', { html: I('checkmark.circle.fill') }), 'Added to ' + loc))]; break;
    }
    function fbtn(b) { return b.primary ? K_.PrimaryButton({ title: b.t, disabled: b.disabled }) : h('button.inv-gray', { type: 'button', disabled: b.disabled ? '' : null }, b.t); }
    var footNodes = footer.map(fbtn);
    var content = h('div.inv-scan', lead ? h('p.lead', lead) : null, body, ax && footNodes.length ? h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px' } }, footNodes) : null);
    var opts = { title: 'Add Item', subtitle: sub, detent: 'large', size: 'form', content: content, leading: toolbar.leading === 'back' ? K_.BackButton({ label: toolbar.backLabel }) : (toolbar.leading === 'none' ? 'none' : 'cancel'),
      trailing: toolbar.trailing, confirm: toolbar.confirm, grabber: step !== 'adding' };
    Inv._foot = !ax && footNodes.length ? h('div.inv-foot', footNodes) : null;
    return opts;
  };
  /** Mock.sheet plus the scan footer pinned under the form (the sheet is a VStack of the form and the step's buttons). */
  Inv.scanScreen = function (ctx, o, presenter) {
    var opts = Inv.scanSheet(ctx, o); var foot = Inv._foot; Inv._foot = null;
    opts.presenter = presenter === undefined ? Inv.page(ctx, { space: (o && o.space) || 'all-food', noFab: true }) : presenter;
    var host = Mock.sheet(ctx, opts);
    if (foot) { var modal = host.querySelector('.ui-modal'); if (modal) modal.appendChild(foot); }
    return host;
  };

  /* ------------------------------------------------------------------ component mockup helpers */
  /** A swatch on the page (always dark, over the wallpaper gradient) or the sheet surface (follows the appearance control). */
  Inv.swatch = function (surface, caption, node, ctx, w) {
    var sheet = surface === 'sheet';
    return h('div.k-swatch.' + (sheet ? 'sheet.in-sheet.' + (ctx && ctx.appearance === 'light' ? 'g-light' : 'g-dark') : 'page.g-dark'), { style: { flex: w ? 'none' : '1 1 300px', width: w ? w + 'px' : '', maxWidth: '100%' } },
      h('div.k-cap', surface + ' · ' + caption), h('div.in', node));
  };
  Inv.grid = function (kids) { return h('div.k-swatch-grid', kids); };
  /** A device frame at `zoom` inside a plain component page (the in-context usage). build(ctx) returns the screen content. */
  Inv.embed = function (deviceKey, ctx, build, zoom, caption) {
    var c = Mock.ctx(deviceKey, { appearance: ctx.appearance, ts: ctx.ts, reduceMotion: ctx.reduceMotion, reduceTransparency: ctx.reduceTransparency });
    var prev = Mock.current; Mock.current = c;
    var node = Mock.frame(c, build(c));
    Mock.current = prev;
    var d = Mock.devices[deviceKey], z = zoom || .6;
    return h('figure', { style: { margin: '0 14px 14px 0', display: 'inline-block', verticalAlign: 'top' } },
      h('div', { style: { width: Math.round((d.w + 2 * d.bezel) * z) + 'px', height: Math.round((d.h + 2 * d.bezel) * z) + 'px', overflow: 'hidden' } }, h('div', { style: { zoom: z } }, node)),
      h('figcaption', { style: { font: '12px var(--font)', opacity: .7, marginTop: '4px', maxWidth: Math.round((d.w + 2 * d.bezel) * z) + 'px' } }, caption || d.short));
  };
  /** A sheet as an embedded fragment (no device): the panel only, for component swatches that show a sheet's content. */
  Inv.sheetPanel = function (ctx, kids, w) {
    return h('div.in-sheet.' + (ctx.appearance === 'light' ? 'g-light' : 'g-dark'), { style: { background: 'var(--sheet-ground)', color: 'var(--ink)', borderRadius: '24px', padding: '16px', width: w ? w + 'px' : 'auto', maxWidth: '100%' } }, kids);
  };
})();
