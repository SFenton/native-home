/* Mock.HC: the missing-house-layout states every layout-driven page shows (decision: .agents/design/house-config-states.md, rules 10 to 16).
 * Not part of the kit. Loaded with <script src="..."> after kit.js; nothing here edits the kit.
 *
 *   HC.skeletonHome(ctx)      the Home skeleton: four chip capsules, the weather module, one section bar, four camera-shaped tiles
 *   HC.skeletonPage(ctx)      the generic skeleton: a bar and four tiles, then a bar and two
 *   HC.message(ctx, key, role) the state message (key: missing | notConfigured | invalid | newer | timeout; role: admin | member)
 *
 * Mirrors apple/Sources/HassUI/Features/HouseConfig (HouseSkeletonPlan, HouseConfigCopy) and UKConfigSkeletonView / UKHouseLayoutGate.
 * The skeleton pulses like the pending value bars (0.35 to 1 over 1.4 s; static 65% under Reduce Motion); the whole skeleton is one
 * VoiceOver element, "Getting your home from Home Assistant". Sizes use the kit's Dynamic Type variables.
 */
(function () {
  if (window.Mock && Mock.HC) return;
  var h = Mock.h, K = function () { return Mock.components; };
  var HC = Mock.HC = {};
  var INTEGRATION = 'S+H Home Integration';
  HC.skeletonLabel = 'Getting your home from Home Assistant';

  var css = [
    '.hc-rail{display:flex;gap:8px;padding:0 16px;overflow:hidden}',
    '.hc-centre{display:flex;align-items:center;justify-content:center;padding:24px 0}',
  ].join('');
  var style = document.createElement('style');
  style.textContent = css;
  document.head.appendChild(style);

  HC.STATES = {
    missing: { symbol: 'puzzlepiece.extension', title: 'Add the ' + INTEGRATION,
      admin: 'S+H gets your rooms, cameras and controls from the ' + INTEGRATION + ' in Home Assistant. Install or update it there; S+H picks it up by itself.',
      member: 'S+H gets your rooms, cameras and controls from the ' + INTEGRATION + ' in Home Assistant. Ask whoever manages your Home Assistant to install or update it.',
      action: 'Open Integrations' },
    notConfigured: { symbol: 'house', title: "Home Isn't Set Up Yet",
      admin: 'The ' + INTEGRATION + ' is installed but has no house layout yet. Add one in Home Assistant; S+H picks it up by itself.',
      member: 'The ' + INTEGRATION + ' is installed but has no house layout yet. Ask whoever manages your Home Assistant to add one.',
      action: 'Open ' + INTEGRATION },
    invalid: { symbol: 'exclamationmark.triangle', title: 'Unable to Read the House Layout',
      admin: "Home Assistant lists what's wrong under Repairs. Fix it there; S+H picks it up by itself.",
      member: 'Ask whoever manages your Home Assistant to check Repairs.',
      action: 'Open Repairs' },
    newer: { symbol: 'arrow.down.circle', title: 'Update S+H',
      admin: 'This Home Assistant has a newer house layout than this version of S+H can read. Update S+H to see your home.' },
    timeout: { symbol: 'exclamationmark.triangle', title: 'Unable to Load the House Layout',
      admin: "Home Assistant hasn't sent the house layout. Try again; if it keeps happening, restart Home Assistant.", action: 'Try Again', everyone: true },
  };

  function skel(style) { return h('div.ui-skel.pulse', { 'aria-hidden': 'true', style: style }); }
  function cols(ctx) { return (ctx.splitAtHinge ? ctx.contentW / 2 : ctx.contentW) >= 700 ? 4 : 2; }
  function tileGrid(ctx, n, ratio) {
    return h('div', { 'aria-hidden': 'true', style: { display: 'grid', gridTemplateColumns: 'repeat(' + cols(ctx) + ', 1fr)', gap: '12px' } },
      Array.apply(null, Array(n)).map(function () { return skel({ aspectRatio: ratio || '1 / 0.78', borderRadius: '20px' }); }));
  }
  function sectionSkel(ctx, n, ratio) {
    return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '12px' } }, skel({ height: '14px', width: '120px', borderRadius: '99px' }), tileGrid(ctx, n, ratio));
  }
  function label() {
    return h('span', { role: 'status', 'aria-label': HC.skeletonLabel, style: { position: 'absolute', width: '1px', height: '1px', overflow: 'hidden' } });
  }

  HC.skeletonHome = function (ctx) {
    var rail = h('div.hc-rail.ui-bleed', { 'aria-hidden': 'true' }, [118, 104, 126, 96].map(function (w) { return skel({ height: 'calc(56px * var(--sc))', width: w + 'px', flex: 'none', borderRadius: '99px' }); }));
    var wx = skel({ height: '168px', borderRadius: '24px' });
    var cams = sectionSkel(ctx, 4);
    var fold = Mock.foldColumns(ctx, { top: [rail], leading: [wx], trailing: [cams] });
    return [label()].concat(fold || [rail, wx, cams]);
  };

  HC.skeletonPage = function (ctx) {
    var a = sectionSkel(ctx, 4), b = sectionSkel(ctx, 2);
    return [label(), a, b];
  };

  HC.message = function (ctx, key, role) {
    var s = HC.STATES[key], admin = role !== 'member';
    var showsAction = s.action && (admin || s.everyone);
    var node = K().ContentUnavailableView({ symbol: s.symbol, title: s.title, description: admin ? s.admin : (s.member || s.admin), action: showsAction ? s.action : null });
    var min = Math.max(320, ctx.h - (ctx.isPhone && !ctx.folded ? 300 : 220));
    var box = h('div.hc-centre', { style: { minHeight: min + 'px' } }, h('div', { style: { maxWidth: '460px' } }, node));
    var fold = Mock.foldColumns(ctx, { leading: [box], trailing: [] });
    return fold || [box];
  };
})();
