/* The Settings tab root and its Appearance section, shared by the Settings page, the App Icon, feedback and Home Assistant settings mockups
 * (each draws the page it opens from behind itself). Needs _settings-account.js first.
 * Source: apple/Sources/HassUI/Features/Settings/SettingsScreen.swift (SettingsScreen), Appearance/AppearanceSettingsSection.swift,
 * Feedback/FeedbackSettingsSection.swift, AppIcon/AppIconSettingsRow.swift, AboutSettingsSection.swift. Copy: HassCore/Config/VacationConfig.swift, Household/HouseholdSettingsPage.swift.
 * The page is a published composition: each group is one `module-list` section drawn by `UKModuleListView` (UIKitPort/Design/UKModule.swift); rows are
 * `UKSettingsStackCell` links and the preferences provider's controls (UIKitPort/ServerUI/UKServerUIPreferencesProvider.swift).
 */
(function () {
  'use strict';
  var h = Mock.h, SA = window.SA;

  /* The Settings root's groups (decision 2026-11-18-settings-grouped-rows; spec build/design/pl-setlist/spec.md): one 26 pt module per
   * published module-list section, rows with no card of their own, 15 pt leading and 17.5 pt trailing content inset, 0.5 pt hairlines that
   * take their leading inset from the row above (15 pt, or 61 pt under a glyph row and 15 pt at accessibility sizes) and stop 16 pt short
   * of the trailing edge. Rows pad 15 pt (links, text buttons, Version) or 10.5 pt (slider, switch) around a 44 pt minimum. Headers are
   * the page section header (title3 bold, primary ink) flush with the card; 24 pt between sections, 8 pt header to card and card to footer.
   * The list fills the page's 16 pt margins in every window (no 20 pt regular margin, no readable-width cap). */
  var css = [
    '.sa-g .ui-mlist .ui-mrow{padding-left:15px;padding-right:17.5px}',
    '.sa-g .ui-mlist .ui-mrow + .ui-mrow::before{left:15px;right:16px}',
    '.sa-g .ui-mlist .sa-link + .ui-mrow::before{left:61px}',
    '[class*="ts-ax"] .sa-g .ui-mlist .sa-link + .ui-mrow::before{left:15px}',
    '.sa-g .sa-link,.sa-g .sa-btnrow,.sa-g .sa-ver{padding-top:15px;padding-bottom:15px;min-height:74px}',
    '.sa-g .sa-col{padding-top:10.5px!important;padding-bottom:10.5px!important}',
    '.sa-g .ui-mrow:has(.ui-toggle){padding-top:10.5px;padding-bottom:10.5px;min-height:65px}',
    '.sa-g .sa-hd:not(.sys){margin:0 0 8px;font:700 var(--fs-t3)/1.2 var(--font-d);color:#fff}',
    '.sa-g .sa-ft:not(.sys){margin:8px 0 0}',
    '.sa-wrap.sa-root{gap:24px}',
    '.sa-wrap.sa-root.reg{max-width:none}',
    '.ui-body > .sa-wrap.sa-root.reg{width:auto}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'sa-settings-root-style'; st.textContent = css; document.head.appendChild(st);
  function G(o) { var s = SA.section(o); s.classList.add('sa-g'); return s; }

  SA.copy = {
    vacation: ['Vacation', 'Set away dates and prepare the house for vacation.'],
    todo: ['To-Do', 'An admin panel for to-do tasks.'],
    household: [
      ['Admin Controls', 'Presence-Based Toggles, Automation Overrides, and More', 'person.badge.shield.checkmark'],
      ['Special Device Modes', 'Allows enabling special device modes, such as High AQI Mode.', 'slider.vertical.3'],
      ['Guest Controls', 'Toggle automations when guests stay over.', 'person.2'],
      ['Car', 'Controls for the car.', 'car.side'],
    ],
    ha: ['Home Assistant Settings', 'Access more in-depth Home Assistant details and settings.'],
    haFooter: 'Server, account and Home Assistant’s own settings pages.',
    performance: ['Performance', 'Scrolling, loading and image cache measurements on this device.'],
    feedback: [
      ['Report an Issue', 'Something broken? Send a report with screenshots or a recording.', 'ladybug'],
      ['Request a Feature', 'Suggest something new or a change to the app.', 'lightbulb'],
    ],
    tapToCopy: 'Tap to copy.', copied: 'Copied.',
    blurFooter: 'How soft the house photo behind every page is. The default matches the web dashboard; less blur can make text harder to read.',
    blurFooterReduced: 'Reduce Transparency is on, so pages use a plain background and the blur has nothing to soften.',
  };

  /** The Appearance section: Background Blur and Reset, Show count on app icon, and the App Icon row where the system can switch icons.
   *  props: {blur?:0..100 (default 50), badgeOn?:boolean, icon?:icon id, noIcon?:boolean, reduceTransparency?:boolean} */
  SA.appearanceSection = function (o) {
    o = o || {};
    var blur = o.blur == null ? 50 : o.blur, icon = o.icon || 'navySky';
    var rows = [SA.sliderRow('Background Blur', blur), SA.buttonRow('Reset to Default', { disabled: blur === 50 }), SA.toggleRow('Show count on app icon', o.badgeOn !== false)];
    if (!o.noIcon) rows.push(SA.link({ title: 'App Icon', subtitle: SA.iconById(icon).name, symbol: 'app.fill', appIcon: icon, chevron: false }));
    return G({ header: 'Appearance', rows: rows, noglyph: true, footer: o.reduceTransparency ? SA.copy.blurFooterReduced : SA.copy.blurFooter });
  };

  /** The Notifications section (NotificationsSettingsSection), drawn only when props carry `notif`. Returns an array of sections.
   *  Today: 'not-determined' (Turn On Notifications), 'granted' (Notifications are on), 'denied' (Open Settings to allow notifications).
   *  Proposed, notifications allowed: 'granted-ts-on' / 'granted-ts-off' (two entries, each glyph + title + status in the row, chevron, opens
   *  iOS Settings; no section footer) and 'split-ts-on' / 'split-ts-off' (the comparison: one section per entry, description as its footer). props: {notif, ctx} */
  SA.notificationsSection = function (o) {
    var ctx = o.ctx || Mock.current || {}, n = o.notif, msg = 'S+H can tell you when a door is left open or someone rings.';
    if (n === 'not-determined') return [G({ header: 'Notifications', rows: [SA.buttonRow('Turn On Notifications')], noglyph: true, footer: msg })];
    if (n === 'denied') return [G({ header: 'Notifications', rows: [SA.buttonRow('Open Settings to allow notifications')], noglyph: true, footer: msg })];
    if (n === 'granted') return [G({ header: 'Notifications', rows: [h('div.ui-mrow', { role: 'group', 'aria-label': 'Notifications are on' }, h('span.rg', { html: Mock.icon('bell.fill') }), h('span.tx', h('span.ti', 'Notifications are on')))], footer: msg })];
    var on = !/off$/.test(n), split = /^split/.test(n);
    var nsub = 'On. Door and camera alerts reach you.', tsub = on ? 'On. Urgent alerts can break through a Focus.' : 'Off. Urgent alerts wait until your Focus ends.';
    var notifRow = SA.link({ title: 'Notifications', subtitle: split ? 'On' : nsub, symbol: 'bell.fill', chevron: true, ctx: ctx });
    var tsRow = SA.link({ title: 'Time Sensitive Notifications', subtitle: split ? (on ? 'On' : 'Off') : tsub, symbol: on ? 'bell.fill' : 'bell.slash', chevron: true, ctx: ctx });
    if (split) return [G({ header: 'Notifications', rows: [notifRow], footer: msg }), G({ rows: [tsRow], footer: on ? 'Urgent alerts, like a door left open, can break through a Focus.' : 'Time Sensitive is off, so urgent alerts wait until your Focus ends.' })];
    return [G({ header: 'Notifications', rows: [notifRow, tsRow] })];
  };

  /** The Settings list on the wallpaper (rows are modules). props: {viewer?:'alex'|'sam'|'guest', blur?, badgeOn?, icon?, noIcon?, reduceTransparency?, long?:boolean} */
  SA.settingsList = function (ctx, o) {
    o = Object.assign({}, o); if (o.reduceTransparency == null) o.reduceTransparency = !!ctx.reduceTransparency;
    var C = SA.copy, long = o.long, link = function (t, s, sym, ch) { return SA.link({ title: t, subtitle: s, symbol: sym, chevron: ch, ctx: ctx }); };
    var top = [link(C.vacation[0], long ? C.vacation[1] + ' Thermostat, locks, the garage door and the lights go to their away settings, and everything comes back when you do.' : C.vacation[1], 'airplane')];
    if (o.viewer !== 'sam') top.push(link(C.todo[0], C.todo[1], 'checklist'));
    var hh = C.household.map(function (r) { return link(r[0], r[1], r[2]); });
    var sections = [
      G({ rows: top }),
      SA.appearanceSection(o),
      G({ header: 'Household', rows: hh }),
      G({ rows: [link(C.ha[0], C.ha[1], 'gearshape', false)], footer: C.haFooter }),
      G({ rows: [link(C.performance[0], C.performance[1], 'gauge.with.dots.needle.67percent')] }),
      G({ rows: C.feedback.map(function (r) { return link(r[0], r[1], r[2], false); }) }),
      G({ header: 'About', rows: [SA.versionRow(SA.fx.build, { ctx: ctx })], footer: o.copied ? C.copied : C.tapToCopy }),
    ];
    if (o.notif) Array.prototype.splice.apply(sections, [2, 0].concat(SA.notificationsSection({ notif: o.notif, ctx: ctx })));
    var wrap = SA.wrap(ctx, sections); wrap.classList.add('sa-root'); wrap.dataset.testid = 'settings.list'; return wrap;
  };

  /** Demo helpers for a Transitions Play: a push (the new page slides in, the old one out, then Back; single-page-motion.md) and a full-screen cover or sheet slide. */
  SA.pushDemo = function (stage, build) {
    var ctx = Mock.current, a = stage.querySelector('.ui-page'); if (!a) return Promise.resolve();
    var b = build(ctx); a.parentNode.insertBefore(b, a.nextSibling);
    return Mock.anim.slide(a, b).then(function () { return Mock.sleep(700); }).then(function () { return Mock.anim.slide(b, a, { back: true }); }).then(function () { Mock.anim.reset(stage); b.remove(); });
  };
  SA.coverDemo = function (stage, build, hold) {
    var ctx = Mock.current, host = build(ctx); stage.appendChild(host);
    return Mock.anim.sheet(host, 'in').then(function () { return Mock.sleep(hold || 1100); }).then(function () { return Mock.anim.sheet(host, 'out'); }).then(function () { host.remove(); });
  };

  /** The Settings tab root page. props as settingsList plus {connection?, badge?, scrollTop?} */
  SA.settingsPage = function (ctx, o) {
    o = o || {};
    return Mock.page(ctx, { title: 'Settings', section: 'settings', badge: o.badge == null ? 3 : o.badge, choresBadge: 2, connection: o.connection || 'live', scrollTop: o.scrollTop, body: [SA.settingsList(ctx, o)] });
  };
})();
