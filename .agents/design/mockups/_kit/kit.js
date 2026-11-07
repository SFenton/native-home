/* S+H mockup kit: entry point.
 *
 * A mockup links only kit.css and kit.js. This file defines the `Mock` namespace and its DOM helpers, then loads the rest of
 * the kit synchronously and deterministically (document.write plus a verify-and-retry step, see the bottom of this file; it keeps
 * `Mock.mount(...)` in the page's next inline script working from file://):
 *   lib/symbols.js   SF Symbol look-alikes (Mock.icon)
 *   lib/anim.js      motion helpers (Mock.anim), every one cites its motion.md section
 *   lib/devices.js   device table and Mock.ctx
 *   lib/chrome.js    Mock.frame / Mock.page / Mock.sheet / Mock.split / Mock.detailPane (shell chrome per device)
 *   lib/reflow.js    Mock.reflow (the split opening and the Duo hinge posture, animated)
 *   lib/mount.js     Mock.mount, Mock.lint, Mock.componentConfig (page furniture)
 *   components/*.js  one file per shared component, each registers Mock.components.<SwiftUIName>
 * tools/mockups_inline.py inlines all of it into one HTML file (it sets window.__MOCK_INLINED and skips the loader).
 */
(function () {
  'use strict';
  var Mock = window.Mock = window.Mock || {};
  Mock.components = Mock.components || {};
  /** Global switches the controls bar flips; every builder and Mock.anim helper reads them. */
  Mock.settings = { reduceMotion: false, reduceTransparency: false };

  /** Files loaded after this one, in order. mockups_check.py verifies components/ matches COMPONENTS. */
  Mock.LIB = ['symbols', 'anim', 'devices', 'chrome', 'reflow', 'mount'];
  Mock.COMPONENTS = [
    'NavigationGlass', 'ArcSpinner', 'GlassTile', 'TileGrid', 'ChipRail', 'ModuleList', 'SettingsSection', 'PageSectionHeader',
    'HassModal', 'SheetCloseItem', 'FloatingActionBar', 'FilterSheet', 'OptionPickerSheet', 'StatusPill', 'InfoBox',
    'PrimaryButton', 'SegmentedChoice', 'Toggle', 'Slider', 'BrightnessTile', 'ThermostatDial', 'ContentGate', 'ImageCard',
    'ModalTabBar', 'TabBar', 'AlarmPanel', 'NavigationFlyout', 'ReconnectingArc', 'ScheduleDateFields', 'FormField', 'Alert', 'WeatherCard',
    'ConfirmationDialog', 'ContentUnavailableView', 'SettingsLinkRow', 'TextToolbarButtons', 'FullScreenCover',
  ];

  var script = document.currentScript;
  Mock.base = script && script.src ? script.src.replace(/kit\.js(\?.*)?$/, '') : '';

  /** DOM builder. h('div.a.b', {style:{}, dataset:{}, aria:{label:'x'}, onclick}, ...children). Children: Node, string, array, null. */
  Mock.h = function (spec, attrs) {
    var m = /^([a-z0-9]*)((?:[.#][\w-]+)*)$/i.exec(spec) || [];
    var el = document.createElement(m[1] || 'div');
    (m[2] || '').replace(/([.#])([\w-]+)/g, function (_, k, v) { if (k === '.') el.classList.add(v); else el.id = v; });
    var rest = 2;
    if (attrs && (attrs.nodeType || typeof attrs === 'string' || Array.isArray(attrs))) rest = 1; else attrs = attrs || {};
    if (rest === 2) Object.keys(attrs).forEach(function (k) {
      var v = attrs[k];
      if (v == null || v === false) return;
      if (k === 'style' && typeof v === 'object') Object.keys(v).forEach(function (p) { if (p.indexOf('--') === 0) el.style.setProperty(p, v[p]); else el.style[p] = v[p]; });
      else if (k === 'style') el.style.cssText = v;
      else if (k === 'dataset') Object.keys(v).forEach(function (d) { el.dataset[d] = v[d]; });
      else if (k === 'aria') Object.keys(v).forEach(function (a) { el.setAttribute('aria-' + a, v[a]); });
      else if (k === 'html') el.innerHTML = v;
      else if (k.slice(0, 2) === 'on' && typeof v === 'function') el.addEventListener(k.slice(2), v);
      else if (k === 'class') v.split(/\s+/).forEach(function (c) { if (c) el.classList.add(c); });
      else el.setAttribute(k, v === true ? '' : v);
    });
    Mock.append(el, Array.prototype.slice.call(arguments, rest));
    return el;
  };
  /** Append nodes, strings (as text) and nested arrays. null/false/undefined are skipped. */
  Mock.append = function (el, kids) {
    (Array.isArray(kids) ? kids : [kids]).forEach(function (k) {
      if (k == null || k === false) return;
      if (Array.isArray(k)) Mock.append(el, k);
      else if (k.nodeType) el.appendChild(k);
      else el.appendChild(document.createTextNode(String(k)));
    });
    return el;
  };
  /** Parse an HTML string into a node (first element) or fragment. */
  Mock.html = function (s) {
    var t = document.createElement('template'); t.innerHTML = String(s).trim();
    return t.content.childNodes.length === 1 ? t.content.firstChild : t.content;
  };
  Mock.esc = function (s) { return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); };
  Mock.sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };

  /**
   * Register a shared component.
   * @param {string} name SwiftUI type name (the key in Mock.components)
   * @param {Function} fn (props) => Node
   * @param {{source:string, doc:string, props:string, variants:Array, states:Array}} meta
   *   variants: [{id,label,props,note?}]  the knobs a designer toggles (family, layout, size...)
   *   states:   [{id,label,props,note?}]  the states the view can be in (off, on, error, pending...)
   *   Component mockups render both lists with Mock.componentConfig(name).
   */
  Mock.register = function (name, fn, meta) {
    meta = meta || {};
    fn.meta = meta; fn.variants = meta.variants || []; fn.states = meta.states || []; fn.source = meta.source || '';
    Mock.components[name] = fn;
    return fn;
  };

  /** Run fn(el) once el is in the document (a builder returns a detached node; layout-dependent code such as the weather ticker waits). */
  Mock.whenAttached = function (el, fn) {
    var n = 0;
    (function tick() { if (el.isConnected) { requestAnimationFrame(function () { fn(el); }); } else if (n++ < 120) requestAnimationFrame(tick); })();
  };

  /** CSS var reference helpers (tokens live in kit.css only). */
  Mock.fam = function (name, part) { return 'var(--fam-' + name + '-' + part + ')'; };

  /** Contrast helpers (ChipTint uses the same maths). */
  Mock.color = {
    hex: function (n) { return '#' + ('000000' + (n >>> 0).toString(16)).slice(-6).toUpperCase(); },
    rgb: function (hex) { var n = parseInt(String(hex).replace('#', ''), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; },
    lum: function (c) { return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]); function lin(v) { v /= 255; return v <= .04045 ? v / 12.92 : Math.pow((v + .055) / 1.055, 2.4); } },
    contrast: function (a, b) { var la = Mock.color.lum(a), lb = Mock.color.lum(b); return (Math.max(la, lb) + .05) / (Math.min(la, lb) + .05); },
    mix: function (a, b, amount) { return a.map(function (v, i) { return Math.round(v * amount + b[i] * (1 - amount)); }); },
    css: function (c) { return 'rgb(' + c.join(',') + ')'; },
  };

  if (window.__MOCK_INLINED) return;
  if (!script || !script.src) return;

  /**
   * Deterministic ordered load (v2). Every file is written as a parser-blocking <script src> (document.write, so `Mock.mount(...)` in the page's
   * next inline script and the helpers' own <script src> keep working from file://), each with an onerror hook. A verify script runs right after the
   * batch: when a request failed (a busy static server drops connections under parallel load) it waits briefly and re-writes the failed file AND
   * every file after it, in the original order (so load-time dependencies hold), up to four times, before the page's own scripts run. It works the
   * same on file:// and http(s) and never relies on timers, so the page cannot start before the kit is complete. A final failure is logged and
   * listed in Mock.loadErrors (Mock.lint shows it in the red banner).
   */
  var files = [];
  Mock.LIB.forEach(function (n) { files.push('lib/' + n + '.js'); });
  Mock.COMPONENTS.forEach(function (n) { files.push('components/' + n + '.js'); });
  Mock.loadErrors = [];
  var failed = [];
  Mock._loadFail = function (i) { failed.push(i); };
  /** Index of the first lib file whose global is missing (a file that fetched but threw), or -1. */
  function libMissing() {
    var need = { symbols: Mock.icon, anim: Mock.anim, devices: Mock.devices, chrome: Mock.frame, reflow: Mock.reflow, mount: Mock.lint };
    for (var k in need) if (!need[k]) return Mock.LIB.indexOf(k);
    return -1;
  }
  function write(from, attempt) {
    for (var i = from; i < files.length; i++) {
      document.write('<script src="' + Mock.base + files[i] + (attempt ? '?retry=' + attempt : '') + '" onerror="Mock._loadFail(' + i + ')"><\/script>');
    }
    document.write('<script>Mock._loadVerify(' + attempt + ')<\/script>');
  }
  Mock._loadVerify = function (attempt) {
    var first = failed.length ? Math.min.apply(null, failed) : libMissing();
    if (first < 0) return;
    failed = [];
    if (attempt >= 4) { Mock.loadErrors.push(files[first]); if (window.console) console.error('Mock kit: ' + files[first] + ' did not load after ' + attempt + ' retries'); return; }
    var until = Date.now() + 80 * (attempt + 1); while (Date.now() < until) { /* let a busy static server drain its queue */ }
    write(first, attempt + 1);
  };
  write(0, 0);
})();
