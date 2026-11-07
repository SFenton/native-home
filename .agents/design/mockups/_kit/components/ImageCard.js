/* ImageCard and CameraTile. apple/Sources/HassDesign/ImageCard.swift; apple/Sources/HassUI/Features/Home/CameraGrid.swift (CameraTile).
 * Cameras (direction-g.md Controls): 2 x 2 on Home and Security, cards 1 : 0.78 (the web's tile, fill-cropped), 22 pt radius, NOTHING over the image except a small name capsule
 * (black 75%) with a red live dot while the stream shows frames (HIG HomeKit must). The viewer is full-bleed. While connecting, or after a live stream stalls, the last snapshot stays fully
 * visible. The home tile never draws a state pill (CameraGrid.swift); the viewer's badge (CameraLiveView.badge, top-leading) says "Last live 6:51 PM" once a stream that was live reconnects,
 * else "Connecting", "Live", "Live · Delayed" or "Snapshot": pass `viewer: true`. ImageCard (recipes): the photo with a scrim and the title/subtitle over it; at accessibility sizes a
 * row with a 64 pt thumbnail so the text (not the picture) fills the card. The photos here are drawn stand-ins (no real camera names or frames: AUTHORING.md rule 3).
 * CameraTile props: {title, state?:'live'|'snapshot'|'connecting', since?:string (last live time, viewer badge), scene?:'front-door'|'driveway'|'upper-deck'|'lower-deck', viewer?:boolean (draw the viewer badge), delayed?:boolean}
 * ImageCard props: {title, subtitle?, scene?:'recipe'|..., ctx?}
 */
(function () {
  var h = Mock.h;
  /** Mock.scene(name): CSS background for a stand-in photo. */
  var SC = {
    'front-door': 'linear-gradient(180deg,#8fa1b4 0 38%,#6c7d68 38% 64%,#4a4036 64%),radial-gradient(60% 60% at 70% 62%,rgba(255,190,110,.55),transparent 70%)',
    'driveway': 'linear-gradient(180deg,#9aa9ba 0 30%,#59644f 30% 50%,#3b3f45 50%)',
    'upper-deck': 'linear-gradient(180deg,#a6b6c4 0 40%,#6e8a5c 40% 62%,#8a6a47 62% 100%)',
    'lower-deck': 'linear-gradient(180deg,#8b9aa9 0 28%,#4e6a45 28% 54%,#7b5d3d 54%)',
    'recipe': 'radial-gradient(70% 70% at 40% 40%,#d98b3a,#8a4a1e 70%,#3a2216)',
  };
  Mock.scene = function (n) { return SC[n] || SC.recipe; };
  Mock.register('CameraTile', function (p) {
    var st = p.state || 'live';
    // The home tile (CameraGrid.CameraTile) draws ONLY the name capsule, with a red dot while the stream shows frames: no state pill (the app never puts one on the
    // picture; VoiceOver reads Live or Snapshot from the value). The pill is the viewer's badge (CameraLiveView.badge): pass viewer:true to draw it top-leading.
    var pill = null;
    if (p.viewer) {
      var text = st === 'live' ? (p.delayed ? 'Live \u00b7 Delayed' : 'Live') : (st === 'snapshot' ? 'Snapshot' : (p.since ? 'Last live ' + p.since : 'Connecting'));
      pill = h('span.state', st === 'connecting' ? Mock.components.ArcSpinner({ size: 'inline', label: 'Connecting' }) : (st === 'live' ? h('span.dot', { 'aria-hidden': 'true' }) : (st === 'snapshot' ? h('span', { html: Mock.icon('photo'), 'aria-hidden': 'true' }) : null)), text);
    }
    var b = h('button.ui-cam' + (st === 'live' ? '' : '.snapshot') + (p.viewer ? '.viewer' : ''), { type: 'button', 'aria-label': p.title + ' camera, ' + (st === 'live' ? 'Live' : 'Snapshot'), title: 'Opens the camera' },
      h('span.photo', { style: { background: Mock.scene(p.scene || 'front-door') }, 'aria-hidden': 'true' }), pill,
      h('span.name', h('span', st === 'live' ? h('span.dot', { 'aria-hidden': 'true' }) : null, p.title)));
    return b;
  }, { source: 'apple/Sources/HassUI/Features/Home/CameraGrid.swift (tile), apple/Sources/HassUI/Features/Cameras/CameraLiveView.swift (viewer badge)', props: '{title, state, since, scene, viewer, delayed}',
    variants: [{ id: 'live', label: 'Live (red dot beside the name)', props: { title: 'Front Door', scene: 'front-door' } }, { id: 'snapshot', label: 'Stalled or reconnecting: the last snapshot, no dot, no pill', props: { title: 'Driveway', state: 'snapshot', scene: 'driveway' } }, { id: 'connecting', label: 'Connecting: the snapshot, no dot', props: { title: 'Upper Deck', state: 'connecting', scene: 'upper-deck' } },
      { id: 'viewer-live', label: 'Viewer badge: Live', props: { title: 'Front Door', scene: 'front-door', viewer: true } }, { id: 'viewer-last', label: 'Viewer badge: Last live 6:51 PM', props: { title: 'Driveway', state: 'connecting', since: '6:51 PM', scene: 'driveway', viewer: true } }, { id: 'viewer-snapshot', label: 'Viewer badge: Snapshot', props: { title: 'Upper Deck', state: 'snapshot', scene: 'upper-deck', viewer: true } }] });
  Mock.register('ImageCard', function (p) {
    var ctx = p.ctx || Mock.current || {};
    if (ctx.axSize) return h('button.ui-img.row', { type: 'button' }, h('span.thumb', { style: { background: Mock.scene(p.scene) }, 'aria-hidden': 'true' }), h('span.lb', h('span.ti', { style: { display: 'block', fontSize: 'var(--fs-sub)', fontWeight: 600 } }, p.title), p.subtitle ? h('span.su', { style: { display: 'block', fontSize: 'var(--fs-foot)', color: 'var(--g-secondary-on-module)' } }, p.subtitle) : null));
    return h('button.ui-img', { type: 'button', 'aria-label': p.title + (p.subtitle ? ', ' + p.subtitle : '') }, h('span.photo', { style: { background: Mock.scene(p.scene) }, 'aria-hidden': 'true' }), h('span.scrim'), h('span.lb', h('span.ti', { style: { display: 'block' } }, p.title), p.subtitle ? h('span.su', { style: { display: 'block' } }, p.subtitle) : null));
  }, { source: 'apple/Sources/HassDesign/ImageCard.swift', props: '{title, subtitle, scene, ctx}',
    variants: [{ id: 'recipe', label: 'Recipe card', props: { title: 'Lemon Herb Roast Chicken', subtitle: '45 min · Serves 4', scene: 'recipe' } }, { id: 'long', label: 'Three-line title', props: { title: 'Slow-Cooked Pulled Pork Sandwiches With Pickled Onions', subtitle: '6 h', scene: 'recipe' } }] });
})();
