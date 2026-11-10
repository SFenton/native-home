/* Mock.anim: motion helpers for the Motion and Transitions lists (Play buttons).
 *
 * Every helper returns a Promise that resolves when the motion ends, honours the Reduce Motion switch (Mock.settings.reduceMotion)
 * and cites the section of .agents/design/motion.md (and the pattern record) that fixes its duration and curve. Durations are the
 * app's `MotionTokens` (HassDesign/Motion/MotionTokens.swift): never invent one here; if a mockup needs a new value, motion.md
 * changes first (owner approval) and then this file.
 *
 *   quick 0.2 s easeOut | state 0.6 s easeInOut (0.2 s reduced) | standard 0.3 s smooth | emphasized spring 0.5 s | stagger 0.06 s
 */
(function () {
  var A = Mock.anim = {};
  function rm() { return !!Mock.settings.reduceMotion; }
  function done(a) { return a && a.finished ? a.finished.catch(function () {}) : Promise.resolve(); }
  function go(el, frames, opts) {
    if (!el || !el.animate) return Promise.resolve();
    return done(el.animate(frames, Object.assign({ fill: 'both' }, opts)));
  }
  function q(root, sel) { return typeof sel === 'string' ? root.querySelector(sel) : sel; }
  function qa(root, sel) { return typeof sel === 'string' ? Array.prototype.slice.call(root.querySelectorAll(sel)) : sel; }
  /** Durations in ms, as MotionTokens (the reduced value applies when Reduce Motion is on). */
  A.ms = {
    quick: function () { return 200; },                  // motion.md section 7 `quick`: .easeOut 0.2 s
    state: function () { return rm() ? 200 : 600; },     // `state`: .easeInOut 0.6 s, 0.2 s reduced
    standard: function () { return 300; },               // `standard`: .smooth 0.3 s
    emphasized: function () { return 500; },             // `emphasized`: spring(response .5, damping .8), the intro mark only
    stagger: function () { return 60; },                 // `arrivalStagger`: 0.06 s per item, first screenful only (cap 8)
    moment: function () { return 350; },                 // section 8: moments under Reduce Motion: cross-fade, about 0.35 s total
  };
  A.easing = { quick: 'cubic-bezier(0,0,.2,1)', state: 'ease-in-out', standard: 'cubic-bezier(.4,0,.2,1)', sheet: 'cubic-bezier(.32,.72,0,1)', push: 'cubic-bezier(.25,.1,.25,1)' };
  /** Remove every running animation under root so a Play always starts from the resting state. */
  A.reset = function (root) {
    (root.getAnimations ? root.getAnimations({ subtree: true }) : []).forEach(function (a) { a.cancel(); });
  };
  A.sleep = Mock.sleep;

  /** Opacity change. motion.md section 7 `quick` (numbers, small fades, button state): 0.2 s easeOut. */
  A.fade = function (el, o) {
    o = o || {}; el = q(document, el);
    return go(el, [{ opacity: o.from == null ? 0 : o.from }, { opacity: o.to == null ? 1 : o.to }], { duration: o.ms || A.ms.quick(), easing: A.easing.quick });
  };
  /** Content gate entrance: fades in and rises 4 pt in 170 ms; Reduce Motion keeps the fade and drops the rise.
   *  motion.md section 3 (network-backed page, nothing saved) and patterns/content-gate.md sequence step 3. */
  A.rise = function (el, o) {
    o = o || {};
    var dy = rm() ? 0 : (o.dy == null ? 4 : o.dy);
    return go(el, [{ opacity: 0, transform: 'translateY(' + dy + 'px)' }, { opacity: 1, transform: 'none' }], { duration: o.ms || 170, easing: 'ease-out' });
  };
  /** A state-driven colour change (fill, tint, rim): cross-fade in 0.6 s easeInOut, 0.2 s under Reduce Motion, colour only.
   *  motion.md section 6 "Background colour changes are always animated" and section 7 `state`. prop is a camelCase CSS property. */
  A.stateColor = function (el, prop, to, o) {
    var from = getComputedStyle(el)[prop], f = {}, t = {};
    f[prop] = from; t[prop] = to;
    return go(el, [f, t], { duration: (o && o.ms) || A.ms.state(), easing: A.easing.state });
  };
  /** Flip a tile or chip between two class sets; the registered colour slots in kit.css cross-fade for `state` (0.6 s).
   *  motion.md section 6 (tiles lit/unlit, chips filled/unfilled). Resolves after the transition. */
  A.toggleState = function (el, add, remove) {
    (remove || []).forEach(function (c) { el.classList.remove(c); });
    (add || []).forEach(function (c) { el.classList.add(c); });
    return Mock.sleep(A.ms.state() + 30);
  };
  /** Numbers roll: only the digits that change slide, 0.2 s (`quick`). Reduce Motion: a plain cross-fade.
   *  motion.md section 6 "Numbers": contentTransition(.numericText(value:)) with MotionTokens.quick. */
  A.roll = function (el, next, o) {
    el = q(document, el); var prev = el.textContent, ms = (o && o.ms) || A.ms.quick();
    if (rm()) { el.textContent = next; return go(el, [{ opacity: 0 }, { opacity: 1 }], { duration: ms, easing: A.easing.quick }); }
    el.textContent = '';
    var anims = [];
    for (var i = 0; i < next.length; i++) {
      var n = next[i], p = prev[i - (next.length - prev.length)] || '';
      if (n === p || !/\d/.test(n)) { el.appendChild(document.createTextNode(n)); continue; }
      var down = (parseInt(n, 10) || 0) > (parseInt(p, 10) || 0);
      var box = Mock.h('span', { style: { display: 'inline-block', overflow: 'hidden', verticalAlign: 'top', height: '1.12em', lineHeight: '1.12', position: 'relative' } });
      var old = Mock.h('span', { style: { display: 'block' } }, p || ' '), neu = Mock.h('span', { style: { display: 'block' } }, n);
      var col = Mock.h('span', { style: { display: 'block' } }, down ? [old, neu] : [neu, old]);
      box.appendChild(col); el.appendChild(box);
      anims.push(go(col, down ? [{ transform: 'translateY(0)' }, { transform: 'translateY(-50%)' }] : [{ transform: 'translateY(-50%)' }, { transform: 'translateY(0)' }], { duration: ms, easing: A.easing.quick }));
    }
    return Promise.all(anims).then(function () { el.textContent = next; });
  };
  /** The tick of a weather condition label that overflows: 30 pt/s, 1.5 s holds, soft fade at both edges, three passes then it rests.
   *  Exception to motion.md sections 9.6 and 9.10, recorded in design/weather-card-header.md. No ticker under Reduce Motion. */
  A.ticker = function (box) {
    var tk = box.firstElementChild, over = tk.offsetWidth - (box.clientWidth - 16);
    tk.getAnimations().forEach(function (a) { a.cancel(); });
    box.classList.toggle('over', over > 1);
    if (over <= 1 || rm() || !tk.animate) return Promise.resolve();
    var shift = over + 16, hold = 1500, run = shift / 30 * 1000, total = 2 * hold + 2 * run;
    return done(tk.animate([
      { transform: 'translateX(0)', offset: 0 }, { transform: 'translateX(0)', offset: hold / total },
      { transform: 'translateX(' + (-shift) + 'px)', offset: (hold + run) / total }, { transform: 'translateX(' + (-shift) + 'px)', offset: (2 * hold + run) / total },
      { transform: 'translateX(0)', offset: 1 }], { duration: total, iterations: 3, easing: 'linear' }));
  };
  /** Arrival stagger: items rise 16 pt with 60 ms between them, the first screenful only (cap 8). Reduce Motion: one 0.35 s cross-fade.
   *  motion.md section 3 (sign-in to Home) and section 7 `arrivalStagger`. */
  A.stagger = function (els, o) {
    els = els.slice(0, (o && o.max) || 8);
    if (rm()) return Promise.all(els.map(function (e) { return go(e, [{ opacity: 0 }, { opacity: 1 }], { duration: A.ms.moment() }); }));
    return Promise.all(els.map(function (e, i) {
      return go(e, [{ opacity: 0, transform: 'translateY(' + ((o && o.dy) || 16) + 'px)' }, { opacity: 1, transform: 'none' }],
        { duration: 400, delay: i * A.ms.stagger(), easing: A.easing.standard, fill: 'backwards' });
    }));
  };
  /** Home arrival after sign-in (about 0.9 s, once per session): wallpaper settles 1.06 to 1, header fades up, chips slide in 30 pt from
   *  the right, cards rise with a 60 ms stagger, the tab bar rises. Reduce Motion: cross-fades only (about 0.35 s).
   *  motion.md section 3 row "Sign in to Home", direction-g.md "Launch and sign-in motion". stage = the .screen element. */
  A.arrival = function (stage) {
    A.reset(stage);
    var wall = stage.querySelector('.ui-wall'), bar = stage.querySelector('.ui-bar'), chips = qa(stage, '.ui-rail-chips .ui-chip'),
        cards = qa(stage, '.ui-body > *:not(.ui-bleed)'), tabs = stage.querySelector('.ui-tabbar, .ui-rail'), title = stage.querySelector('.ui-title-wrap');
    if (rm()) return Promise.all([wall, bar, title, tabs].concat(chips, cards).filter(Boolean).map(function (e) { return go(e, [{ opacity: 0 }, { opacity: 1 }], { duration: A.ms.moment() }); }));
    var out = [];
    if (wall) out.push(go(wall, [{ opacity: 0, transform: 'scale(1.06)' }, { opacity: 1, transform: 'scale(1)' }], { duration: 700, easing: 'ease-out' }));
    if (bar) out.push(go(bar, [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }], { duration: 400, delay: 150, easing: A.easing.standard, fill: 'backwards' }));
    if (title) out.push(go(title, [{ opacity: 0, transform: 'translateY(10px)' }, { opacity: 1, transform: 'none' }], { duration: 400, delay: 150, easing: A.easing.standard, fill: 'backwards' }));
    chips.forEach(function (c) { out.push(go(c, [{ opacity: 0, transform: 'translateX(30px)' }, { opacity: 1, transform: 'none' }], { duration: 450, delay: 220, easing: A.easing.standard, fill: 'backwards' })); });
    cards.forEach(function (c, i) { if (i < 8) out.push(go(c, [{ opacity: 0, transform: 'translateY(16px)' }, { opacity: 1, transform: 'none' }], { duration: 400, delay: 300 + i * A.ms.stagger(), easing: A.easing.standard, fill: 'backwards' })); });
    if (tabs) out.push(go(tabs, [{ opacity: 0, transform: 'translateY(40px)' }, { opacity: 1, transform: 'none' }], { duration: 450, delay: 350, easing: A.easing.standard, fill: 'backwards' }));
    return Promise.all(out);
  };
  /** The reconnecting arc: fades in over 0.35 s ease-in-out once the connection has been down 2 s, out over 0.35 s when live again.
   *  ReconnectingArc.swift. slot = the .ui-slot element. */
  A.arc = function (slot, on) {
    slot.hidden = false; void slot.offsetWidth; slot.classList.toggle('on', !!on);
    return Mock.sleep(380).then(function () { if (!on) slot.hidden = true; });
  };
  /** System sheet present or dismiss: slides up (or down) with the system spring, the presenter scales back and dims; Reduce Motion
   *  cross-fades. motion.md section 2 table, "Modal": the system sheet, never decorated. dir = 'in' | 'out'. */
  A.sheet = function (host, dir) {
    var sheet = host.querySelector('.ui-sheet'), dim = host.querySelector('.ui-dim'), pres = host.querySelector('.ui-presenter');
    var inn = dir !== 'out', out = [], d = rm() ? 250 : 500;
    var s = rm() ? (inn ? [{ opacity: 0 }, { opacity: 1 }] : [{ opacity: 1 }, { opacity: 0 }]) : (inn ? [{ transform: 'translateY(100%)' }, { transform: 'none' }] : [{ transform: 'none' }, { transform: 'translateY(100%)' }]);
    if (sheet) out.push(go(sheet, s, { duration: d, easing: A.easing.sheet }));
    if (dim) out.push(go(dim, inn ? [{ opacity: 0 }, { opacity: 1 }] : [{ opacity: 1 }, { opacity: 0 }], { duration: d, easing: A.easing.sheet }));
    if (pres && !rm()) { var t = pres.style.transform || 'none'; out.push(go(pres, inn ? [{ transform: 'none' }, { transform: t }] : [{ transform: t }, { transform: 'none' }], { duration: d, easing: A.easing.sheet })); }
    return Promise.all(out);
  };
  /** System push: the new page slides in from the trailing edge, the old one shifts left about 30% and dims; the edge swipe back is
   *  interactive. Reduce Motion: cross-fade. motion.md section 2 and 4.2 (never replaced, slowed or decorated); about 0.35 s. */
  A.push = function (outEl, inEl, o) {
    var back = o && o.back;
    if (rm()) return Promise.all([go(outEl, [{ opacity: 1 }, { opacity: 0 }], { duration: A.ms.moment() }), go(inEl, [{ opacity: 0 }, { opacity: 1 }], { duration: A.ms.moment() })]);
    var d = 350, e = A.easing.push;
    return Promise.all([
      go(outEl, back ? [{ transform: 'translateX(0)' }, { transform: 'translateX(100%)' }] : [{ transform: 'translateX(0)', filter: 'brightness(1)' }, { transform: 'translateX(-30%)', filter: 'brightness(.7)' }], { duration: d, easing: e }),
      go(inEl, back ? [{ transform: 'translateX(-30%)', filter: 'brightness(.7)' }, { transform: 'translateX(0)', filter: 'brightness(1)' }] : [{ transform: 'translateX(100%)' }, { transform: 'translateX(0)' }], { duration: d, easing: e })]);
  };
  /** Single-page push and pop of the UIKit port (design/single-page-motion.md S2): the columns' motion with one column. Both pages move a
   *  full width over the still wallpaper, the new one in from the trailing edge and the old one out by the leading edge (Back reverses it),
   *  on `standard` (smooth spring 0.3 s); no dim, shadow or fade. Reduce Motion: a 0.2 s cross-fade in place. outEl and inEl are the
   *  pages, transparent, over a wallpaper that does not move; o.back reverses. */
  A.slide = function (outEl, inEl, o) {
    var back = o && o.back;
    if (rm()) return Promise.all([go(outEl, [{ opacity: 1 }, { opacity: 0 }], { duration: A.ms.quick() }), go(inEl, [{ opacity: 0 }, { opacity: 1 }], { duration: A.ms.quick() })]);
    var d = A.ms.standard(), e = A.easing.standard;
    return Promise.all([
      go(outEl, [{ transform: 'translateX(0)' }, { transform: back ? 'translateX(100%)' : 'translateX(-100%)' }], { duration: d, easing: e }),
      go(inEl, [{ transform: back ? 'translateX(-100%)' : 'translateX(100%)' }, { transform: 'translateX(0)' }], { duration: d, easing: e })]);
  };
  /** iOS 18 zoom navigation transition: the source view grows into the destination (about 0.5 s, the system's own curve); the system
   *  turns it into a cross-fade under Reduce Motion. motion.md section 4.3 (only where a tile IS the thing it opens). srcEl, destEl
   *  are elements in the same positioned container; destEl starts hidden and ends at rest. */
  A.zoom = function (srcEl, destEl) {
    var s = srcEl.getBoundingClientRect(), d = destEl.getBoundingClientRect();
    if (rm() || !d.width) return go(destEl, [{ opacity: 0 }, { opacity: 1 }], { duration: A.ms.moment() });
    var sx = s.width / d.width, sy = s.height / d.height, tx = s.left - d.left, ty = s.top - d.top;
    return Promise.all([
      go(destEl, [{ transform: 'translate(' + tx + 'px,' + ty + 'px) scale(' + sx + ',' + sy + ')', borderRadius: '22px', opacity: .2 }, { transform: 'none', opacity: 1 }], { duration: 500, easing: A.easing.sheet }),
      go(srcEl, [{ opacity: 1 }, { opacity: 0 }], { duration: 200, fill: 'forwards' })]);
  };
  /** Tab switch is a cut: no slide, no fade (motion.md section 4.1). Shown so the Transitions list can say "cut" and play it. */
  A.cut = function (outEl, inEl) { outEl.hidden = true; inEl.hidden = false; return Promise.resolve(); };
  /** Flyout (NavigationFlyout) opening: the panel slides in from the leading edge on `standard` (0.3 s smooth) with the scrim fading;
   *  Reduce Motion: `quick` cross-fade. design/apple/ipados.md. */
  A.flyout = function (stage, open) {
    var panel = stage.querySelector('.ui-flyout'), scrim = stage.querySelector('.ui-flyout-scrim');
    var d = rm() ? A.ms.quick() : A.ms.standard(), out = [];
    var p = rm() ? (open ? [{ opacity: 0 }, { opacity: 1 }] : [{ opacity: 1 }, { opacity: 0 }]) : (open ? [{ transform: 'translateX(-100%)' }, { transform: 'none' }] : [{ transform: 'none' }, { transform: 'translateX(-100%)' }]);
    if (panel) out.push(go(panel, p, { duration: d, easing: A.easing.standard }));
    if (scrim) out.push(go(scrim, open ? [{ opacity: 0 }, { opacity: 1 }] : [{ opacity: 1 }, { opacity: 0 }], { duration: d }));
    return Promise.all(out);
  };
  /** The loading gate (ContentGate): content laid out but hidden; a spinner fades in after 150 ms (`.page` profile: at once, 200 ms, held at
   *  least 1 s); when ready the spinner fades out (140 ms, 500 ms on `.page`) and the content fades in and rises 4 pt (170 ms).
   *  patterns/content-gate.md "Sequence" and "Timing profiles"; motion.md section 5. gate = the .ui-gate element. */
  A.gate = function (gate, o) {
    o = o || {}; var page = o.profile === 'page', loadMs = o.loadMs || (page ? 1200 : 900);
    var spin = gate.querySelector('.spin'), content = gate.querySelector('.content');
    A.reset(gate);
    gate.dataset.phase = 'loading';
    return Mock.sleep(page ? 0 : 150).then(function () {
      gate.dataset.phase = 'spinner'; spin.style.transitionDuration = page ? '.2s' : '.2s';
      return Mock.sleep(loadMs);
    }).then(function () {
      spin.style.transitionDuration = (page ? 500 : 140) + 'ms'; gate.dataset.phase = 'ready';
      return Mock.sleep(page ? 500 : 140);
    }).then(function () {
      content.style.transitionDuration = '0s'; content.style.opacity = 0;
      return A.rise(content, { ms: 170 }).then(function () { content.style.opacity = ''; content.style.transitionDuration = ''; });
    });
  };
  /** The sheet reveal (ContentGateModel.Profile.sheet; patterns/content-gate.md "Sheet reveal", design/sheet-reveal.md, owner 2026-11-05
   *  "Arc only if not ready"). Mock.anim.sheetReveal.layer(host, {label, arc}) prepares a Mock.sheet host for it (statically too): the root page's
   *  content is hidden and a 44 pt arc layer sits centred in the content area, below the header and above the bottom inset (absolute in the
   *  .ui-mscroll scroller, inset 0, so it centres on the visible viewport, never under the bar). Mock.anim.sheetReveal(host, o) plays it: the
   *  sheet slides up with the chrome showing and the content hidden. When the slide ends, ready content (o.readyAt 0) fades in all at once,
   *  200 ms ease-out (`quick`), with no rise and no stagger. Not ready: after a 150 ms grace the arc fades in (200 ms ease-in), holds at least
   *  500 ms from the start of its fade-in, fades out (200 ms ease-out) once ready, then the content fades in (200 ms). A load that ends inside
   *  the grace shows no arc. Reduce Motion: the same fades (the sheet itself cross-fades in A.sheet). o: {readyAt: ms after the slide ends,
   *  label, say(text) for a readout}. Resolves with the content shown. */
  A.sheetReveal = function (host, o) {
    o = o || {}; var say = o.say || function () {}, t0 = 0;
    var L = A.sheetReveal.layer(host, { label: o.label });
    if (!L) return Promise.resolve();
    function at() { return Math.round(performance.now() - t0) + ' ms · '; }
    function showContent() { say(at() + 'content fades in together (200 ms, no rise)'); return Promise.all(L.content.map(function (c) { return go(c, [{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: 'ease-out' }); })); }
    say('sheet slides up; title and Close show, content hidden');
    return A.sheet(host, 'in').then(function () {
      t0 = performance.now(); var ready = o.readyAt || 0;
      if (ready <= 0) { say('0 ms · presented, content ready'); return showContent(); }
      if (ready <= 150) { say('0 ms · presented, not ready: 150 ms grace'); return Mock.sleep(ready).then(showContent); }
      say('0 ms · presented, not ready: 150 ms grace');
      return Mock.sleep(150).then(function () {
        say(at() + 'arc fades in (200 ms), held at least 500 ms');
        var shown = performance.now();
        return go(L.arc, [{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: 'ease-in' }).then(function () {
          var wait = Math.max(ready - (performance.now() - t0), 500 - (performance.now() - shown));
          if (ready < 650) say(at() + 'ready at ' + ready + ' ms, during the arc: it finishes its 500 ms hold (no pop)');
          return Mock.sleep(Math.max(0, wait));
        });
      }).then(function () { say(at() + 'ready; arc fades out (200 ms)'); return go(L.arc, [{ opacity: 1 }, { opacity: 0 }], { duration: 200, easing: 'ease-out' }); })
        .then(showContent);
    }).then(function () { say(at() + 'open: nothing animates; the reveal lets go'); });
  };
  /** Hides the content of a Mock.sheet host and adds the centred arc layer. o.arc true shows the arc at once (a static state). Returns {arc, content} or null. */
  A.sheetReveal.layer = function (host, o) {
    o = o || {}; var body = host.querySelector('.ui-sheet .ui-mscroll'); if (!body) return null;
    var content = Array.prototype.slice.call(body.children).filter(function (c) { return !c.hasAttribute('data-reveal-arc'); });
    content.forEach(function (c) { c.style.opacity = 0; c.setAttribute('aria-hidden', 'true'); });
    var arc = body.querySelector('[data-reveal-arc]');
    if (!arc) {
      body.style.position = 'relative';
      arc = Mock.h('div', { 'data-reveal-arc': 'true', role: 'status', 'aria-label': o.label || 'Loading', style: { position: 'absolute', inset: 0, display: 'grid', placeItems: 'center', pointerEvents: 'none', color: 'var(--ink)', opacity: o.arc ? 1 : 0 } },
        Mock.components.ArcSpinner({ size: 'page', label: o.label || 'Loading' }));
      body.appendChild(arc);
    }
    return { arc: arc, content: content };
  };
  /** Pending placeholders on the first sign-in: a soft bar pulses 0.35 to 1 over 1.4 s where the value goes; static under Reduce Motion
   *  (motion.md sections 5 and 8). The pulse is a CSS animation on .ui-pending; this just reports whether it should run. */
  A.pulsing = function () { return !rm(); };
  /** The one spinner: ArcSpinner (0.82 s a turn, half speed under Reduce Motion; CSS in kit.css). size 'page' | 'compact' | 'inline'. */
  A.spinner = function (size, o) { return Mock.components.ArcSpinner(Object.assign({ size: size || 'page' }, o)); };
  /** Ordered play: runs functions that return promises one after another (the Play-all button). */
  A.series = function (fns) { return fns.reduce(function (p, f) { return p.then(function () { return f(); }); }, Promise.resolve()); };
})();
