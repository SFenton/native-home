/* Mock.reflow: animate a landscape window's on-demand split (Mock.split panes, Mock.detailPane) and the Duo's hinge posture.
 *
 * Two moves, both on `.screen` of a staged device:
 *   open / close  the split opens (the root page springs to the leading pane and the detail slides in) or closes again; any landscape window
 *                 that may split (iPad landscape, unfolded Duo landscape in either posture).
 *   posture       the Duo hinge goes from fully open (flat) to slightly closed (book pose) or back: the physical band cross-fades between the flat
 *                 seam and the fold's crease, and an open split's divider slides between the midpoint of the free space and the hinge.
 *
 * Duration and curve: MotionTokens.standard (a smooth 0.3 s, no bounce), 0.2 s under Reduce Motion, which also drops the sliding: the geometry cuts
 * and the page cross-fades (motion.md section 7; OnDemandSplit.swift animates the open item with `standard`, reduced `quick`). Moving the divider
 * for a posture change is the owner's 2026-10-24 rule and in flight: the app's layout follows the hinge rect it is handed, and the mockup shows the
 * motion it should have (the same token) rather than a cut.
 *
 * Content reflows live: the panes animate their real `width`, so a TileGrid recounts its columns every frame and text rewraps. A component that
 * computes a fixed width when it is drawn (the weather card's hour count, a carousel) keeps its width until the next render and is not resized
 * mid-move; each mockup that has one says so in its notes.
 */
(function () {
  var A = Mock.anim, R = Mock.reflow = {};
  function rm() { return !!Mock.settings.reduceMotion; }
  function px(n) { return n.toFixed(2) + 'px'; }
  function anim(el, frames, ms) {
    if (!el || !el.animate) return Promise.resolve();
    var a = el.animate(frames, { duration: ms, easing: A.easing.standard, fill: 'both' });
    return a.finished.catch(function () {});
  }
  /** What a staged device holds that can reflow: `.ui-split[data-split]` containers and `[data-detail-pane]` panes. */
  R.find = function (root) {
    return { panes: [].slice.call(root.querySelectorAll('.ui-split[data-split]')), details: [].slice.call(root.querySelectorAll('[data-detail-pane]')) };
  };
  /** True when the staged device has a split to animate. */
  R.has = function (root) { var f = R.find(root); return !!(f.panes.length || f.details.length); };

  function setPanes(split, g) {
    var k = split.children;
    k[0].style.width = px(g.leading); k[1].style.width = px(g.band); k[2].style.width = px(g.trailing);
  }
  function setDetail(pane, ctx, g) {
    var page = pane.closest('.ui-page'), rail = ctx.rail;
    pane.style.left = px(g.leading + g.band);
    if (page) {
      page.style.setProperty('--split-inset', px(ctx.contentW - g.leading));
    }
  }
  /** The frame keyframes for one detail pane's page: the scroll area and the floating bar narrow with the leading pane. */
  function detailTargets(pane) { var page = pane.closest('.ui-page'); return page ? [].slice.call(page.querySelectorAll('.ui-scroll, .ui-actions-slot')) : []; }

  /**
   * Move every split in `root` from one frame to another.
   * @param {HTMLElement} root the staged .screen
   * @param {object} ctx the render ctx (contentW, rail)
   * @param {{leading:number,band:number,trailing:number}} from
   * @param {{leading:number,band:number,trailing:number}} to
   * @param {{reveal?:'in'|'out'|null, ms?:number}} [o] reveal: the trailing pane fades in (opening) or out (closing) while it moves
   * @returns {Promise} resolves when the move ends (the panes rest at `to`)
   */
  R.move = function (root, ctx, from, to, o) {
    o = o || {};
    var f = R.find(root), ms = o.ms || (rm() ? A.ms.quick() : A.ms.standard()), jobs = [];
    if (rm()) {   // Reduce Motion: no sliding; cut to the end geometry and cross-fade the page
      f.panes.forEach(function (s) { setPanes(s, to); });
      f.details.forEach(function (p) { setDetail(p, ctx, to); });
      return anim(root.querySelector('.ui-page') || root, [{ opacity: .35 }, { opacity: 1 }], ms);
    }
    f.panes.forEach(function (s) {
      var k = s.children;
      setPanes(s, to);
      jobs.push(anim(k[0], [{ width: px(from.leading) }, { width: px(to.leading) }], ms));
      jobs.push(anim(k[1], [{ width: px(from.band) }, { width: px(to.band) }], ms));
      jobs.push(anim(k[2], [{ width: px(from.trailing), opacity: o.reveal === 'in' ? 0 : 1 }, { width: px(to.trailing), opacity: o.reveal === 'out' ? 0 : 1 }], ms));
    });
    f.details.forEach(function (p) {
      setDetail(p, ctx, to);
      var r0 = ctx.rail + (ctx.contentW - from.leading), r1 = ctx.rail + (ctx.contentW - to.leading);
      jobs.push(anim(p, [{ left: px(from.leading + from.band), opacity: o.reveal === 'in' ? 0 : 1 }, { left: px(to.leading + to.band), opacity: o.reveal === 'out' ? 0 : 1 }], ms));
      detailTargets(p).forEach(function (el) { jobs.push(anim(el, [{ right: px(r0) }, { right: px(r1) }], ms)); });
    });
    return Promise.all(jobs);
  };

  /** Open the split (`dir` 'open') from a single page to the geometry in ctx, or close it ('close') the other way. */
  R.split = function (root, ctx, dir) {
    var g = ctx.splitGeometry; if (!g) return Promise.resolve();
    var closed = Mock.closedFrame(ctx.contentW);
    return dir === 'close' ? R.move(root, ctx, g, closed, { reveal: 'out' }) : R.move(root, ctx, closed, g, { reveal: 'in' });
  };

  /**
   * The Duo's hinge from one posture to the other. `ctxFrom` and `ctxTo` are Mock.ctx for the same device in each posture; the band cross-fades
   * and any open split slides from one geometry to the other.
   */
  R.posture = function (root, ctxFrom, ctxTo) {
    var ms = rm() ? A.ms.quick() : A.ms.standard();
    var band = root.querySelector('.k-hinge');
    if (band) { band.style.setProperty('--k-posture-ms', ms + 'ms'); band.dataset.posture = ctxTo.posture; var l = band.querySelector('.k-hinge-label'); if (l) l.textContent = Mock.postures[ctxTo.posture].short; }
    root.dataset.posture = ctxTo.posture;
    var a = ctxFrom.splitGeometry, b = ctxTo.splitGeometry;
    var moved = a && b && R.has(root) ? R.move(root, ctxTo, a, b, { ms: ms }) : Promise.resolve();
    return Promise.all([moved, Mock.sleep(ms + 40)]);
  };
})();
