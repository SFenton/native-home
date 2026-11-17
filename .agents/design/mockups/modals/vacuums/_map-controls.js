/* Map controls and map orientation for the vacuum mockups (local helper; promote to kit as MapControls when the build is on main).
 *
 * Stand-in for UKMapControlsView (corner groups, glass plate, More menu), MapControlFit (the fit rule) and MapOrientation (the flip),
 * which live on t3/native-ingest. Load it after modals/vacuums/_devices-vacuums.js: it wraps vac.mapCard.
 *
 *   vac.mapCard({ ..., controls: c })            one card
 *   vac.mapControls.with(c, function () { ... }) every card built inside the call (the sheet builders)
 *
 * c: { flipH, flipV,                       the vacuum source's orientation
 *      groups: [{ corner, axis, buttons }], corner: 'top-leading' | 'top-trailing' | 'bottom-leading' | 'bottom-trailing'; axis: 'row' | 'column'
 *      blocked: { id: reason },            a command the vacuum offers but cannot run: dimmed, the reason is its VoiceOver value
 *      unoffered: [ids],                   a command the vacuum does not offer: not drawn
 *      menu: corner,                       draws that corner's More menu open
 *      contrast: true,                     Increase Contrast: opaque plate with a 1 pt outline
 *      height: pt }                        the card's height (default: the frame's own)
 * A button is { id, sym, label, hint?, kind: 'locate' | 'command' | 'service' }. Locate is not drawn while the robot is unavailable.
 * With no groups the card keeps today's Locate circle. */
