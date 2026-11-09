/* GlassTile: the tile. apple/Sources/HassDesign/GlassTile.swift (+ TileFaceStyle, TintedGlassGround/Sheen/Rim, TileFinish, TileLayout,
 * TileMetrics, LitTile). patterns/entity-tile.md; direction-g.md "Colour families" and "Tile finish: tinted glass".
 *
 * props: {title, subtitle?, symbol, family?, fill?:cssColor, room?:'kitchen', quickLink?:'rooms', tint?:cssColor, isActive?, isUnavailable?, isError?,
 *   kind?:'toggle'|'navigate'|'command'|'selection'|'state', selected?:boolean, wash?:cssColor, progress?:0..1, progressTint?:cssColor, layout?:'row'|'stack',
 *   titleLines?:2, accessory?:Node, actions?:[{id,symbol,label,on?,dim?,busy?}] (action-tiles.md: up to two trail as 44 pt discs, left of the chevron on a navigate tile;
 *   three or more, `below:true` or AX sizes go in a strip under the text), behavior?:'perform'|'navigate'|'inert' ('perform' with trailing discs drops the leading glyph: text . disc;
 *   'inert' is the flat read-only face: glyph kept, no sheen or rim, no press, no chevron or disc), under?:Node (custom controls under the text: the transport's volume slider, Mock.tileVolume), pending?:boolean (first sign-in: a soft pulsing bar where the value goes), singleLine?:boolean, showsChevron?:boolean, id?:string}
 *   family: 'lights' 'heating' 'cooling' 'vents' 'air' 'water' 'occupancy' 'contact' 'media' 'cleaning' 'power' 'cooking' 'climate' 'sec-home' ...
 *   (see kit.css --fam-*). Face resolution is TileFaceStyle.resolve: error > fill (room, Quick Link) > off (inactive or unavailable) > tinted (no
 *   family) > lit (lights) > filled (family fill). Off keeps the family glyph mixed toward grey; on fills the family colour (tinted glass: 78% over a
 *   dark underlay on a page, opaque in a sheet) with white ink; lights are the warm lit tile and power bright yellow with dark ink, both opaque.
 *   Layout: Row (Apple Home's tile, 72 pt min) is the default for device tiles; layout:'stack' + titleLines:2 is the navigation tile (Rooms, Quick
 *   Links: glyph top-leading, name anchored bottom, two-line reserve, 96 pt); accessibility sizes switch every tile to the stacked layout.
 *   Reduce Transparency draws the solid finish (kit.css .k-reduce-transparency). A colour change cross-fades in 0.6 s (state token).
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  var NO_FILL = { lights: 1, neutral: 1 };

  function GlassTile(p) {
    var fam = p.family || null, unavail = !!p.isUnavailable, active = !!p.isActive, kind = p.kind || 'toggle';
    var beh = p.behavior || null, acts = p.actions || [];
    if (beh === 'inert') kind = 'state'; else if (beh === 'navigate') kind = 'navigate'; else if (beh === 'perform' && kind === 'navigate') kind = 'toggle';
    var below = acts.length > 0 && (p.below === true || acts.length > 2);   // AX sizes are handled in CSS (.ts-ax5)
    var trailing = acts.length > 0 && !below;
    var noGlyph = beh === 'perform' && trailing;
    var fillVar = p.fill || (p.room ? 'var(--room-' + p.room + ')' : (p.quickLink ? 'var(--ql-' + p.quickLink + ')' : null));
    var face;
    if (p.isError) face = 'error';
    else if (fillVar && !unavail) face = 'colored';
    else if (unavail || !active) face = 'off';
    else if (!fam) face = 'tinted';
    else if (fam === 'lights') face = 'lit';
    else if (NO_FILL[fam]) face = 'tinted';
    else face = fam === 'power' ? 'power' : 'on';
    var cls = 'ui-tile ' + (face === 'tinted' ? 'tinted' : face);
    if (face === 'power') cls += ' on-power';
    if (unavail) cls += ' unavail';
    var chevron = kind === 'navigate' || !!p.showsChevron;   // showsChevron: a tile that opens details on tap but keeps its own semantics (BrightnessTile with onOpen)
    if (chevron) cls += ' navigate';
    if (p.wash) cls += ' wash';
    if (p.layout === 'stack' || p.layout === 'anchoredBottom') cls += ' stack';
    if (p.titleLines === 2) cls += ' lines2';
    if (p.accessory) cls += ' has-acc';
    if (beh === 'inert' || kind === 'state') cls += ' flat';
    if (noGlyph) cls += ' no-glyph';
    if (trailing) cls += ' has-discs d' + acts.length;
    if (acts.length) cls += ' has-actions';
    var style = {};
    if (fam) { style['--glyph'] = 'var(--fam-' + fam + '-glyph)'; style['--glyph-light'] = 'var(--fam-' + fam + '-glyph-light)'; if (!NO_FILL[fam]) style['--fill'] = 'var(--fam-' + fam + '-fill)'; }
    if (p.tint) { style['--glyph'] = p.tint; style['--glyph-light'] = p.tint; }
    if (fillVar) style['--fill'] = fillVar;
    if (p.wash) style['--wash'] = p.wash;
    if (p.progressTint) style['--bulb'] = p.progressTint;
    var filledGlyph = face === 'on' || face === 'power' || face === 'lit' || face === 'colored';
    var kids = [];
    // progress: a band from the leading edge (vacuum, dishwasher cycle; brightness) per face
    var lv = p.progress;
    if (face === 'lit') kids.push(h('span.band' + (p.progressTint ? '.tinted' : ''), { style: { width: Math.round((lv == null ? 1 : lv) * 100) + '%' }, 'aria-hidden': 'true' }));
    else if (lv > 0 && face === 'on') kids.push(h('span.band.shade', { style: { width: Math.round((1 - lv) * 100) + '%' }, 'aria-hidden': 'true' }));
    else if (lv > 0 && face === 'power') kids.push(h('span.band.light', { style: { width: Math.round(lv * 100) + '%' }, 'aria-hidden': 'true' }));
    else if (lv > 0) kids.push(h('span.band.off-band', { style: { width: Math.round(lv * 100) + '%' }, 'aria-hidden': 'true' }));
    if (!noGlyph) kids.push(h('span.glyph', { html: I(p.symbol || 'lightbulb', { fill: active || filledGlyph || face === 'colored' }) }));
    var tx = h('span.tx', h('span.ti', p.title));
    if (p.subtitle != null) {
      if (p.pending) { var w = h('span.st-wrap', h('span.st' + (p.singleLine ? '.one' : ''), { 'aria-hidden': 'true', style: { visibility: 'hidden' } }, p.subtitle), h('span.ui-pending', { 'aria-hidden': 'true' })); tx.appendChild(w); }
      else tx.appendChild(h('span.st' + (p.singleLine ? '.one' : ''), p.subtitle));
    }
    kids.push(tx);
    /* A pure stroke symbol (power) drawn filled becomes a blob: the disc draws it as an outline, as SF Symbols does; every other glyph keeps the filled variant. */
    function discGlyph(name) { return I(name, { fill: name !== 'power' }); }
    function discs() {
      return acts.map(function (a) {
        return h('span.disc' + (a.on ? '.on' : '') + (a.dim ? '.dim' : '') + (a.busy ? '.busy' : ''), { role: 'button', 'aria-label': a.label, 'data-action': a.id || '', 'aria-disabled': a.dim ? 'true' : null, html: a.busy ? '<span class="spin"></span>' : discGlyph(a.symbol) });
      });
    }
    if (trailing) kids.push(h('span.discs', discs()));
    if (chevron) kids.push(h('span.chev', { html: I('chevron.right', { weight: 2.4 }), 'aria-hidden': 'true' }));
    if (p.accessory) { kids.push(h('span.acc', p.accessory)); style['--acc-w'] = (p.accessoryWidth || 64) + 'px'; }
    if (below) kids.push(h('span.strip', discs()));
    if (p.under) kids.push(h('span.under', p.under));
    var attrs = { type: 'button', style: style, dataset: { face: face, family: fam || '' } };
    if (p.id) attrs.id = p.id;
    var label = p.title + (p.subtitle ? ', ' + (p.pending ? 'Loading' : p.subtitle) : '');
    var tag = kind === 'state' ? 'div' : 'button';
    if (kind === 'state') { attrs = { style: style, role: 'group', 'aria-label': label, dataset: attrs.dataset }; }
    else {
      attrs['aria-label'] = label;
      if (kind === 'toggle') attrs['aria-pressed'] = active ? 'true' : 'false';
      if (kind === 'selection') attrs['aria-pressed'] = p.selected ? 'true' : 'false';
      if (unavail) attrs.disabled = true;
    }
    return h(tag + '.' + cls.split(' ').join('.'), attrs, kids);
  }
  Mock.tile = GlassTile;
  /** The playing remote's volume slider (TileVolumeSlider): speaker glyphs at the ends, a 44 pt target, writes on release. Pass as a tile's `below`. */
  Mock.tileVolume = function (pct, label) {
    return h('span.ui-slider-t', { role: 'slider', 'aria-label': label || 'Volume', 'aria-valuenow': String(pct), 'aria-valuemin': '0', 'aria-valuemax': '100' },
      h('span', { html: I('speaker.fill'), style: { width: '16px', display: 'grid' } }), h('span.track', h('i', { style: { width: pct + '%' } })), h('span', { html: I('speaker.wave.3.fill'), style: { width: '20px', display: 'grid' } }));
  };

  var V = [], fams = [['lights', 'Lights (lit tile)', 'Kitchen Lights', 'On at 70%', 'lightbulb'], ['heating', 'Heating', 'Bedroom 1', 'Heating to 70°', 'thermometer.medium'], ['cooling', 'Cooling', 'Office', 'Cooling to 72°', 'snowflake'],
    ['vents', 'Vents', 'Study Vent', 'Open 50%', 'wind'], ['air', 'Air', 'Air Purifier', 'High', 'fan'], ['water', 'Water', 'Humidifier', 'Mist 40%', 'humidity'], ['occupancy', 'Occupancy', 'Gym', 'Detected', 'figure.walk.motion'],
    ['contact', 'Doors and windows', 'Front Door', 'Unlocked', 'lock.open'], ['media', 'Media', 'Living Room TV', 'On', 'tv'], ['cleaning', 'Cleaning', 'Robot Vacuum', 'Cleaning 40%', 'robotic.vacuum'],
    ['power', 'Power (dark ink)', 'Towel Rack', 'On', 'bolt.fill'], ['cooking', 'Cooking', 'Oven', '350°', 'flame'], ['sec-home', 'Security: Home', 'Security System', 'Armed Home', 'shield'], ['sec-triggered', 'Security: Triggered', 'Security System', 'Alarm Triggered', 'shield']];
  fams.forEach(function (f) { V.push({ id: f[0], label: f[1] + ' · on', props: { title: f[2], subtitle: f[3], symbol: f[4], family: f[0], isActive: true, progress: f[0] === 'cleaning' ? .4 : undefined } }); });
  ['kitchen', 'master-bedroom', 'gym', 'theater-room'].forEach(function (r) { V.push({ id: 'room-' + r, label: 'Room fill · ' + r, props: { title: r.replace(/-/g, ' ').replace(/\b\w/g, function (c) { return c.toUpperCase(); }), symbol: 'house', room: r, layout: 'stack', titleLines: 2, kind: 'navigate' } }); });
  V.push({ id: 'quick-rooms', label: 'Quick Link · Rooms', props: { title: 'Rooms', symbol: 'square.split.2x2', quickLink: 'rooms', layout: 'stack', titleLines: 2, kind: 'navigate' } });
  V.push({ id: 'layout-stack', label: 'Layout · stacked (navigation tile)', props: { title: 'Bedroom 1 Closet', symbol: 'door.left.hand.closed', family: 'contact', layout: 'stack', titleLines: 2, isActive: false } });

  Mock.register('GlassTile', GlassTile, { source: 'apple/Sources/HassDesign/GlassTile.swift', props: 'see the file header',
    variants: V,
    states: [
      { id: 'off', label: 'Off', props: { title: 'Front Door', subtitle: 'Locked', symbol: 'lock', family: 'contact', isActive: false } },
      { id: 'on', label: 'On (family fill)', props: { title: 'Front Door', subtitle: 'Unlocked', symbol: 'lock.open', family: 'contact', isActive: true } },
      { id: 'lit', label: 'Lit (lights)', props: { title: 'Table Light', subtitle: 'On at 70%', symbol: 'lightbulb', family: 'lights', isActive: true, progress: .7 } },
      { id: 'error', label: 'Error ("Didn\'t respond")', props: { title: 'Left Door', subtitle: 'Didn\'t respond', symbol: 'door.garage.closed', family: 'contact', isError: true } },
      { id: 'pending', label: 'Pending (first sign-in)', props: { title: 'Thermostat', subtitle: '70°', symbol: 'thermometer.medium', family: 'heating', pending: true } },
      { id: 'unavailable', label: 'Unavailable', props: { title: 'Back Deck Light', subtitle: 'Unavailable', symbol: 'lightbulb', family: 'lights', isUnavailable: true } },
      { id: 'progress', label: 'Progress band', props: { title: 'Robot Vacuum', subtitle: 'Cleaning · 40%', symbol: 'robotic.vacuum', family: 'cleaning', isActive: true, progress: .4 } },
      { id: 'tinted', label: 'Tinted (no family)', props: { title: 'Custom Scene', subtitle: 'Ready', symbol: 'sparkles', tint: '#64B0FF', isActive: true } },
      { id: 'navigate', label: 'Navigate (chevron)', props: { title: 'Rooms', subtitle: '16 rooms', symbol: 'square.split.2x2', family: 'contact', kind: 'navigate', isActive: false } },
      { id: 'two-line', label: 'Wraps to two lines', props: { title: 'Bedroom 1 Closet Light', subtitle: 'Off', symbol: 'lightbulb', family: 'lights', isActive: false } },
    ] });
  /** Alias: the face alone (no button semantics needed in a mockup). */
  Mock.components.GlassTileFace = GlassTile;
})();
