/* ReconnectingArc and OfflineChip.
 *
 * ReconnectingArc: a 20 pt white arc LEFT of Quick Links, the same gap from it as Quick Links is from Profile. It fades in over 0.35 s once the
 * connection has been down 2 s (at once before the first state arrives) and out over 0.35 s when live; no text; labelled "Reconnecting to Home
 * Assistant"; not a control. On the Duo rail it stays in the page header, trailing, and never joins the rail.
 * Source: apple/Sources/HassUI/App/Shell/ReconnectingArc.swift. Decision: .agents/design/reconnecting-spinner.md.
 * OfflineChip: "Offline. Showing last known values." under the header when there is no network path (nothing is retrying, so no arc).
 * Source: apple/Sources/HassUI/App/Shell/OfflineChip.swift, OfflineOverlay.swift.
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  /** props: {on?:boolean (visible), hidden?:boolean} */
  Mock.register('ReconnectingArc', function (p) {
    p = p || {};
    var s = h('span.ui-slot' + (p.on !== false ? '.on' : ''), { role: 'img', 'aria-label': 'Reconnecting to Home Assistant', dataset: { anim: 'reconnecting-arc' } }, Mock.components.ArcSpinner({ size: 'compact', label: 'Reconnecting to Home Assistant', color: '#fff' }));
    s.firstChild.setAttribute('aria-hidden', 'true'); s.firstChild.removeAttribute('role');
    if (p.hidden) s.hidden = true;
    return s;
  }, { source: 'apple/Sources/HassUI/App/Shell/ReconnectingArc.swift', props: '{on, hidden}',
    states: [{ id: 'visible', label: 'Visible (down 2 s+)', props: { on: true } }, { id: 'hidden', label: 'Hidden (live)', props: { on: false } }] });
  /** props: {text?:string} */
  Mock.register('OfflineChip', function (p) {
    p = p || {};
    var chip = h('div.ui-conn', { role: 'status' }, h('span', { html: I('icloud.slash') }), p.text || 'Offline. Showing last known values.');
    return h('div.ui-conn-row', chip);
  }, { source: 'apple/Sources/HassUI/App/Shell/OfflineChip.swift', props: '{text}',
    states: [{ id: 'offline', label: 'Offline', props: {} }] });
})();
