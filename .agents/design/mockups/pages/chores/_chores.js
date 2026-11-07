/* Chores batch helper: fixtures, the todo row, list section, quick links, empty state, floating Add bar, swipe and context menu drawings,
 * the confirmation dialog, the four sheets' forms, and the page builder every Chores mockup shares.
 * Mirrors apple/Sources/HassUI/Features/Chores (ChoresScreen, TodoPageView, TodoListSection, DonetickTaskSheet, TodoItemSheets) and
 * HassCore/Config/ChoresConfig.swift, HassCore/Todo (TodoItem.dueLabel, TodoRowActions, DonetickTaskForm).
 * PROMOTE TO KIT: TodoItemRow / TodoListSection, ActionSheet (confirmationDialog), the missing SF Symbol drawings added below, a swipe-action drawing.
 * Loaded by relative path from pages/chores/*, modals/chores/* and components/chores/* (all this batch's folders). Never fetches.
 */
(function () {
  var h = Mock.h, I = Mock.icon, K = Mock.components;
  var H = 3600, D = 86400;

  /* ------------------------------------------------------------------ symbols the kit lacks (Mock.symbols is the kit's open map) */
  var S = Mock.symbols;
  function add(n, v) { if (!S[n]) S[n] = v; }
  function g(d) { return '<path d="' + d + '"/>'; }
  add('circle', ['<circle cx="12" cy="12" r="8.8"/>']);
  add('square.and.pencil', [g('M11 4.5H6.5a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V13') + g('M17.2 3.8a1.8 1.8 0 0 1 2.5 2.5l-7.4 7.4-3.4.9.9-3.4z')]);
  add('arrow.uturn.backward.circle', S['arrow.uturn.left.circle']);
  add('chevron.up.chevron.down', [g('M8.3 9.5 12 6l3.7 3.5M8.3 14.5 12 18l3.7-3.5')]);
  add('photo.on.rectangle.angled', S['photo.on.rectangle']);
  function discGlyph(shapes) {
    // outline: a ring with the glyph; filled: a disc with the glyph cut out in the tile's fill colour (the tile sets --fill)
    return ['<circle cx="12" cy="12" r="9.2"/>' + shapes,
      '<circle cx="12" cy="12" r="9.4" fill="currentColor" stroke="none"/><g style="stroke:var(--fill,#000);fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round">' + shapes + '</g>'];
  }
  add('cart.circle.fill', discGlyph(g('M6.8 8h1.7l1.3 6.1h6.1l1.2-4.3H9.2') + '<circle cx="10.4" cy="16.7" r=".6"/><circle cx="15.4" cy="16.7" r=".6"/>'));
  add('hammer.circle.fill', discGlyph(g('M7.6 16.4l5.6-5.6') + g('M11.6 7.6l2-1.6 3.6 3.6-1.6 2z')));
  add('tray.circle.fill', discGlyph(g('M6.8 13.4h3l1 1.6h2.4l1-1.6h3M6.8 13.4l1.3-4.4h7.8l1.3 4.4v3.2H6.8z')));

  /* ------------------------------------------------------------------ local CSS (kit tokens only) */
  var css = [
    '.cz-row{display:flex;align-items:center;position:relative;color:#fff;background:none}',
    '.cz-row + .cz-row::before,.cz-sw1 + .cz-row::before{content:"";position:absolute;top:0;right:0;left:calc(16px + 24px * var(--sc) + 14px);height:.5px;background:var(--sep,rgba(255,255,255,.14))}',
    '.cz-row .tg{flex:1;min-width:0;display:flex;align-items:center;gap:0;padding:11px 0 11px 16px;min-height:52px;background:none;border:0;color:inherit;font:inherit;text-align:left;cursor:pointer;align-self:stretch}',
    '.cz-row.due .tg{min-height:60px}',
    '.cz-row .rw{display:flex;align-items:center;gap:14px;flex:1;min-width:0}',
    '.cz-row .ck{flex:none;width:calc(24px * var(--sc));height:calc(var(--fs-body) * 1.3);display:grid;place-items:center;font-size:var(--fs-body);color:var(--g-secondary-on-module);transition:color var(--t-state) var(--ease-state)}',
    '.cz-row .ck svg{width:1.1em;height:1.1em}',
    '.cz-row.done .ck{color:#30D158}',
    '.cz-row .vt{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}',
    '.cz-row .tt{font-size:var(--fs-body);line-height:1.3;color:#fff;overflow-wrap:anywhere;transition:color var(--t-state) var(--ease-state)}',
    '.cz-row.done .tt{text-decoration:line-through;color:var(--g-secondary-on-module)}',
    '.cz-due{display:flex;align-items:baseline;gap:4px;font-size:var(--fs-sub);line-height:1.25;font-variant-numeric:tabular-nums;color:var(--g-secondary-on-module)}',
    '.cz-due svg{width:.8em;height:.8em;flex:none;align-self:center}',
    '.cz-due.hours{color:var(--g-orange)} .cz-due.long{color:var(--g-red)}',
    '.cz-row .ed{flex:none;min-width:44px;min-height:44px;margin-right:4px;display:grid;place-items:center;background:none;border:0;color:var(--g-secondary-on-module);font-size:var(--fs-t3);cursor:pointer}',
    '.cz-row .ed svg{width:1em;height:1em}',
    '.cz-row .pad{width:16px;flex:none}',
    '.cz-row .ed.undo{font-size:var(--fs-body);font-weight:600;color:var(--ink-action,#5AB0FF);padding:0 16px 0 4px}',
    '.in-sheet .cz-row{color:var(--ink)} .in-sheet .cz-row .tt{color:var(--ink)} .in-sheet .cz-row .ck,.in-sheet .cz-row .ed,.in-sheet .cz-row.done .tt,.in-sheet .cz-due{color:var(--ink-sheet-2)}',
    '.in-sheet .cz-row.done .ck{color:var(--ink-success)} .in-sheet .cz-due.hours{color:var(--ink-warning)} .in-sheet .cz-due.long{color:var(--ink-error)}',
    '.in-sheet .cz-row + .cz-row::before{background:var(--sep)}',
    '.cz-spin{display:flex;align-items:center;justify-content:center;min-height:44px;color:#fff}',
    '.cz-empty{display:flex;flex-direction:column;align-items:center;text-align:center;gap:6px;padding:24px 16px;color:#fff}',
    '.cz-empty .gl{font-size:calc(var(--fs-lt) * 1.3);color:var(--g-secondary-on-wallpaper);line-height:1} .cz-empty .gl svg{width:1em;height:1em}',
    '.cz-empty h2{margin:6px 0 0;font:700 var(--fs-t2)/1.2 var(--font-d)} .cz-empty p{margin:0;font-size:var(--fs-body);color:var(--g-secondary-on-wallpaper)}',
    '.in-sheet .cz-empty{color:var(--ink)} .in-sheet .cz-empty .gl,.in-sheet .cz-empty p{color:var(--ink-sheet-2)}',
    '.ui-grid.cz-one > .span2{grid-column:auto}',
    '.cz-ql{position:relative;display:flex;min-width:0} .cz-ql > .ui-tile{flex:1;min-width:0}',
    /* swipe */
    '.cz-sw1{position:relative;overflow:hidden}',
    '.cz-sw1 .acts{position:absolute;top:0;bottom:0;display:flex}',
    '.cz-sw1 .acts.l{left:0} .cz-sw1 .acts.t{right:0}',
    '.cz-sw1 .acts button{width:calc(76px * var(--sc, 1));min-width:76px;border:0;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;font:600 var(--fs-foot)/1.1 var(--font);cursor:pointer;padding:0 6px}',
    '.cz-sw1 .acts button svg{width:22px;height:22px}',
    '.cz-sw1 .acts.full button{flex:1;width:auto}',
    '.cz-sw1 .acts .complete,.cz-sw1 .acts .reopen{background:var(--fam-occupancy-fill,#2A732E)} .cz-sw1 .acts .edit{background:#0071E3} .cz-sw1 .acts .delete{background:var(--g-badge,#D93025)}',
    '.cz-sw1 .slide{position:relative;transition:transform var(--t-standard) var(--ease-standard);background:var(--g-module-thin)}',
    '.cz-sw1 .slide.dense{background:var(--g-module-dense)}',
    '.in-sheet .cz-sw1 .slide{background:var(--sheet-cell)}',
    /* context menu */
    '.cz-ctx{position:absolute;inset:0;z-index:120;background:rgba(0,0,0,.38);-webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px);display:flex;flex-direction:column;justify-content:center;gap:12px;padding:0 24px}',
    '.cz-ctx .lift{border-radius:var(--radius-module);overflow:hidden;background:var(--g-module-dense);box-shadow:0 18px 50px rgba(0,0,0,.5)}',
    '.cz-menu{align-self:flex-start;width:min(260px,100%);border-radius:14px;overflow:hidden;background:rgba(44,44,46,.92);-webkit-backdrop-filter:blur(30px);backdrop-filter:blur(30px);color:#fff}',
    '.cz-menu button{display:flex;align-items:center;justify-content:space-between;gap:12px;width:100%;min-height:44px;padding:8px 16px;border:0;background:none;color:inherit;font:400 var(--fs-body)/1.2 var(--font);cursor:pointer;text-align:left}',
    '.cz-menu button + button{border-top:.5px solid rgba(255,255,255,.14)} .cz-menu button svg{width:20px;height:20px;flex:none} .cz-menu .delete{color:#FF6961}',
    /* action sheet / confirmation dialog */
    '.cz-act-scrim{position:absolute;inset:0;z-index:95;background:rgba(0,0,0,.4);display:flex;flex-direction:column;justify-content:flex-end;align-items:stretch;gap:8px;padding:0 8px calc(var(--safe-bottom, 20px) - 6px);font-family:var(--font)}',
    '.cz-act-scrim.pop{justify-content:center;align-items:center;padding:0}',
    '.cz-act{border-radius:26px;overflow:hidden;background:rgba(246,246,248,.94);-webkit-backdrop-filter:blur(30px);backdrop-filter:blur(30px);color:#000;text-align:center}',
    '.cz-act-scrim.g-dark .cz-act{background:rgba(44,44,46,.94);color:#fff}',
    '.cz-act .hd{padding:14px 16px 12px;display:flex;flex-direction:column;gap:2px}',
    '.cz-act .hd .ti{font:600 var(--fs-foot)/1.3 var(--font);color:var(--ink-sheet-2)} .cz-act .hd .ms{font-size:var(--fs-foot);line-height:1.3;color:var(--ink-sheet-2)}',
    '.cz-act button{display:block;width:100%;min-height:56px;padding:8px 16px;border:0;border-top:.5px solid var(--sep);background:none;font:400 var(--fs-hd)/1.25 var(--font);color:var(--ink-action);cursor:pointer}',
    '.cz-act button.destructive{color:var(--ink-error)} .cz-act.cancel button{border-top:0;font-weight:600}',
    '.cz-act.popover{width:min(300px,86%);border-radius:18px}',
    '.cz-act.popover button{min-height:48px}',
    /* sheet forms */
    '.cz-form{display:flex;flex-direction:column;gap:24px;padding:8px 0 8px}',
    '.cz-form.busy{opacity:.55}',
    '.cz-busy .ui-mhead .ui-circle.x{opacity:.4}',
    '.cz-form .ui-field .lb.tf{text-align:left}',
    '.cz-form .ui-field .lb.ph{color:var(--ink-sheet-2)}',
    '.cz-form .ui-field.multi{align-items:flex-start;min-height:calc(3 * var(--fs-body) * 1.3 + 22px);padding-top:11px;padding-bottom:11px}',
    '.cz-form .ui-field.act{color:var(--ink-action)}',
    '.cz-form .ui-field.danger{color:var(--ink-danger)}',
    '.cz-form .ui-field .va svg{width:.8em;height:.8em;vertical-align:-.05em}',
    '.cz-form .ui-field .tick{color:var(--ink-action)} .cz-form .ui-field .tick svg{width:1em;height:1em}',
    '.cz-form .ui-field .thumb{width:44px;height:44px;border-radius:8px;flex:none}',
    '.cz-form .ui-field .rm{min-width:44px;min-height:44px;display:grid;place-items:center;border:0;background:none;color:var(--ink-danger);font-size:var(--fs-t3);cursor:pointer;margin-right:-10px}',
    '.cz-form .ui-field .rm svg{width:1em;height:1em}',
    '.cz-form .ui-inline-alert.error .ui-sym{color:inherit}',
    '.cz-form .alert{padding:12px 16px;background:var(--sheet-cell);border-radius:var(--radius-chip)}',
    '.cz-form .ui-field input.real{flex:1;text-align:left;background:none;border:0;color:var(--ink);font:inherit;min-width:0}',
    '.cz-caret{display:inline-block;width:2px;height:1.1em;background:var(--ink-action);vertical-align:text-bottom;margin-left:1px}',
    '.cz-load{min-height:280px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;color:var(--ink-sheet-2);font-size:var(--fs-sub)}',
    '.cz-load .ui-arc{color:var(--ink-sheet-2)}',
    '.cz-unavail{min-height:280px;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;gap:6px;padding:0 24px;color:var(--ink)}',
    '.cz-unavail .gl{font-size:calc(var(--fs-lt) * 1.3);color:var(--ink-sheet-2);line-height:1} .cz-unavail .gl svg{width:1em;height:1em}',
    '.cz-unavail h2{margin:6px 0 0;font:700 var(--fs-t2)/1.2 var(--font-d)} .cz-unavail p{margin:0;font-size:var(--fs-body);color:var(--ink-sheet-2)}',
    '.cz-swatch-stack{display:flex;flex-direction:column;gap:18px}',
    /* kit gap: `.k-wrap h2` (atlas furniture, later in kit.css) beats `.ui-hdr h2` on a tie and adds 44 pt of margin to every section header; restate it with more weight (promote a fix to kit.css) */
    '.k-wrap .ui-hdr h2{margin:0;font:700 var(--fs-t3)/1.2 var(--font-d);letter-spacing:0;scroll-margin-top:0}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'cz-style'; st.textContent = css; document.head.appendChild(st);

  /* ------------------------------------------------------------------ fixtures (fixture data, never the house) */
  var Chores = window.Chores = {};
  Chores.H = H; Chores.D = D;

  /** TodoItem.dueLabel: "Due in 3 days" / "2 hours overdue", tone future | hours | long. `off` is seconds from now (null: undated). */
  Chores.due = function (off) {
    if (off == null) return null;
    var mag = Math.abs(off), unit, div;
    if (mag < D) { unit = 'hour'; div = H; } else if (mag < 21 * D) { unit = 'day'; div = D; } else if (mag < 60 * D) { unit = 'week'; div = 7 * D; } else { unit = 'month'; div = 30 * D; }
    var n = Math.max(1, Math.round(mag / div)), span = n + ' ' + unit + (n === 1 ? '' : 's');
    if (off >= 0) return { text: 'Due in ' + span, tone: 'future' };
    return { text: span + ' overdue', tone: unit === 'hour' ? 'hours' : 'long' };
  };
  function R(title, due) { return { title: title, due: due }; }

  /* Lists per page, in the order the code draws them (ChoresConfig). Rows are sorted by due, undated last (TodoItem.sortedByDue). */
  var LISTS = {
    // The Chores tab, signed in as Alex: choresTabLists() keeps only lists of the viewer's with open items, in this order.
    'chores:alex': [
      ['Past Due', [R('Clean the gutters', -9 * D), R('Replace Humidifier Filter', -1 * D), R('Take out the recycling', -3 * H)]],
      ['Evening Tasks', [R('Run the dishwasher', 5 * H)]],
      ['Afternoon Tasks', [R('Check the mail', 2 * H)]],
      ['No Due Date', [R('Replace Battery · 18%', null)]],
      ['Upcoming', [R('Water the plants', 2 * D)]],
    ],
    'chores:sam': [
      ['Afternoon Tasks', [R('Fold laundry', 3 * H)]],
      ['Upcoming', [R('Book the vet', 30 * D)]],
    ],
    'alexs-chores': [
      ['Past Due', [R('Take out the recycling', -3 * H), R('Replace Humidifier Filter', -1 * D), R('Clean the gutters', -9 * D)].sort(function (a, b) { return a.due - b.due; })],
      ['Due Today', [R('Check the mail', 2 * H), R('Run the dishwasher', 5 * H)]],
      ['Upcoming', [R('Water the plants', 2 * D)]],
      ['No Due Date', [R('Replace Battery · 18%', null)]],
    ],
    'sams-chores': [
      ['Due Today', [R('Fold laundry', 3 * H)]],
      ['Upcoming', [R('Book the vet', 30 * D)]],
    ],
    'unassigned-chores': [
      ['Past Due', [R('Vacuum the stairs', -2 * D)]],
      ['No Due Date', [R('Organize the garage', null)]],
    ],
    'home-improvement-chores': [
      ['Upcoming', [R('Re-caulk the shower', 21 * D), R('Paint the deck', 75 * D)]],
    ],
    'groceries': [
      ['Grocery List', [R('Oat milk'), R('Coffee beans'), R('Lemons')]],
    ],
    'admin-todo': [
      ['Admin To-Do', [R('Port the Chores page'), R('Check the backup job')]],
    ],
  };
  Chores.LISTS = LISTS;

  /** Page config (ChoresConfig.Page): title, back label, tab, add button, empty copy, who edits, who deletes. */
  var PAGES = {
    'chores': { title: 'Chores', section: 'chores', add: 'Add Task', header: true, edit: true, del: true, empty: ['No Chores Due', 'You have no chores due. Nice job!'], vacation: true },
    'groceries': { title: 'Groceries', section: 'chores', back: 'Chores', add: 'Add Groceries', edit: false, del: true, longTitle: 'Organic free-range eggs, large, a dozen, from the farmers market stand by the north entrance', empty: ['No Groceries Listed', 'Add some groceries to see them appear.'], isGrocery: true },
    'alexs-chores': { title: "Alex's Chores", section: 'chores', back: 'Chores', add: 'Add Task', edit: true, del: true, resident: 'alex', empty: ['No Chores Due', "Alex has no chores due. Nice job!"], vacation: true },
    'sams-chores': { title: "Sam's Chores", section: 'chores', back: 'Chores', add: 'Add Task', edit: true, del: true, resident: 'sam', empty: ['No Chores Due', "Sam has no chores due. Nice job!"], vacation: true },
    'unassigned-chores': { title: 'Unassigned Chores', section: 'chores', back: 'Chores', add: 'Add Task', edit: true, del: true, empty: ['No Chores Due', 'There are no unassigned chores due. Nice job!'], vacation: true },
    'home-improvement-chores': { title: 'Home Improvement Tasks', section: 'chores', back: 'Chores', add: 'Add Task', edit: true, del: true, empty: ['No Tasks Due', 'There are no home improvement tasks due. Nice job!'], vacation: true },
    'admin-todo': { title: 'To-Do', section: 'settings', back: 'Settings', add: 'Add Task', edit: true, del: false, noHeaders: true, longTitle: 'Port the Chores page to the new list style and then re-run the whole accessibility audit on every device family before the release branch is cut', empty: ['No To-Do Tasks', 'Use Add Task to create an admin to-do.'], admin: true },
  };
  Chores.PAGES = PAGES;

  /** ChoresConfig.Page.emptyDescription(viewer, vacationModeOn). */
  Chores.emptyCopy = function (id, o) {
    var P = PAGES[id]; o = o || {};
    if (P.vacation && o.vacation) return [P.empty[0], 'Enjoy vacation!'];
    if (P.resident && P.resident === (o.viewer || 'alex')) return [P.empty[0], 'You have no chores due. Nice job!'];
    return P.empty;
  };

  /** The page's sections as drawn: [{title, items}], viewer-filtered. */
  Chores.sections = function (id, o) {
    o = o || {};
    var key = id === 'chores' ? 'chores:' + (o.viewer || 'alex') : id;
    return (LISTS[key] || []).map(function (l) { return { title: l[0], items: l[1].map(function (r) { return Object.assign({}, r); }) }; });
  };

  /** Quick-link counts (ChoresConfig.counts) from the same fixtures: overdue = Past Due, upcoming = Due Today + Upcoming, noDueDate. */
  Chores.counts = function (pageId) {
    var c = { overdue: 0, upcoming: 0, noDueDate: 0, total: 0 };
    (LISTS[pageId] || []).forEach(function (l) {
      var n = l[1].length;
      if (l[0] === 'Past Due') c.overdue += n; else if (l[0] === 'Due Today' || l[0] === 'Upcoming') c.upcoming += n; else if (l[0] === 'No Due Date') c.noDueDate += n;
      c.total += n;
    });
    return c;
  };
  function plural(n, a, b) { return n + ' ' + (n === 1 ? a : b); }
  /** ChoresConfig.choreSubtitle / grocerySubtitle. */
  Chores.subtitle = function (pageId, zero) {
    var c = zero ? { overdue: 0, upcoming: 0, noDueDate: 0, total: 0 } : Chores.counts(pageId);
    if (pageId === 'groceries') return c.total > 0 ? plural(c.total, 'item', 'items') : 'No groceries listed';
    var dated = c.overdue > 0 ? plural(c.overdue, 'overdue task', 'overdue tasks') : c.upcoming > 0 ? plural(c.upcoming, 'upcoming task', 'upcoming tasks') : '';
    var undated = c.noDueDate > 0 ? plural(c.noDueDate, 'task listed', 'tasks listed') : '';
    if (dated && undated) return dated + ' · ' + undated;
    return dated || undated || 'No tasks listed';
  };

  /* ------------------------------------------------------------------ the quick links (ChoreQuickLinks) */
  var LINKS = [
    { page: 'alexs-chores', resident: 'alex', family: 'chore-resident1', symbol: 'person.crop.circle.fill', title: "Alex's Tasks" },
    { page: 'sams-chores', resident: 'sam', family: 'chore-resident2', symbol: 'person.crop.circle.fill', title: "Sam's Tasks" },
    { page: 'unassigned-chores', family: 'chore-unassigned', symbol: 'tray.circle.fill', title: 'Unassigned Tasks' },
    { page: 'home-improvement-chores', family: 'chore-home', symbol: 'hammer.circle.fill', title: 'Home Tasks' },
    { page: 'groceries', family: 'groceries', symbol: 'cart.circle.fill', title: 'Groceries', grocery: true },
  ];
  Chores.LINKS = LINKS;
  /** QuickLink.title(viewer): "Your Chores" on the viewer's own link, "{Name}'s Chores" on the other resident's. */
  Chores.linkTitle = function (l, viewer) {
    if (!l.resident || !viewer) return l.title;
    return l.resident === viewer ? 'Your Chores' : (l.resident === 'alex' ? "Alex's Chores" : "Sam's Chores");
  };
  /** The navigation tile's state line (ChoresConfig.openSubtitle, rollout M 2026-10-28, owner item 26 A): the open count the numeral used to carry. */
  Chores.openSubtitle = function (pageId, zero) {
    var c = zero ? { overdue: 0, total: 0 } : Chores.counts(pageId);
    if (c.total <= 0) return 'Nothing open';
    return c.total + ' open' + (c.overdue > 0 ? ' \u00b7 ' + c.overdue + ' overdue' : '');
  };
  /** One tile (rollout M): a NAVIGATION tile (behavior 'navigate': glyph, text, chevron, no numeral) on the page's chore family; the state line is the open count. */
  Chores.quickLinkTile = function (l, o) {
    o = o || {};
    var title = Chores.linkTitle(l, o.viewer === undefined ? 'alex' : o.viewer), sub = Chores.openSubtitle(l.page, o.zero);
    var tile = K.GlassTile({ title: title, subtitle: sub, symbol: l.symbol, family: l.family, isActive: true, behavior: 'navigate' });
    tile.removeAttribute('aria-pressed'); tile.dataset.link = l.page;
    return h('div.cz-ql', tile);
  };
  /** The section: "Quick Links" header over a DynamicGridLayout (min 150, max 4 columns, equal row heights), Groceries spanning two tracks. */
  Chores.quickLinks = function (o) {
    o = o || {};
    var items = LINKS.map(function (l) { return Chores.quickLinkTile(l, o); });
    var sc0 = (Mock.current && Mock.current.scale) || 1;
    // ChoreQuickLinks passes a literal minCellWidth of 150 (not @ScaledMetric): the kit scales min by --sc, so divide it back; at AX5 on an iPhone that is still two tracks.
    var grid = K.TileGrid({ items: items, min: 150 / sc0, max: 4, equal: true, span: { 4: 2 } });
    // kit gap: a one-track grid whose scaled minimum is wider than the screen (AX sizes) overflows, and a span of two then adds a second track. DynamicGridLayout clamps both.
    if (window.ResizeObserver) {
      var mine = false;
      new ResizeObserver(function () {
        var w = grid.clientWidth, screen = grid.closest('.screen, .ui-root'); if (!w) return;
        var sc = parseFloat(screen ? getComputedStyle(screen).getPropertyValue('--sc') : 1) || 1, one = Math.floor((w + 12) / (150 + 12)) < 2;
        if (one) { grid.style.gridTemplateColumns = 'minmax(0,1fr)'; mine = true; } else if (mine) { grid.style.gridTemplateColumns = ''; mine = false; }
        grid.classList.toggle('cz-one', one);
      }).observe(grid);
    }
    return h('div.ui-section', { dataset: { part: 'quick-links' } }, K.PageSectionHeader({ title: 'Quick Links' }), grid);
  };

  /* ------------------------------------------------------------------ rows and sections (TodoItemRow, TodoListSection) */
  /**
   * One TodoItemRow. it: {title, due (seconds), done?}; o: {edit (show Edit button), id}.
   * The whole left side is one toggle (52 pt, 60 pt with a due line); the Edit glyph is its own 44 pt button.
   */
  Chores.row = function (it, o) {
    o = o || {};
    var done = !!it.done, d = done ? null : Chores.due(it.due);
    var value = done ? 'Done' : ['Not done', d && d.text].filter(Boolean).join(', ');
    var tg = h('button.tg', { type: 'button', role: 'switch', 'aria-checked': done ? 'true' : 'false', 'aria-label': it.title, 'aria-description': value + '. ' + (done ? 'Marks the task not done.' : 'Marks the task done.') },
      h('span.rw', h('span.ck', { html: I(done ? 'checkmark.circle.fill' : 'circle') }),
        h('span.vt', h('span.tt', it.title), d ? h('span.cz-due.' + d.tone, h('span', { html: I(d.tone === 'future' ? 'calendar' : 'clock') }), h('span', d.text)) : null)));
    var row = h('div.cz-row' + (d ? '.due' : '') + (done ? '.done' : ''), { role: 'listitem', dataset: { item: it.title } }, tg,
      o.undo ? h('button.ed.undo', { type: 'button', 'aria-label': 'Undo ' + it.title }, 'Undo') : o.edit ? h('button.ed', { type: 'button', 'aria-label': 'Edit ' + it.title, html: I('square.and.pencil') }) : h('span.pad'));
    return row;
  };
  function hasLate(items) { return items.some(function (i) { var d = i.done ? null : Chores.due(i.due); return d && d.tone !== 'future'; }); }
  Chores.hasLate = hasLate;
  function spinnerRow(title) { return h('div.cz-spin', K.ArcSpinner({ size: 'compact', label: 'Loading ' + title })); }
  /**
   * One TodoListSection: optional header, optional error (InlineAlert, warning), a compact arc while the list has never loaded, then its rows on one
   * module (dense when a row is overdue: orange and red text need it).
   * o: {title, items, header (default true), error, loading, edit, rowsOverride (nodes)}
   */
  Chores.section = function (o) {
    var kids = [];
    if (o.header !== false) kids.push(K.PageSectionHeader({ title: o.title }));
    if (o.error) kids.push(K.InlineAlert({ message: o.error }));
    if (o.loading) kids.push(spinnerRow(o.title));
    else if (o.items && o.items.length) {
      var rows = o.rowsOverride || o.items.map(function (it) { return Chores.row(it, { edit: o.edit, undo: o.undo && o.undo.indexOf(it.title) >= 0 }); });
      kids.push(h('div.ui-mlist' + (hasLate(o.items) ? '.dense' : ''), { role: 'list', 'aria-label': o.title }, rows));
    }
    return h('div.ui-section', { dataset: { list: o.title } }, kids);
  };
  /** ContentUnavailableView on the wallpaper: checklist glyph, title, description. */
  Chores.empty = function (copy) {
    return h('div.cz-empty', { role: 'group', 'aria-label': copy[0] + '. ' + copy[1] }, h('span.gl', { html: I('checklist') }), h('h2', copy[0]), h('p', copy[1]));
  };

  /* ------------------------------------------------------------------ swipe and context menu drawings */
  var ACTIONS = { complete: ['Complete', 'checkmark.circle.fill'], reopen: ['Mark Not Done', 'arrow.uturn.backward.circle'], edit: ['Edit', 'square.and.pencil'], delete: ['Delete', 'trash'] };
  function actBtn(a) { return h('button.' + a, { type: 'button', 'aria-label': ACTIONS[a][0] }, h('span', { html: I(ACTIONS[a][1], { fill: true }) }), ACTIONS[a][0]); }
  /** A row swiped open. edge 'leading' (Complete, a full swipe performs it) or 'trailing' (Delete outermost, then Edit); full: the first action fills the row. */
  Chores.swipeRow = function (rowNode, edge, o) {
    o = o || {};
    var acts = edge === 'leading' ? ['complete'] : (o.actions || ['delete', 'edit']);
    var n = acts.length, w = 76 * n;
    var box = h('div.cz-sw1.' + edge);
    var strip = h('div.acts.' + (edge === 'leading' ? 'l' : 't') + (o.full ? '.full' : ''), { style: { width: o.full ? '100%' : w + 'px' } }, edge === 'leading' ? acts.map(actBtn) : acts.map(actBtn));
    var slide = h('div.slide' + (o.dense ? '.dense' : ''), { style: { transform: 'translateX(' + (o.full ? (edge === 'leading' ? '78%' : '-78%') : (edge === 'leading' ? w + 'px' : -w + 'px')) + ')' } }, rowNode);
    box.appendChild(strip); box.appendChild(slide);
    return box;
  };
  /** Context menu over a lifted row: actions in swipe order, destructive last (HIG Context menus). */
  Chores.contextMenu = function (rowNode, actions) {
    var items = (actions || ['complete', 'edit', 'delete']).map(function (a) { return h('button' + (a === 'delete' ? '.delete' : ''), { type: 'button' }, ACTIONS[a][0], h('span', { html: I(ACTIONS[a][1]) })); });
    return h('div.cz-ctx', { role: 'menu' }, h('div.lift', rowNode), h('div.cz-menu', items));
  };

  /* ------------------------------------------------------------------ the confirmation dialog */
  /**
   * confirmationDialog(title, titleVisibility: .visible) { Button(role: .destructive) } message: "This can't be undone.".
   * iPhone: an action sheet at the bottom (title and message on the card, destructive button, Cancel on its own card).
   * iPad and Duo unfolded: a popover with no Cancel row (tapping outside cancels). o: {title, destructive, dark}
   */
  Chores.actionSheet = function (ctx, o) {
    var cls = (o.dark ? 'g-dark' : (ctx.appearance === 'dark' ? 'g-dark' : 'g-light'));
    var head = h('div.hd', h('div.ti', o.title), h('div.ms', o.message || "This can't be undone."));
    var card = h('div.cz-act' + (ctx.compact ? '' : '.popover'), { role: 'alertdialog', 'aria-label': o.title }, head, h('button.destructive', { type: 'button' }, o.destructive || 'Delete Task'));
    if (ctx.compact) return h('div.cz-act-scrim.' + cls, card, h('div.cz-act.cancel', h('button', { type: 'button' }, 'Cancel')));
    return h('div.cz-act-scrim.pop.' + cls, card);
  };

  /* ------------------------------------------------------------------ the floating Add bar and the page */
  Chores.fab = function (ctx, id) { return K.FloatingActionBar({ actions: [{ id: 'add', title: PAGES[id].add, symbol: 'plus' }], ctx: ctx }); };

  /**
   * The page body for a todo page.
   * o: viewer ('alex'|'sam'), mode ('default'|'loading'|'error'|'empty'), vacation, long (long titles), zeroLinks, nodes: extra override
   */
  Chores.body = function (ctx, id, o) {
    o = o || {};
    var P = PAGES[id], out = [], secs = Chores.sections(id, o), mode = o.mode || 'default';
    if (P.header) out.push(Chores.quickLinks({ viewer: o.viewer === undefined ? 'alex' : o.viewer, zero: mode === 'empty' || o.zeroLinks }));
    if (o.long && secs[0]) secs[0].items[0] = { title: P.longTitle || 'Replace the batteries in the upstairs hallway smoke detector and then test every alarm in the whole house, including the garage', due: P.isGrocery || P.admin ? undefined : (secs[0].items[0].due == null ? -3 * H : secs[0].items[0].due) };
    if (o.long && secs[1] && !P.isGrocery) secs[1].items.push({ title: 'Call the plumber about the slow drain under the guest bathroom sink', due: 40 * D });
    if (mode === 'empty') { out.push(Chores.empty(Chores.emptyCopy(id, o))); return out; }
    secs.forEach(function (s, i) {
      var opt = { title: s.title, items: s.items, header: !P.noHeaders, edit: P.edit };
      if (mode === 'loading') opt.loading = true;
      if (mode === 'error') {
        if (i === 0) opt.error = P.isGrocery ? 'Unable to delete task' : 'Unable to update task';
        else if (i === 1) { opt.error = 'Unable to load list'; opt.loading = true; }
      }
      out.push(Chores.section(opt));
    });
    return out;
  };

  /**
   * A whole page (tab root or pushed). o: as body, plus connection, swipe ('leading'|'trailing'|'trailing-full'), menu (true: context menu on the first row),
   * dialog ({title, destructive, dark}) and noFab.
   */
  Chores.page = function (ctx, id, o) {
    o = o || {};
    var P = PAGES[id], viewer = o.viewer === undefined ? 'alex' : o.viewer;
    var body = Chores.body(ctx, id, o);
    var overdue = viewer === 'alex' && !o.noBadge ? 3 : 0;
    var page = Mock.page(ctx, { title: P.title, section: P.section, back: P.back, body: body, floating: o.noFab ? null : Chores.fab(ctx, id), connection: o.connection,
      badge: overdue || undefined, choresBadge: overdue || undefined });
    if (o.swipe || o.menu) {
      var first = page.querySelector('.ui-mlist .cz-row');
      if (first) {
        var list = first.parentNode, dense = list.classList.contains('dense');
        if (o.swipe) {
          var sw = Chores.swipeRow(first.cloneNode(true), o.swipe === 'leading' ? 'leading' : 'trailing', { full: /full/.test(o.swipe), dense: dense, actions: P.del === false ? ['edit'] : (P.edit ? ['delete', 'edit'] : ['delete']) });
          list.replaceChild(sw, first);
        } else {
          var lifted = first.cloneNode(true);
          page.appendChild(Chores.contextMenu(lifted, P.edit ? ['complete', 'edit'].concat(P.del ? ['delete'] : []) : ['complete'].concat(P.del ? ['delete'] : [])));
        }
      }
    }
    if (o.dialog) page.appendChild(Chores.actionSheet(ctx, Object.assign({ dark: true }, o.dialog)));
    return page;
  };

  /* ------------------------------------------------------------------ forms inside the sheets */
  function sec(header, footer, rows) {
    return h('section', header ? h('p.ui-formhead', { role: 'heading', 'aria-level': '2' }, header) : null, h('div.ui-form', rows), footer ? h('p.ui-formfoot', footer) : null);
  }
  function txt(placeholder, value, o) {
    o = o || {};
    var body = value ? [value, o.caret ? h('span.cz-caret') : null] : [o.caret ? h('span.cz-caret') : null, h('span', placeholder)];
    var span = h('span.lb.tf' + (value ? '' : '.ph'), { role: 'textbox', 'aria-label': placeholder, 'aria-multiline': o.multi ? 'true' : null }, body);
    return h('div.ui-field' + (o.multi ? '.multi' : ''), span);
  }
  function pick(label, value) { return h('div.ui-field', { role: 'button', 'aria-label': label + ', ' + value }, h('span.lb', label), h('span.va', value, ' ', h('span', { html: I('chevron.up.chevron.down') }))); }
  function tog(label, on) { return K.FormField({ label: label, kind: 'toggle', on: !!on }); }
  function datep(label, text) { return h('div.ui-field', { role: 'button', 'aria-label': label + ', ' + text }, h('span.lb', label), h('span.ui-date', text)); }
  function valp(label, value) { return h('div.ui-field', h('span.lb', label), h('span.va', value)); }
  function tick(label, on) { return h('div.ui-field', { role: 'checkbox', 'aria-checked': on ? 'true' : 'false' }, h('span.lb', label), on ? h('span.tick', { html: I('checkmark', { weight: 2.4 }) }) : null); }
  function errSec(message) { return h('section', h('div.alert', K.InlineAlert({ message: message, severity: 'error' }))); }
  Chores.form = { sec: sec, txt: txt, pick: pick, tog: tog, datep: datep, valp: valp, tick: tick, errSec: errSec };

  var NAME_FOOTER = 'A short name for the chore, as it appears in your lists. For example, “Take out the recycling”.';
  var DESC_FOOTER = 'Optional. Add steps, notes or where to find supplies. It shows with the task when you open it.';
  var PRIORITIES = { none: 'None', low: 'P1', medium: 'P2', high: 'P3', critical: 'P4' };
  var RECURRENCES = { no_repeat: 'No Recurrence', daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly', yearly: 'Yearly', interval: 'Custom Interval', days_of_the_week: 'Specific Days of Week', adaptive: 'Adaptive' };
  var WEEKDAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  Chores.TASK_DEFAULTS = { name: '', description: '', assignee: 'Anyone', priority: 'critical', dueDate: null, dueTime: null, recurrence: 'no_repeat', interval: '1', unit: 'Days', days: [], hide: true };

  /** DonetickTaskFormFields: what, who, when, then vacation; Repeat Every and Days of Week only for their recurrence; Delete Task only when editing. */
  Chores.taskForm = function (f, o) {
    o = o || {};
    var rows = [];
    if (o.error) rows.push(errSec(o.error));
    rows.push(sec('Task Name', NAME_FOOTER, [txt('Task Name', f.name, { caret: o.focusName })]));
    rows.push(sec('Description', DESC_FOOTER, [txt('Description', f.description, { multi: true })]));
    rows.push(sec(null, null, [pick('Assignee', f.assignee), pick('Priority', PRIORITIES[f.priority])]));
    var when = [tog('Due Date', !!f.dueDate)];
    if (f.dueDate) when.push(datep('Date', f.dueDate));
    when.push(tog('Due Time', !!f.dueTime));
    if (f.dueTime) when.push(datep('Time', f.dueTime));
    when.push(pick('Repeat', RECURRENCES[f.recurrence] + (o.editing ? '' : '')));
    rows.push(sec(null, null, when));
    if (f.recurrence === 'interval') rows.push(sec(null, 'How often to repeat: every 1 to 365 days, weeks, months, or years.', [valp('Repeat Every', f.interval), pick('Interval Unit', f.unit)]));
    if (f.recurrence === 'days_of_the_week') rows.push(sec('Days of Week', null, WEEKDAYS.map(function (d) { return tick(d, f.days.indexOf(d) >= 0); })));
    rows.push(sec(null, 'This task will not show up in your chores lists while Vacation Mode is on.', [tog('Hide While On Vacation', f.hide)]));
    if (o.editing) rows.push(sec(null, null, [h('div.ui-field.danger', { role: 'button' }, h('span.lb', 'Delete Task'))]));
    return h('div.cz-form' + (o.busy ? '.busy' : ''), rows);
  };
  Chores.EDIT_FORM = Object.assign({}, Chores.TASK_DEFAULTS, { name: 'Water the plants', description: 'Two cans for the ferns, one for the herbs.', assignee: 'You', priority: 'high', dueDate: 'Oct 25, 2026', dueTime: '9:00 AM', recurrence: 'weekly' });

  Chores.loadingView = function () { return h('div.cz-load', { role: 'status' }, K.ArcSpinner({ size: 'page', label: 'Loading task' }), h('span', 'Loading task')); };
  Chores.unavailableView = function (msg) {
    return h('div.cz-unavail', { role: 'group', 'aria-label': 'Unable to Load Task. ' + msg }, h('span.gl', { html: I('exclamationmark.triangle') }), h('h2', 'Unable to Load Task'), h('p', msg));
  };

  /** Presenting page for a sheet, with the sheet's own options. */
  function present(ctx, o, sheetOpts) {
    if (o.optsOnly) return Object.assign({ size: 'form', detent: o.detent || 'fitted', leading: 'cancel', trailing: 'confirm' }, sheetOpts);
    var presenter = o.presenter === false ? null : (o.presenter || Chores.page(ctx, o.from || 'chores', { connection: o.connection }));
    var sh = Mock.sheet(ctx, Object.assign({ size: 'form', detent: o.detent || 'fitted', leading: 'cancel', trailing: 'confirm', presenter: presenter }, sheetOpts));
    if (o.busy) sh.classList.add('cz-busy');
    return sh;
  }

  /**
   * DonetickTaskSheet. o: mode 'create'|'edit', phase 'loading'|'load-error', form (overrides), error, busy 'saving'|'deleting', changed (edit has changes),
   * detent, from (presenting page id), deleteDialog (shows "Delete {name}?"), focusName.
   */
  Chores.taskSheet = function (ctx, o) {
    o = o || {};
    var editing = o.mode === 'edit', f = Object.assign({}, editing ? Chores.EDIT_FORM : Chores.TASK_DEFAULTS, o.form || {});
    var content, loaded = !(editing && o.phase);
    if (editing && o.phase === 'loading') content = Chores.loadingView();
    else if (editing && o.phase === 'load-error') content = Chores.unavailableView('Unable to load task');
    else content = Chores.taskForm(f, { editing: editing, error: o.error, busy: !!o.busy, focusName: o.focusName });
    var valid = loaded && !!f.name.trim(), enabled = valid && (!editing || !!o.changed) && !o.busy;
    var sh = present(ctx, o, { title: editing ? 'Edit Task' : 'New Task', content: content,
      confirm: { title: editing ? 'Save' : 'Create', busyTitle: editing ? 'Saving' : 'Creating', enabled: enabled, busy: o.busy === 'saving' } });
    if (o.deleteDialog) sh.appendChild(Chores.actionSheet(ctx, { title: 'Delete ' + f.name + '?', destructive: 'Delete Task', dark: false }));
    return sh;
  };

  /** AddGroceryItemSheet: one Item field; Add is disabled until the trimmed text is not empty. */
  Chores.grocerySheet = function (ctx, o) {
    o = o || {};
    var rows = [];
    if (o.error) rows.push(errSec(o.error));
    rows.push(sec('Item', 'Added to the Groceries list.', [txt('Item', o.value || '', { caret: !o.busy })]));
    var content = h('div.cz-form' + (o.busy ? '.busy' : ''), rows);
    return present(ctx, Object.assign({ from: 'groceries' }, o), { title: 'Add Grocery Item', subtitle: 'Groceries', content: content,
      confirm: { title: 'Add', busyTitle: 'Adding', enabled: !!(o.value || '').trim() && !o.busy, busy: o.busy === 'saving' } });
  };

  /** AddAdminTodoSheet: Task (1 to 4 lines, 1000 characters), then Images (up to four, 10 MB each) behind a PhotosPicker row. */
  Chores.adminSheet = function (ctx, o) {
    o = o || {};
    var rows = [];
    if (o.error) rows.push(errSec(o.error));
    rows.push(sec('Task', 'This issue is synchronized from the dashboard Admin To-Do list. The repository is public.', [txt('Task', o.value || '', { caret: !o.busy && !o.images })]));
    var imgRows = (o.images || []).map(function (im, i) {
      return h('div.ui-field', h('span.thumb', { style: { background: Mock.scene(i ? 'upper-deck' : 'driveway') }, 'aria-hidden': 'true' }), h('span.lb', im),
        h('button.rm', { type: 'button', 'aria-label': 'Remove ' + im, html: I('xmark.circle.fill') }));
    });
    imgRows.push(h('div.ui-field.act', { role: 'button' }, h('span', { html: I('photo.on.rectangle.angled', { size: '1.2em' }) }), h('span.lb', { style: { marginLeft: '8px' } }, (o.images || []).length ? 'Choose Different Images' : 'Add Images')));
    rows.push(sec('Images', 'Add up to four PNG, JPEG, or WebP images, 10 MB each.', imgRows));
    return present(ctx, Object.assign({ from: 'admin-todo' }, o), { title: 'Add Task', subtitle: 'Admin To-Do', content: h('div.cz-form' + (o.busy ? '.busy' : ''), rows),
      confirm: { title: 'Add', busyTitle: 'Adding', enabled: !!(o.value || '').trim() && !o.busy, busy: o.busy === 'saving' } });
  };

  /** RenameTodoItemSheet: Task Name prefilled; Reset to Original shows only when the draft differs or an error shows; Save needs a new, non-empty name. */
  Chores.renameSheet = function (ctx, o) {
    o = o || {};
    var original = 'Port the Chores page', draft = o.draft == null ? original : o.draft, rows = [];
    if (o.error) rows.push(errSec(o.error));
    if (o.noIdentity) rows.push(errSec('This task cannot be edited because its Home Assistant identity is unavailable.'));
    rows.push(sec(null, 'This issue is synchronized from the dashboard Admin To-Do list. The repository is public.', [txt('Task Name', draft, { caret: !o.busy })]));
    if (draft !== original || o.error) rows.push(sec(null, null, [h('div.ui-field.act', { role: 'button' }, h('span.lb', 'Reset to Original'))]));
    var can = !o.noIdentity && !!draft.trim() && draft.trim() !== original && !o.busy;
    return present(ctx, Object.assign({ from: 'admin-todo' }, o), { title: 'Edit Task', subtitle: 'Admin To-Do', content: h('div.cz-form' + (o.busy ? '.busy' : ''), rows),
      confirm: { title: 'Save', busyTitle: 'Saving', enabled: can, busy: o.busy === 'saving' } });
  };

  /* ------------------------------------------------------------------ small shared pieces for transitions and motion */
  /** The dialog presenting over the stage's page: the scrim fades in, the card rises (system action sheet; Reduce Motion cross-fades), then it leaves again. */
  Chores.dialogDemo = function (stage, o) {
    var ctx = Mock.current, page = stage.querySelector('.ui-page'), rm = Mock.settings.reduceMotion;
    if (!page) return Promise.resolve();
    var ov = Chores.actionSheet(ctx, Object.assign({ dark: true }, o)), cards = [].slice.call(ov.children);
    page.appendChild(ov);
    var d = rm ? 250 : 450, ease = 'cubic-bezier(.32,.72,0,1)';
    function go(el, fr, dur) { return el.animate(fr, { duration: dur, easing: ease, fill: 'both' }).finished.catch(function () {}); }
    var inn = [go(ov, [{ backgroundColor: 'rgba(0,0,0,0)' }, { backgroundColor: 'rgba(0,0,0,.4)' }], d)].concat(cards.map(function (c) { return go(c, rm ? [{ opacity: 0 }, { opacity: 1 }] : [{ transform: 'translateY(120%)' }, { transform: 'none' }], d); }));
    return Promise.all(inn).then(function () { return Mock.sleep(1200); }).then(function () {
      return Promise.all([go(ov, [{ backgroundColor: 'rgba(0,0,0,.4)' }, { backgroundColor: 'rgba(0,0,0,0)' }], d)].concat(cards.map(function (c) { return go(c, rm ? [{ opacity: 1 }, { opacity: 0 }] : [{ transform: 'none' }, { transform: 'translateY(120%)' }], d); })));
    }).then(function () { ov.remove(); });
  };
  /** Slide a pushed page over the stage's page and back (system push, Mock.anim.push); the pushed page is built by `make`. */
  Chores.pushDemo = function (stage, make) {
    var ctx = Mock.current, a = stage.querySelector('.ui-page');
    if (!a) return Promise.resolve();
    var b = make(ctx);
    a.parentNode.insertBefore(b, a.nextSibling);
    return Mock.anim.push(a, b).then(function () { return Mock.sleep(700); }).then(function () { return Mock.anim.push(b, a, { back: true }); }).then(function () { b.remove(); Mock.anim.reset(stage); });
  };
  /** A row leaves the list: the page's one implicit animation, `standard` 0.3 s (0.2 s fade under Reduce Motion). */
  Chores.leave = function (row) {
    var rm = Mock.settings.reduceMotion, hgt = row.offsetHeight;
    var frames = rm ? [{ opacity: 1 }, { opacity: 0 }] : [{ opacity: 1, height: hgt + 'px' }, { opacity: 0, height: '0px' }];
    row.style.overflow = 'hidden';
    var a = row.animate(frames, { duration: rm ? Mock.anim.ms.quick() : Mock.anim.ms.standard(), easing: rm ? 'cubic-bezier(0,0,.2,1)' : 'cubic-bezier(.4,0,.2,1)', fill: 'forwards' });
    return a.finished.catch(function () {});
  };
  Chores.enter = function (row) {
    var rm = Mock.settings.reduceMotion, hgt = row.scrollHeight;
    row.getAnimations().forEach(function (a) { a.cancel(); });
    var frames = rm ? [{ opacity: 0 }, { opacity: 1 }] : [{ opacity: 0, height: '0px' }, { opacity: 1, height: hgt + 'px' }];
    var a = row.animate(frames, { duration: rm ? Mock.anim.ms.quick() : Mock.anim.ms.standard(), easing: 'cubic-bezier(.4,0,.2,1)' });
    return a.finished.catch(function () {});
  };
  /** Swatch surfaces for the component mockups: the page (always dark, on a gradient) and a sheet (follows the appearance control). */
  Chores.swatch = function (ctx, surface, caption, node, note) {
    var box = h('div.k-swatch.' + (surface === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light')), { style: { flex: '1 1 340px', maxWidth: '100%' } },
      h('div.k-cap', surface + ' · ' + caption), h('div.in', node), note ? h('div', { style: { font: '12px var(--font)', opacity: .7, marginTop: '8px' } }, note) : null);
    return box;
  };
  Chores.swatches = function (items) { return h('div.k-swatch-grid', items); };


  /** The add or edit sheet a page presents (options only when `optsOnly`): groceries and the admin page have their own; resident pages preassign the assignee. */
  var ASSIGNEE = { 'alexs-chores': 'You', 'sams-chores': 'Sam', 'home-improvement-chores': 'Home Improvement', 'unassigned-chores': 'Anyone', 'chores': 'Anyone' };
  Chores.sheetFor = function (ctx, id, kind, extra) {
    var o = Object.assign({ from: id }, extra || {});
    if (id === 'groceries') return Chores.grocerySheet(ctx, o);
    if (id === 'admin-todo') return kind === 'edit' ? Chores.renameSheet(ctx, o) : Chores.adminSheet(ctx, o);
    if (kind === 'edit') return Chores.taskSheet(ctx, Object.assign({ mode: 'edit' }, o));
    return Chores.taskSheet(ctx, Object.assign({ mode: 'create', form: { assignee: ASSIGNEE[id] || 'Anyone' } }, o));
  };

  /** States every todo page shares, rendered through Chores.page. ex: {extra: {key: state}}. */
  Chores.pageStates = function (id, ex) {
    ex = ex || {}; var P = PAGES[id];
    function pg(o) { return function (d) { return Chores.page(d, id, o); }; }
    var st = {
      'default': { title: ex.defaultTitle || 'Lists loaded', render: pg({}) },
      'loading': { title: 'First launch, nothing saved: each list spins', note: 'the list entity says it has open items but nothing is fetched yet: header plus a compact arc', render: pg({ mode: 'loading' }) },
      'refreshing': { title: 'Saved items on screen, a fetch swaps in', note: 'identical to default by design: TodoItemsCache shows the last items before the first fetch, and rows only move when the list really changed', render: pg({}) },
      'empty': { title: P.empty[0], note: 'every list is settled and hidden: ContentUnavailableView on the wallpaper', render: pg({ mode: 'empty' }) },
    };
    if (P.vacation) st['vacation'] = { title: 'Vacation Mode on', note: 'the same empty state reads "Enjoy vacation!" while input_boolean.demo_mode_4 is on', render: pg({ mode: 'empty', vacation: true }) };
    if (P.resident) st['empty-other-viewer'] = { title: 'Empty, signed in as ' + (P.resident === 'alex' ? 'Sam' : 'Alex'), note: 'the personal "You have no chores due" copy only reads on your own page', render: pg({ mode: 'empty', viewer: P.resident === 'alex' ? 'sam' : 'alex' }) };
    st['error'] = { title: P.isGrocery ? 'A delete failed' : 'A check-off failed' + (P.admin || P.isGrocery ? '' : ' and a list failed to load'), note: 'inline warning under the list header; the failed row returns' + (P.isGrocery || P.admin ? '' : '; the failed list keeps its arc'), render: pg({ mode: 'error' }) };
    st['offline'] = { title: 'No network', note: 'saved items stay; offline chip under the header and a cloud badge on Profile; check-offs would fail with "Unable to update task"', render: pg({ connection: 'offline' }) };
    st['reconnecting'] = { title: 'Connection down 2 s+', note: 'arc left of Quick Links', render: pg({ connection: 'reconnecting' }) };
    st['long-text'] = { title: 'Long titles wrap, never truncate', render: pg({ long: true }) };
    st['swipe-trailing'] = { title: 'Swipe from the trailing edge', note: P.edit ? (P.del ? 'Delete (red, outermost) then Edit (blue)' : 'Edit only: the admin To-Do is synced to GitHub issues, so it cannot be deleted') : 'Delete only: groceries have no editor', render: pg({ swipe: 'trailing' }) };
    st['swipe-complete'] = { title: 'Swipe from the leading edge: Complete', note: 'green; a full swipe performs it', render: pg({ swipe: 'leading' }) };
    st['context-menu'] = { title: 'Touch and hold a row', render: pg({ menu: true }) };
    if (P.del) st['delete-confirm'] = { title: 'Delete asks first', note: 'confirmationDialog (see todo-delete-dialog)', render: pg({ dialog: { title: 'Delete ' + (P.isGrocery ? 'Oat milk' : (id === 'chores' || id === 'alexs-chores' ? 'Clean the gutters' : Chores.sections(id)[0].items[0].title)) + '?', destructive: P.isGrocery ? 'Delete Item' : 'Delete Task' } }) };
    Object.keys(ex.extra || {}).forEach(function (k) { st[k] = ex.extra[k]; });
    st['ax5'] = { title: 'Accessibility 5 text size', override: { ts: 'ax5' }, note: 'rows wrap, the Add button full width, headers stack', render: pg({}) };
    return st;
  };

  var SRC = ['apple/Sources/HassUI/Features/Chores/ChoresScreen.swift', 'apple/Sources/HassUI/Features/Chores/TodoPageView.swift', 'apple/Sources/HassUI/Features/Chores/TodoListSection.swift',
    'apple/Sources/HassCore/Config/ChoresConfig.swift', 'apple/Sources/HassCore/Todo/TodoItem.swift', 'apple/Sources/HassCore/Todo/TodoRowActions.swift', 'apple/Sources/HassCore/Todo/TodoListController.swift'];
  var SECS = function (d, t) { return d.querySelector('.ui-section[data-list="' + t + '"]'); };

  /** The motion every todo page has: a row leaving and returning, the arc giving way to rows. firstTitle/secondTitle: row names on this page. */
  Chores.pageMotion = function (id, ex) {
    ex = ex || {};
    var secs = Chores.sections(id), t1 = secs[0].items[secs[0].items.length > 1 ? 1 : 0].title, listTitle = secs[0].title;
    return [
      { id: 'row-complete', what: 'Checking a task off: its row leaves the list and the module closes up', token: 'standard 0.3 s smooth (the list animation keyed by the page layout); 0.2 s fade under Reduce Motion', state: 'default',
        source: 'HassUI/Features/Chores/TodoPageView.swift motionSafeAnimation(MotionTokens.standard, reduced: .quick); motion.md section 6', reduce: 'the row fades out at 0.2 s (quick) and nothing slides',
        play: function (stage) { var r = stage.querySelector('.cz-row[data-item="' + t1 + '"]'); return r ? Chores.leave(r).then(function () { return Mock.sleep(500); }) : Promise.resolve(); } },
      { id: 'row-rollback', what: 'The call fails (or nothing confirms in 15 s): the row comes back and the list says why', token: 'standard 0.3 s; the alert row appears with it', state: 'default',
        source: 'TodoListController.toggle / remove (optimistic revert, "' + (id === 'groceries' ? 'Unable to delete task' : 'Unable to update task') + '"); TodoPageView animation', reduce: 'the row fades back at 0.2 s',
        play: function (stage) {
          var r = stage.querySelector('.cz-row[data-item="' + t1 + '"]'), s = SECS(stage, listTitle) || stage.querySelector('.ui-section[data-list]'); if (!r || !s) return Promise.resolve();
          return Chores.leave(r).then(function () { return Mock.sleep(900); }).then(function () {
            var al = K.InlineAlert({ message: 'Unable to update task' }); s.insertBefore(al, s.children[s.children.length > 1 ? 1 : 0]); Chores.enter(r);
            return Mock.anim.fade(al, { ms: Mock.anim.ms.standard() }).then(function () { return Mock.sleep(900); });
          });
        } },
      { id: 'list-arrives', what: 'The first fetch lands: the arc gives way to the list\'s rows', token: 'standard 0.3 s (the same implicit list animation); the arc turns once per 0.82 s, linear', state: 'loading',
        source: 'TodoListSection (controller.items nil: ArcSpinner(.compact)); ArcSpinner.swift', reduce: 'rows fade in at 0.2 s; the arc keeps turning at half speed',
        play: function (stage) {
          return Mock.sleep(1400).then(function () {
            var jobs = [].slice.call(stage.querySelectorAll('.ui-section[data-list]')).map(function (s) {
              var sp = s.querySelector('.cz-spin'); if (!sp) return Promise.resolve();
              var def = Chores.sections(id).filter(function (x) { return x.title === s.dataset.list; })[0]; if (!def) return Promise.resolve();
              var fresh = Chores.section({ title: def.title, items: def.items, edit: PAGES[id].edit }).querySelector('.ui-mlist'); s.replaceChild(fresh, sp);
              return Mock.anim.fade(fresh, { ms: Mock.settings.reduceMotion ? Mock.anim.ms.quick() : Mock.anim.ms.standard() });
            });
            return Promise.all(jobs);
          }).then(function () { return Mock.sleep(500); });
        } },
    ];
  };

  Chores.pageTransitions = function (id) {
    var P = PAGES[id], t = [];
    if (P.back === 'Chores') t.push({ from: 'Chores tab', to: P.title, kind: 'push', note: 'A Quick Links tile (or, for Groceries, the Kitchen page\'s Groceries section and a Home route) pushes the page from the trailing edge; the sending page slides left. A push, never a zoom. The back swipe is the system\'s.',
      play: function (stage) { return Chores.pushDemo(stage, function (ctx) { return Chores.page(ctx, id); }); } });
    if (id === 'admin-todo') t.push({ from: 'Settings', to: 'To-Do', kind: 'push', note: 'The To-Do row in Settings (Alex only) pushes the page; back returns to Settings.',
      play: function (stage) { return Chores.pushDemo(stage, function (ctx) { return Chores.page(ctx, id); }); } });
    t.push({ from: P.add, to: id === 'groceries' ? 'Add Grocery Item sheet' : id === 'admin-todo' ? 'Add Task (admin) sheet' : 'New Task sheet', kind: 'sheet', note: 'The floating Add button presents a fitted form sheet (540 pt on iPad). Content is present on arrival (motion.md section 4.4).',
      play: function (stage) { return Mock.presentDemo(stage, Chores.sheetFor(Mock.current, id, 'add', { optsOnly: true }), { hold: 1200 }); } });
    if (P.edit) t.push({ from: 'Edit glyph or Edit swipe', to: id === 'admin-todo' ? 'Edit Task (rename) sheet' : 'Edit Task sheet', kind: 'sheet', note: id === 'admin-todo' ? 'A one-field rename sheet; Save stays disabled until the name changes.' : 'Loads the task first ("Loading task"); Save stays disabled until something changes.',
      play: function (stage) { return Mock.presentDemo(stage, Chores.sheetFor(Mock.current, id, 'edit', { optsOnly: true }), { hold: 1200 }); } });
    if (P.del) t.push({ from: 'Full Delete swipe', to: 'Delete confirmation', kind: 'overlay', note: 'An action sheet on iPhone, a popover on iPad. Cancel is always there; the row stays until the destructive button is chosen.',
      play: function (stage) { return Chores.dialogDemo(stage, { title: 'Delete ' + (P.isGrocery ? 'Oat milk' : (id === 'chores' || id === 'alexs-chores' ? 'Clean the gutters' : Chores.sections(id)[0].items[0].title)) + '?', destructive: P.isGrocery ? 'Delete Item' : 'Delete Task' }); } });
    return t;
  };

  var A11Y = [
    { rule: 'Task rows', note: 'The left side is one toggle: label = title, value "Not done, Due in 3 days" or "Done", trait toggle, hint "Marks the task done." The Edit glyph (where the page edits) is its own button "Edit {title}". Edit and Delete are also VoiceOver custom actions on the toggle and in the context menu; Complete is the toggle itself.' },
    { rule: 'Due state is not colour alone', note: 'Overdue under a day is orange text with a clock glyph and "3 hours overdue"; a day or more is red with the clock; future is a calendar glyph and "Due in 2 days". The module turns dense under orange or red text to keep 4.5:1.' },
    { rule: 'Targets', note: 'Rows are 52 pt, 60 pt with a due line, the whole row is the hit area; the Edit button is 44 x 44; the Add button is a 52 pt capsule.' },
    { rule: 'Dynamic Type', note: 'Titles wrap (fixedSize vertical) and may break inside a long word at AX5; the check circle follows the title inside a 24 pt scaled column; section headers stack; the Add bar goes full width. Nothing is truncated.' },
    { rule: 'Swipe, menu and actions', note: 'Swipe is a convenience: every action is also in the context menu and VoiceOver actions. Delete always asks first.' },
    { rule: 'Reduce Motion', note: 'Rows fade instead of sliding when a task leaves or returns; the arc turns at half speed; push and sheet are the system\'s cross-fades.' },
  ];
  var REVIEWS = {
    date: '2026-10-23',
    hig: [
      { rule: 'Lists and tables: primary action leads, destructive trails outermost', verdict: 'pass', note: 'TodoRowActions: Complete leads; Delete outermost then Edit (owner 2026-10-16).' },
      { rule: 'Context menus: same actions as the swipe, destructive last', verdict: 'pass', note: 'One source (TodoRowActions) feeds swipe, menu and VoiceOver.' },
      { rule: 'Color: do not rely on colour alone', verdict: 'pass', note: 'Overdue has its own glyph and words.' },
      { rule: 'Loading: show content as soon as possible', verdict: 'pass', note: 'Cached items first; a compact arc only where a list has never loaded.' },
      { rule: 'Materials: dense module under red or orange text', verdict: 'departure', note: 'direction-g.md Layers: #141416 at 78% instead of the thin module so 4.5:1 holds over the lit windows.' },
    ],
    swiftui: [
      { rule: 'Use List for swipe actions before iOS 27', verdict: 'departure', note: 'ios.md 2026-10-16: an inset-grouped List whose plain rows draw no card and task rows draw their module share.' },
      { rule: 'Animate with the app token, honour Reduce Motion', verdict: 'pass', note: 'One motionSafeAnimation(standard, reduced: quick) keyed by TodoPageLayout.animationKey.' },
      { rule: 'Dynamic Type: no truncation, scaled metrics', verdict: 'pass', note: '@ScaledMetric check column; title fixedSize vertical.' },
      { rule: '44 pt targets and accessibility traits', verdict: 'pass', note: 'Edit minWidth/minHeight = minTarget; toggle trait with value and hint.' },
    ],
  };
  Chores.A11Y = A11Y; Chores.REVIEWS = REVIEWS;

  /**
   * A complete page config. spec: {id, title, summary, source[], docs[], entities[], notes[], a11y[], states(ex), reviews{hig,swiftui}, devices, status, extraMotion[], extraTransitions[]}
   * Todo pages never split (OnDemandSplitStack has no adopter), so every device is a single column.
   */
  Chores.pageConfig = function (id, spec) {
    var P = PAGES[id];
    return {
      kind: 'page', id: id === 'chores' ? 'chores' : id, title: spec.title, area: 'chores', status: spec.status || 'shipped', summary: spec.summary,
      source: SRC.concat(spec.source || []), spec: spec.docs || ['.agents/pages/chores/spec.md', '.agents/pages/chores/ios.md'],
      patterns: ['module-list', 'floating-actions', 'page-backdrop', 'header-edge-fade', 'motion'].concat(spec.patterns || []),
      hig: ['Lists and tables', 'Context menus', 'Buttons', 'Dynamic Type', 'Color', 'Motion', 'Loading'], entities: spec.entities || [],
      kitComponents: ['PageSectionHeader', 'ModuleList', 'InlineAlert', 'ArcSpinner', 'FloatingActionBar', 'Alert', 'NavigationGlass'],
      devices: spec.devices || ['iphone', 'duo-folded', 'duo-unfolded-landscape', 'duo-unfolded-portrait', 'ipad-portrait', 'ipad-landscape'],
      states: Chores.pageStates(id, { extra: spec.extraStates, defaultTitle: spec.defaultTitle }),
      motion: Chores.pageMotion(id).concat(spec.extraMotion || []), transitions: Chores.pageTransitions(id).concat(spec.extraTransitions || []),
      a11y: (spec.a11y || []).concat(A11Y),
      reviews: spec.reviews && spec.reviews.date ? spec.reviews : { date: REVIEWS.date, hig: REVIEWS.hig.concat((spec.reviews || {}).hig || []), swiftui: REVIEWS.swiftui.concat((spec.reviews || {}).swiftui || []) },  // a skill review (per mockup) replaces the shared author self-check
      notes: (spec.notes || []).concat([
        'Docs versus code: ios.md says the Choreapp form opens at the large detent and one-field sheets at medium; the code fits every todo sheet to its content (TodoPageLayout.isShortPrompt only survives for tests). split-view.md says Chores lists split to item detail; sub-pages push full width on every device and edits are sheets.',
        'iPad and Duo: inset-grouped List margins are the system\'s (16 pt compact, wider on regular); the mockup draws 16 pt everywhere, so module edges are approximate on iPad. The unfolded Duo does not split this page: a one-column page crosses the hinge band (dynamic-grid.md notes the same).',
        'Swipe, context menu and dialogs are drawn statically (system gestures); Play shows the app-owned motion only. Wallpaper and glyphs are kit stand-ins; task names are fixtures.',
        'Promote to kit: TodoItemRow / TodoListSection, ActionSheet (confirmationDialog), swipe-action drawing, and the SF Symbol drawings _chores.js adds (circle, square.and.pencil, chevron.up.chevron.down, cart / hammer / tray circle fills, photo.on.rectangle.angled). Kit CSS gap: `.k-wrap h2` out-weighs `.ui-hdr h2`; _chores.js restates the section-header rule.',
      ]),
      changelog: [{ date: '2026-10-23', note: 'First pass: all states, swipe, context menu, rollback and push motion, sheets and dialog transitions.' }],
    };
  };


  /* ------------------------------------------------------------------ modal config shared by the four sheets */
  var SHEET_A11Y = [
    { rule: 'Reading order', note: 'The sheet is modal: focus lands on the title (and subtitle), then Cancel, the fields top to bottom with each section\'s header and footer, then the confirm check. Escape and the two-finger scrub dismiss while nothing is saving.' },
    { rule: 'Header buttons', note: 'Cancel is the circle x labelled "Cancel"; the confirm is a filled check labelled with its verb ("Create", "Save", "Add") and is disabled, not hidden, until the form is valid or changed (owner 2026-10-16). While saving it becomes an arc spoken as its busy verb ("Saving", "Adding") and the sheet cannot be swiped away.' },
    { rule: 'Fields', note: 'Every field has a label (the placeholder is its accessibility label) and a header and footer saying what goes in it (owner 2026-10-16); errors are a red "Error: ..." line at the top of the form, spoken first. Text and controls are 52 pt rows, far over 44 pt.' },
    { rule: 'Dynamic Type', note: 'Rows grow with the text; at AX5 the sheet reaches the large detent and the form scrolls; nothing is truncated. The keyboard (not drawn) pushes the fitted sheet up as the system does.' },
    { rule: 'Light and dark', note: 'The sheet follows the system appearance: white cells on #F2F2F7 in light, #2C2C2E on #1C1C1E in dark; footers and secondary text 4.5:1 or better on both grounds (Ink.secondary).' },
  ];
  var SHEET_REVIEWS = {
    date: '2026-10-23',
    hig: [
      { rule: 'Sheets: as tall as the content, grabber visible, a clear way out', verdict: 'pass', note: 'Fitted detent (owner 2026-10-16), grabber, circle x Cancel leading; swiping down works until a save is in flight.' },
      { rule: 'Sheets on iPad: prefer page or form sizing', verdict: 'pass', note: 'hassSheet(.form): a 540 pt form sheet on iPad and the unfolded Duo (modal-sheet.md "iPad size").' },
      { rule: 'Toolbars: Cancel and a confirm with a verb, never "Done"', verdict: 'departure', note: 'direction-g.md Sheets: a circle x and a filled check (as Calendar and Reminders), the verb is the accessibility label; the check is always visible and disabled until valid.' },
      { rule: 'Text fields: label and describe', verdict: 'pass', note: 'FormHeader and FormFooter on every text field; error text is above the fields.' },
      { rule: 'Materials: a sheet draws on an opaque ground', verdict: 'departure', note: 'Opaque sheet ground at every detent (direction-g.md Sheets, modal-sheet.md).' },
    ],
    swiftui: [
      { rule: 'Use presentationDetents with a measured height', verdict: 'pass', note: 'hassSheet(.form): the custom height detent from SheetFit, capped at large; every todo sheet is fitted.' },
      { rule: 'Block dismissal while work is in flight', verdict: 'pass', note: 'interactiveDismissDisabled(submitting) and Cancel disabled while busy; the form is disabled too.' },
      { rule: 'Adaptive colour tokens, no hard-coded white or black in a sheet', verdict: 'pass', note: 'Form cells and ink are the sheet tokens; the accent rows use Ink.action (the app accent measured 3.3:1 on the modal ground, iPad audit 2026-10-13).' },
      { rule: 'Dynamic Type and 44 pt targets', verdict: 'pass', note: 'Standard Form rows; the remove buttons are 44 x 44.' },
    ],
  };
  Chores.SHEET_A11Y = SHEET_A11Y;

  /**
   * A complete modal config. spec: {id, title, summary, source[], docs[], entities[], from (presenting page id), build(ctx, o), defaultO, loadingO?, errorO, offlineO, extra: {key: {title, note, o}},
   * notes[], a11y[], reviews{}, transitions[], savingO (the busy state), missing: notes text for states this sheet lacks}
   */
  Chores.sheetConfig = function (spec) {
    var from = spec.from;
    function mk(o) { return function (d) { return spec.build(d, Object.assign({ from: from }, o || {})); }; }
    var st = {
      'default': { title: spec.defaultTitle || 'Default', note: spec.defaultNote, render: mk(spec.defaultO) },
    };
    if (spec.loadingO) st['loading'] = { title: spec.loadingTitle, note: spec.loadingNote, render: mk(spec.loadingO) };
    st['error'] = { title: spec.errorTitle, note: spec.errorNote, render: mk(spec.errorO) };
    st['offline'] = { title: 'Offline: the call fails', note: 'the sheet has no offline UI of its own; the save fails and the form shows the error. The page behind carries the offline chip and the cloud badge', render: mk(Object.assign({}, spec.offlineO || spec.errorO, { connection: 'offline' })) };
    Object.keys(spec.extra || {}).forEach(function (k) { var e = spec.extra[k]; st[k] = { title: e.title, note: e.note, override: e.override, render: mk(e.o) }; });
    st['medium'] = { title: 'Medium detent', note: 'never used: the app fits the sheet; this is what the system would draw for a medium detent', render: mk({ detent: 'medium' }) };
    st['large'] = { title: 'Large detent', note: 'where a fitted sheet ends up when the content is taller than the window (AX sizes, the task form)', render: mk({ detent: 'large' }) };
    st['fitted'] = { title: 'Fitted detent (shipped)', render: mk({ detent: 'fitted' }) };
    st['closed'] = { title: 'Before presenting / after dismissing', note: 'the page the sheet scales back', render: function (d) { return Chores.page(d, from); } };
    st['ax5'] = { title: 'Accessibility 5 text size', override: { ts: 'ax5' }, note: 'reaches the large cap and the form scrolls', render: mk(spec.ax5O || spec.defaultO) };
    return {
      kind: 'modal', id: spec.id, title: spec.title, area: 'chores', status: 'shipped', summary: spec.summary,
      source: ['apple/Sources/HassUI/Features/Chores/' + spec.file, 'apple/Sources/HassUI/Features/Chores/TodoPageView.swift', 'apple/Sources/HassDesign/HassModal.swift', 'apple/Sources/HassDesign/SheetFit.swift', 'apple/Sources/HassDesign/SheetEditToolbar.swift'].concat(spec.source || []),
      spec: spec.docs || ['.agents/pages/chores/spec.md', '.agents/pages/chores/ios.md', '.agents/patterns/modal-sheet.md'],
      patterns: ['modal-sheet', 'header-edge-fade', 'motion'].concat(spec.patterns || []), hig: ['Sheets', 'Toolbars', 'Text fields', 'Dark Mode', 'Dynamic Type'],
      entities: spec.entities || [], kitComponents: ['HassModal', 'SheetCancelItem', 'SheetConfirmItem', 'FormField', 'InlineAlert', 'ArcSpinner', 'FloatingActionBar'],
      devices: ['iphone', 'duo-folded', 'duo-unfolded-landscape', 'ipad-portrait', 'ipad-landscape'], states: st,
      motion: [{ id: 'confirm-busy', what: 'Saving: the confirm check gives way to a turning arc and the form disables', token: 'ArcSpinner 0.82 s a turn, linear; the form dims at once (no animation token)', state: 'saving',
        source: 'HassDesign/SheetEditToolbar.swift SheetConfirmItem(isBusy:); ArcSpinner.swift', reduce: 'the arc keeps turning at half speed (a still arc reads as frozen, motion.md section 8)',
        play: function () { return Mock.sleep(2400); } }].concat(spec.motion || []),
      transitions: [
        { from: spec.fromLabel, to: spec.title, kind: 'sheet', state: 'closed', note: 'Presented as a fitted form sheet: the system slides it up, the page scales back and dims. Content is present on arrival, no entrance animation inside the sheet (motion.md section 4.4).',
          play: function (stage) { return Mock.presentDemo(stage, spec.build(Mock.current, Object.assign({ from: from, optsOnly: true }, spec.defaultO)), { hold: 1200 }); } },
        { from: spec.title, to: spec.fromLabel, kind: 'sheet', state: 'default', note: 'Cancel, a successful save, or a swipe down (interactive, system-owned; disabled while saving). The sheet slides away and the page returns to full size.',
          play: function (stage) { var host = stage.querySelector('.ui-host'); return Mock.anim.sheet(host, 'out').then(function () { return Mock.sleep(500); }); } },
      ].concat(spec.transitions || []),
      a11y: (spec.a11y || []).concat(SHEET_A11Y),
      reviews: spec.reviews && spec.reviews.date ? spec.reviews : { date: SHEET_REVIEWS.date, hig: SHEET_REVIEWS.hig.concat((spec.reviews || {}).hig || []), swiftui: SHEET_REVIEWS.swiftui.concat((spec.reviews || {}).swiftui || []) },
      notes: (spec.notes || []).concat([
        'Docs versus code: ios.md still says the Choreapp form opens at the large detent and the one-field sheets at medium; the code content-fits every todo sheet (hassSheet(.form), height .fitted, owner 2026-10-16), so medium and large here are what the system would draw, not shipped detents.',
        'Presenter is the page the sheet opens from (a trimmed copy). Wallpaper, glyphs and photos are kit stand-ins; field values are fixtures.',
        'Promote to kit: the form row builders (text field, menu picker, date pill, accent row) and the ActionSheet used for confirmation dialogs.',
      ]),
      changelog: [{ date: '2026-10-23', note: 'First pass: every state, three detents, light and dark, saving motion and present and dismiss transitions.' }],
    };
  };

  /** Reviews every Chores mockup shares (author self-check; skill reviewers replace them). */
  Chores.REVIEW_DATE = '2026-10-23';
})();
