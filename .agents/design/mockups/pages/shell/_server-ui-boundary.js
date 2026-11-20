/* Mock.SB: the recovery boundary the server-driven root shows before a published layout is on screen
 * (rules: .agents/design/server-ui-boundary.md).
 * Not part of the kit. Loaded with <script src="..."> after kit.js; nothing here edits the kit. Promote to kit when a second surface needs a bare ground.
 *
 *   SB.screen(ctx, key, { copy?: 'built' | 'proposed', alert?: 'clear' | 'signOut' | 'signOutFailed', leadingOnHinge?: boolean })
 *
 * key: waiting | unpublished | update | unavailable | unavailableBare. Mirrors UKServerUIProductionHost.showStatus and
 * UKServerUIProductionHost.Boundary (UKServerUIRecoveryBoundary.swift): UKStateMessageView centred in the space above two plain
 * 44 pt text buttons, Clear (the failed state only) and Sign Out (every state), in a scroll view pinned to the safe area, on the
 * backdrop's base colour. The DEBUG diagnostic line is not drawn. Sizes use the kit's Dynamic Type variables.
 */
(function () {
  if (window.Mock && Mock.SB) return;
  var h = Mock.h, K = function () { return Mock.components; };
  var SB = Mock.SB = {};

  var style = document.createElement('style');
  style.textContent = [
    '.sb-root{position:absolute;inset:0;overflow:hidden;background:var(--g-wall-base);color:#fff;font-family:var(--font);z-index:10}',
    '.sb-scroll{position:absolute;inset:0;overflow-y:auto;overflow-x:hidden;scrollbar-width:none;display:flex;flex-direction:column;padding-top:var(--safe-top,54px);padding-bottom:var(--safe-bottom,34px)}',
    '.sb-scroll::-webkit-scrollbar{display:none}',
    '.sb-centre{flex:1 0 auto;display:flex;align-items:center;justify-content:center;padding:24px 16px;min-width:0}',
    '.sb-centre>div{max-width:460px;min-width:0}',
    '.sb-plain{display:block;width:100%;min-height:44px;padding:8px 16px;background:none;border:0;cursor:pointer;font:400 var(--fs-body)/1.25 var(--font);color:var(--ink-action,#409CFF);overflow-wrap:anywhere}',
    '.sb-lead{display:flex;flex-direction:column;flex:1 0 auto}',
  ].join('');
  document.head.appendChild(style);

  /* The strings of UKServerUIRecoveryBoundary.swift and UKServerUIProductionHost.swift, byte for byte. */
  SB.BUILT = {
    waiting: { symbol: 'arrow.down.circle', title: 'Getting Your Layout…', message: 'Waiting for your Home Assistant to send the layout.' },
    unpublished: { symbol: 'exclamationmark.triangle', title: 'No Layout Published', message: 'Your Home Assistant has no layout yet. Publish one from the Configurator, then try again.', retry: true },
    update: { symbol: 'arrow.down.app', title: 'Update Required', message: 'The layout published for your home needs a newer version of S+H. Update the app to see it.' },
    unavailable: { symbol: 'exclamationmark.triangle', title: 'Layout Unavailable', message: 'No usable layout is available. Try again, or clear a rejected saved layout and download it again.', retry: true, clear: true },
    unavailableBare: { symbol: 'exclamationmark.triangle', title: 'Layout Unavailable', message: 'No usable layout is available. Try again, or clear a rejected saved layout and download it again.' },
    retryTitle: 'Try Again', clearTitle: 'Clear Rejected Layout', signOutTitle: 'Sign Out',
    alerts: {
      clear: { title: 'Clear Rejected Layout?', message: 'Only this account’s downloaded layout will be cleared. Your Home Assistant sign-in is kept.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Clear Layout', role: 'destructive' }] },
      signOut: { title: 'Sign Out?', message: 'Sign out of Home Assistant on this device?', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Sign Out', role: 'destructive' }] },
      signOutFailed: { title: 'Couldn’t Sign Out', message: 'Your session is still signed in. Try again.', buttons: [{ title: 'OK', role: 'cancel' }] },
    },
  };

  /* Option B of proposals/server-ui-boundary-copy: the same screen worded to .agents/patterns/copy.md. `device` is the {{device}} argument. */
  SB.proposed = function (device) {
    var signOutFailed = 'Signing out needs a connection so this ' + device + ' stops reporting its location. Connect and try again.';
    return {
      waiting: { symbol: 'arrow.down.circle', title: 'Getting Your Layout…', message: 'Waiting for your Home Assistant to send the layout.' },
      unpublished: { symbol: 'house', title: 'No Layout Published', message: 'Your Home Assistant has no layout yet. Publish one in Native Home Studio, or ask whoever manages your Home Assistant. S+H shows it as soon as it’s published.', retry: true },
      update: { symbol: 'arrow.down.app', title: 'Update S+H', message: 'Your home’s layout needs a newer version of S+H. Update S+H to see your home.' },
      unavailable: { symbol: 'exclamationmark.triangle', title: 'Unable to Load the Layout', message: 'S+H couldn’t use the layout from your Home Assistant. Try again, or clear the saved layout to download it again.', retry: true, clear: true },
      unavailableBare: { symbol: 'exclamationmark.triangle', title: 'Unable to Load the Layout', message: 'S+H couldn’t use the layout from your Home Assistant. Sign out and sign in again to download it again.' },
      retryTitle: 'Try Again', clearTitle: 'Clear Saved Layout', signOutTitle: 'Sign Out',
      alerts: {
        clear: { title: 'Clear Saved Layout?', message: 'This clears the layout saved on this ' + device + ' for this account. You stay signed in to Home Assistant.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Clear Layout', role: 'destructive' }] },
        signOut: { title: 'Sign Out of Home Assistant?', message: 'You’ll need your username and password to sign in again.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Sign Out', role: 'destructive' }] },
        signOutFailed: { title: 'Couldn’t Sign Out', message: signOutFailed, buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Try Again' }] },
      },
    };
  };

  /* The two rewordings the owner approved on 2026-11-14 (groups 7 and 9), laid over the built strings: Option A of the proposal. */
  SB.approved = function (device) {
    var c = JSON.parse(JSON.stringify(SB.BUILT)), p = SB.proposed(device);
    c.waiting.title = p.waiting.title;
    c.alerts.signOut = p.alerts.signOut;
    c.alerts.signOutFailed = p.alerts.signOutFailed;
    return c;
  };

  SB.copy = function (ctx, which) {
    var device = ctx.isIPad ? 'iPad' : 'iPhone';
    return which === 'proposed' ? SB.proposed(device) : (which === 'approved' ? SB.approved(device) : SB.BUILT);
  };

  SB.screen = function (ctx, key, o) {
    o = o || {};
    var c = SB.copy(ctx, o.copy), s = c[key], dev = ctx.device;
    var message = K().ContentUnavailableView({ symbol: s.symbol, title: s.title, description: s.message, action: s.retry ? c.retryTitle : null });
    var column = [h('div.sb-centre', h('div', message))];
    if (s.clear) column.push(h('button', { 'class': 'sb-plain',  type: 'button' }, c.clearTitle));
    column.push(h('button', { 'class': 'sb-plain',  type: 'button' }, c.signOutTitle));
    var scroll = h('div.sb-scroll');
    var fold = o.leadingOnHinge ? Mock.foldColumns(ctx, { leading: [h('div.sb-lead', { style: { minHeight: (ctx.h - dev.safeTop - dev.safeBottom) + 'px' } }, column)], trailing: [] }) : null;
    Mock.append(scroll, fold || column);
    var root = h('div.sb-root', { role: 'group', 'aria-label': 'Layout recovery', style: { '--safe-top': dev.safeTop + 'px', '--safe-bottom': dev.safeBottom + 'px' } }, scroll);
    if (o.alert) root.appendChild(h('div.ui-alert-scrim', K().Alert(Object.assign({ ctx: ctx }, c.alerts[o.alert]))));
    return root;
  };
})();
