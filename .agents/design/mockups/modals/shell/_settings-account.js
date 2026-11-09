/* Builders for the Your Summary sheet (the header Profile button) and its sign-out alerts. Needs pages/settings/_settings-account.js, _settings-page.js
 * and modals/settings/_settings-account.js first.
 * Sources: apple/Sources/HassUI/Features/Settings/Profile/*, HassCore/Profile/{SummaryTab,ProfileSummary}.swift, HassUI/Features/Location/LocationAccountSection.swift,
 * HassUI/Features/Chores/TodoListSection.swift (TodoItemRow, DueLabel), HassUI/Features/Inventory/InventoryRow.swift.
 * Promote to kit: TodoItemRow + DueLabel (chores batch), InventoryRow (inventory batch), AccountHeader, PersonRow, SummaryEmptyState (= SA.contentUnavailable).
 */
(function () {
  'use strict';
  var h = Mock.h, I = Mock.icon, K = Mock.components, SA = window.SA;

  var css = [
    '.sa-edit{width:44px;height:44px;display:grid;place-items:center;border:0;background:none;color:var(--ink-sheet-2);font-size:var(--fs-t3);flex:none;padding:0;cursor:pointer}',
    '.sa-edit.act{color:var(--ink-action);font-size:var(--fs-body)}',
    '.sa-due{display:flex;align-items:baseline;gap:4px;font-size:var(--fs-sub);font-variant-numeric:tabular-nums}',
    '.sa-due .ui-sym{width:.85em;height:.85em}',
    '.sa-acct{display:flex;flex-direction:column;align-items:center;gap:8px;padding:8px 0;text-align:center}',
    '.sa-acct .nm{font:700 var(--fs-t2)/1.2 var(--font-d);color:var(--ink)}',
    '.sa-acct .sv{font-size:var(--fs-sub);color:var(--ink-sheet-2)}',
    '.sa-qty{font-size:var(--fs-body);color:var(--ink-sheet-2);font-variant-numeric:tabular-nums;padding-right:4px}',
    '.sa-person .st{font-size:var(--fs-body)}',
    '.sa-person .st.home{color:var(--ink-success)}',
    '.sa-person .st.away{color:var(--ink-sheet-2)}',
    '.sa-sumhd{margin:0 0 8px;display:block}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'sa-shell-style'; st.textContent = css; document.head.appendChild(st);

  var PERSON_FILL = { alex: 'var(--fam-chore-resident1-fill)', sam: 'var(--fam-chore-resident2-fill)', guest: '#666666' };

  /** TodoItemRow in the Summary: open circle in the secondary ink, title, a DueLabel (calendar for the future, clock for overdue; orange within a day, red beyond), edit button. */
  SA.todoRow = function (o) {
    var tone = o.tone || 'future', ink = tone === 'future' ? 'var(--ink-sheet-2)' : (tone === 'hours' ? 'var(--ink-warning)' : 'var(--ink-error)');
    var due = o.due ? h('span.sa-due', { style: { color: ink } }, h('span', { html: I(tone === 'future' ? 'calendar' : 'clock') }), o.due) : null;
    return h('div.ui-mrow' + (due ? '.sub' : ''), { role: 'group', 'aria-label': o.title + (o.due ? ', Not done, ' + o.due : ', Not done') },
      h('span.rg', { style: { color: 'var(--ink-sheet-2)' }, html: I('circle') }), h('span.tx', h('span.ti', o.title), due),
      h('button.sa-edit', { type: 'button', 'aria-label': 'Edit ' + o.title, html: I('square.and.pencil') }));
  };
  /** InventoryRow for an expired card: name over a red "Expired <date>" with the warning glyph, a stock count above one, the cart in the action tint and a chevron. */
  SA.expiredRow = function (o) {
    return h('div.ui-mrow.sub', { role: 'group', 'aria-label': o.name + (o.qty ? ', Quantity ' + o.qty : '') + ', ' + o.label },
      h('span.tx', h('span.ti', o.name), h('span.su.sa-due', { style: { color: 'var(--ink-error)', fontSize: 'var(--fs-sub)' } }, h('span', { html: I('exclamationmark.triangle', { fill: true }) }), o.label)),
      o.qty ? h('span.sa-qty', { 'aria-hidden': 'true' }, o.qty) : null,
      h('button.sa-edit.act', { type: 'button', 'aria-label': 'Add ' + o.name + ' to shopping list', html: I('cart.badge.plus') }),
      h('button.sa-edit', { type: 'button', 'aria-label': 'Edit ' + o.name, html: I('chevron.right', { weight: 2.4 }), style: { fontSize: 'var(--fs-sub)' } }));
  };

  /* ---- tabs ---- */
  SA.tabs = {
    profile: { id: 'profile', title: 'Profile', symbol: 'person.crop.circle' },
    overdue: { id: 'overdue', title: 'Overdue Chores', symbol: 'exclamationmark.circle' },
    upcoming: { id: 'upcoming', title: 'Upcoming Chores', symbol: 'checklist' },
    'expired-food': { id: 'expired-food', title: 'Expired Food', symbol: 'fork.knife' },
  };
  SA.empty = {
    overdue: ['No Chores Due', 'You are all caught up on chores that slipped past their due date.', 'checkmark.circle'],
    upcoming: ['No Chores Upcoming', 'There is nothing else on your schedule for the rest of today.', 'checklist'],
    food: ['No Expired Food', 'Everything in the kitchen is still within date.', 'checkmark.circle'],
    vacation: 'Enjoy vacation!',
  };

  function pageHeader(t) { return h('div', { style: { margin: '0 0 8px 0' } }, K.PageSectionHeader({ title: t })); }
  function empty(t, d, sym) { return SA.contentUnavailable({ symbol: sym, title: t, description: d }); }

  /** The Profile tab: account header, People at Home, Location (phones only), Sign Out. props: {name?, locationStatus?:'Always'|'Off'|'Not Set'|..., warning?} */
  function profileTab(ctx, o) {
    var name = o.viewer === 'guest' ? 'Guest' : (o.viewer === 'sam' ? SA.fx.sam : SA.fx.name);
    var secs = [];
    secs.push(h('section', h('div.sa-acct', { role: 'group', 'aria-label': name + ', ' + SA.fx.server }, SA.monogram(name, Math.round(84 * (ctx.axSize ? 1.6 : 1)), '#0071E3', o.photos ? (o.viewer === 'sam' ? 'b' : (o.viewer === 'guest' ? null : 'a')) : null), h('div.nm', name), h('div.sv', SA.fx.server))));
    var people = SA.fx.people.slice().sort(function (a, b) { return (a.state === 'home' ? 0 : 1) - (b.state === 'home' ? 0 : 1) || (a.name < b.name ? -1 : 1); });
    var rows = people.map(function (p) {
      var home = p.state === 'home';
      return h('div.ui-mrow.sa-person', { role: 'group', 'aria-label': p.name + ', ' + (home ? 'Home' : 'Away') }, SA.monogram(p.name, Math.round(36 * (ctx.scale || 1)), PERSON_FILL[p.resident || 'guest'], o.photos ? p.photo : null), h('span.tx', h('span.ti', p.name)), h('span.st.' + (home ? 'home' : 'away'), home ? 'Home' : 'Away'));
    });
    secs.push(SA.section({ header: 'People at Home', rows: rows, noglyph: true, footer: people.filter(function (p) { return p.state === 'home'; }).length + ' of ' + people.length + ' Home' }));
    if (!ctx.isIPad) {
      var status = o.locationStatus || 'Always';
      var share = h('button.ui-mrow.press.sa-val', { type: 'button', 'aria-label': 'Share Location, ' + status }, h('span.rg', { style: { color: 'var(--ink)' }, html: I('location.fill') }), h('span.tx', h('span.ti', 'Share Location')), h('span.va', status), h('span.chev', { html: I('chevron.right', { weight: 2.4 }) }));
      var foot = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px', margin: '6px 0 0' } }, o.warning ? K.InlineAlert({ message: o.warning }) : null,
        h('div.sa-ft.sys', { style: { margin: '0 16px' } }, 'Whenever location access is on, this iPhone reports to Home Assistant as its own device, and Home Assistant follows it for the person you sign in as.'));
      secs.push(SA.section({ header: 'Location', sys: true, rows: [share], footerNode: foot }));
    }
    secs.push(SA.section({ rows: [SA.buttonRow('Sign Out', { danger: true, center: true })] }));
    return SA.wrap(ctx, secs);
  }
  function overdueTab(ctx, o) {
    if (o.empty || o.vacation) return SA.wrap(ctx, [empty('No Chores Due', o.vacation ? SA.empty.vacation : SA.empty.overdue[1], o.vacation ? 'airplane' : 'checkmark.circle')]);
    return SA.wrap(ctx, [h('section', pageHeader('Overdue Chores'), K.ModuleList({ rows: [
      SA.todoRow({ title: 'Take out the recycling', due: '3 hours overdue', tone: 'hours' }), SA.todoRow({ title: 'Clean the gutters', due: '9 days overdue', tone: 'long' }), SA.todoRow({ title: 'Replace battery · 18%', due: '2 days overdue', tone: 'long' })] }))]);
  }
  function upcomingTab(ctx, o) {
    if (o.empty || o.vacation) return SA.wrap(ctx, [empty('No Chores Upcoming', o.vacation ? SA.empty.vacation : SA.empty.upcoming[1], o.vacation ? 'airplane' : 'checklist')]);
    return SA.wrap(ctx, [
      h('section', pageHeader('Upcoming Chores'), K.ModuleList({ rows: [SA.todoRow({ title: 'Run the dishwasher', due: 'Due in 5 hours', tone: 'future' }), SA.todoRow({ title: 'Water the plants', due: 'Due in 2 days', tone: 'future' })] })),
      h('section', pageHeader('No Due Date'), K.ModuleList({ rows: [SA.todoRow({ title: 'Organize the garage' })] })),
    ]);
  }
  function expiredTab(ctx, o) {
    var title = 'Expired Food';
    if (o.vacation) return SA.wrap(ctx, [empty(o.zero ? 'No Expired Food' : 'Expired Food Hidden', SA.empty.vacation, 'airplane')]);
    if (o.empty) return SA.wrap(ctx, [empty('No Expired Food', SA.empty.food[1], 'checkmark.circle')]);
    var body;
    if (o.phase === 'loading') body = h('div', { style: { display: 'flex', justifyContent: 'center', minHeight: '44px', alignItems: 'center' } }, K.ArcSpinner({ size: 'compact', label: 'Loading Expired Food' }));
    else if (o.phase === 'error') body = K.InlineAlert({ message: 'Couldn’t reach Pantryhub. Check your connection and try again.', severity: 'error' });
    else body = K.ModuleList({ density: 'dense', rows: [SA.expiredRow({ name: 'Greek Yogurt', label: 'Expired Oct 22, 2026' }), SA.expiredRow({ name: 'Cereal', label: 'Expired Sep 8, 2026', qty: '2' }), SA.expiredRow({ name: 'Leftover Chili', label: 'Expired Sep 30, 2026' })] });
    return SA.wrap(ctx, [h('section', pageHeader(title), body)]);
  }

  /** The Summary sheet. props: {tab, viewer:'alex'|'sam'|'guest', vacation?, empty?, phase?, connection?, alert?:Node, locationStatus?, warning?} */
  SA.summarySheet = function (ctx, o) {
    o = o || {}; var viewer = o.viewer || 'alex', guest = viewer === 'guest';
    var order = guest ? ['profile', 'expired-food'] : ['profile', 'overdue', 'upcoming', 'expired-food'];
    var tab = o.tab || (guest ? 'expired-food' : 'overdue');
    var overdue = o.empty ? 0 : 3, expired = (o.empty || o.vacation) ? 0 : 3;
    var tabs = order.map(function (k) { var t = Object.assign({}, SA.tabs[k]); if (k === 'overdue' && overdue) t.badge = overdue; if (k === 'expired-food' && expired) t.badge = expired; return t; });
    var content = ({ profile: profileTab, overdue: overdueTab, upcoming: upcomingTab, 'expired-food': expiredTab })[tab](ctx, Object.assign({}, o, { viewer: viewer }));
    var badge = overdue + expired;
    var presenter = Mock.page(ctx, { title: 'Home', section: 'home', badge: badge || undefined, choresBadge: overdue || undefined, connection: o.connection || 'live', body: [K.ChipRail({ chips: Mock.chips.home() }), K.WeatherCard({ condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 })] });
    var host = Mock.sheet(ctx, { title: guest ? 'Summary' : 'Your Summary', detent: 'large', size: 'form', trailing: 'close', content: content, tabs: K.ModalTabBar({ tabs: tabs, selected: tab, ctx: ctx }), presenter: presenter, alert: o.alert || null });
    var panel = host.querySelector('.ui-sheet');
    if (panel && ctx.regular) panel.style.height = (ctx.device.h - 2 * ctx.device.sheetTop) + 'px';   // .full: a form sheet at full height on iPad
    return host;
  };

  /* ---- alerts over the Summary ---- */
  SA.signOutAlert = function () { return K.Alert({ title: 'Sign Out of Home Assistant?', message: 'You’ll need your username and password to sign in again.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Sign Out', role: 'destructive' }] }); };
  SA.signOutFailedAlert = function () { return K.Alert({ title: 'Couldn’t Sign Out', message: 'Check your connection and try again.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Try Again' }] }); };
})();
