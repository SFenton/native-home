/* StatusPill: a read-only labelled value with a toned icon (battery, next run, connection). apple/Sources/HassDesign/StatusPill.swift; patterns/status-pill.md.
 * Tones: neutral, ok (green), active (water blue), warning (orange), danger (red), unavailable (grey): the tone colours the ICON only, text stays the primary ink.
 * One accessibility element ("label", then "value, detail"); never a button (use GlassTile for an action). Lay out in a grid with a 150 pt scaled minimum so pills
 * wrap at large text. In a grouped list or a sheet the pill is a solid cell (a material over a sheet's glass smeared the content behind it).
 * props: {label, value, detail?, symbol, tone?:'neutral'|'ok'|'active'|'warning'|'danger'|'unavailable'}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  var TONE = { neutral: 'var(--ink-2, rgba(255,255,255,.72))', ok: '#34C759', active: '#0D66B3', warning: '#FF9500', danger: '#FF3B30', unavailable: '#8E8E93' };
  Mock.register('StatusPill', function (p) {
    var tone = p.tone || 'neutral';
    return h('div.ui-pill', { role: 'group', 'aria-label': p.label + ': ' + [p.value, p.detail].filter(Boolean).join(', '), style: { '--pill-tone': TONE[tone] } },
      h('span.ico', { html: I(p.symbol || 'info.circle') }), h('span.tx', h('span.la', p.label), h('span.va', p.value), p.detail ? h('span.de', p.detail) : null));
  }, { source: 'apple/Sources/HassDesign/StatusPill.swift', props: '{label, value, detail, symbol, tone}',
    variants: ['neutral', 'ok', 'active', 'warning', 'danger', 'unavailable'].map(function (t) { return { id: t, label: t, props: { label: 'Battery', value: t === 'unavailable' ? 'Unavailable' : '82%', detail: t === 'warning' ? 'Low soon' : undefined, symbol: 'battery.75percent', tone: t } }; }) });
})();
