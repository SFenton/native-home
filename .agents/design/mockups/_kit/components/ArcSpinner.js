/* ArcSpinner and ArcProgress: apple/Sources/HassDesign/ArcSpinner.swift, ArcProgressViewStyle.swift. The web's arc (DashboardPageLoading),
 * not the system petal indicator (direction-g.md "Loading and feedback"): a ring at 22% opacity with the top quarter at 96% and the right
 * quarter at 72%, one turn per 820 ms, linear, in the colour of the text around it (currentColor). Sizes: page 44 pt / 3 pt ring, compact
 * 20 / 2.5 (pills, rows, the header arc), inline 16 / 2 (buttons, subtitles). Spoken as "Loading". Under Reduce Motion it keeps turning at
 * half speed: a still arc reads as frozen (motion.md section 8).
 */
(function () {
  var h = Mock.h;
  var SIZES = { page: [44, 3], compact: [20, 2.5], inline: [16, 2] };
  /** props: {size?:'page'|'compact'|'inline', label?:string (default 'Loading'), color?:cssColor} */
  var Arc = Mock.register('ArcSpinner', function (p) {
    p = p || {};
    var s = SIZES[p.size || 'page'], d = s[0], lw = s[1], r = (d - lw) / 2, c = 2 * Math.PI * r, q = c / 4;
    var svg = '<svg viewBox="0 0 ' + d + ' ' + d + '" aria-hidden="true"><circle cx="' + d / 2 + '" cy="' + d / 2 + '" r="' + r + '" fill="none" stroke="currentColor" stroke-opacity=".22" stroke-width="' + lw + '"/>' +
      '<circle cx="' + d / 2 + '" cy="' + d / 2 + '" r="' + r + '" fill="none" stroke="currentColor" stroke-opacity=".96" stroke-width="' + lw + '" stroke-dasharray="' + q + ' ' + (c - q) + '" transform="rotate(-135 ' + d / 2 + ' ' + d / 2 + ')"/>' +
      '<circle cx="' + d / 2 + '" cy="' + d / 2 + '" r="' + r + '" fill="none" stroke="currentColor" stroke-opacity=".72" stroke-width="' + lw + '" stroke-dasharray="' + q + ' ' + (c - q) + '" transform="rotate(-45 ' + d / 2 + ' ' + d / 2 + ')"/></svg>';
    return h('span.ui-arc', { role: 'img', 'aria-label': p.label || 'Loading', style: { width: d + 'px', height: d + 'px', color: p.color || 'inherit' }, html: svg });
  }, { source: 'apple/Sources/HassDesign/ArcSpinner.swift', props: '{size, label, color}',
    variants: [{ id: 'page', label: 'page 44', props: { size: 'page' } }, { id: 'compact', label: 'compact 20', props: { size: 'compact' } }, { id: 'inline', label: 'inline 16 (orange)', props: { size: 'inline', color: '#FF9F0A' } }],
    states: [{ id: 'default', label: 'Turning (0.82 s; Reduce Motion halves it)', props: { size: 'page' } }] });

  /** A titled arc, or a linear bar when `fraction` is known. props: {label, fraction?:0..1, size?} (ArcProgressViewStyle) */
  Mock.register('ArcProgress', function (p) {
    p = p || {};
    if (p.fraction != null) {
      return h('div', { role: 'progressbar', 'aria-valuenow': Math.round(p.fraction * 100), 'aria-label': p.label || 'Progress', style: { width: '220px' } },
        h('div', { style: { fontSize: 'var(--fs-sub)', marginBottom: '6px', color: 'var(--g-secondary-on-wallpaper)' } }, p.label || ''),
        h('div', { style: { height: '4px', borderRadius: '2px', background: 'rgba(255,255,255,.22)', overflow: 'hidden' } }, h('div', { style: { height: '100%', width: Math.round(p.fraction * 100) + '%', background: 'currentColor' } })));
    }
    return h('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px', textAlign: 'center' }, 'aria-live': 'polite' }, Arc({ size: p.size || 'page', label: p.label }),
      h('span', { style: { fontSize: 'var(--fs-sub)', color: 'var(--g-secondary-on-wallpaper)' } }, p.label || 'Loading'));
  }, { source: 'apple/Sources/HassDesign/ArcProgressViewStyle.swift', props: '{label, fraction?, size?}',
    variants: [{ id: 'indeterminate', label: 'Indeterminate', props: { label: 'Loading recipes' } }, { id: 'determinate', label: 'Fraction known', props: { label: 'Importing', fraction: .4 } }] });
})();
