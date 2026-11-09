/* Shell chrome per device: Mock.frame (device + status bar), Mock.page (a tab root or pushed page), Mock.sheet (a presented modal),
 * Mock.split and Mock.detailPane (the on-demand split: on the hinge while a Duo is slightly closed, else the midpoint of the free space).
 *
 * What the chrome is, per device (direction-g.md Navigation; design/apple/{iphone,ipados,duo,split-view}.md):
 *   iphone                  hamburger leading (owner 2026-10-20), Quick Links circle + Profile monogram trailing 12 pt apart, large title
 *                           below the bar, glass floating tab bar (5 tabs, Settings last).
 *   duo-folded              no hamburger; tabs and one glass group (Quick Links + Profile as the person symbol, no spacer) in the trailing
 *                           vertical rail; the title shares the header row (inlineLarge) because nothing else leads.
 *   duo-unfolded-landscape tab bar kept (owner 2026-10-26; a window with a hinge): the trailing vertical bar like the folded Duo, no hamburger, 24 pt title in the header row (observed on the unfolded simulator).
 *   duo-unfolded-portrait  the iPhone chrome at regular width (horizontal bars, no vertical bar; ShellNavigationStyle.resolve -> tabBar because of the hinge,
 *                           ShellChrome.resolve(inVerticalBar: false) -> menu button + title below the bar): hamburger leading, Quick Links and Profile
 *                           trailing, the system large title that collapses into the inline title beside the hamburger, floating tab bar. Single page (portrait never splits).
 *   ipad-*                  flyout style (regular width, no hinge); hamburger leading; Quick Links and Profile circles trailing; title below the bar; no tab bar.
 * Quick Links and Profile are on every page, root or pushed. A pushed page swaps the hamburger for a glass Back circle.
 */
