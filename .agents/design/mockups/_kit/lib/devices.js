/* Device table and the per-render context (`ctx`) every builder receives.
 *
 * Sizes are WINDOW sizes in points; CSS pixels equal points, and the stage scales with `zoom`, never the frame.
 *   iphone                  402 x 874   iPhone 17 Pro (project simulator; portrait only, owner 2026-10-10)
 *   ipad-portrait           834 x 1194  iPad Pro 11; ipad-landscape 1194 x 834
 *   duo-unfolded-landscape  951 x 669   measured on the Duo simulator: hinge band 455.3 to 495.7 pt (split-view.md, duo.md)
 *   duo-unfolded-portrait   669 x 951   the same panel rotated; the hinge band is horizontal at y 455.3 to 495.7 (symmetry: not
 *                                       measured, "unfolded portrait was not run", duo.md). Horizontal bars, no vertical bar: the iPhone chrome at
 *                                       regular width (hamburger leading, Quick Links and Profile trailing, system large title that collapses,
 *                                       floating tab bar), single page. ShellNavigationStyle.resolve(hasHinge) = tabBar; ShellChrome.resolve(inVerticalBar: false)
 *                                       = menu button, title below the bar (MainTabView.swift, Shell/AppSection.swift; duo.md, owner 2026-10-30).
 *   duo-folded              466 x 678   the OUTER display, portrait. The project docs only say "iPhone-like"; FestivalNativeApps measured
 *                                       the folded portrait window at 466 x 678 (design/apple/duo.md, "Folded portrait") and S+H
 *                                       shares the hardware, so that is used here. Compact width, tabs in the trailing vertical bar.
 * The system's trailing vertical bar (folded, unfolded landscape) covers about 83 pt (ipados.md, duo.md): the page content ends at window width - 83.
 * Unfolded portrait has none (rail 0): its content spans the whole 669 pt width.
 * Everything geometric (split, even columns, chip gap) is derived from `hinge` and `rail`, never from the device name
 * (AGENTS.md: "The rule is geometric (SplitPolicy), never a device-name check").
 *
 * HINGE POSTURE (owner, 2026-10-24; in flight, supersedes "always on the hinge" in split-view.md): the unfolded Duo is either
 *   open  Fully open (flat): the on-demand split sits at the MIDPOINT of the free space, that is the window minus the trailing rail
 *         (951 - 83 = 868, so panes of 433 and 434 around a 1 pt band); the physical hinge is a seam the content simply crosses.
 *   part  Slightly closed (book pose): the split sits ON THE HINGE (leading pane ends at the band, trailing starts after it).
 * Mock.postures names them; `ctx.posture` carries the choice ('open' is the default); iPad has no hinge and always uses the midpoint.
 */
