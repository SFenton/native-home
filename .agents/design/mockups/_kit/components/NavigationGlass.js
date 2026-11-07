/* NavigationGlass: the glass header circles. apple/Sources/HassDesign/NavigationGlass.swift (the `navigationGlass(in:)` material) and
 * apple/Sources/HassUI/App/Shell/ShellHeader.swift (Quick Links, Profile, Open Navigation, Back).
 *
 * Registers: NavigationGlass, QuickLinksButton, ProfileButton, HamburgerButton, BackButton, CloseButton, RailGroup.
 * Rules (direction-g.md Navigation): Quick Links is a plain 44 pt glass circle; Profile with a known name is a 44 pt monogram disc that
 * IS the whole button (no glass ring), with the attention badge on its top-trailing edge ("9+" past nine); the two sit 12 pt apart on
 * iPhone and iPad. In the Duo's vertical rail they share ONE glass group with the person symbol (owner 2026-10-20). Liquid Glass only on
 * the navigation layer: never on tiles or cards.
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function circle(symbol, label, o) {
    o = o || {};
    return h('button.ui-circle.ui-glass' + (o.cls ? '.' + o.cls : ''), { type: 'button', 'aria-label': label, title: label, html: I(symbol, { fill: o.fill }) });
  }
  function badgeText(n) { return n > 9 ? '9+' : String(n); }

  /** A glass circle with one symbol. props: {symbol, label, fill?} */
  Mock.register('NavigationGlass', function (p) { return circle(p.symbol || 'square.grid.2x2', p.label || 'Button', p); }, {
    source: 'apple/Sources/HassDesign/NavigationGlass.swift', doc: 'Liquid Glass circle for navigation controls (thin material before iOS 26).',
    variants: [
      { id: 'quick-links', label: 'Quick Links', props: { symbol: 'square.grid.2x2', label: 'Quick Links' } },
      { id: 'back', label: 'Back', props: { symbol: 'chevron.left', label: 'Back' } },
      { id: 'close', label: 'Close', props: { symbol: 'xmark', label: 'Close' } },
      { id: 'menu', label: 'Open Navigation', props: { symbol: 'line.3.horizontal', label: 'Open Navigation' } },
    ] });

  /** Quick Links: opens the Quick Links sheet. identifier quickLinks.open. props: none */
  Mock.register('QuickLinksButton', function () { return circle('square.grid.2x2', 'Quick Links'); }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeader.swift' });
  /** Open Navigation (hamburger), nav.open; leading on iPhone and iPad, in the rail on the unfolded Duo. props: {inRail?} */
  Mock.register('HamburgerButton', function (p) { var b = circle('line.3.horizontal', 'Open Navigation'); b.title = 'Open Navigation'; return b; }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeader.swift' });
  /** Back on a pushed page. props: {label?} */
  Mock.register('BackButton', function (p) { return circle('chevron.left', (p && p.label) || 'Back'); }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeader.swift' });
  /** Close (circle x) as used in the header of a pushed full-screen page. For sheets use SheetCloseItem. */
  Mock.register('CloseButton', function () { return circle('xmark', 'Close'); }, { source: 'apple/Sources/HassDesign/HassModal.swift' });

  /** Stand-in portraits (illustrations, never real photos) for the profile-photos mockups: Mock.portrait('a'|'b'|'c'|'d') is an image data URI. */
  var PORTRAITS = {
    a: '<rect width="100" height="100" fill="#e8b98a"/><circle cx="50" cy="40" r="19" fill="#7a4b2a"/><path d="M12 100c2-24 18-34 38-34s36 10 38 34z" fill="#2f5d8a"/><circle cx="50" cy="42" r="16" fill="#f1c9a5"/><path d="M33 36c3-14 31-16 35 0-10-6-24-6-35 0z" fill="#4a2c16"/>',
    b: '<rect width="100" height="100" fill="#bcd9c6"/><circle cx="50" cy="40" r="19" fill="#2a1a12"/><path d="M10 100c2-24 18-34 40-34s38 10 40 34z" fill="#a8326f"/><circle cx="50" cy="43" r="16" fill="#e9b894"/><path d="M30 44c-2-22 38-26 40 0-3-12-12-18-20-18s-17 6-20 18z" fill="#2a1a12"/>',
    c: '<rect width="100" height="100" fill="#f2d98a"/><circle cx="50" cy="41" r="17" fill="#d79a72"/><path d="M14 100c2-22 16-32 36-32s34 10 36 32z" fill="#24304a"/><path d="M34 34c4-12 28-12 32 0-8-4-24-4-32 0z" fill="#1c1c1c"/>',
    d: '<rect width="100" height="100" fill="#c9bfe8"/><circle cx="50" cy="41" r="17" fill="#8a5a3a"/><path d="M12 100c2-24 18-34 38-34s36 10 38 34z" fill="#e0e0e0"/><path d="M33 40c0-14 34-14 34 0-8-6-26-6-34 0z" fill="#111"/>',
  };
  Mock.portrait = function (id) { return 'data:image/svg+xml;utf8,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' + (PORTRAITS[id] || PORTRAITS.a) + '</svg>'); };
  /** A photo layer over a monogram (AvatarView): the initials stay underneath; the layer fades by opacity (.on). Returns the img. */
  Mock.portraitLayer = function (id, on) { var l = h('img.ui-photo', { src: Mock.portrait(id), alt: '', 'aria-hidden': 'true', draggable: 'false' }); if (on !== false) l.classList.add('on'); return l; };

  /**
   * Profile (nav.profile). props: {name?:string (initials are taken from it; omit for the person-symbol-on-glass form shown before the name is known),
   * badge?:number, offline?:boolean, fill?:cssColor (the monogram fill, default #0066CC: 5.6:1 under white),
   * photo?:'a'|'b'|'c'|'d' (the person's Home Assistant photo, drawn over the initials with a 0.5 pt hairline; the button's label and value do not change)}
   */
  Mock.register('ProfileButton', function (p) {
    p = p || {};
    var name = p.name === undefined ? 'Alex Demo' : p.name, label = 'Profile' + (name ? ', ' + name : '') + (p.badge ? ', ' + p.badge + ' items need attention' : '');
    var b;
    if (name) {
      var initials = name.split(/\s+/).map(function (w) { return w[0]; }).join('').slice(0, 2).toUpperCase();
      b = h('button.ui-monogram', { type: 'button', 'aria-label': label, title: label, style: p.fill ? { background: p.fill } : null }, initials);
      if (p.photo) { b.classList.add('has-photo'); b.appendChild(Mock.portraitLayer(p.photo)); }
    } else b = circle('person', label);
    if (p.badge) { b.style.position = 'relative'; b.appendChild(h('span.ui-badge', { 'aria-hidden': 'true' }, badgeText(p.badge))); }
    if (p.offline) { b.style.position = 'relative'; b.appendChild(h('span.ui-badge.status', { 'aria-hidden': 'true', html: I('icloud.slash') })); }
    return b;
  }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeader.swift', props: '{name?, badge?, offline?, fill?, photo?}',
    variants: [{ id: 'monogram', label: 'Monogram', props: { name: 'Alex Demo' } }, { id: 'badge', label: 'Badge 3', props: { badge: 3 } }, { id: 'badge9', label: 'Badge 12 (9+)', props: { badge: 12 } },
      { id: 'noname', label: 'No name yet', props: { name: '' } }, { id: 'photo', label: 'Photo (Home Assistant picture)', props: { photo: 'a' } }],
    states: [{ id: 'live', label: 'Live', props: {} }, { id: 'offline', label: 'Offline (cloud badge)', props: { offline: true } }] });

  /** The Duo rail's single glass group: Quick Links and the person symbol, no spacer. props: {badge?} */
  Mock.register('RailGroup', function (p) {
    p = p || {};
    var prof = h('button', { type: 'button', 'aria-label': 'Profile', title: 'Profile', html: I('person.crop.circle.fill') });
    prof.style.position = 'relative';
    if (p.badge) prof.appendChild(h('span.ui-badge', { style: { top: '4px', right: '2px' }, 'aria-hidden': 'true' }, badgeText(p.badge)));
    return h('div.ui-railblob.ui-glass', h('button', { type: 'button', 'aria-label': 'Quick Links', title: 'Quick Links', html: I('square.grid.2x2') }), prof);
  }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeaderGrouping.swift', doc: 'ShellHeaderGrouping.oneGroup' });
})();
