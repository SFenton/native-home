/* Shared builders for the settings-account modals: the Home Assistant settings cover (and its sign-out dialog and web page), the feedback form (and its
 * discard dialog, result alerts and attachment strip) and the App Icon sheet. Needs pages/settings/_settings-account.js and _settings-page.js first.
 *
 * Sources: apple/Sources/HassUI/Features/Settings/HomeAssistantSettingsView.swift, HomeAssistantWebPage.swift, Feedback/*, AppIcon/*.
 * Promote to kit: SA.haList (Form with LabeledContent rows), SA.fieldHeader (FeedbackFieldHeader), SA.capButton (text toolbar buttons of a Cancel/Submit sheet),
 * SA.attachTile, SA.appIconChoice.
 */
(function () {
  'use strict';
  var h = Mock.h, I = Mock.icon, K = Mock.components, SA = window.SA;

  var css = [
    '.sa-cap{min-height:44px;padding:0 14px;border-radius:999px;font:400 min(var(--fs-body),23px)/1.2 var(--font);cursor:pointer;flex:none;color:var(--glass-ink)}',
    '.sa-cap.prom{background:#0071E3;color:#fff;border:0;font-weight:600}',
    '.sa-cap[disabled]{opacity:.4;cursor:default}',
    '.sa-strip{display:flex;gap:12px;overflow-x:auto;scrollbar-width:none;padding:4px 0}',
    '.sa-strip::-webkit-scrollbar{display:none}',
    '.sa-tile{position:relative;width:86px;height:86px;margin:2px 12px 0 0;flex:none}',
    '.sa-tile .th{position:absolute;left:0;top:10px;width:76px;height:76px;border-radius:12px;overflow:hidden;box-shadow:inset 0 0 0 .5px var(--sep);border:0;padding:0;cursor:pointer}',
    '.sa-tile .th .ph{position:absolute;inset:0}',
    '.sa-tile .th .pl{position:absolute;left:5px;bottom:5px;width:22px;height:22px;border-radius:50%;background:rgba(0,0,0,.55);color:#fff;display:grid;place-items:center;font-size:11px}',
    '.sa-tile .rm{position:absolute;right:-12px;top:-12px;width:44px;height:44px;border:0;background:none;display:grid;place-items:center;cursor:pointer;padding:0}',
    '.sa-tile .rm i{width:22px;height:22px;border-radius:50%;background:rgba(0,0,0,.7);color:#fff;display:grid;place-items:center;font-style:normal}',
    '.sa-tile .rm i svg{width:12px;height:12px}',
    '.sa-prow{display:flex;flex-direction:column;gap:6px;width:100%}',
    '.sa-prow .bar{height:4px;border-radius:2px;background:var(--fill-tertiary);overflow:hidden}',
    '.sa-prow .bar i{display:block;height:100%;background:var(--ink-action)}',
    '.sa-te{min-height:96px;width:100%;font-size:var(--fs-body);color:var(--ink);white-space:pre-wrap;padding:6px 0}',
    '.sa-tf{width:100%;font-size:var(--fs-body);color:var(--ink)}',
    '.sa-tf .ph{color:var(--ink-sheet-2)}',
    '.sa-dim{opacity:.5}',
    '.sa-icgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(calc(130px * var(--sc)),1fr));column-gap:16px;row-gap:24px;align-items:start}',
    '.sa-ic{display:flex;flex-direction:column;align-items:center;gap:8px;min-height:44px;background:none;border:0;padding:0;color:var(--ink);font-family:var(--font);cursor:pointer}',
    '.sa-ic[disabled]{opacity:.4;cursor:default}',
    '.sa-ic .ring{padding:5px;box-shadow:inset 0 0 0 3px transparent;transition:box-shadow var(--t-state) var(--ease-state)}',
    '.sa-ic.sel .ring{box-shadow:inset 0 0 0 3px var(--ink-action)}',
    '.sa-ic .nm{display:flex;align-items:center;gap:4px;font:600 var(--fs-sub)/1.25 var(--font);text-align:center}',
    '.sa-ic .nm i{color:var(--ink-action);display:none;font-style:normal}',
    '.sa-ic.sel .nm i{display:inline-flex}',
    '.sa-ic .df{font-size:var(--fs-c1);color:var(--ink-sheet-2)}',
    '.sa-web{position:absolute;inset:0;display:flex;flex-direction:column;background:#000;color:#fff;overflow:hidden}',
    '.sa-web .tb{height:56px;flex:none;background:#1a1d23;display:flex;align-items:center;gap:12px;padding:0 16px}',
    '.sa-web .tb i{display:block;height:12px;border-radius:6px;background:rgba(255,255,255,.18)}',
    '.sa-web .pg{flex:1;padding:16px;display:flex;flex-direction:column;gap:12px}',
    '.sa-web .pg i{display:block;height:64px;border-radius:12px;background:#1c2028}',
    '.sa-web .cap{position:absolute;left:0;right:0;bottom:12px;text-align:center;font:600 var(--fs-c1)/1.3 var(--font);color:rgba(255,255,255,.5)}',
    '.sa-web .over{position:absolute;inset:0;display:grid;place-items:center;pointer-events:none}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'sa-modal-style'; st.textContent = css; document.head.appendChild(st);

  /* ================================================================== Home Assistant settings (full-screen cover) */

  SA.webPages = {
    settings: { title: 'Settings', symbol: 'gearshape', subtitle: 'Devices, integrations, automations and system.', path: '/config' },
    profile: { title: 'Profile', symbol: 'person.crop.circle', subtitle: 'Language, theme and security for this account.', path: '/profile' },
  };
  /** The Form: Server, Account, Home Assistant, Sign Out.
   *  props: {status?:'Connected'|'Connecting…'|'Reconnecting…'|'Offline'|'Disconnected'|'Signed out by server', version?:string|null, account?:'loaded'|'loading'|'unavailable', role?:'Owner'|'Administrator'|'User', name?} */
  SA.haList = function (ctx, o) {
    o = o || {};
    var status = o.status || 'Connected', version = o.version === undefined ? (status === 'Connected' ? SA.fx.version : null) : o.version, role = o.role || 'Administrator';
    var info = function (l, v) { return SA.valueRow(l, v); };
    var server = [info('Address', SA.fx.server), info('Connection', status)]; if (version) server.push(info('Version', version));
    var account;
    if (o.account === 'loading') account = [h('div.ui-mrow.sa-val', { role: 'group', 'aria-label': 'Signed in as, loading' }, h('span.ti', 'Signed in as'), h('span.va', K.ArcSpinner({ size: 'compact', label: 'Loading' })))];
    else if (o.account === 'unavailable') account = [info('Signed in as', 'Unavailable offline')];
    else account = [info('Signed in as', o.name || SA.fx.name), info('Role', role)];
    var pages = role === 'User' ? ['profile'] : ['settings', 'profile'];
    var web = pages.map(function (k) { var w = SA.webPages[k]; return SA.link({ title: w.title, subtitle: w.subtitle, symbol: w.symbol, ctx: ctx }); });
    var signOut = SA.section({ rows: [SA.buttonRow('Sign Out', { danger: true, center: true })], solid: true, sys: true });
    signOut.classList.add('sa-signout');
    return SA.wrap(ctx, [
      SA.section({ header: 'Server', rows: server, solid: true, sys: true }),
      SA.section({ header: 'Account', rows: account, solid: true, sys: true }),
      SA.section({ header: 'Home Assistant', rows: web, solid: true, sys: true, footer: 'Opens Home Assistant’s own pages, signed in as you.' }),
      signOut,
    ]);
  };
  var CONFIRM = { title: 'Sign Out of Home Assistant?', message: 'You’ll need your username and password to sign in again.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Sign Out', role: 'destructive' }] };
  var FAILED = { title: 'Couldn’t Sign Out', message: 'Signing out needs a connection so this phone stops reporting its location. Connect and try again.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Try Again' }] };
  SA.signOutDialogCopy = CONFIRM;
  SA.signOutFailedCopy = FAILED;
  /** The cover. props: haList options plus {confirm?:'popover'|'sheet', failed?:boolean, presenter?:Node} */
  SA.haCover = function (ctx, o) {
    o = o || {};
    var list = SA.haList(ctx, o), overlay = [];
        // Sign Out is an alert here and on the Account sheet (alert-conventions, 2026-10-24).
    if (o.confirm) overlay.push(SA.alertScrim(ctx, K.Alert(Object.assign({ stacked: !!ctx.axSize }, CONFIRM)), true));
    if (o.failed) overlay.push(SA.alertScrim(ctx, K.Alert(Object.assign({ stacked: !!ctx.axSize }, FAILED)), true));
    return SA.cover(ctx, { title: 'Home Assistant', content: list, presenter: o.presenter || null, overlay: overlay, scrollEnd: !!(o.confirm || o.scrollEnd) });
  };

  /** The web page pushed inside the cover. props: {page:'settings'|'profile', phase:'loaded'|'loading'|'preparing'|'failed'|'reloading'} */
  SA.webCover = function (ctx, o) {
    var w = SA.webPages[o.page || 'settings'], ph = o.phase || 'loaded', content, reloadDisabled = (ph === 'failed' || ph === 'preparing');
    if (ph === 'failed') content = SA.contentUnavailable({ symbol: 'wifi.exclamationmark', title: 'Can’t open ' + w.title, description: 'Home Assistant couldn’t be reached. Check your connection and try again.', action: 'Try Again' });
    else if (ph === 'preparing') content = h('div.sa-web', h('div.over', { style: { background: '#000' } }, K.ArcProgress({ label: 'Loading ' + w.title + '…' })));
    else {
      var web = h('div.sa-web', h('div.tb', h('i', { style: { width: '24px', height: '24px', borderRadius: '50%' } }), h('i', { style: { width: '120px' } }), h('div', { style: { flex: 1 } }), h('i', { style: { width: '24px', height: '24px', borderRadius: '50%' } })),
        h('div.pg', w.title === 'Profile' ? [h('i', { style: { width: '84px', height: '84px', borderRadius: '50%', margin: '0 auto' } }), h('i'), h('i'), h('i')] : [h('i'), h('i'), h('i'), h('i'), h('i')]),
        h('div.cap', 'Home Assistant frontend: WKWebView stand-in (live pages stay out of the repo)'));
      if (ph === 'loading' || ph === 'reloading') web.appendChild(h('div.over', { style: { background: ph === 'loading' ? 'rgba(0,0,0,.35)' : 'transparent' } }, K.ArcProgress({ label: 'Loading ' + w.title + '…' })));
      content = web;
    }
    var reload = h('button.ui-circle.ui-glass.x', { type: 'button', 'aria-label': 'Reload', title: 'Reload', html: I('arrow.clockwise'), style: reloadDisabled ? { opacity: .4 } : null });
    if (reloadDisabled) reload.disabled = true;
    return SA.cover(ctx, { title: w.title, leading: 'back', trailing: reload, content: content, bleed: true, presenter: null });
  };

  /* ================================================================== text toolbar buttons (Cancel / Submit) */
  /** A system text toolbar button on glass; `prom` is the iOS 26 prominent confirmation style. */
  SA.capButton = function (title, o) {
    o = o || {};
    var b = h('button.sa-cap' + (o.prom ? '.prom' : '.ui-glass'), { type: 'button' }, title); if (o.disabled) b.disabled = true; return b;
  };

  /* ================================================================== feedback form */

  SA.kinds = {
    bug: { title: 'Report an Issue', prefix: '[Bug] ', noun: 'report', sent: 'Report Sent', titleDetail: 'Keep the [Bug] prefix and sum up the problem in a few words.', descDetail: 'What went wrong? Say which page you were on and what you saw.' },
    feature: { title: 'Request a Feature', prefix: '[Feature] ', noun: 'request', sent: 'Request Sent', titleDetail: 'Keep the [Feature] prefix and name the idea in a few words.', descDetail: 'Describe the feature and how it would help.' },
  };
  SA.mediaDetail = 'Optional screenshots or screen recordings: up to 4 photos or videos. Large videos are compressed, and location is removed.';
  /** FeedbackFieldHeader: the box's name (15 Semibold, primary) over a visible 13 pt line saying what to write. */
  SA.fieldHeader = function (title, detail) { return h('div.sa-hd.field', { role: 'heading', 'aria-level': '2', 'aria-label': title + '. ' + detail }, title, h('span', detail)); };
  var SCENES = ['front-door', 'driveway', 'upper-deck', 'lower-deck'];
  /** One thumbnail with its remove button. props: {kind:'photo'|'video', n:1-based position, name} */
  SA.attachTile = function (o) {
    var video = o.kind === 'video', name = o.name || (video ? 'recording.mov' : 'screenshot.png');
    var th = h('button.th', { type: 'button', 'aria-label': (video ? 'Video ' : 'Photo ') + o.n + ', ' + name + ', ' + (o.size || '1.2 MB'), title: 'Opens in Quick Look' },
      h('span.ph', { style: { background: Mock.scene(SCENES[(o.n - 1) % 4]) } }), video ? h('span.pl', { html: I('play.fill') }) : null);
    var rm = h('button.rm', { type: 'button', 'aria-label': 'Remove ' + name }, h('i', { html: I('xmark', { weight: 2.6 }) }));
    return h('div.sa-tile', th, rm);
  };
  /** The attachment strip (horizontal scroll, 12 pt apart). props: items:[{kind, name?}] */
  SA.attachStrip = function (items) { return h('div.sa-strip', { role: 'list', 'aria-label': 'Attachments' }, items.map(function (it, i) { return SA.attachTile(Object.assign({ n: i + 1 }, it)); })); };

  function textRow(text, ph, dim) { return h('div.ui-mrow' + (dim ? '.sa-dim' : ''), { style: { minHeight: '44px' } }, h('div.sa-tf', text ? text : h('span.ph', ph))); }
  function boxRow(text, dim) { return h('div.ui-mrow' + (dim ? '.sa-dim' : ''), h('div.sa-te', text || '')); }
  function noteRow(text, ink) { return h('div.ui-mrow', h('span.tx', h('span.su', { style: { color: ink || 'var(--ink)', fontSize: 'var(--fs-foot)' } }, text))); }

  /** The form content. props: {kind, title?, desc?, steps?, expected?, attachments?:[{kind}], phase?:'editing'|'sending'|'filing', step?, reason?, setup?:boolean, notice?, importing?} */
  SA.feedbackForm = function (ctx, o) {
    var k = SA.kinds[o.kind || 'bug'], sending = o.phase === 'sending' || o.phase === 'filing', att = o.attachments || [], sections = [];
    if (o.setup) sections.push(h('div', { style: { margin: '0 0 0' } }, K.InfoBox({ tone: 'neutral', title: 'Reporting isn’t set up yet', message: 'Reports are filed through Home Assistant. Whoever manages it can add the Fenton Home Feedback integration in Settings → Devices & services.' })));
    sections.push(SA.section({ headerNode: SA.fieldHeader('Title', k.titleDetail), rows: [textRow(k.prefix + (o.title || ''), 'Title', sending)] }));
    sections.push(SA.section({ headerNode: SA.fieldHeader('Description', k.descDetail), rows: [boxRow(o.desc, sending)] }));
    if (o.kind !== 'feature') {
      sections.push(SA.section({ headerNode: SA.fieldHeader('Steps to Reproduce', 'List the steps that make it happen, one per line.'), rows: [boxRow(o.steps, sending)] }));
      sections.push(SA.section({ headerNode: SA.fieldHeader('Expected Behavior', 'What did you expect to happen instead?'), rows: [boxRow(o.expected, sending)] }));
    }
    var mrows = [];
    if (att.length) mrows.push(h('div.ui-mrow' + (sending ? '.sa-dim' : ''), { style: { minHeight: 0, paddingTop: '4px', paddingBottom: '4px' } }, SA.attachStrip(att)));
    mrows.push(SA.labelRow('paperclip', 'Attach Media', { disabled: att.length >= 4 || sending }));
    if (o.importing) mrows.push(h('div.ui-mrow', { style: { minHeight: '44px', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', gap: '8px' }, role: 'status', 'aria-label': 'Adding media' }, K.ArcSpinner({ size: 'compact', label: 'Adding media…' }), h('span', { style: { fontSize: 'var(--fs-sub)', color: 'var(--ink-sheet-2)' } }, 'Adding media…')));
    if (o.notice) mrows.push(noteRow(o.notice, 'var(--ink-danger)'));
    sections.push(SA.section({ headerNode: SA.fieldHeader('Media', SA.mediaDetail), rows: mrows }));
    if (sending) {
      var total = att.length + 1, step = o.phase === 'filing' ? total : (o.step || 1), text = step < total ? 'Uploading media ' + step + ' of ' + (total - 1) + '…' : 'Filing your ' + k.noun + ' on GitHub…';
      var rows = [h('div.ui-mrow', { role: 'progressbar', 'aria-label': text, 'aria-valuenow': Math.round((step - 1) / total * 100) }, h('div.sa-prow', h('span', { style: { fontSize: 'var(--fs-body)' } }, text), h('div.bar', h('i', { style: { width: Math.round((step - 1) / total * 100) + '%' } }))))];
      if (step < total) rows.push(SA.buttonRow('Stop Sending', { danger: true }));
      sections.push(SA.section({ rows: rows }));
    } else if (o.reason) sections.push(SA.section({ rows: [noteRow(o.reason)] }));
    return SA.wrap(ctx, sections);
  };

  /** The feedback sheet. props: feedbackForm options plus {detent?, canSubmit?, alert?:Node, popover?:boolean, presenter?:false} */
  SA.feedbackSheet = function (ctx, o) {
    var k = SA.kinds[o.kind || 'bug'], can = o.canSubmit === true;
    var sheet = Mock.sheet(ctx, { title: k.title, detent: o.detent || 'fitted', size: 'form', leading: SA.capButton('Cancel'), trailing: SA.capButton('Submit', { prom: true, disabled: !can }),
      content: SA.feedbackForm(ctx, o), presenter: o.presenter === false ? null : SA.settingsPage(ctx, {}), alert: o.alert || null });
    if (o.scrollEnd) { var sc = sheet.querySelector('.ui-mscroll'); requestAnimationFrame(function () { requestAnimationFrame(function () { if (sc) sc.scrollTop = sc.scrollHeight; }); }); }
    var ct = sheet.querySelector('.ui-mhead .ct'); if (ct) { ct.style.left = '104px'; ct.style.right = '104px'; }
    if (o.popover || (o.actionSheet && ctx.regular)) {
      var head = sheet.querySelector('.ui-mhead');
      if (head) head.appendChild(SA.popover({ title: 'Discard this ' + k.noun + '?', message: 'Your text and attached media will be lost.', buttons: [{ title: 'Discard Changes', role: 'destructive' }, { title: 'Keep Editing', role: 'cancel' }], style: { left: '12px', top: '60px' } }));
    }
    if (o.actionSheet && !ctx.regular) sheet.appendChild(SA.actionSheet({ title: 'Discard this ' + k.noun + '?', message: 'Your text and attached media will be lost.', buttons: [{ title: 'Discard Changes', role: 'destructive' }, { title: 'Keep Editing', role: 'cancel' }] }));
    return sheet;
  };
  /** Typical filled-in examples (fixture text). */
  SA.fb = {
    bug: { title: 'Garage door tile reads Unknown after the phone wakes', desc: 'On the Home page the Garage Door tile shows Unknown for about a minute after I unlock the phone, then fixes itself.', steps: '1. Lock the phone for ten minutes\n2. Unlock and open S+H\n3. Look at the Garage Door tile', expected: 'The last known state until the live one arrives.' },
    feature: { title: 'Dim the porch light from the lock screen', desc: 'A Live Activity button for the porch light would save opening the app when I get home after dark.' },
  };

  /* ================================================================== App Icon sheet */

  /** One icon: its art with a 5 pt ring gap, a 3 pt ring in the action ink when installed, the name (with a check when installed) and "Default" under the app's own. */
  SA.appIconChoice = function (ic, selected, o) {
    o = o || {}; var side = 88;
    var art = SA.appIcon(ic.id, side); art.style.width = 'calc(88px * var(--sc))'; art.style.height = 'calc(88px * var(--sc))';
    var ring = h('span.ring', { style: { borderRadius: 'calc(88px * var(--sc) * .2237 + 5px)', display: 'block' } }, art);
    var b = h('button.sa-ic' + (selected ? '.sel' : ''), { type: 'button', 'aria-label': ic.name.replace(' + ', ' and ') + (ic.id === 'navySky' ? ', default' : ''), 'aria-pressed': selected ? 'true' : 'false', title: selected ? 'Selected' : 'Not selected', dataset: { icon: ic.id } },
      ring, h('span.nm', h('i', { html: I('checkmark.circle', { fill: true }) }), h('span', ic.name)), ic.id === 'navySky' ? h('span.df', 'Default') : null);
    if (o.disabled) b.disabled = true;
    return b;
  };
  /** The sheet's content: the grid and its footer. props: {selected, changing?} */
  SA.appIconContent = function (ctx, o) {
    var grid = h('div.sa-icgrid', { role: 'list' }, SA.icons.map(function (ic) { return SA.appIconChoice(ic, ic.id === (o.selected || 'navySky'), { disabled: !!o.changing }); }));
    return h('div', { style: { padding: '8px 0 16px', display: 'flex', flexDirection: 'column', gap: '16px' } }, grid,
      h('p', { style: { margin: 0, fontSize: 'var(--fs-foot)', color: 'var(--ink-sheet-2)' } }, 'iOS shows its own notice when the icon changes. Every icon also has dark and tinted Home Screen versions.'));
  };
  SA.appIconSheet = function (ctx, o) {
    o = o || {};
    return Mock.sheet(ctx, { title: 'App Icon', detent: o.detent || 'fitted', size: 'form', trailing: 'close', content: SA.appIconContent(ctx, o), presenter: SA.settingsPage(ctx, { icon: o.selected || 'navySky' }),
      alert: o.failure ? K.Alert({ title: 'Couldn’t Change Icon', message: 'The icon wasn’t changed to ' + SA.iconById(o.failed || 'plumLilac').name + '. The operation couldn’t be completed.', buttons: [{ title: 'OK', role: 'cancel' }] }) : null });
  };
})();