(function () {
  var HINGE = { at: 455.3, size: 40.4 };
  /** Mock.devices[key]: static facts about a window. */
  Mock.devices = {
    'iphone': { key: 'iphone', label: 'iPhone 17 Pro (402 × 874)', short: 'iPhone', w: 402, h: 874, r: 55, bezel: 9, family: 'phone', regular: false, safeTop: 54, safeBottom: 34,
      barTop: 54, island: true, rail: 0, menu: true, tabs: 'floating', titleInHeader: false, sheetTop: 60, hinge: null },
    'duo-folded': { key: 'duo-folded', label: 'iPhone Duo, folded (466 × 678)', short: 'Duo folded', w: 466, h: 678, r: 30, bezel: 10, family: 'duo', regular: false, safeTop: 36, safeBottom: 20,
      barTop: 40, punch: true, rail: 83, menu: false, tabs: 'rail', titleInHeader: true, verticalBar: true, sheetTop: 44, hinge: null },
    'duo-unfolded-portrait': { key: 'duo-unfolded-portrait', label: 'iPhone Duo, unfolded portrait (669 × 951)', short: 'Duo unfolded portrait', w: 669, h: 951, r: 24, bezel: 10, family: 'duo', regular: true,
      safeTop: 24, safeBottom: 20, barTop: 30, rail: 0, menu: true, tabs: 'floating', titleInHeader: false, sheetTop: 28, hinge: { axis: 'h', at: HINGE.at, size: HINGE.size } },
    'duo-unfolded-landscape': { key: 'duo-unfolded-landscape', label: 'iPhone Duo, unfolded landscape (951 × 669)', short: 'Duo unfolded landscape', w: 951, h: 669, r: 24, bezel: 10, family: 'duo', regular: true,
      safeTop: 24, safeBottom: 20, barTop: 30, rail: 83, menu: false, tabs: 'rail', titleInHeader: true, verticalBar: true, sheetTop: 28, hinge: { axis: 'v', at: HINGE.at, size: HINGE.size } },
    'ipad-portrait': { key: 'ipad-portrait', label: 'iPad Pro 11, portrait (834 × 1194)', short: 'iPad portrait', w: 834, h: 1194, r: 20, bezel: 14, family: 'ipad', regular: true, safeTop: 24, safeBottom: 20,
      barTop: 30, rail: 0, menu: true, tabs: 'flyout', titleInHeader: false, sheetTop: 28, hinge: null },
    'ipad-landscape': { key: 'ipad-landscape', label: 'iPad Pro 11, landscape (1194 × 834)', short: 'iPad landscape', w: 1194, h: 834, r: 20, bezel: 14, family: 'ipad', regular: true, safeTop: 24, safeBottom: 20,
      barTop: 30, rail: 0, menu: true, tabs: 'flyout', titleInHeader: false, sheetTop: 28, hinge: null },
  };
  Mock.deviceKeys = Object.keys(Mock.devices);
  /** Hinge postures of the unfolded Duo (see the header): `open` is flat, `part` is the book pose. */
  Mock.postures = { open: { key: 'open', label: 'Fully open (flat)', short: 'Fully open' }, part: { key: 'part', label: 'Slightly closed (book pose)', short: 'Slightly closed' } };

  /**
   * SplitPolicy.geometry for the on-demand split, with the posture rule. Pure: the animators call it for the start and the end of a move.
   * @param {number} contentW window width minus the trailing rail
   * @param {{x:number,w:number}|null} hinge the vertical hinge band in window x, or null (iPad)
   * @param {'open'|'part'} posture
   * @returns {{leading:number, band:number, trailing:number, atHinge:boolean}|null} null when a pane would be under 360 pt
   */
  Mock.splitFrame = function (contentW, hinge, posture) {
    var atHinge = !!hinge && posture === 'part';
    var band = atHinge ? hinge.w : 1, lead = atHinge ? hinge.x : Math.floor((contentW - 1) / 2), trail = contentW - lead - band;
    return lead >= 360 && trail >= 360 ? { leading: lead, band: band, trailing: trail, atHinge: atHinge } : null;
  };
  /** The split geometry part-way between two frames (t from 0 to 1): between postures, or from a closed split (Mock.closedFrame) to an open one. */
  Mock.lerpFrame = function (a, b, t) {
    function m(x, y) { return x + (y - x) * t; }
    return { leading: m(a.leading, b.leading), band: m(a.band, b.band), trailing: m(a.trailing, b.trailing) };
  };
  /** A split that is not open yet: the leading pane takes the whole content width. */
  Mock.closedFrame = function (contentW) { return { leading: contentW, band: 0, trailing: 0 }; };

  /** Text sizes (HIG Dynamic Type): Large (default), xxxLarge, AX5. */
  Mock.textSizes = { 'default': { label: 'Large (default)', cls: '' }, 'xxxl': { label: 'xxxLarge', cls: 'ts-xxxl' }, 'ax5': { label: 'Accessibility 5', cls: 'ts-ax5' } };

  /**
   * Build the context a state's render(ctx) receives.
   * @param {string} key device key
   * @param {{appearance?:'dark'|'light', ts?:'default'|'xxxl'|'ax5', reduceMotion?:boolean, reduceTransparency?:boolean, posture?:'open'|'part'}} [o]
   * @returns {object} ctx with: key, w, h (window), contentW (window minus the vertical bar), contentH, regular (size class), compact,
   *   rail (bar width or 0), hinge ({x,w} in window x, or null; axis 'v' only splits), canSplit (SplitPolicy: regular width, wider than
   *   tall, each half >= 360), splitGeometry ({leading, band, trailing} widths) or null, isPhone/isDuo/isIPad, folded, family,
   *   appearance ('dark'|'light': what sheets use), ts, scale (the Dynamic Type metric scale), reduceMotion, reduceTransparency, posture
   *   ('open'|'part' on a Duo with a hinge, else null), splitAtHinge (the divider is on the hinge band).
   */
  Mock.ctx = function (key, o) {
    o = o || {};
    var d = Mock.devices[key] || Mock.devices.iphone;
    var ctx = Object.assign({}, d);
    ctx.device = d;
    ctx.appearance = o.appearance || 'dark';
    ctx.ts = o.ts || 'default';
    ctx.scale = { 'default': 1, xxxl: 1.353, ax5: 3.118 }[ctx.ts];
    ctx.axSize = ctx.ts === 'ax5';
    ctx.reduceMotion = !!o.reduceMotion;
    ctx.reduceTransparency = !!o.reduceTransparency;
    ctx.compact = !d.regular;
    ctx.contentW = d.w - d.rail;
    ctx.contentH = d.h;
    ctx.isPhone = d.family === 'phone'; ctx.isDuo = d.family === 'duo'; ctx.isIPad = d.family === 'ipad';
    ctx.folded = key === 'duo-folded';
    ctx.hinge = d.hinge && d.hinge.axis === 'v' ? { x: d.hinge.at, w: d.hinge.size } : null;   // the vertical hinge splits columns
    ctx.hingeAny = d.hinge || null;
    ctx.posture = d.hinge ? (o.posture === 'part' ? 'part' : 'open') : null;
    ctx.canSplit = d.regular && d.w > d.h;   // SplitPolicy: regular width, wider than tall (portrait never splits)
    // SplitPolicy.geometry with the posture rule: on the hinge band while slightly closed, else a 1 pt band at the midpoint of the free space; each pane >= 360 pt.
    ctx.splitGeometry = null; ctx.splitAtHinge = false;
    if (ctx.canSplit) {
      var g = Mock.splitFrame(ctx.contentW, ctx.hinge, ctx.posture);
      if (g) { ctx.splitGeometry = { leading: g.leading, band: g.band, trailing: g.trailing }; ctx.splitAtHinge = g.atHinge; }
      else ctx.canSplit = false;
    }
    return ctx;
  };
})();
