/* ModuleList and ModuleRow: inset lists. apple/Sources/HassDesign/ModuleList.swift, Module.swift; patterns/module-list.md. direction-g.md Controls: Lists.
 *
 * One 26 pt card (#1C1C1E at 66% on a page; the sheet cell in a sheet, white in a light sheet) with hairlines inset to the text; rows are 52 pt, 60 pt with a
 * subtitle; a family-coloured glyph, the title (17), an optional subtitle (13), a trailing accessory (a state capsule, a pop-up, a switch) and an optional
 * chevron. `dense` (#141416 at 78%) when a row carries red or orange text. At accessibility sizes the accessory moves under the text. A row that does
 * something is a button (pressed highlight); unavailable rows dim the glyph only. hasGlyphs:false starts the hairlines at the 16 pt margin.
 * ModuleRow props: {title, subtitle?, symbol?, glyph?:cssColor, glyphOpacity?, subtitleInk?:cssColor, chevron?:boolean, accessory?:Node, press?:boolean}
 * ModuleList props: {rows:Array<ModuleRow props|Node>, density?:'thin'|'dense', hasGlyphs?:boolean (default true)}
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function ModuleRow(p) {
    var kids = [];
    if (p.symbol) kids.push(h('span.rg', { style: { color: p.glyph || '', opacity: p.glyphOpacity == null ? '' : p.glyphOpacity }, html: I(p.symbol) }));
    kids.push(h('span.tx', h('span.ti', p.title), p.subtitle ? h('span.su', { style: { color: p.subtitleInk || '' } }, p.subtitle) : null));
    if (p.accessory) kids.push(h('span.acc', p.accessory));
    if (p.chevron) kids.push(h('span.chev', { html: I('chevron.right', { weight: 2.4 }), 'aria-hidden': 'true' }));
    return h((p.press || p.chevron ? 'button' : 'div') + '.ui-mrow' + (p.subtitle ? '.sub' : '') + (p.press || p.chevron ? '.press' : ''), (p.press || p.chevron) ? { type: 'button', style: { '--sep-inset': 'calc(16px + 28px * var(--sc) + 12px)' } } : { style: { '--sep-inset': 'calc(16px + 28px * var(--sc) + 12px)' } }, kids);
  }
  function ModuleList(p) {
    var rows = (p.rows || []).map(function (r) { return r && r.nodeType ? r : ModuleRow(r); });
    return h('div.ui-mlist' + (p.density === 'dense' ? '.dense' : '') + (p.hasGlyphs === false ? '.noglyph' : ''), { role: 'list' }, rows);
  }
  var rows = [{ title: 'Thermostat Hub', subtitle: 'Heat', symbol: 'thermometer.medium', glyph: 'var(--fam-heating-glyph)', chevron: true }, { title: 'Hallway Vent', symbol: 'wind', glyph: 'var(--fam-vents-glyph)' }, { title: 'Back Deck Light', subtitle: 'Unavailable', symbol: 'lightbulb', glyph: 'var(--fam-lights-glyph)', glyphOpacity: .5 }];
  Mock.register('ModuleRow', ModuleRow, { source: 'apple/Sources/HassDesign/ModuleList.swift', props: '{title, subtitle, symbol, glyph, glyphOpacity, subtitleInk, chevron, accessory, press}',
    variants: [{ id: 'plain', label: 'Title only', props: { title: 'Front Yard', symbol: 'leaf', glyph: 'var(--fam-air-glyph)' } }, { id: 'subtitle', label: 'Title and subtitle (60 pt)', props: rows[0] }, { id: 'dim', label: 'Unavailable (glyph dims only)', props: rows[2] }] });
  Mock.register('ModuleList', ModuleList, { source: 'apple/Sources/HassDesign/ModuleList.swift', props: '{rows, density, hasGlyphs}',
    variants: [{ id: 'thin', label: 'Thin module', props: { rows: rows } }, { id: 'dense', label: 'Dense (red or orange text)', props: { density: 'dense', rows: [{ title: 'Replace the furnace filter', subtitle: 'Overdue · 3 days', subtitleInk: 'var(--g-red)', symbol: 'exclamationmark.circle', glyph: 'var(--g-red)' }, { title: 'Water the planters', subtitle: 'Due tomorrow', subtitleInk: 'var(--g-orange)', symbol: 'drop', glyph: 'var(--g-orange)' }] } },
      { id: 'noglyph', label: 'No glyphs: hairlines at the 16 pt margin', props: { hasGlyphs: false, rows: [{ title: 'Preheat the oven' }, { title: 'Season the chicken' }, { title: 'Roast for 45 minutes' }] } }] });
})();
