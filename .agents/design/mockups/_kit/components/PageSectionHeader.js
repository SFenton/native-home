/* PageSectionHeader (and RoomSectionHeader, its Home alias): the 20 pt bold heading over a tile grid or inset list on a page, with an optional detail on the
 * baseline ("Page 1 of 5"). apple/Sources/HassDesign/PageSectionHeader.swift. Detail text is white at 85% (Ink.onDarkSecondary). Stacks at accessibility
 * sizes. A heading trait for VoiceOver. props: {title, detail?}
 */
(function () {
  var h = Mock.h;
  function F(p) { return h('div.ui-hdr', h('h2', { role: 'heading', 'aria-level': '2' }, p.title), p.detail ? h('span.detail', p.detail) : null); }
  Mock.register('PageSectionHeader', F, { source: 'apple/Sources/HassDesign/PageSectionHeader.swift', props: '{title, detail}',
    variants: [{ id: 'plain', label: 'Title', props: { title: 'Robot Vacuums' } }, { id: 'detail', label: 'With detail', props: { title: 'Suggested Recipes', detail: 'Page 1 of 5' } }] });
  Mock.components.RoomSectionHeader = F;
})();