(function () {
  var h = Mock.h;
  var C = function () { return Mock.components; };

  var STATUS_R = '<svg viewBox="0 0 72 13" aria-hidden="true"><g fill="currentColor"><rect x="0" y="8" width="3" height="5" rx=".8"/><rect x="5" y="5.5" width="3" height="7.5" rx=".8"/><rect x="10" y="3" width="3" height="10" rx=".8"/><rect x="15" y="0" width="3" height="13" rx=".8"/></g>' +
    '<path fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" d="M24 5.2a8 8 0 0 1 12 0M26.4 8a4.6 4.6 0 0 1 7.2 0"/><circle cx="30" cy="11.3" r="1.2" fill="currentColor"/>' +
    '<rect x="42" y=".7" width="25" height="11.6" rx="3.4" fill="none" stroke="currentColor" stroke-opacity=".45"/><rect x="43.7" y="2.4" width="19" height="8.2" rx="2" fill="currentColor"/><rect x="68.6" y="4.4" width="1.8" height="4.2" rx=".9" fill="currentColor" fill-opacity=".5"/></svg>';

  /**
   * Wrap a screen body in a device: bezel, true-size .screen, status bar, Dynamic Island, home indicator, hinge band.
   * @param {object} ctx from Mock.ctx
   * @param {Node|Node[]|string} content what render() returned (a Mock.page / Mock.sheet node or your own)
   * @returns {HTMLElement} .k-device
   */
  Mock.frame = function (ctx, content, o) {
    o = o || {};
    var d = ctx.device, ts = Mock.textSizes[ctx.ts] || Mock.textSizes['default'];
    var screen = h('div.screen.ui-root.g-dark' + (ts.cls ? '.' + ts.cls : '') + (ctx.reduceMotion ? '.k-reduce-motion' : '') + (ctx.reduceTransparency ? '.k-reduce-transparency' : ''),
      { dataset: { device: ctx.key }, style: { '--w': d.w + 'px', '--h': d.h + 'px', '--r': d.r + 'px', '--safe-top': d.safeTop + 'px', '--safe-bottom': d.safeBottom + 'px' } });
    if (d.hinge) screen.dataset.hinge = d.hinge.axis;
    if (typeof content === 'string') content = Mock.html(content);
    Mock.append(screen, content);
    var first = content && content.nodeType ? content : (Array.isArray(content) ? content[0] : null);
    var indicator = first && first.dataset && first.dataset.indicator === 'dark';
    var statusDark = first && first.dataset && first.dataset.statusInk === 'dark';
    if (indicator) screen.style.setProperty('--indicator', 'rgba(0,0,0,.85)');
    var phone = d.family === 'phone';
    var time = phone || ctx.folded ? '9:41' : '9:41 Fri Oct 23';
    screen.appendChild(h('div.k-status' + (statusDark ? '.dark-ink' : ''), { 'aria-hidden': 'true' }, h('span.l', time), h('span.r', { html: STATUS_R })));
    if (d.island) screen.appendChild(h('div.k-island', { 'aria-hidden': 'true' }));
    if (d.punch) screen.appendChild(h('div.k-punch', { 'aria-hidden': 'true' }));
    if (d.hinge) {
      var v = d.hinge.axis === 'v', pose = Mock.postures[ctx.posture] || Mock.postures.open;
      screen.dataset.posture = ctx.posture || 'open';
      var hv = h('div.k-hinge.' + (v ? 'v' : 'h'), { 'aria-hidden': 'true', dataset: { posture: ctx.posture || 'open' }, title: 'Hinge band ' + d.hinge.at + ' to ' + (d.hinge.at + d.hinge.size).toFixed(1) + ' pt (nothing interactive here). ' + pose.label },
        h('span.k-hinge-label', pose.short));
      if (v) { hv.style.left = d.hinge.at + 'px'; hv.style.width = d.hinge.size + 'px'; } else { hv.style.top = d.hinge.at + 'px'; hv.style.height = d.hinge.size + 'px'; }
      screen.appendChild(hv);
    }
    screen.appendChild(h('div.k-home', { 'aria-hidden': 'true' }));
    var dev = h('div.k-device', { dataset: { device: ctx.key } }, h('div.k-bezel', { style: { '--r': d.r + 'px', '--bz': d.bezel + 'px' } }, screen));
    return dev;
  };

  /**
   * A page (tab root or pushed): wallpaper, scrolling body with large title, header buttons, tab bar or rail or flyout.
   * @param {object} ctx
   * @param {{title:string, subtitle?:string, section?:string, back?:string|boolean, body?:Node|Node[], connection?:'live'|'offline'|'reconnecting',
   *   badge?:number, choresBadge?:number, flyoutOpen?:boolean, floating?:Node, scrollTop?:number, collapsed?:boolean, noTabs?:boolean, profileName?:string, bottomPad?:number}} o
   *   section: which tab/flyout row is selected ('home'|'security'|'climate'|'chores'|'settings'); back: pushed page (label for VoiceOver);
   *   connection: 'reconnecting' draws the arc left of Quick Links;
   *   badge: Profile attention count; choresBadge: overdue chores on the Chores tab/row; floating: a FloatingActionBar node; collapsed: the scrolled state where the large title has collapsed into
   *   the bar's inline title (it also fades in by itself as any page scrolls; the Page scroll control's Top resets it, Middle and End scroll on).
   */
  Mock.page = function (ctx, o) {
    o = o || {};
    var K = C(), d = ctx.device, barBottom = d.barTop + 44;
    var page = h('div.ui-page', { style: { '--bar-top': d.barTop + 'px', '--bar-bottom': barBottom + 'px', '--rail-w': d.rail + 'px', '--safe-top': d.safeTop + 'px' } });
    page.appendChild(h('div.ui-wall'));
    var lead = o.back ? K.BackButton({ label: typeof o.back === 'string' ? o.back : 'Back' }) : (d.menu && !d.menuInRail ? K.HamburgerButton() : null);
    var bar = h('div.ui-bar', lead);
    // The Duo's vertical bar (folded, unfolded landscape, book pose): a fixed 24 pt semibold inline title that never collapses (header-edge-fade R7 (6)).
    // Unfolded portrait has horizontal bars: it takes the iPhone chrome (large title below the bar, titleInHeader false), not this branch.
    var titleCls = d.verticalBar ? 'h1.ui-t-vbar' : 'h1.ui-t-large';
    if (d.titleInHeader && !o.back) bar.appendChild(h(titleCls, { style: { marginLeft: lead ? 0 : 4, whiteSpace: 'nowrap' } }, o.title));
    else if (d.titleInHeader && o.back) bar.appendChild(h(titleCls, { style: { whiteSpace: 'nowrap' } }, o.title));
    bar.appendChild(h('div.sp'));
    // The inline title: where the large title lives below the bar, it fades into the bar as the large title scrolls under it (standard large-title collapse).
    var inlineTitle = d.titleInHeader ? null : h('div.inline-title', { 'aria-hidden': 'true' }, o.title);
    if (inlineTitle) bar.appendChild(inlineTitle);
    if (o.connection === 'reconnecting') bar.appendChild(K.ReconnectingArc({ on: true }));
    if (!d.rail) {
      bar.appendChild(K.QuickLinksButton());
      bar.appendChild(K.ProfileButton({ badge: o.badge, offline: o.connection === 'offline', name: o.profileName }));
    }
    page.appendChild(bar);

    var scroll = h('div.ui-scroll');
    var bottom = (d.tabs === 'floating' ? 110 : 24) + (o.floating ? 64 : 0) + (o.bottomPad || 0);
    scroll.style.setProperty('--bottom-pad', bottom + 'px');
    if (!d.titleInHeader) scroll.appendChild(h('div.ui-title-wrap', h('h1.ui-t-large', o.title), o.subtitle ? h('p.sub', o.subtitle) : null));
    else scroll.appendChild(h('div', { style: { height: '4px' } }));
    var body = h('div.ui-body', o.body);
    scroll.appendChild(body);
    var titleWrap = scroll.querySelector('.ui-title-wrap');
    scroll.addEventListener('scroll', function () {
      scroll.style.setProperty('--ramp', Math.min(40, scroll.scrollTop) + 'px');
      if (inlineTitle) { var th = (titleWrap && titleWrap.offsetHeight) || 60; inlineTitle.style.opacity = Math.max(0, Math.min(1, (scroll.scrollTop - th * .45) / (th * .4))).toFixed(2); }
    });
    page.appendChild(scroll);
    if (o.collapsed && !d.titleInHeader) {   // the collapsed-title state: scrolled so the large title is under the bar and the inline title shows
      scroll.dataset.scrollPinned = 'true'; body.style.minHeight = '100%';   // enough content that the large title can scroll away
      var settle = function () { scroll.scrollTop = ((titleWrap && titleWrap.offsetHeight) || 60) + 4; scroll.dispatchEvent(new Event('scroll')); };
      requestAnimationFrame(function () { requestAnimationFrame(settle); });
    } else if (o.scrollTop) requestAnimationFrame(function () { scroll.scrollTop = o.scrollTop; });

    if (o.connection === 'offline') {
      page.appendChild(h('div', { style: { position: 'absolute', left: 0, right: d.rail + 'px', top: (barBottom + 4) + 'px', zIndex: 15, pointerEvents: 'none' } }, K.OfflineChip({ variant: 'offline' })));
    }
    if (o.floating) {
      var bot = d.tabs === 'floating' ? 22 + 62 + 6 : Math.max(12, d.safeBottom - 8);
      page.appendChild(h('div.ui-actions-slot', { style: { bottom: bot + 'px' } }, o.floating));
    }
    if (d.tabs === 'floating' && !o.noTabs) page.appendChild(K.TabBar({ selected: o.section || 'home', badges: { chores: o.choresBadge } }));
    if (d.rail) {
      var rail = h('div.ui-rail');
      if (d.menuInRail && d.menu) rail.appendChild(K.HamburgerButton({ inRail: true }));
      rail.appendChild(K.RailGroup({ badge: o.badge }));
      rail.appendChild(h('div.grow'));
      if (d.tabs === 'rail' && !o.noTabs) rail.appendChild(K.TabBar({ selected: o.section || 'home', orientation: 'vertical', badges: { chores: o.choresBadge } }));
      page.appendChild(rail);
    }
    if (o.flyoutOpen) page.appendChild(K.NavigationFlyout({ selected: o.section || 'home', badges: { chores: o.choresBadge } }));
    return page;
  };

  /**
   * Two columns on the on-demand split (SplitPolicy.geometry): leading ends at the divider, the band between them stays empty. The divider is the
   * hinge band while a Duo is slightly closed, else the midpoint of the free space (Duo fully open, iPad landscape); see lib/devices.js.
   * Returns the single stacked column when the window may not split (portrait, compact, a pane under 360 pt).
   * The panes are tagged (`data-split`) so Mock.reflow can animate them: the divider sliding between postures, or a detail pane opening.
   * @param {object} ctx
   * @param {{leading:Node[], trailing:Node[], forceSplit?:boolean}} o  leading/trailing: the panes' children (a .ui-bleed child ignores pane padding)
   */
  Mock.split = function (ctx, o) {
    var g = ctx.splitGeometry;
    if (!g) {
      var col = h('div.ui-split', { style: { flexDirection: 'column', gap: '24px', alignItems: 'stretch' } });
      [].concat(o.leading || [], o.trailing || []).forEach(function (n) { col.appendChild(h('div', { class: n.classList && n.classList.contains('ui-bleed') ? 'ui-bleed' : '', style: n.classList && n.classList.contains('ui-bleed') ? {} : { margin: '0 16px' } }, n)); });
      col.classList.add('ui-bleed'); col.style.margin = '0';
      return col;
    }
    var s = h('div.ui-split.ui-bleed', { style: { margin: 0 }, dataset: { split: ctx.splitAtHinge ? 'hinge' : 'midpoint' } },
      h('div.pane', { dataset: { pane: 'leading' }, style: { width: g.leading + 'px' } }, o.leading),
      h('div.band', { style: { width: g.band + 'px', alignSelf: 'stretch' }, 'aria-hidden': 'true' }),
      h('div.pane', { dataset: { pane: 'trailing' }, style: { width: g.trailing + 'px' } }, o.trailing));
    return s;
  };

  /**
   * Fold columns (UKFoldColumns; design/section-sides.md, owner 2026-11-03): only while a Duo is partly folded (`ctx.splitAtHinge`), each section sits
   * wholly in the leading or the trailing region, stacked top to bottom in one page scroll; strips in `top` (the status rail) span both. Returns null in
   * every other pose (flat Duo, folded, portrait, iPad, iPhone), so the page draws its own layout there, unchanged.
   * The first trailing section starts level with the leading column, directly under the top strip (section-sides.md rule 11, owner 2026-11-03:
   * "Cameras top right like home page"). At an accessibility text size the rail wraps and stops short of the fold (status-rail.md), so `top`
   * heads the leading column instead of spanning, and the trailing column (Cameras) starts at the top right, level with the rail.
   * @param {object} ctx
   * @param {{top?:Node[], leading:Node[], trailing:Node[]}} o  the page's fixed assignment (never balanced by live height)
   * @returns {Node[]|null}
   */
  Mock.foldColumns = function (ctx, o) {
    if (!ctx.splitAtHinge || !ctx.splitGeometry) return null;
    var keep = function (a) { return [].concat(a || []).filter(Boolean); };
    var top = keep(o.top), lead = keep(o.leading);
    if (ctx.axSize && top.length) { lead = top.concat(lead); top = []; }
    var sp = Mock.split(ctx, { leading: lead, trailing: keep(o.trailing) });
    sp.dataset.fold = 'columns';
    return top.concat([sp]);
  };

  /**
   * A detail pane that fills the window beside a page (the trailing half of a list and detail page: Recipes, Inventory): full height under the bar,
   * from the divider to the rail. The page's scroll area and floating bar are inset by the leading pane's complement (`--split-inset`), so the whole
   * page narrows to the leading pane; Mock.reflow animates the inset and the pane's `left`.
   * @param {object} ctx
   * @param {HTMLElement} page the .ui-page from Mock.page
   * @param {Node|Node[]} content the pane's content
   * @param {{top?:number, zIndex?:number}} [o] top defaults to the bottom of the bar
   * @returns {HTMLElement} the pane (also appended to `page`)
   */
  Mock.detailPane = function (ctx, page, content, o) {
    o = o || {};
    var g = ctx.splitGeometry || { leading: Math.floor(ctx.contentW / 2), band: 1, trailing: ctx.contentW - Math.floor(ctx.contentW / 2) - 1 };
    var inset = ctx.contentW - g.leading;
    page.style.setProperty('--split-inset', inset + 'px');
    var pane = h('div.ui-detail-pane', { dataset: { detailPane: ctx.splitAtHinge ? 'hinge' : 'midpoint', band: g.band }, style: { top: (o.top == null ? ctx.device.barTop + 44 : o.top) + 'px', left: (g.leading + g.band) + 'px', right: ctx.rail + 'px', zIndex: o.zIndex || 6 } }, content);
    page.appendChild(pane);
    return pane;
  };

  /**
   * Demo of a sheet presenting over the stage's current page and dismissing again (for the Transitions list). The page becomes the presenter,
   * the system sheet slides up (presenter scales back and dims), holds, then slides down. Reduce Motion cross-fades (Mock.anim.sheet).
   * @param {HTMLElement} stage the .screen from play(stage); @param {object} sheetOpts as Mock.sheet; @param {{hold?:number}} [o]
   */
  Mock.presentDemo = function (stage, sheetOpts, o) {
    var ctx = Mock.current, page = stage.querySelector('.ui-page');
    if (!page || !ctx) return Promise.resolve();
    var parent = page.parentNode, next = page.nextSibling;
    var host = Mock.sheet(ctx, Object.assign({}, sheetOpts, { presenter: page }));
    parent.insertBefore(host, next);
    return Mock.anim.sheet(host, 'in').then(function () { return Mock.sleep((o && o.hold) || 900); }).then(function () { return Mock.anim.sheet(host, 'out'); }).then(function () {
      page.style.transform = ''; parent.insertBefore(page, host); host.remove();
    });
  };

  /**
   * A presented modal over an optional presenter page.
   * @param {object} ctx
   * @param {{title:string, subtitle?:string, detent?:'medium'|'large'|'fitted', size?:'page'|'form', leading?:'none'|'back'|'cancel'|Node,
   *   trailing?:'close'|'confirm'|'none'|Node, confirm?:{enabled?:boolean, busy?:boolean, title?:string}, content:Node|Node[], tabs?:Node,
   *   appearance?:'system'|'dark', presenter?:Node, alert?:Node, grabber?:boolean}} o
   *   detent: compact width opens at medium (about half the window), large (below the status bar) or fitted (the header, the content and ONE bottom band, the
   *   home-indicator safe area, capped at large; hassSheet's default). The band is drawn once: since 2026-10-28 the app's detent no longer asks for the safe area
   *   the system adds to a custom detent, so a real fitted sheet has exactly this one band (`proposals/sheet-bottom-gap`, option B; it used to have two). Regular width ignores detents except `large`: iPad and the unfolded Duo present a centred form (540 pt)
   *   or page (704 pt) sheet, fitted to the content (iOS 18 and later). appearance 'dark' = always dark (Weather, camera viewer, Login,
   *   Location permission); otherwise the sheet follows ctx.appearance (the Appearance control). The presenter scales back and dims (compact).
   */
  Mock.sheet = function (ctx, o) {
    var K = C(), d = ctx.device;
    var dark = o.appearance === 'dark' || ctx.appearance === 'dark';
    var detent = o.detent || 'fitted';
    var compact = ctx.compact;
    var host = h('div.ui-host' + (compact ? '' : '.regular'), { dataset: { indicator: !dark && compact ? 'dark' : 'light' }, style: { display: 'flex', justifyContent: 'center', alignItems: compact ? 'flex-end' : 'center' } });
    if (o.presenter) {
      var pres = h('div.ui-presenter', o.presenter);
      if (compact) { pres.style.transform = 'translateY(10px) scale(.92)'; pres.style.borderRadius = '38px'; }
      host.appendChild(pres);
    }
    host.appendChild(h('div.ui-dim'));
    var panel = h('div.ui-sheet.in-sheet.' + (dark ? 'g-dark' : 'g-light'), { role: 'dialog', aria: { modal: 'true', label: o.title }, dataset: { detent: detent, size: o.size || 'form' } });
    panel.style.position = 'relative';
    var top = d.sheetTop;
    if (compact) {
      panel.style.width = '100%'; panel.style.borderRadius = '38px 38px 0 0'; panel.style.paddingBottom = d.safeBottom + 'px';
      if (detent === 'medium') panel.style.height = '50%';
      else if (detent === 'large') panel.style.height = 'calc(100% - ' + top + 'px)';
      else panel.style.maxHeight = 'calc(100% - ' + top + 'px)';
    } else {
      var width = Math.min(o.size === 'page' ? 704 : 540, d.w - 64);
      panel.style.width = width + 'px'; panel.style.borderRadius = '28px'; panel.style.boxShadow = '0 20px 60px rgba(0,0,0,.45)';
      var maxH = d.h - 2 * top;
      if (detent === 'large') panel.style.height = Math.min(maxH, o.size === 'page' ? maxH : 620) + 'px'; else panel.style.maxHeight = maxH + 'px';
      panel.style.paddingBottom = '8px';
    }
    if (o.grabber !== false && compact) panel.appendChild(h('div.grab'));
    panel.appendChild(K.HassModal({ title: o.title, subtitle: o.subtitle, leading: o.leading, trailing: o.trailing, confirm: o.confirm, content: o.content, tabs: o.tabs, fitted: detent === 'fitted' }));
    host.appendChild(panel);
    if (o.alert) host.appendChild(o.alert.classList && o.alert.classList.contains('ui-confirm-scrim') ? o.alert : h('div.ui-alert-scrim.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light'), o.alert));   // a ConfirmationDialog brings its own scrim
    return host;
  };

  /* ---------------------------------------------------------------------------------------------------------------------------------------
   * Mock.scrollFit: the "scroll only when there is something to scroll" rule (patterns/scroll-fit.md), measured instead of asserted.
   * A vertical scroller whose content fits its viewport is static (no bounce, no drag response, no indicator); one whose content is taller scrolls.
   * The decision is geometry: content height (scrollHeight) against viewport height (clientHeight), never a device name. It is a measuring helper
   * and a drawing aid, so a mockup can show the rule per device and text size from what it really rendered.
   *
   *   Mock.scrollFit(el)                 -> {kind, content, viewport, over, scrolls, always, cap, label, short}   one .ui-scroll (page) or .ui-mscroll (sheet)
   *   Mock.scrollFit.list(root)          -> the vertical scrollers under root (skips the presenter page behind a sheet)
   *   Mock.scrollFit.mark(root, o)       -> measures every scroller, sets data-fit / data-fit-over, and (o.indicator) draws the indicator only when it scrolls
   *   Mock.scrollFit.badge(root, o)      -> a live annotation node (one row per scroller); re-measures when the content resizes
   *   Mock.scrollFit.bounce(root, o)     -> Promise: a drag past the end. Scrolling stretches and springs back; static does nothing; o.always (pull to refresh) stretches
   * Options: {always: true (pull-to-refresh: always bounces), indicator: true, lock: true (a static scroller gets overflow-y hidden), refresh: true (bounce shows the spinner)}
   * Enabled for a whole mockup with `scrollFit: {indicator, lock, always}` in the Mock.mount config (the stage and the States gallery get a badge under each device).
   * Note on the numbers: a page's content includes the space reserved under the floating tab bar (the safe-area inset SwiftUI also counts), and the viewport
   * is the full screen height (the scroll view runs under the header); a sheet's viewport is the area under its header.
   * ------------------------------------------------------------------------------------------------------------------------------------- */
  var SF_SEL = '.ui-scroll, .ui-mscroll';
  function sfList(root) {
    return [].filter.call(root.querySelectorAll(SF_SEL), function (s) { return !s.closest('.ui-presenter') && !s.closest('[data-fit-ignore]'); });
  }
  function sfCap(el) {   // a fitted sheet grows with its content up to this viewport height (the large-detent cap)
    var panel = el.closest('.ui-sheet'); if (!panel || panel.dataset.detent !== 'fitted') return null;
    var mh = getComputedStyle(panel).maxHeight; if (!mh || mh === 'none') return null;
    var keepH = panel.style.height, keepMax = panel.style.maxHeight, before = panel.offsetHeight, chrome = before - el.clientHeight;
    panel.style.maxHeight = 'none'; panel.style.height = mh;
    var capPanel = panel.offsetHeight;
    panel.style.height = keepH; panel.style.maxHeight = keepMax;
    return Math.max(0, Math.round(capPanel - chrome));
  }
  function sfLabel(r) {
    var pt = function (n) { return n + ' pt'; };
    if (r.always && !r.scrolls) return 'Bounces · pull to refresh (content ' + pt(r.content) + ' ≤ viewport ' + pt(r.viewport) + '; always bounces)';
    if (r.scrolls) return 'Scrolls · overflows by ' + pt(r.over) + (r.cap != null ? ' (content ' + pt(r.content) + ', sheet capped at ' + pt(r.viewport) + ')' : ' (content ' + pt(r.content) + ' > viewport ' + pt(r.viewport) + ')');
    if (r.cap != null) return 'Static · fits (content ' + pt(r.content) + ' ≤ cap ' + pt(r.cap) + '; the sheet is fitted to its content)';
    return 'Static · fits (content ' + pt(r.content) + ' ≤ viewport ' + pt(r.viewport) + ')';
  }
  Mock.scrollFit = function (el, o) {
    o = o || {};
    var viewport = Math.round(el.clientHeight), content = Math.round(el.scrollHeight);
    if (content <= viewport) {   // scrollHeight never reports less than the viewport: read where the content really ends (a zero-height probe, plus the bottom padding)
      var probe = document.createElement('div'); probe.style.cssText = 'display:block;height:0;margin:0;padding:0;border:0;flex:none;clear:both;'; el.appendChild(probe);
      content = Math.min(viewport, Math.round(probe.offsetTop + (parseFloat(getComputedStyle(el).paddingBottom) || 0))); probe.remove();
    }
    var over = content - viewport;
    var r = { kind: el.classList.contains('ui-mscroll') ? 'sheet' : 'page', content: content, viewport: viewport, over: Math.max(0, over), scrolls: over >= 1, always: !!(o.always || el.dataset.fitAlways === 'true'), cap: null };
    r.cap = r.kind === 'sheet' ? sfCap(el) : null;
    r.label = sfLabel(r);
    r.short = r.scrolls ? 'Scrolls' : (r.always ? 'Bounces' : 'Static');
    return r;
  };
  Mock.scrollFit.list = sfList;
  Mock.scrollFit.label = sfLabel;

  function sfIndicator(el, r, o) {
    var host = el.offsetParent || el.parentNode, bar = el._sbar;
    if (!r.scrolls || !o.indicator) { if (bar) bar.hidden = true; return; }
    if (!bar) {
      bar = el._sbar = Mock.h('div.k-sbar', { 'aria-hidden': 'true', dataset: { fitIndicator: 'true' } });
      host.appendChild(bar);
      el.addEventListener('scroll', function () { if (el._sbarUpdate) el._sbarUpdate(); });
    }
    bar.hidden = false;
    el._sbarUpdate = function () {
      var rr = el._fit || r, top = parseFloat(getComputedStyle(host).getPropertyValue('--bar-bottom')) || 0, inset = el.classList.contains('ui-mscroll') ? 6 : 6;
      var trackTop = el.offsetTop + (el.classList.contains('ui-scroll') ? top : 0) + inset, trackH = el.clientHeight - (el.classList.contains('ui-scroll') ? top : 0) - 2 * inset - (el.classList.contains('ui-scroll') ? 20 : 0);
      var thumb = Math.max(36, Math.round(trackH * rr.viewport / rr.content)), pos = rr.over > 0 ? el.scrollTop / rr.over : 0;
      bar.style.height = thumb + 'px'; bar.style.top = Math.round(trackTop + pos * (trackH - thumb)) + 'px';
      bar.style.right = Math.max(2, host.clientWidth - el.offsetLeft - el.clientWidth + 3) + 'px';
    };
    el._sbarUpdate();
  }
  /** Measure every scroller under root, tag it and draw/hide its indicator. Returns the measurements. */
  Mock.scrollFit.mark = function (root, o) {
    o = o || {};
    return sfList(root).map(function (el) {
      var r = Mock.scrollFit(el, o); el._fit = r;
      el.dataset.fit = r.scrolls ? 'scrolls' : (r.always ? 'bounces' : 'static'); el.dataset.fitOver = String(r.over);
      if (o.always) el.dataset.fitAlways = 'true';
      if (o.lock && !r.scrolls && !r.always) el.style.overflowY = 'hidden'; else if (o.lock) el.style.overflowY = '';
      sfIndicator(el, r, o);
      return r;
    });
  };
  /** A live annotation for the scrollers under root (and any horizontal chip rail, which the rule leaves alone). */
  Mock.scrollFit.badge = function (root, o) {
    o = o || {};
    var box = Mock.h('div.k-fit', { role: 'note', 'aria-label': 'Scroll fit measurement' });
    function paint() {
      if (!root.isConnected) return;
      var rs = Mock.scrollFit.mark(root, o);
      box.innerHTML = '';
      sfList(root).forEach(function (el, i) {
        var r = rs[i], what = r.kind === 'sheet' ? 'Sheet' : 'Page';
        box.appendChild(Mock.h('div.k-fitrow.' + (r.scrolls ? 'scrolls' : (r.always ? 'bounces' : 'static')), Mock.h('b', what + ': '), r.label));
      });
      [].forEach.call(root.querySelectorAll('.ui-rail-chips.scroll'), function (rail) {
        if (rail.closest('.ui-presenter')) return;
        box.appendChild(Mock.h('div.k-fitrow.horizontal', Mock.h('b', 'Chip rail (horizontal): '), (rail.scrollWidth > rail.clientWidth + 1 ? 'scrolls sideways' : 'fits') + ' · out of scope, keeps its own behavior'));
      });
      if (!box.firstChild) box.appendChild(Mock.h('div.k-fitrow', 'No vertical scroller on this surface.'));
    }
    var pend = false;
    function later() { if (pend) return; pend = true; requestAnimationFrame(function () { pend = false; paint(); }); }
    requestAnimationFrame(function () { requestAnimationFrame(function () {
      paint();
      if (window.ResizeObserver) {
        var ro = new ResizeObserver(later);
        sfList(root).forEach(function (el) { ro.observe(el); [].forEach.call(el.children, function (c) { ro.observe(c); }); });
        box._ro = ro;
      }
      if (document.fonts && document.fonts.ready) document.fonts.ready.then(later);
    }); });
    return box;
  };
  /** A drag past the end of every scroller under root. Scrolling: stretches and springs back. Static: nothing moves. o.always / o.refresh: pull to refresh. */
  Mock.scrollFit.bounce = function (root, o) {
    o = o || {};
    var reduce = Mock.settings && Mock.settings.reduceMotion;
    var jobs = sfList(root).map(function (el) {
      var r = Mock.scrollFit(el, o), moves = r.scrolls || r.always || o.always;
      el.classList.add('k-fit-flash'); el.dataset.fitFlash = moves ? 'moves' : 'still';
      var host = el.offsetParent || el.parentNode, spin = null;
      if (o.refresh && moves) {
        var top = (parseFloat(getComputedStyle(host).getPropertyValue('--bar-bottom')) || 0) + 8;
        spin = Mock.h('div.k-pull', { style: { top: top + 'px' } }, Mock.components.ArcSpinner({ size: 'compact', label: 'Refreshing' })); host.appendChild(spin);
      }
      var done = function () { el.classList.remove('k-fit-flash'); delete el.dataset.fitFlash; if (spin) spin.remove(); };
      if (!moves || reduce || !el.animate) return Mock.sleep(moves ? 600 : 900).then(done);   // reduced: a held outline, no travel
      var px = o.refresh ? 56 : 44;
      return el.animate([{ transform: 'translateY(0)', easing: 'cubic-bezier(.2,.8,.3,1)' }, { transform: 'translateY(' + px + 'px)', offset: .32, easing: 'cubic-bezier(.3,1.25,.5,1)' }, { transform: 'translateY(' + (o.refresh ? px : 0) + 'px)' }], { duration: o.refresh ? 700 : 900, fill: 'forwards' }).finished
        .then(function () { return o.refresh ? Mock.sleep(900) : null; })
        .then(function () { return o.refresh ? el.animate([{ transform: 'translateY(' + px + 'px)' }, { transform: 'translateY(0)' }], { duration: 400, easing: 'cubic-bezier(.3,0,.2,1)', fill: 'forwards' }).finished : null; })
        .then(function () { el.getAnimations().forEach(function (a) { a.cancel(); }); done(); });
    });
    return Promise.all(jobs);
  };
})();
