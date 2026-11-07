/* ContentGate, Skeleton, PendingValueBar: how a page waits for content. apple/Sources/HassDesign/Loading/ContentGate.swift, patterns/content-gate.md, motion.md section 5.
 * ONLY for network-backed pages and sheets with nothing saved; never gate a page that reads EntityStore (the store is always ready from the disk snapshot) and never a spinner sheet.
 * Sequence: content laid out but hidden (opacity 0, no hit testing, hidden from VoiceOver) -> a centred ArcSpinner labelled "Loading" fades in after 150 ms -> when ready the spinner
 * fades out (140 ms) and the content fades in and rises 4 pt (170 ms; Reduce Motion drops the rise). `.page` profile (cold page loads): spinner at once (200 ms), held at least 1 s,
 * out over 500 ms (the web's DashboardPageLoadGate). A reopen with data in memory starts open: no spinner, no fade. NO shimmer sweeps: first sign-in placeholders are a soft pulsing
 * bar (PendingValueBar, opacity 0.35 to 1 over 1.4 s, static under Reduce Motion) where a value goes. Mock.anim.gate(el, {profile}) plays the sequence.
 * ContentGate props: {content:Node|Node[], phase?:'loading'|'spinner'|'ready', label?:string, minHeight?:number}; Skeleton: {lines?:3, width?, height?, pulse?}; PendingValueBar: {}
 */
(function () {
  var h = Mock.h;
  Mock.register('ContentGate', function (p) {
    var ph = p.phase || 'ready';
    return h('div.ui-gate', { dataset: { phase: ph, anim: 'gate' }, style: { minHeight: (p.minHeight || 120) + 'px' }, 'aria-busy': ph === 'ready' ? 'false' : 'true' },
      h('div.content', { 'aria-hidden': ph === 'ready' ? null : 'true' }, p.content),
      h('div.spin', { role: 'status' }, h('div.in', Mock.components.ArcSpinner({ size: 'page', label: p.label || 'Loading' }), p.label ? h('span', p.label) : null)));
  }, { source: 'apple/Sources/HassDesign/Loading/ContentGate.swift', props: '{content, phase, label, minHeight}',
    states: [{ id: 'loading', label: 'Loading (first 150 ms: nothing yet)', props: { phase: 'loading', content: 'Recipes appear here.' } }, { id: 'spinner', label: 'Spinner (after 150 ms)', props: { phase: 'spinner', content: 'Recipes appear here.', label: 'Loading recipes' } }, { id: 'ready', label: 'Ready (content faded in)', props: { phase: 'ready', content: 'Recipes appear here.' } }] });
  Mock.register('Skeleton', function (p) {
    var n = p.lines || 3;
    return h('div', { style: { display: 'flex', flexDirection: 'column', gap: '10px', width: p.width || '100%' }, 'aria-hidden': 'true' }, Array.apply(null, Array(n)).map(function (_, i) { return h('div.ui-skel' + (p.pulse === false ? '' : '.pulse'), { style: { height: (p.height || 14) + 'px', width: i === n - 1 ? '60%' : '100%' } }); }));
  }, { source: 'apple/Sources/HassDesign/PendingValue.swift', props: '{lines, width, height, pulse}', variants: [{ id: 'lines', label: 'Pulsing placeholder lines (no shimmer)', props: { lines: 3 } }] });
  Mock.register('PendingValueBar', function () { return h('span.ui-pending', { 'aria-hidden': 'true', style: { position: 'relative', display: 'inline-block', top: 0 } }); }, { source: 'apple/Sources/HassDesign/PendingValue.swift', variants: [{ id: 'bar', label: 'Soft bar, 0.35 to 1 over 1.4 s', props: {} }] });
})();
