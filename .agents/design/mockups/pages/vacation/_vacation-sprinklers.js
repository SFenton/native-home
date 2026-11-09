/* Local helper for the vacation mockups (batch vacation-sprinklers): copy, fixtures and builders for Vacation (chooser), Vacation Mode, Solo Trip,
 * their two form sheets and the disable alert, from kit components. Loaded with a relative <script src> by every vacation item.
 * Promote to kit: the AwaySection / AwaySectionGrid / AwayActionButton / SoloTripNoticeBox builders (V.section, V.actionButton, V.notice), the checklist row,
 * the settings link row (V.linkRow) and the `circle` symbol.
 *
 * Source of truth: apple/Sources/HassUI/Features/Vacation/{VacationScreen,VacationModeScreen,SoloTripScreen,VacationComponents}.swift,
 * HassCore/Config/VacationConfig.swift (copy), HassCore/HouseholdAway/{SoloTripCopy,SoloTripStatus,SoloTripController,VacationModeController}.swift.
 */
(function () {
  var h = Mock.h, I = Mock.icon, K = Mock.components;
  var VS = Mock.VS = Mock.VS || {};
  var V = VS.V = {};

  if (!Mock.symbols['circle']) Mock.symbols['circle'] = ['<circle cx="12" cy="12" r="8.8"/>'];

  var css = [
    '.vs-sec { display: flex; flex-direction: column; gap: 8px; min-width: 0; }',
    '.vs-sec .vs-desc, .vs-datewrap .vs-desc { margin: 0; font-size: var(--fs-sub); color: var(--g-secondary-on-wallpaper); }',
    '.in-sheet .vs-sec .vs-desc, .in-sheet .vs-datewrap .vs-desc, .vs-form-sheet .vs-desc { color: var(--ink-sheet-2); }',
    '.vs-sec-title { min-width: 0; } .in-sheet .vs-sec-title .ui-hdr h2 { font: 600 var(--fs-sub)/1.2 var(--font); color: var(--ink-sheet-2); padding: 0 16px; }',
    '.vs-datewrap { display: flex; flex-direction: column; gap: 12px; min-width: 0; }',
    '.vs-btn { display: flex; align-items: center; justify-content: center; width: 100%; min-height: 50px; padding: 8px 20px; border-radius: 25px; border: 0; cursor: pointer; font: 400 var(--fs-body)/1.2 var(--font); text-align: center;',
    '  background: color-mix(in srgb, var(--btn-tint, #409CFF) 22%, transparent); color: var(--btn-ink, #fff); } .vs-btn.destructive { --btn-tint: #FF6961; --btn-ink: #FF6961; } .vs-btn[disabled] { opacity: .4; cursor: default; }',
    '.in-sheet .vs-btn { --btn-ink: var(--ink); } .g-light .vs-btn.destructive { --btn-ink: #C21717; --btn-tint: #C21717; }',
    '.vs-cl .ui-mrow .rg { font-size: var(--fs-t3); width: auto; margin-right: 2px; transition: color var(--t-quick) var(--ease-quick), opacity var(--t-quick) var(--ease-quick); }',
    '.vs-cl .ui-mrow { padding: 12px 16px; gap: 14px; align-items: baseline; min-height: 52px; } .vs-cl .ui-mrow .rg { align-self: baseline; }',
    '.vs-cl .ui-mrow .ti { font-size: var(--fs-body); }',
    '.vs-linklist { border-radius: var(--radius-module); overflow: hidden; background: #1C1C1E; color: #fff; display: flex; flex-direction: column; }',
    '.vs-link { display: flex; align-items: center; gap: 12px; width: 100%; min-height: 60px; padding: 8px 16px; border: 0; background: none; color: inherit; font: inherit; text-align: left; position: relative; cursor: pointer; }',
    '.vs-link + .vs-link::before { content: ""; position: absolute; top: 0; right: 0; left: 62px; height: .5px; background: rgba(84,84,88,.6); }',
    '.vs-link .ico { width: 34px; flex: none; text-align: center; font-size: var(--fs-t3); color: var(--g-secondary-on-module); display: grid; place-items: center; }',
    '.vs-link .tx { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; } .vs-link .ti { font-size: var(--fs-body); } .vs-link .su { font-size: var(--fs-sub); color: var(--g-secondary-on-module); }',
    '.vs-link .chev { color: rgba(235,235,245,.3); font-size: var(--fs-foot); flex: none; }',
    '.ts-ax5 .vs-link { flex-wrap: wrap; } .ts-ax5 .vs-link .ico { width: 100%; justify-items: start; text-align: left; } .ts-ax5 .vs-link .tx { flex-basis: calc(100% - 40px); }',
    '.vs-dim { opacity: .45; pointer-events: none; }', '.vs-muteglyph .glyph { opacity: .5; }',
    '.vs-stack { display: flex; flex-direction: column; gap: 16px; }',
    /* Rollout M (2026-10-28): the cards are action tiles (text, one power disc) and the travelers selection tiles (selected face, check disc). The tinted face carries the tint as the glyph colour, so a disc on a filled tile restates its ink. */
    '.ui-tile.vs-t.tinted .disc:not(.on) { background: rgba(0,0,0,.18); color: #fff; } .ui-tile.vs-t.tinted .disc.on { background: #fff; color: var(--glyph); }',
    '.ui-tile.vs-t.off .disc { background: rgba(255,255,255,.16); color: var(--tile-glyph); } .ui-tile.vs-t .disc.dim, .ui-tile.unavail .disc { opacity: .5; }',
    '.sl-ind { --d: calc(44px * min(var(--sc, 1), 1.5)); width: var(--d); height: var(--d); display: grid; place-items: center; flex: none; position: relative; }',
    '.sl-c { --c: calc(28px * min(var(--sc, 1), 1.5)); width: var(--c); height: var(--c); border-radius: 50%; box-sizing: border-box; display: grid; place-items: center; position: relative; border: 2px solid color-mix(in srgb, var(--tile-glyph, #fff) 85%, transparent); background: transparent; color: var(--fill, #333); transition: background-color var(--t-quick) var(--ease-state), border-color var(--t-quick) var(--ease-state); }',
    '.sl-c .tk { display: grid; place-items: center; opacity: 0; transform: scale(.5); transition: opacity var(--t-quick) cubic-bezier(0, 0, .2, 1), transform var(--t-quick) cubic-bezier(0, 0, .2, 1); } .sl-c .tk svg { width: calc(var(--c) * .56); height: calc(var(--c) * .56); }',
    '.sl-c.on { background: #fff; border-color: #fff; } .sl-c.on .tk { opacity: 1; transform: none; } .k-reduce-motion .sl-c .tk { transform: none; } .ui-tile.sl-locked .sl-ind { opacity: .5; }',
  ].join('\n');
  if (!document.getElementById('vs-vacation-css')) { var st = document.createElement('style'); st.id = 'vs-vacation-css'; st.textContent = css; document.head.appendChild(st); }

  /* ---------------------------------------------------------------- copy (VacationConfig.Copy, SoloTripCopy) */
  var C = V.copy = {
    chooserTitle: 'Vacation', vacationLinkSubtitle: 'Set away dates and prepare the house for vacation.', modeTitle: 'Vacation Mode', modeDescription: 'Enable or disable vacation mode for the house',
    preChecklistError: 'All pre-vacation tasks must be checked off before Vacation Mode can be enabled.', checklistTitle: 'Pre-Vacation Checklist', datesTitle: 'Vacation Dates',
    datesDescription: 'Set the start and end time for your vacation. Vacation mode will automatically be turned off at the set end date and time.',
    dateRangeError: 'Start date and time must be before end date and time. Vacation mode is disabled until the dates are fixed.', confirmTitle: 'Confirm Vacation', confirmAction: 'Confirm Vacation',
    starts: 'Starts', ends: 'Ends', disableTitle: 'Turn Off Vacation Mode?', disableMessage: 'Your checklist and helpers reset.', disableConfirm: 'Turn Off', disableCancel: 'Cancel',
    soloTitle: 'Solo Trip', soloChooserSubtitle: 'One traveler, one home resident', setupSubtitle: 'Needs setup in Home Assistant', soloDescription: 'Enable or disable Solo Trip mode for the house.',
    awayTitle: 'Away From Home', awayDescription: 'Select the user that will be away from home', toggleDisabled: 'Select the user that will be away from home first.',
    editorTitle: 'Schedule Solo Trip', editorDescription: 'Choose when Solo Trip starts and ends for the selected traveler.', editorConfirm: 'Schedule Solo Trip', departs: 'Departs', returns: 'Returns',
    endAfterStart: 'Return must be after departure.', endInFuture: 'Return date/time must be in the future.', commandFailed: 'Home Assistant could not apply the Solo Trip change. Try again.',
    setupRequired: 'Solo Trip scheduling is unavailable. Complete Household Away setup, then try again.', travelerRequired: 'Select the user that will be away from home to continue.',
    vacationConflict: 'Vacation Mode is already engaged. Turn it off before scheduling Solo Trip.',
    activeNotice: 'While Alex is away from home and the Solo Trip setting is enabled in settings, your controls and alarms will control the entire bed.',
    activeNoticeTraveler: 'While you are away from home and the Solo Trip setting is enabled in settings, Sam\'s controls and alarms will control the entire bed.',
    restoreTitle: 'Solo Trip Needs Attention', restoreDescription: 'The away-side schedule changed unexpectedly during Solo Trip. Choose how to resolve it before Solo Trip can finish.',
    keepCurrent: 'Keep Current Schedule', restoreSaved: 'Restore Saved Schedule', degradedTitle: 'Solo Trip Degraded', degradedDescription: 'Some requested effects are unconfirmed. Retries continue automatically, or end away mode.',
    endingTitle: 'Ending Solo Trip', endingDescription: 'Solo Trip is ending and restoring normal settings.',
    checklist: ['Turn off outdoor sprinklers', 'Pour boiling water down the drain', 'Make the bed', 'Unload and Check Dishwasher', 'Take out the trash'],
  };
  /** Fixture moments (the stage clock reads Fri Oct 23, 9:41). */
  V.when = { now: 'Oct 23, 2026 · 9:41 AM', plus1: 'Oct 24, 2026 · 9:41 AM', plus3: 'Oct 26, 2026 · 9:41 AM', vStart: 'Oct 24, 2026 · 6:00 PM', vEnd: 'Nov 2, 2026 · 12:00 PM', vBefore: 'Oct 20, 2026 · 8:00 AM' };
  V.tint = { vacation: '#42A147', pending: '#1F87E6', solo: '#5C8CF0' };

  /* ---------------------------------------------------------------- building blocks */
  /** AwaySection: an optional title (PageSectionHeader on a page, a 15 pt semibold FormHeader in a sheet), an optional description, then the content. */
  V.section = function (o) {
    var kids = [];
    if (o.title) kids.push(h('div.vs-sec-title', K.PageSectionHeader({ title: o.title })));
    if (o.description) kids.push(h('p.vs-desc', o.description));
    return h('div.vs-sec', kids, o.content);
  };
  /** Two sections side by side when the page is wide enough (DynamicGridLayout min 340, 2 columns, spacing 24). */
  /* The app's grids use a literal 340 pt (AwaySectionGrid) and 140 pt (traveler tiles) minimum, not a scaled one: the kit scales min by --sc, so divide it back. */
  V.grid = function (sections) { var c = Mock.current, sc = (c && c.scale) || 1; return K.TileGrid({ min: 340 / sc, max: 2, gap: 24, equal: false, items: sections }); };
  V.err = function (msg) { return K.InlineAlert({ message: msg, severity: 'error' }); };
  /** AwayActionButton: the prominent one is the screen's primary capsule; the rest are bordered in the action tint, or red when destructive. */
  V.actionButton = function (title, o) {
    o = o || {};
    if (o.prominent) return K.PrimaryButton({ title: title, disabled: o.disabled });
    var b = h('button.vs-btn' + (o.destructive ? '.destructive' : ''), { type: 'button' }, title);
    if (o.disabled) b.disabled = true;
    return b;
  };
  V.notice = function (title, message, success) { return K.InfoBox({ title: title, message: message, tone: success ? 'success' : 'neutral' }); };
  V.dateFields = function (o) {
    return h('div.vs-datewrap', h('p.vs-desc', o.description || C.datesDescription), o.invalid ? V.err(C.dateRangeError) : null, K.ScheduleDateFields({ fields: o.fields }));
  };
  V.checklist = function (checked, unavailable) {
    unavailable = unavailable || [];
    var rows = C.checklist.map(function (t, i) {
      var on = !!checked[i];
      var r = K.ModuleRow({ title: t, symbol: on ? 'checkmark.circle.fill' : 'circle', glyph: on ? 'var(--ink-success)' : 'var(--g-secondary-on-module)', glyphOpacity: unavailable[i] ? .5 : 1, press: true });
      r.style.setProperty('--sep-inset', '54px'); r.setAttribute('role', 'checkbox'); r.setAttribute('aria-checked', String(on)); r.setAttribute('aria-label', t + ', ' + (unavailable[i] ? 'Unavailable' : on ? 'Checked' : 'Not checked'));
      if (unavailable[i]) r.disabled = true;
      return r;
    });
    return h('div.vs-cl', K.ModuleList({ rows: rows }));
  };
  /** A Settings-style link row (SettingsLinkRow inside a NavigationLink): grey glyph, 17 pt title, 15 pt secondary subtitle, system chevron. */
  V.linkRow = function (title, subtitle, symbol) {
    var b = h('button.vs-link', { type: 'button', 'aria-label': title + ', ' + subtitle }, h('span.ico', { html: I(symbol) }), h('span.tx', h('span.ti', title), h('span.su', subtitle)), h('span.chev', { html: I('chevron.right', { weight: 2.4 }) }));
    return b;
  };

  /** An ACTION tile (rollout M, AwayTileActions): text and one 44 pt `power` disc, no leading glyph; the disc is toggle-styled (white when on). o: {title, sub, tint, active, unavailable, dim, label} */
  V.actTile = function (o) {
    var t = K.GlassTile({ title: o.title, subtitle: o.sub, symbol: 'power', tint: o.tint, isActive: !!o.active, isUnavailable: !!o.unavailable, kind: 'toggle', behavior: 'perform',
      actions: [{ id: 'power', symbol: 'power', label: o.label || o.title, on: !!o.active, dim: !!o.dim || !!o.unavailable }] });
    t.classList.add('vs-t'); return t;
  };
  /** A single-choice SELECTION tile (the selected face, SelectionActions.single): no leading glyph; chosen = filled family colour with a white check disc, not chosen = dark with an empty ring.
   *  o: {title, sub, family, selected, locked (disc dimmed in place)} */
  V.selTile = function (o) {
    var ring = h('span.sl-ind', h('span.sl-c' + (o.selected ? '.on' : ''), { 'aria-hidden': 'true' }, h('span.tk', { html: I('checkmark', { weight: 3 }) })));
    var t = K.GlassTile({ title: o.title, subtitle: o.sub || undefined, symbol: 'person', family: o.family, isActive: !!o.selected, kind: 'selection', selected: !!o.selected, accessory: ring, accessoryWidth: 52 });
    var g = t.querySelector(':scope > .glyph'); if (g) g.remove();
    t.classList.add('no-glyph'); if (o.locked) t.classList.add('sl-locked');
    t.style.setProperty('--acc-w', 'calc(44px * min(var(--sc, 1), 1.5) + 8px)');
    return t;
  };

  /* ---------------------------------------------------------------- Vacation (chooser) */
  V.chooserBody = function (o) {
    o = o || {};
    return [h('div.vs-linklist', { role: 'list' }, V.linkRow('Vacation', C.vacationLinkSubtitle, 'airplane'), V.linkRow(C.soloTitle, o.setup ? C.setupSubtitle : C.soloChooserSubtitle, 'suitcase'))];
  };
  V.chooserPage = function (ctx, o) { o = o || {}; return Mock.page(ctx, { title: C.chooserTitle, back: 'Settings', section: 'settings', badge: 3, choresBadge: 2, connection: o.connection || 'live', body: V.chooserBody(o) }); };

  /* ---------------------------------------------------------------- Vacation Mode */
  /** o: {on, pending, unavailable, checks:[bool]x5, unavailableChecks, errorShown, invalid, dates:{start,end}, solo:'active'|'restore'|'degraded'|'ending'|'error'} */
  V.modeBody = function (ctx, o) {
    o = o || {};
    if (o.solo) return [V.soloStatusOnly(o.solo)];
    var enabled = !!(o.on || o.pending), sub = o.pending ? 'Pending' : o.unavailable ? 'Unavailable' : o.on ? 'On' : 'Off';
    /* Rollout M (VacationModeTile): an action tile, power disc; off opens the dates sheet, on asks "Turn Off Vacation Mode?"; unavailable dims the disc in place. */
    var tile = V.actTile({ title: C.modeTitle, sub: sub, tint: o.pending ? V.tint.pending : V.tint.vacation, active: enabled, unavailable: !!o.unavailable });
    var mode = V.section({ description: C.modeDescription, content: [o.errorShown ? V.err(C.preChecklistError) : null, tile] });
    var second;
    if (o.on) {
      var d = o.dates || { start: V.when.vStart, end: V.when.vEnd };
      second = V.section({ title: C.datesTitle, content: V.dateFields({ fields: [{ label: C.starts, value: d.start }, { label: C.ends, value: d.end }], invalid: o.invalid }) });
    } else {
      var checks = o.checks || [true, true, false, false, false], done = checks.filter(Boolean).length;
      second = V.section({ title: C.checklistTitle + ' · ' + done + ' of 5', content: V.checklist(checks, o.unavailableChecks) });
    }
    return [V.grid([mode, second])];
  };
  V.modePage = function (ctx, o) { o = o || {}; return Mock.page(ctx, { title: C.modeTitle, back: 'Settings', section: 'settings', badge: 3, choresBadge: 2, connection: o.connection || 'live', body: V.modeBody(ctx, o) }); };

  /* ---------------------------------------------------------------- Solo Trip */
  var STATUS = {
    active: { notice: true },
    restore: { title: C.restoreTitle, description: C.restoreDescription, actions: [[C.keepCurrent], [C.restoreSaved]] },
    degraded: { title: C.degradedTitle, description: C.degradedDescription },
    ending: { title: C.endingTitle, description: C.endingDescription },
    error: { error: C.commandFailed },
  };
  /** The Solo Trip status section: title, description, error, a notice, then bordered action buttons (End Solo Trip Now is red). */
  V.soloStatus = function (key, disabled) {
    var s = STATUS[key], kids = [];
    if (s.error) kids.push(V.err(s.error));
    if (s.notice) kids.push(V.notice('Alex Away', C.activeNotice, true));
    (s.actions || []).forEach(function (a) { kids.push(V.actionButton(a[0], { disabled: disabled })); });
    return V.section({ title: s.title, description: s.description, content: kids });
  };
  V.soloStatusOnly = function (key) { return V.soloStatus(key); };

  /** o: {selected:'alex'|'sam'|null, engaged:null|'scheduled'|'active'|'restore'|'degraded'|'error', setup, vacation, scheduling, ret:{value,error}, viewer:'alex'|'sam'}
   *  Mirrors SoloTripController: toggleSubtitle, travelerTiles (subtitle, icon, muted), notice, status (soloTripPage options: restore and degraded show their section, error shows only the alert). */
  V.soloBody = function (ctx, o) {
    o = o || {};
    var eng = o.engaged || null, sel = o.selected || (eng ? 'alex' : null), vac = !!o.vacation, viewer = o.viewer || 'alex', checked = !!eng;
    var notice = null;
    if (eng === 'active' || eng === 'error') notice = V.notice('Alex Away', viewer === 'alex' ? C.activeNoticeTraveler : C.activeNotice, true);
    else if (eng === 'restore' || eng === 'degraded') notice = V.notice('Alex Away', null, false);
    var sub = checked ? 'On' : vac ? 'Off' : o.setup ? C.setupSubtitle : sel ? 'Off' : C.toggleDisabled;
    var disabled = eng === 'restore' || vac || !!o.setup || (!checked && !sel);
    /* Rollout M (SoloTripToggleTile): the same action tile; off opens the editor, on asks "End Solo Trip?"; the disc dims while no traveler is chosen. */
    var toggle = V.actTile({ title: C.soloTitle, sub: sub, tint: V.tint.solo, active: checked, dim: disabled });
    var setupErr = vac ? C.vacationConflict : o.setup ? C.setupRequired : null;
    var toggleSection = V.section({ content: [notice, h('p.vs-desc', C.soloDescription), toggle, setupErr ? V.err(setupErr) : null] });

    var locked = !!eng || vac || !!o.scheduling;
    function tile(who, name) {
      var mine = sel === who, home = !!eng && !!sel && !mine, subT = null;
      if (eng) subT = mine ? 'Away' : home ? 'Home' : null; else if (locked && mine) subT = 'Selected';
      /* Rollout M (TravelerTileView): the selected face. The app borrows the Vents family blue (Solo Trip's own blue is not a colour family); the disc dims while locked. */
      return V.selTile({ title: name, sub: subT, family: 'vents', selected: mine && !vac, locked: locked });
    }
    var cw = Mock.current ? Mock.current.contentW - 32 : 370, sc0 = (Mock.current && Mock.current.scale) || 1;
    var tiles = K.TileGrid({ min: 140 / sc0, max: 2, gap: 8, equal: false, items: [tile('alex', viewer === 'alex' ? 'You' : 'Alex'), tile('sam', viewer === 'sam' ? 'You' : 'Sam')] });
    var extra = [tiles];
    if (eng) {
      var rv = o.ret || { value: V.when.plus3 };
      extra.push(K.ScheduleDateFields({ fields: [{ label: C.returns, value: rv.value }] }));
      if (rv.error) extra.push(V.err(rv.error));
    }
    if (eng === 'restore') extra.push(V.soloStatus('restore'));
    if (eng === 'degraded') extra.push(V.soloStatus('degraded'));
    if (eng === 'error') extra.push(V.soloStatus('error'));
    var travelerSection = V.section({ title: C.awayTitle, description: C.awayDescription, content: extra });
    return [V.grid([toggleSection, travelerSection])];
  };
  V.soloPage = function (ctx, o) { o = o || {}; return Mock.page(ctx, { title: C.soloTitle, back: o.back || 'Settings', section: 'settings', badge: 3, choresBadge: 2, connection: o.connection || 'live', body: V.soloBody(ctx, o) }); };

  /* ---------------------------------------------------------------- sheets and alert */
  /** Confirm Vacation (form sheet, fitted): description, Starts and Ends, an error when the range is wrong, and the prominent button unless invalid. */
  V.confirmSheet = function (ctx, o) {
    o = o || {};
    var f = [{ label: C.starts, value: o.start || V.when.now }, { label: C.ends, value: o.end || V.when.plus1 }];
    var content = h('div.vs-stack', V.dateFields({ fields: f, invalid: o.invalid }), o.invalid ? null : V.actionButton(C.confirmAction, { prominent: true }));
    return Mock.sheet(ctx, { title: C.confirmTitle, detent: o.detent || 'fitted', size: 'form', leading: 'cancel', trailing: 'none', content: content,
      presenter: o.noPresenter ? null : V.modePage(ctx, { pending: true, checks: [true, true, true, true, true], connection: o.connection }) });
  };
  /** Schedule Solo Trip (form sheet, fitted, not dismissible while scheduling). */
  V.editorSheet = function (ctx, o) {
    o = o || {};
    var f = [{ label: C.departs, value: o.start || V.when.now }, { label: C.returns, value: o.end || V.when.plus3 }];
    var fields = h('div', { class: o.scheduling ? 'vs-dim' : '' }, K.ScheduleDateFields({ fields: f }));
    var content = h('div.vs-stack', h('p.vs-desc', { style: { margin: 0, fontSize: 'var(--fs-sub)', color: 'var(--ink-sheet-2)' } }, C.editorDescription), fields,
      (o.alerts || []).map(function (a) { return V.err(a); }), V.actionButton(C.editorConfirm, { prominent: true, disabled: !!o.disabled || !!o.scheduling }));
    var host = Mock.sheet(ctx, { title: C.editorTitle, detent: o.detent || 'fitted', size: 'form', leading: 'cancel', trailing: 'none', content: content,
      presenter: o.noPresenter ? null : V.soloPage(ctx, { selected: 'alex', scheduling: o.scheduling, connection: o.connection }) });
    if (o.scheduling) { var cancel = host.querySelector('.ui-cancel, .ui-mhead .ui-circle'); if (cancel) { cancel.disabled = true; cancel.style.opacity = .4; } }
    return host;
  };
  /** "End Solo Trip?" over a running trip (AlertCopy.endSoloTrip): the toggle tile's confirmation, also End Solo Trip Now. */
  V.endSoloAlert = function (ctx, o) {
    o = o || {};
    var page = V.soloPage(ctx, { engaged: 'active', connection: o.connection });
    var alert = K.Alert({ title: 'End Solo Trip?', message: 'The house goes back to its normal automations right away.', buttons: [{ title: C.disableCancel, role: 'cancel' }, { title: 'End Solo Trip' }], stacked: !!ctx.axSize });
    return h('div.ui-host', h('div.ui-presenter', page), h('div.ui-alert-scrim.g-dark', alert));
  };
  /** The turn-off alert over Vacation Mode on. The page is always dark, so the alert is too (presented from the shell's preferredColorScheme(.dark)). */
  V.disableAlert = function (ctx, o) {
    o = o || {};
    var page = V.modePage(ctx, { on: true, connection: o.connection });
    var alert = K.Alert({ title: C.disableTitle, message: C.disableMessage, buttons: [{ title: C.disableCancel, role: 'cancel' }, { title: C.disableConfirm }], stacked: !!ctx.axSize });
    return h('div.ui-host', h('div.ui-presenter', page), h('div.ui-alert-scrim.g-dark', alert));
  };
})();