(function () {
  var h = Mock.h, I = Mock.icon, vac = Mock.dv.vac;
  var BTN = 'button';
  var SIZE = 44, INSET = 8, GAP = 12;   // MapControlFit.controlSize, inset, gap
  var st = document.getElementById('mc-style');
  if (!st) { st = document.createElement('style'); st.id = 'mc-style'; document.head.appendChild(st); }
  st.textContent = [
    '.mc-grp { position: absolute; z-index: 3; display: flex; border-radius: 22px; padding: 0; color: var(--glass-ink); }',
    '.mc-grp.col { flex-direction: column; }',
    '.mc-grp.top-leading { top: 8px; left: 8px; } .mc-grp.top-trailing { top: 8px; right: 8px; } .mc-grp.bottom-leading { bottom: 8px; left: 8px; } .mc-grp.bottom-trailing { bottom: 8px; right: 8px; }',
    '.mc-b { width: 44px; height: 44px; flex: none; border: 0; padding: 0; background: none; color: inherit; display: grid; place-items: center; border-radius: 22px; cursor: pointer; font: inherit; }',
    '.mc-b svg { width: 20px; height: 20px; } .mc-b.dim svg { opacity: .4; } .mc-b.dim { cursor: default; }',
    '.mc-contrast .mc-grp, .mc-contrast .vc-locate { border: 1px solid currentColor; background: #3A3A3C; color: #fff; backdrop-filter: none; -webkit-backdrop-filter: none; }',
    '.g-light .mc-contrast .mc-grp, .g-light .mc-contrast .vc-locate { background: #fff; color: #000; }',
    '.mc-menu { position: absolute; z-index: 40; min-width: 220px; max-width: 250px; padding: 0; border-radius: 14px; overflow: hidden; background: rgba(250,250,252,.96); color: #000; box-shadow: 0 10px 34px rgba(0,0,0,.35); border: .5px solid rgba(0,0,0,.08); }',
    '.g-dark .mc-menu { background: rgba(58,58,60,.97); color: #fff; border-color: rgba(255,255,255,.12); }',
    '.mc-menu div { display: flex; align-items: center; gap: 10px; min-height: 44px; padding: 6px 14px; font: 400 var(--fs-body)/1.25 var(--font); } .mc-menu div + div { border-top: .5px solid rgba(128,128,128,.35); }',
    '.mc-menu .tx { flex: 1; min-width: 0; display: flex; flex-direction: column; overflow-wrap: anywhere; } .mc-menu .tx small { font-size: var(--fs-foot); opacity: .6; } .mc-menu svg { width: 20px; height: 20px; flex: none; } .mc-menu div.dim { opacity: .4; }',
  ].join('\n');

  var mc = vac.mapControls = { current: null };
  mc.B = {
    locate: { id: 'locate', sym: 'scope', label: 'Locate', hint: 'Asks the robot to play a sound.', kind: 'locate' },
    clean: { id: 'clean', sym: 'play.fill', label: 'Clean', kind: 'command' },
    lights: { id: 'lights', sym: 'lightbulb', label: 'Kitchen Lights', kind: 'service' },
    fan: { id: 'fan', sym: 'fan', label: 'Hallway Fan', kind: 'service' },
    outlet: { id: 'outlet', sym: 'bolt', label: 'Counter Outlet', kind: 'service' },
    night: { id: 'night', sym: 'moon', label: 'Night Lights', kind: 'service' },
    day: { id: 'day', sym: 'sun.max', label: 'Day Lights', kind: 'service' },
    purifier: { id: 'purifier', sym: 'wind', label: 'Air Purifier', kind: 'service' },
    humidifier: { id: 'humidifier', sym: 'drop', label: 'Humidifier', kind: 'service' },
    plants: { id: 'plants', sym: 'leaf', label: 'Plant Light', kind: 'service' },
  };
  mc.MORE = { id: 'more', sym: 'ellipsis', label: 'More Map Controls', hint: 'Shows the rest of the buttons in this corner.' };
  mc.NAMES = { 'top-leading': 'Top Leading', 'top-trailing': 'Top Trailing', 'bottom-leading': 'Bottom Leading', 'bottom-trailing': 'Bottom Trailing' };
  /** Today's map: Locate alone at top leading. */
  mc.DEFAULT = [{ corner: 'top-leading', axis: 'column', buttons: [mc.B.locate] }];

  /* MapControlFit.fit: how many buttons of each group show on a card of W by H, and whether the last slot is More. */
  function axisOf(g) { return g.buttons.length === 1 ? 'column' : g.axis; }   // a group of one counts as a column
  function edgeOf(g) { var p = g.corner.split('-'); return axisOf(g) === 'row' ? p[0] : p[1]; }
  function across(g) { var p = g.corner.split('-'); return axisOf(g) === 'row' ? p[0] + '-' + (p[1] === 'leading' ? 'trailing' : 'leading') : (p[0] === 'top' ? 'bottom' : 'top') + '-' + p[1]; }
  mc.fit = function (W, H, groups) {
    return groups.map(function (g) {
      var length = axisOf(g) === 'row' ? W : H, n = g.buttons.length, nb = groups.filter(function (o) { return o.corner === across(g); })[0];
      var along = nb ? edgeOf(nb) === edgeOf(g) : false, own = SIZE * n, theirs = nb ? (along ? SIZE * nb.buttons.length : SIZE) : 0;
      var total = length - 2 * INSET - (nb ? GAP : 0), available = total;
      if (own + theirs > total) { if (!along) available = total - theirs; else { var half = total / 2; available = own <= half ? own : theirs < half ? total - theirs : half; } }
      var room = Math.max(1, Math.floor(available / SIZE));
      return n > room ? { shown: room - 1, more: true } : { shown: n, more: false };
    });
  };

  function button(b, c) {
    var reason = c.blocked && c.blocked[b.id];
    var attrs = { type: 'button', 'aria-label': b.label, title: reason ? b.label + ': ' + reason : b.label, html: I(b.sym, { weight: 2 }) };
    if (b.hint) attrs['aria-description'] = b.hint;
    if (reason) { attrs['aria-disabled'] = 'true'; attrs['aria-description'] = reason; }
    if (b === mc.MORE) attrs['aria-haspopup'] = 'menu';
    return h(BTN + '.mc-b' + (reason ? '.dim' : ''), attrs);
  }
  function menu(hidden, c) {
    return h('div.mc-menu', { role: 'menu', 'aria-label': mc.MORE.label }, hidden.map(function (b) {
      var reason = c.blocked && c.blocked[b.id];
      var attrs = { role: 'menuitem' }; if (reason) attrs['aria-disabled'] = 'true';
      return h('div' + (reason ? '.dim' : ''), attrs, h('span.tx', b.label, reason ? h('small', reason) : null), h('span', { html: I(b.sym, { weight: 2 }) }));
    }));
  }
  function place(card, groups, c) {
    var W = card.offsetWidth, H = card.offsetHeight; if (!W || !H) return;
    var old = card.querySelector('.mc-menu'); if (old) old.remove();
    mc.fit(W, H, groups).forEach(function (r, i) {
      var g = groups[i], shown = g.buttons.slice(0, r.shown).concat(r.more ? [mc.MORE] : []), row = g.axis === 'row' && shown.length > 1, p = g.corner.split('-');
      g.el.className = 'mc-grp ui-glass ' + g.corner + (row ? '' : ' col');
      g.el.replaceChildren.apply(g.el, shown.map(function (b) { return button(b, c); }));
      if (r.more && c.menu === g.corner) {   // the system menu opens beside More, towards the middle of the card
        var m = menu(g.buttons.slice(r.shown), c), side = (row ? SIZE * shown.length : SIZE) + INSET + 8, down = row ? SIZE + INSET + 8 : INSET;
        m.style[p[1] === 'leading' ? 'left' : 'right'] = (row ? INSET : side) + 'px'; m.style[p[0]] = down + 'px';
        card.style.overflow = 'visible'; card.appendChild(m);
      }
    });
  }
  /** Adds the orientation and the corner groups to a vac.mapCard node. available: false hides Locate. */
  mc.decorate = function (card, c) {
    c = c || {};
    var inner = card.querySelector('.vc-mapin');
    if (c.height && inner) inner.style.setProperty('--mh', (c.height - 24) + 'px');
    var map = card.querySelector('.vc-map');
    if (map && (c.flipH || c.flipV)) {
      // The picture and what sits on it move together; badges are placed from the flipped positions and stay upright; hatching keeps its on-screen direction.
      map.firstChild.style.transform = 'scale(' + (c.flipH ? -1 : 1) + ',' + (c.flipV ? -1 : 1) + ')';
      map.querySelectorAll('.lb').forEach(function (l) { if (c.flipH) l.style.left = (100 - parseFloat(l.style.left)) + '%'; if (c.flipV) l.style.top = (100 - parseFloat(l.style.top)) + '%'; });
      var hatch = map.querySelector('pattern'); if (hatch && !!c.flipH !== !!c.flipV) hatch.setAttribute('patternTransform', 'rotate(-45)');
    }
    if (c.contrast) card.classList.add('mc-contrast');
    if (!c.groups) return card;
    var locate = card.querySelector('.vc-locate'); if (locate) locate.remove();
    var groups = c.groups.map(function (g) {
      return { corner: g.corner, axis: g.axis, buttons: g.buttons.filter(function (b) { return !(b.kind === 'locate' && c.available === false) && !(c.unoffered && c.unoffered.indexOf(b.id) >= 0); }) };
    }).filter(function (g) { return g.buttons.length; });
    var fallback = card.querySelector('.vc-mapfb');   // an authored top corner clears the fallback's words
    if (fallback && groups.some(function (g) { return g.corner.indexOf('top') === 0; })) fallback.style.paddingTop = '60px';
    groups.forEach(function (g) { g.el = h('div', { role: 'group', 'aria-label': 'Map Controls, ' + mc.NAMES[g.corner] }); card.appendChild(g.el); });
    place(card, groups, c);
    if (window.ResizeObserver) new ResizeObserver(function () { place(card, groups, c); }).observe(card);
    return card;
  };
  /** Runs fn with c applied to every map card it builds. */
  mc.with = function (c, fn) { var was = mc.current; mc.current = c || null; try { return fn(); } finally { mc.current = was; } };

  var base = vac.mapCard;
  vac.mapCard = function (o) {
    var c = o.controls || mc.current, card = base(o);
    return c ? mc.decorate(card, Object.assign({ available: o.locate !== false }, c)) : card;
  };
})();
