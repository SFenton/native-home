/* BrightnessTile (the light dragger, a signature control): apple/Sources/HassDesign/BrightnessTile.swift; direction-g.md Controls. Tap toggles the light; press and drag sideways sets
 * brightness: the bright band follows the finger, a dark capsule bubble ("30%", white text in both appearances like the system volume HUD) floats beside it, a haptic tick every 10%,
 * and the tile lifts while dragging. A room's lights stack as full-width slabs that work the same way. The band is the lit tile's cream gradient from the leading edge over `#EADBC4`;
 * 0% is the off face. The band width is progress, kept on `quick` (0.2 s) so a dragged value never lags the finger (motion-system departures).
 * Rollout L: a `power` disc trails (`actions`), the glyph goes, and with `chevron` the disc sits left of the chevron on a navigation tile (two tracks wide in a grid).
 * The status line is the percent alone (70%, Off, Unavailable); `chevron: true` is the tile that opens the light's details on tap (onOpen). The dragging bubble is a 60 x 32 pt
 * capsule in the sheet-cell dark with white text, its centre 24 pt above the tile's top edge (BrightnessBubble).
 * props: {title, percent, symbol?, dragging?:boolean, unavailable?, chevron?:boolean, tint?:cssColor (a coloured bulb tints the band, never past dark-ink contrast)}
 */
(function () {
  var h = Mock.h;
  Mock.register('BrightnessTile', function (p) {
    var pct = p.percent || 0;
    // BrightnessTile.status: Off, 45% or Unavailable (the old "On at 70%" was the web's wording, not the app's).
    var un = !!p.unavailable, on = pct > 0 && !un;
    /* Rollout L (owner 2026-10-27): every brightness tile is an action tile with a `power` disc (text . disc, no leading glyph); with `chevron` it is a navigation tile (glyph, text, the disc left of the
       chevron) that opens the light's details, and an unavailable one has no disc. The drag stays on the body. */
    var disc = p.chevron && un ? null : [{ id: 'power', symbol: 'power', label: (on ? 'Turn Off ' : 'Turn On ') + p.title, on: on, dim: un }];
    var tile = Mock.tile({ title: p.title, subtitle: un ? 'Unavailable' : (pct > 0 ? pct + '%' : 'Off'), symbol: p.symbol || 'lightbulb', family: 'lights', isActive: on, isUnavailable: p.unavailable,
      progress: on ? pct / 100 : undefined, progressTint: p.tint, kind: p.chevron ? 'navigate' : 'toggle', behavior: p.chevron ? 'navigate' : 'perform', actions: disc });
    if (p.chevron && disc) tile.dataset.wide = '1';
    tile.dataset.anim = 'brightness';
    if (p.dragging) {
      // The tile lifts (1.03 and a shadow; only the shadow with Reduce Motion); the bubble is a 60 x 32 capsule centred 24 pt above the tile's top edge,
      // over the band's edge and kept inside the tile (BrightnessBubble.lift/width/height, bubbleCenter).
      if (!Mock.settings.reduceMotion) tile.style.transform = 'scale(1.03)';
      tile.style.boxShadow = '0 6px 12px rgba(0,0,0,.35)'; tile.style.zIndex = 5;
      var bubble = h('span.ui-bubble', { 'aria-hidden': 'true', style: { '--pct': pct } }, pct + '%');
      tile.style.overflow = 'visible'; tile.appendChild(bubble);
    }
    tile.setAttribute('role', 'slider'); tile.setAttribute('aria-valuenow', pct); tile.setAttribute('aria-valuemin', 0); tile.setAttribute('aria-valuemax', 100);
    return tile;
  }, { source: 'apple/Sources/HassDesign/BrightnessTile.swift', props: '{title, percent, symbol, dragging, unavailable, chevron, tint}',
    variants: [{ id: '70', label: '70%', props: { title: 'Table Light', percent: 70 } }, { id: '30', label: '30%', props: { title: 'Floor Lamp', percent: 30 } }, { id: 'bulb', label: 'Coloured bulb tints the band', props: { title: 'Accent Strip', percent: 60, tint: '#FF5E8A' } }],
    states: [{ id: 'off', label: 'Off (0%)', props: { title: 'Table Light', percent: 0 } }, { id: 'drag', label: 'Dragging (bubble, lifted)', props: { title: 'Table Light', percent: 40, dragging: true } }, { id: 'unavailable', label: 'Unavailable', props: { title: 'Back Deck Light', percent: 0, unavailable: true } }, { id: 'chevron', label: 'Opens details (chevron)', props: { title: 'Table Light', percent: 70, chevron: true } }] });
})();