/* Registered locally for the component mockups (not in Mock.COMPONENTS). */
(function () {
  var h = Mock.h, K = Mock.components, V = Mock.VS.V, C = V.copy;
  function part(p) {
    switch (p.kind) {
      case 'section': return V.section({ title: p.title, description: p.description, content: p.content ? h('p', { style: { margin: 0, fontSize: 'var(--fs-body)' } }, p.content) : V.actTile({ title: 'Vacation Mode', sub: 'Off', tint: V.tint.vacation, active: false }) });
      case 'button': return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '10px', width: '100%' } }, V.actionButton(p.title, { prominent: p.prominent, destructive: p.destructive, disabled: p.disabled }));
      case 'notice': return V.notice(p.title, p.message, p.success);
      case 'alert': return V.err(p.message);
      case 'grid': return V.grid([V.section({ description: C.modeDescription, content: V.actTile({ title: 'Vacation Mode', sub: 'Off', tint: V.tint.vacation, active: false }) }),
        V.section({ title: C.checklistTitle + ' · 2 of 5', content: V.checklist([true, true, false, false, false]) })]);
    }
    return h('span');
  }
  Mock.register('AwayParts', part, { source: 'apple/Sources/HassUI/Features/Vacation/VacationComponents.swift', props: '{kind: section|button|notice|alert|grid, ...}',
    variants: [
      { id: 'section-full', label: 'AwaySection: title, description, content', props: { kind: 'section', title: 'Away From Home', description: C.awayDescription, content: 'Content goes here.' } },
      { id: 'section-desc', label: 'AwaySection: description only (no title, the nav title says it)', props: { kind: 'section', description: C.modeDescription } },
      { id: 'button-prominent', label: 'AwayActionButton: prominent (the primary capsule)', props: { kind: 'button', title: 'Schedule Solo Trip', prominent: true } },
      { id: 'button-bordered', label: 'AwayActionButton: bordered (restore actions)', props: { kind: 'button', title: C.keepCurrent } },
      { id: 'button-destructive', label: 'AwayActionButton: destructive (End Solo Trip Now)', props: { kind: 'button', title: 'End Solo Trip Now', destructive: true } },
      { id: 'notice-success', label: 'SoloTripNoticeBox: success (confirmed)', props: { kind: 'notice', title: 'Alex Away', message: C.activeNotice, success: true } },
      { id: 'notice-neutral', label: 'SoloTripNoticeBox: neutral (degraded, restore)', props: { kind: 'notice', title: 'Alex Away' } },
      { id: 'alert-error', label: 'InlineAlert error (setup, command failed)', props: { kind: 'alert', message: C.setupRequired } }],
    states: [{ id: 'button-disabled', label: 'AwayActionButton disabled (40%)', props: { kind: 'button', title: C.restoreSaved, disabled: true } }] });
  Mock.register('VacationDateFields', function (p) {
    return V.dateFields({ fields: p.fields, invalid: p.invalid, description: p.description });
  }, { source: 'apple/Sources/HassUI/Features/Vacation/VacationModeScreen.swift', props: '{fields:[{label,value}], invalid, description}',
    variants: [
      { id: 'valid', label: 'Starts and Ends, valid range', props: { fields: [{ label: C.starts, value: V.when.vStart }, { label: C.ends, value: V.when.vEnd }] } },
      { id: 'invalid', label: 'Invalid range: error under the description', props: { invalid: true, fields: [{ label: C.starts, value: V.when.vEnd }, { label: C.ends, value: V.when.vStart }] } },
      { id: 'return-only', label: 'One field (Solo Trip Returns, no description)', props: { description: C.editorDescription, fields: [{ label: C.returns, value: V.when.plus3 }] } }],
    states: [{ id: 'long-value', label: 'Long label stacks at AX or narrow widths', props: { fields: [{ label: 'Departs (local time)', value: V.when.now }, { label: 'Returns (local time)', value: V.when.plus3 }] } }] });
})();
