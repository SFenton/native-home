/* Local helper for the login-launch-flows batch (pages/login, components/login, components/location, modals/location, flows/*).
 *
 * Not part of the kit. Load it with a relative <script src> straight after kit.js. Everything here is a stand-in drawn from the SwiftUI in
 * apple/Sources/HassUI/Features/{Login,Location}, App/RootView.swift and App/Motion; "promote to kit" candidates are listed in each
 * mockup's notes:
 *   Mock.LL.screen        the sign-in root layer (LoginView) on every device
 *   Mock.LL.mark / monogram / header / fields / failureCard / inlineError / signInButton   LoginView's parts
 *   Mock.LL.introAt/run   the launch intro timeline (MotionTokens.Intro), sampled so the same maths draws static frames and plays
 *   Mock.LL.arrivalAt     the Home arrival timeline (MotionTokens.Arrival, HomeArrival, ArrivalChromeProbe)
 *   Mock.LL.homePage      a trimmed Home (chips, weather, cameras) for the flows
 *   Mock.LL.locationContent / locationSheet   LocationPermissionView
 *   Mock.LL.accountSheet  YourSummarySheet's Profile tab, for the sign-out flow
 *   Mock.LL.confirmationDialog   SwiftUI's confirmationDialog (action sheet on a phone, popover on iPad)
 */
(function () {
  var h = Mock.h, K = Mock.components, I = Mock.icon;
  var LL = Mock.LL = {};

  /* ---------------------------------------------------------------- styles (local; every size uses the kit's Dynamic Type variables) */
  var css = [
    '.ll-root{position:absolute;inset:0;overflow:hidden;background:#121722;color:#fff;font-family:var(--font);z-index:10}',
    '.ll-ground,.ll-glow{position:absolute;inset:0}',
    '.ll-scroll{position:absolute;inset:0;overflow-y:auto;overflow-x:hidden;scrollbar-width:none;padding-top:var(--safe-top,54px);padding-bottom:max(0px,calc(var(--safe-bottom,34px) - 8px))}',
    '.ll-scroll::-webkit-scrollbar{display:none}',
    '.ll-col{box-sizing:border-box;margin:0 auto;width:100%;max-width:460px;min-height:100%;display:flex;flex-direction:column;padding:0 24px 16px}',
    '.ll-sp{flex:1 1 0;min-height:24px}',
    '.ll-header{display:flex;flex-direction:column;align-items:center;gap:8px;text-align:center}',
    '.ll-mark{padding-bottom:12px;display:flex;justify-content:center;transform-origin:50% 50%}',
    '.ll-name{font:700 var(--fs-lt)/1.2 var(--font-d);margin:0;color:#fff}',
    '.ll-line{font-size:var(--fs-body);line-height:1.3;color:var(--g-secondary-on-wallpaper);margin:0}',
    '.ll-formwrap{display:flex;flex-direction:column;flex:1 1 auto}',
    '.ll-form{display:flex;flex-direction:column;gap:16px}',
    '.ll-foot{font-size:var(--fs-foot);line-height:1.35;color:var(--g-secondary-on-wallpaper);text-align:center;margin:0}',
    '.ll-module{position:relative;overflow:hidden;transition:opacity var(--t-quick) var(--ease-quick)}',
    '.ll-module::after{content:"";position:absolute;inset:0;border-radius:inherit;box-shadow:inset 0 0 0 .5px rgba(255,255,255,.14);pointer-events:none}',
    '.ll-module.dim{opacity:.5}',
    '.ll-row{position:relative;display:flex;align-items:center;gap:12px;padding:0 16px;min-height:calc(52px * var(--sc));font-size:var(--fs-body);color:#fff}',
    '.ll-row .lb{flex:none;width:calc(96px * var(--sc));text-align:left}',
    '.ll-row .fd{flex:1;min-width:0;text-align:left;overflow-wrap:anywhere}',
    '.ll-row .fd.ro{color:rgba(255,255,255,.85)}',
    '.ll-row .fd .dots{letter-spacing:.14em}',
    '.ll-row.ax{flex-direction:column;align-items:flex-start;gap:4px;padding-top:12px;padding-bottom:12px}',
    '.ll-row.ax .lb{width:auto}',
    '.ll-hair{height:.5px;margin-left:16px;background:rgba(255,255,255,.14)}',
    '.ll-caret{display:inline-block;width:2px;height:1.15em;margin-left:1px;vertical-align:-.2em;background:#409CFF}',
    '.ll-redline{position:absolute;inset:0;border:1px solid #FF6961;border-radius:0 0 26px 26px;pointer-events:none}',
    '.ll-redline.top{border-radius:26px 26px 0 0}',
    '.ll-row .fd.ph{color:rgba(255,255,255,.4)}',
    '.ll-row .fd.ro.mid{white-space:nowrap}',
    '.ll-fail{padding:16px;border-radius:20px;background:rgba(255,105,97,.16);border:1px solid rgba(255,105,97,.45);display:flex;flex-direction:column;gap:8px}',
    '.ll-fail .ti{display:flex;align-items:baseline;gap:8px;font:600 var(--fs-hd)/1.25 var(--font);color:#fff}',
    '.ll-fail .ti .ui-sym{flex:none}',
    '.ll-fail .ms{font-size:var(--fs-sub);color:rgba(255,255,255,.88);margin:0}',
    '.ll-fail .dt{display:flex;justify-content:space-between;align-items:center;min-height:44px;width:100%;background:none;border:0;color:#fff;font:600 var(--fs-sub)/1.2 var(--font);cursor:pointer;padding:0}',
    '.ll-fail .dt .chev{display:inline-grid;transition:transform var(--t-quick) var(--ease-quick)}',
    '.ll-fail .dt[aria-expanded="true"] .chev{transform:rotate(90deg)}',
    '.ll-fail .raw{font:var(--fs-foot)/1.4 var(--mono);color:rgba(255,255,255,.88);margin:0;overflow-wrap:anywhere}',
    '.ll-err{display:flex;gap:8px;align-items:baseline;padding:0 8px;font-size:var(--fs-sub);line-height:1.3;color:#FF6961}',
    '.ll-err .ui-sym{flex:none}',
    '.ll-link{min-height:44px;width:100%;display:flex;align-items:center;justify-content:center;background:none;border:0;color:#8AC4FF;font:var(--fs-body)/1.2 var(--font);cursor:pointer;padding:0}',
    '.ll-btn .ui-primary{transition:transform .12s ease-out,opacity var(--t-quick) var(--ease-quick)}',
    '.ll-btn .ui-primary.pressed{transform:scale(.96)}',
    '.ll-launch{position:absolute;inset:0;background:#121722;z-index:50}',
    '.ll-swatch{border-radius:16px;padding:14px;min-width:0;color:#fff;background:#121722 radial-gradient(150% 120% at 50% 20%,#3A4E73 0,#1E2A44 50%,#121722 100%)}',
    '.ll-swatch .k-cap{font:600 11px var(--mono);letter-spacing:.04em;margin-bottom:10px;opacity:.65}',
    '.ll-swatch .in{display:flex;flex-direction:column;gap:12px;align-items:stretch}',
    '.ll-swatch .ll-fixed{max-width:412px;width:100%}',
    '.ll-loc{display:flex;flex-direction:column;gap:24px;max-width:560px;margin:0 auto;padding:16px 8px 8px}',
    '.ll-loc .intro{display:flex;flex-direction:column;gap:12px}',
    '.ll-loc .big{font-size:calc(56px * var(--ltsc,1));line-height:1}',
    '.ll-loc h2{margin:0;font:700 var(--fs-t2)/1.2 var(--font-d);color:var(--ink)}',
    '.ll-loc p{margin:0}',
    '.ll-loc .msg{font-size:var(--fs-body);color:var(--ink-sheet-2)}',
    '.ll-stat{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:4px 12px;padding:12px 16px;min-height:52px;border-radius:22px;background:var(--sheet-cell);font-size:var(--fs-body)}',
    '.ll-pt{display:flex;gap:12px;align-items:baseline}',
    '.ll-pt .g{flex:none;width:calc(32px * var(--t2sc,1));font-size:var(--fs-t2);color:var(--ink-action);display:grid;place-items:center}',
    '.ll-pt .tx{display:flex;flex-direction:column;gap:4px;min-width:0}',
    '.ll-pt .ti{font:600 var(--fs-hd)/1.25 var(--font);color:var(--ink)}',
    '.ll-pt .de{font-size:var(--fs-sub);color:var(--ink-sheet-2)}',
    '.ll-list{display:flex;flex-direction:column;gap:24px}',
    '.ll-sec .hd{font:600 var(--fs-sub)/1.2 var(--font);color:var(--ink-sheet-2);margin:0 0 8px 16px}',
    '.ll-sec .ft{font-size:var(--fs-foot);color:var(--ink-sheet-2);margin:8px 16px 0;display:flex;flex-direction:column;gap:8px}',
    '.ll-cell{display:flex;align-items:center;gap:12px;padding:8px 16px;min-height:52px;background:var(--sheet-cell);font-size:var(--fs-body);color:var(--ink);width:100%;border:0;text-align:left;font-family:var(--font)}',
    '.ll-cell + .ll-cell{border-top:.5px solid var(--sep)}',
    '.ll-cell .v{margin-left:auto;color:var(--ink-sheet-2);text-align:right}',
    '.ll-cell.wrap{flex-wrap:wrap}',
    '.ll-card{border-radius:16px;overflow:hidden;background:var(--sheet-cell)}',
    '.ll-signout{justify-content:center;color:var(--ink-danger);min-height:max(44px,calc(44px * var(--sc)));cursor:pointer}',
    '.ll-avatar{display:grid;place-items:center;border-radius:50%;background:#0071E3;color:#fff;font-weight:600;flex:none}',
    '.ll-acc{display:flex;flex-direction:column;align-items:center;gap:8px;padding:8px 0;text-align:center}',
    '.ll-acc .nm{font:700 var(--fs-t2)/1.2 var(--font-d);color:var(--ink);margin:0}',
    '.ll-acc .sv{font-size:var(--fs-sub);color:var(--ink-sheet-2);margin:0}',
    '.ll-person{width:calc(36px * var(--sc));height:calc(36px * var(--sc));font-size:calc(14.4px * var(--sc))}',
    '.ll-actionsheet{display:flex;flex-direction:column;gap:8px;width:min(398px,calc(100% - 16px));align-self:end;justify-self:center;margin-bottom:max(8px,calc(var(--safe-bottom,34px) - 8px))}',
    '.ll-actionsheet .card{border-radius:26px;overflow:hidden;background:rgba(44,44,46,.92);color:#fff;backdrop-filter:blur(30px);text-align:center}',
    '.g-light .ll-actionsheet .card{background:rgba(250,250,252,.92);color:#000}',
    '.ll-actionsheet .hd{padding:16px 16px 12px;font-size:var(--fs-foot);line-height:1.3}',
    '.ll-actionsheet .hd b{display:block;font-weight:600}',
    '.ll-actionsheet .hd span{display:block;color:var(--ink-sheet-2);margin-top:2px}',
    '.ll-actionsheet button{width:100%;min-height:56px;border:0;border-top:.5px solid rgba(128,128,128,.4);background:none;font:400 var(--fs-body)/1.2 var(--font);color:#0A84FF;cursor:pointer}',
    '.g-light .ll-actionsheet button{color:#0066CC}',
    '.ll-actionsheet button.destructive{color:#FF6961}',
    '.g-light .ll-actionsheet button.destructive{color:#C21717}',
    '.ll-actionsheet button.cancel{border-top:0;font-weight:600}',
    '.ll-popover{align-self:center;justify-self:center;width:min(300px,80%);border-radius:18px;overflow:hidden;background:rgba(44,44,46,.96);color:#fff;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.45)}',
    '.g-light .ll-popover{background:rgba(250,250,252,.96);color:#000}',
    '.ll-popover .hd{padding:14px 16px 12px;font-size:var(--fs-foot)}',
    '.ll-popover .hd b{display:block;font-weight:600}',
    '.ll-popover .hd span{display:block;color:var(--ink-sheet-2);margin-top:2px}',
    '.ll-popover button{width:100%;min-height:44px;border:0;border-top:.5px solid rgba(128,128,128,.4);background:none;font:400 var(--fs-body)/1.2 var(--font);color:#0A84FF;cursor:pointer}',
    '.g-light .ll-popover button{color:#0066CC}',
    '.ll-popover button.destructive{color:#FF6961}',
    '.g-light .ll-popover button.destructive{color:#C21717}',
    '.g-light .ll-actionsheet.dk .card,.g-light .ll-popover.dk{background:rgba(44,44,46,.92);color:#fff}',
    '.g-light .ll-actionsheet.dk button,.g-light .ll-popover.dk button{color:#0A84FF}',
    '.g-light .ll-actionsheet.dk button.destructive,.g-light .ll-popover.dk button.destructive{color:#FF6961}',
    '.g-light .ll-actionsheet.dk .hd span,.g-light .ll-popover.dk .hd span{color:rgba(235,235,245,.6)}',
    '.ll-note{font:12px var(--mono);opacity:.7}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'll-css'; st.textContent = css; document.head.appendChild(st);

  /* ---------------------------------------------------------------- symbols the kit lacks (promote to kit: lib/symbols.js) */
  var S = Mock.symbols;
  S['location.circle'] = ['<circle cx="12" cy="12" r="9"/><path d="M16.6 7.4 7.4 11.2l4.4 1 1 4.4z"/>', '<path fill-rule="evenodd" d="M12 2.8a9.2 9.2 0 1 0 0 18.4 9.2 9.2 0 0 0 0-18.4zM16.6 7.4l-3.6 9.2-1.2-4.4-4.4-1.2z"/>'];
  S['location.slash'] = ['<path d="M20 4 4 11l7 2 2 7z"/><path d="M3.5 3.5l17 17"/>', '<path d="M20 4 4 11l7 2 2 7z"/><path d="M3.5 3.5l17 17" stroke="currentColor" stroke-width="2"/>'];
  S['scope'] = ['<circle cx="12" cy="12" r="6.5"/><path d="M12 2.5v4M12 17.5v4M2.5 12h4M17.5 12h4"/><circle cx="12" cy="12" r="1.2"/>'];
  S['figure.walk.arrival'] = [(Array.isArray(S['figure.walk']) ? S['figure.walk'][0] : S['figure.walk']) + '<path d="M5.5 5.5H3v13"/>'];

  /* ---------------------------------------------------------------- tokens from the code */
  /** AppIconChoice (HassCore/Settings/AppIconChoice.swift): tint and glyph colours; the mark takes the glyph. */
  LL.icons = {
    navySky: { name: 'Navy + Sky', tint: '#0E1E46', glyph: '#7CC4FF' }, tealMint: { name: 'Teal + Mint', tint: '#063A3E', glyph: '#6EE7C8' },
    plumLilac: { name: 'Plum + Lilac', tint: '#3A1648', glyph: '#D3A8FF' }, forestGreen: { name: 'Forest + Green', tint: '#10301E', glyph: '#9BE29B' },
    burgundyRose: { name: 'Burgundy + Rose', tint: '#48101E', glyph: '#FF9EB0' }, indigoPeriwinkle: { name: 'Indigo + Periwinkle', tint: '#221C5A', glyph: '#A8B4FF' },
    espressoAmber: { name: 'Espresso + Amber', tint: '#342014', glyph: '#FFB35C' }, midnightGold: { name: 'Midnight + Gold', tint: '#101630', glyph: '#FFD36B' },
  };
  /** SignInStyle */
  LL.style = { base: '#121722', glowCentre: '#3A4E73', glowMiddle: '#1E2A44', link: '#8AC4FF', error: '#FF6961', columnWidth: 460 };
  /** LoginCopy */
  LL.copy = {
    appName: 'S+H', subtitle: 'Sign in to your Home Assistant', signIn: 'Sign In', busy: 'Signing In…', retry: 'Try Again',
    footnote: 'Your password goes only to your Home Assistant. S+H keeps a sign-in key in your Keychain, never the password.',
    wrong: "That username and password don't match. Check them and try again.", twoStep: "Two-step sign-in isn't supported. Turn it off for this account in Home Assistant.",
    serverLabel: 'Server', serverAccessibilityLabel: 'Server address', serverPlaceholder: 'homeassistant.local:8123',
    badAddress: 'Enter the address you open Home Assistant with, like homeassistant.local:8123.',
    notHomeAssistant: "Home Assistant didn't answer at that address. Check it and try again.",
    unreachableTitle: "Can't reach Home Assistant", unreachableBody: 'Check the server address and that this phone is online. If both are right, Home Assistant may be restarting; try again in a minute.',
    failedTitle: "Sign-in didn't work", failedBody: 'Something went wrong while signing in. Try again; if it keeps happening, the details may say why.',
    welcomeSubtitle: 'Your sign-in ended. Enter your password to pick up where you left off.', different: 'Use a Different Account',
  };

  /** Scale of a text style relative to Large (for @ScaledMetric(relativeTo:)): the kit's --sc is the body scale. */
  LL.scale = function (ctx, style) {
    var t = (ctx && ctx.ts) || 'default';
    var tab = { lt: { 'default': 1, xxxl: 40 / 34, ax5: 44 / 34 }, t2: { 'default': 1, xxxl: 28 / 22, ax5: 48 / 22 } };
    return (tab[style] || tab.lt)[t];
  };

  /* ---------------------------------------------------------------- easing and the timeline sampler */
  function bez(x1, y1, x2, y2) {
    function cx(t) { return 3 * x1 * t * (1 - t) * (1 - t) + 3 * x2 * t * t * (1 - t) + t * t * t; }
    function cy(t) { return 3 * y1 * t * (1 - t) * (1 - t) + 3 * y2 * t * t * (1 - t) + t * t * t; }
    return function (x) {
      if (x <= 0) return 0; if (x >= 1) return 1;
      var lo = 0, hi = 1, t = x;
      for (var i = 0; i < 24; i++) { t = (lo + hi) / 2; if (cx(t) < x) lo = t; else hi = t; }
      return cy(t);
    };
  }
  var EASE = { out: bez(0, 0, .58, 1), inOut: bez(.42, 0, .58, 1), smooth: bez(.4, 0, .2, 1), spring: bez(.2, .9, .3, 1.0) };
  LL.ease = EASE;
  function seg(t, delay, dur, ease) { return (ease || EASE.out)(Math.max(0, Math.min(1, (t - delay) / dur))); }
  function lerp(a, b, p) { return a + (b - a) * p; }
  /** Sample a timeline: fn(t) is called every frame for `total` ms; resolves at the end. */
  LL.run = function (total, fn) {
    return new Promise(function (resolve) {
      var t0 = performance.now();
      (function tick(now) {
        var t = Math.min(total, now - t0); fn(t);
        if (t < total) requestAnimationFrame(tick); else resolve();
      })(t0);
    });
  };

  /**
   * The launch intro at time t (ms) on a `.ll-root` (LoginView.playIntro, MotionTokens.Intro): glow 0 to 1 easeOut 0.5 s; the mark rises 0.86 to 1.03
   * (opacity 0 to 1) easeOut 0.28 s from 0.15 s, then settles to 1 on `emphasized` (spring 0.5 s, 0.8) from 0.43 s; the header (title and line, and the mark
   * inside it) fades and rises 10 pt easeOut 0.4 s from 0.46 s; the form fades and rises 28 pt easeOut 0.45 s from 0.71 s (ends at 1.16 s). Reduce Motion:
   * every piece cross-fades together over 0.35 s (MotionTokens.crossFade), no rise, no scale.
   */
  LL.introAt = function (root, t, reduce) {
    var glow = root.querySelector('.ll-glow'), mark = root.querySelector('.ll-mark'), title = root.querySelector('.ll-titlewrap'), form = root.querySelector('.ll-formwrap');
    if (reduce) {
      var p = EASE.inOut(Math.max(0, Math.min(1, t / 350)));
      glow.style.opacity = p; title.style.opacity = p; form.style.opacity = p; title.style.transform = 'none'; form.style.transform = 'none'; mark.style.opacity = 1; mark.style.transform = 'none';
      return;
    }
    glow.style.opacity = seg(t, 0, 500, EASE.out);
    var rise = seg(t, 150, 280, EASE.out), settle = seg(t, 430, 500, EASE.spring);
    mark.style.opacity = rise;
    mark.style.transform = 'scale(' + (t < 430 ? lerp(.86, 1.03, rise) : lerp(1.03, 1, settle)).toFixed(4) + ')';
    var to = seg(t, 460, 400, EASE.out), fo = seg(t, 710, 450, EASE.out);
    title.style.opacity = to; title.style.transform = 'translateY(' + (10 * (1 - to)).toFixed(2) + 'px)';
    form.style.opacity = fo; form.style.transform = 'translateY(' + (28 * (1 - fo)).toFixed(2) + 'px)';
  };
  LL.INTRO_MS = 1160;

  /**
   * Home's arrival after a sign-in at time t (ms) over a stage holding Home and the sign-in layer (HomeArrival, ArrivalMotion, ArrivalChromeProbe,
   * RootView.signedIn, HouseBackdrop): the layer lifts -18 pt, scales to 0.97 and fades over 0.4 s easeOut; the backdrop settles 1.06 to 1 and fades in over
   * 0.6 s easeOut; the navigation bar fades up 10 pt over 0.4 s from 0.1 s; the chips slide 30 pt in over 0.3 s (standard) from 0.12 s; the weather card
   * and each camera rise 16 pt over 0.3 s from 0.2 s + 0.06 s per index (index 0 weather, 1 to 4 cameras, the stagger is capped at index 5); the tab
   * bar rises 48 pt over 0.4 s from 0.22 s. About 0.9 s in all. Reduce Motion: the layer, backdrop and every piece cross-fade over 0.35 s, nothing moves.
   */
  LL.arrivalAt = function (stage, t, reduce, only) {
    var layer = stage.querySelector('.ll-root'), wall = stage.querySelector('.ui-wall'), bars = [].slice.call(stage.querySelectorAll('.ui-bar, .ui-title-wrap')),
      chips = stage.querySelector('.ui-rail-chips'), wx = stage.querySelector('.ui-weather'), cams = [].slice.call(stage.querySelectorAll('.ui-cam')),
      tabs = [].slice.call(stage.querySelectorAll('.ui-tabbar, .ui-rail .tabs'));
    function set(el, o, y, x, s) { if (!el) return; el.style.opacity = o; el.style.transform = (x || y || s) ? 'translate(' + (x || 0) + 'px,' + (y || 0) + 'px)' + (s ? ' scale(' + s + ')' : '') : 'none'; }
    /* `only` names one piece to sample; every other piece is held at its finished state (so a single piece can be played on its own). */
    function at(name) { return !only || only === name ? t : 99999; }
    if (reduce) {
      var p = EASE.inOut(Math.max(0, Math.min(1, t / 350)));
      set(layer, 1 - p); [wall].concat(bars, [chips, wx], cams, tabs).forEach(function (e) { set(e, p); });
      return;
    }
    var lift = seg(at('layer'), 0, 400, EASE.out);
    set(layer, 1 - lift, -18 * lift, 0, lerp(1, .97, lift));
    var b = seg(at('wall'), 0, 600, EASE.out); set(wall, b); if (wall) wall.style.transform = 'scale(' + lerp(1.06, 1, b).toFixed(4) + ')';
    var n = seg(at('bar'), 100, 400, EASE.out); bars.forEach(function (e) { set(e, n, 10 * (1 - n)); });
    var c = seg(at('chips'), 120, 300, EASE.smooth); set(chips, c, 0, 30 * (1 - c));
    var w = seg(at('weather'), 200, 300, EASE.smooth); set(wx, w, 16 * (1 - w));
    cams.forEach(function (e, i) { var q = seg(at('cams'), 200 + Math.min(i + 1, 5) * 60, 300, EASE.smooth); set(e, q, 16 * (1 - q)); });
    var tb = seg(at('tabs'), 220, 400, EASE.out); tabs.forEach(function (e) { set(e, tb, 48 * (1 - tb)); });
  };
  LL.ARRIVAL_MS = 900;

  /* ---------------------------------------------------------------- the sign-in layer */
  var uid = 0;
  var HOUSE = 'M50 12 90 44Q92 46 89 47L82 47 82 84Q82 88 78 88L22 88Q18 88 18 84L18 47 11 47Q8 46 10 44ZM25 59h9.5v9.5H25zM37 59h9.5v9.5H37zM25 71h9.5v9.5H25zM37 71h9.5v9.5H37z';
  var HEART = 'M50 88C20 66 8 50 8 34C8 20 19 10 32 10C40 10 46 14 50 21C54 14 60 10 68 10C81 10 92 20 92 34C92 50 80 66 50 88Z';
  /** SignInMark: the bare house and heart (HouseHeartShape), the heart's ring cut out of the house. size 96 pt (fixed, not scaled). */
  LL.mark = function (o) {
    o = o || {}; var size = o.size || 96, color = o.color || LL.icons.navySky.glyph, id = 'llm' + (++uid);
    return h('span', { 'aria-hidden': 'true', style: { display: 'inline-block', width: size + 'px', height: size + 'px', lineHeight: 0 }, html:
      '<svg viewBox="0 0 100 100" width="' + size + '" height="' + size + '"><defs><mask id="' + id + '"><rect width="100" height="100" fill="#fff"/><g transform="translate(55 60) scale(.4)"><path d="' + HEART + '" fill="#000" stroke="#000" stroke-width="16" stroke-linejoin="round"/></g></mask></defs>' +
      '<path d="' + HOUSE + '" fill="' + color + '" fill-rule="evenodd" mask="url(#' + id + ')"/><path d="' + HEART + '" transform="translate(55 60) scale(.4)" fill="' + color + '"/></svg>' });
  };
  function initials(name) { return (name || '').split(/\s+/).filter(Boolean).map(function (w) { return w[0]; }).join('').slice(0, 2).toUpperCase(); }
  /** SignInMonogram: the person's initials on a disc in the icon's colours (88 pt scaled with the large title). */
  LL.monogram = function (o) {
    o = o || {}; var ic = LL.icons[o.icon || 'navySky'], size = Math.round(88 * (o.lt || 1)), ini = initials(o.name);
    return h('span', { 'aria-hidden': 'true', style: { width: size + 'px', height: size + 'px', borderRadius: '50%', background: ic.glyph, color: ic.tint, display: 'grid', placeItems: 'center', font: '600 var(--fs-t1)/1 ui-rounded, "SF Pro Rounded", var(--font)' } },
      ini || h('span', { html: I('person', { fill: true, size: 'var(--fs-t1)' }) }));
  };
  /** LoginHeader. mode 'fresh' | 'welcome'. */
  LL.header = function (o) {
    var c = LL.copy, ic = o.icon || 'navySky';
    if (o.mode === 'welcome') return h('div.ll-header', { role: 'group' }, h('div.ll-mark', LL.monogram({ name: o.name, icon: ic, lt: o.lt })), h('h1.ll-name', { style: { textAlign: 'center' } }, 'Welcome back, ' + (o.first || 'Alex')), h('p.ll-line', c.welcomeSubtitle));
    return h('div.ll-header', { role: 'group' }, h('div.ll-mark', LL.mark({ color: LL.icons[ic].glyph })), h('h1.ll-name', { 'aria-label': 'S and H' }, c.appName), h('p.ll-line', c.subtitle));
  };
  function row(label, field, o) {
    return h('div.ll-row' + (o && o.ax ? '.ax' : ''), h('span.lb', { 'aria-hidden': 'true' }, label), field, o && o.redline ? h('span.ll-redline' + (o.redline === 'top' ? '.top' : ''), { 'aria-hidden': 'true' }) : null);
  }
  /** Middle truncation (UILabel .byTruncatingMiddle) for the read-only server row. */
  function middle(text, max) { return text.length <= max ? text : text.slice(0, Math.ceil((max - 1) / 2)) + '…' + text.slice(text.length - Math.floor((max - 1) / 2)); }
  /** LoginFieldsModule. o: {mode, server, username, password, focus, working, wrong, badServer, ax, passwordLen}. The Server row is first
   *  (house-config-states rules 1 to 7); `server` is the field text ('' shows the placeholder) or, in welcome back, the host shown read-only. */
  LL.fields = function (o) {
    var c = LL.copy, userField, passField, serverField;
    var server = o.server == null ? 'https://ha.example.com' : o.server;
    var caretS = o.focus === 'server' ? h('span.ll-caret') : null;
    if (o.mode === 'welcome') serverField = h('span.fd.ro.mid', { role: 'text', 'aria-label': c.serverLabel + ', ' + server.replace(/^https?:\/\//, '') }, middle(server.replace(/^https?:\/\//, ''), o.ax ? 22 : 26));
    else if (server === '') serverField = h('span.fd.ph', { 'aria-label': c.serverAccessibilityLabel }, c.serverPlaceholder, caretS);
    else serverField = h('span.fd', { 'aria-label': c.serverAccessibilityLabel }, server, caretS);
    var dots = h('span.dots', o.password ? '•'.repeat(o.password) : '');
    var caretU = o.focus === 'username' ? h('span.ll-caret') : null, caretP = o.focus === 'password' ? h('span.ll-caret') : null;
    if (o.mode === 'welcome') userField = h('span.fd.ro', { role: 'text', 'aria-label': 'Username, ' + o.username }, o.username);
    else userField = h('span.fd', o.username || '', caretU);
    passField = h('span.fd', typeof o.password === 'number' ? dots : o.password || '', caretP);
    var mod = h('div.ll-module.ui-module' + (o.working ? '.dim' : ''), { role: 'group', 'aria-label': 'Account' },
      row(c.serverLabel, serverField, { ax: o.ax, redline: o.badServer ? 'top' : false }), h('div.ll-hair', { 'aria-hidden': 'true' }),
      row('Username', userField, { ax: o.ax }), h('div.ll-hair', { 'aria-hidden': 'true' }), row('Password', passField, { ax: o.ax, redline: o.wrong }));
    return mod;
  };
  /** LoginFailureCard. o: {title, message, detail, expanded} */
  LL.failureCard = function (o) {
    var card = h('div.ll-fail', { role: 'group' }, h('div.ti', { role: 'heading', 'aria-level': '2' }, h('span', { html: I('exclamationmark.triangle', { fill: true }) }), o.title), h('p.ms', o.message));
    if (o.detail) {
      var raw = h('p.raw', o.detail);
      var btn = h('button.dt', { type: 'button', 'aria-expanded': o.expanded ? 'true' : 'false' }, h('span', 'Details'), h('span.chev', { 'aria-hidden': 'true', html: I('chevron.right', { weight: 2.4, size: '.8em' }) }));
      raw.hidden = !o.expanded;
      btn.addEventListener('click', function () { var on = btn.getAttribute('aria-expanded') !== 'true'; btn.setAttribute('aria-expanded', on ? 'true' : 'false'); raw.hidden = !on; });
      card.appendChild(btn); card.appendChild(raw);
    }
    return card;
  };
  /** LoginInlineError: warning glyph and the sentence (the glyph keeps it from resting on colour alone). */
  LL.inlineError = function (msg) { return h('div.ll-err', { role: 'alert' }, h('span', { html: I('exclamationmark.triangle', { fill: true }) }), h('span', msg)); };
  /** The Sign In capsule (PrimaryButtonStyle): disabled 40% while a field is empty; working keeps it solid with an inline arc. */
  LL.signInButton = function (o) {
    var b = K.PrimaryButton({ title: o.title });
    b.setAttribute('aria-label', o.title.replace('…', ''));
    if (o.working) {
      b.insertBefore(K.ArcSpinner({ size: 'inline', color: '#fff', label: 'Signing In' }), b.firstChild);
      b.firstChild.setAttribute('aria-hidden', 'true');
      b.setAttribute('aria-description', 'Signing In');
    }
    if (o.disabled) b.disabled = true;
    return h('div.ll-btn', b);
  };

  /**
   * The sign-in root layer (LoginView) for a device. o:
   *   mode 'fresh'|'welcome', server, username, password (number of dots, or a string), focus, working, failure {kind:'wrong'|'unreachable'|'failed'|'twostep', detail, expanded},
   *   name, first, icon, intro (a time in ms, or undefined for the finished screen), glow, noFootnote
   */
  LL.screen = function (ctx, o) {
    o = o || {}; var c = LL.copy, dev = ctx.device, ax = !!ctx.axSize, lt = LL.scale(ctx, 'lt');
    var root = h('div.ll-root', { role: 'group', 'aria-label': 'Sign in', dataset: { ll: 'login' }, style: { '--safe-top': dev.safeTop + 'px', '--safe-bottom': dev.safeBottom + 'px' } });
    var r = Math.round(0.95 * Math.max(dev.w, dev.h));
    root.appendChild(h('div.ll-ground', { 'aria-hidden': 'true' }));
    root.appendChild(h('div.ll-glow', { 'aria-hidden': 'true', style: { background: 'radial-gradient(circle ' + r + 'px at 50% 20%, ' + LL.style.glowCentre + ' 0%, ' + LL.style.glowMiddle + ' 50%, ' + LL.style.base + ' 100%)' } }));
    var f = o.failure && o.failure.kind, mode = o.mode || 'fresh';
    var canSubmit = !o.working && o.server !== '' && (mode === 'welcome' || (o.username || '').trim()) && (typeof o.password === 'number' ? o.password > 0 : !!o.password);
    var title = o.working ? c.busy : (f === 'unreachable' || f === 'failed' ? c.retry : c.signIn);
    var form = h('div.ll-form');
    if (f === 'unreachable') form.appendChild(LL.failureCard({ title: c.unreachableTitle, message: c.unreachableBody, detail: o.failure.detail || 'HTTP 502: Bad Gateway', expanded: o.failure.expanded }));
    if (f === 'failed') form.appendChild(LL.failureCard({ title: c.failedTitle, message: c.failedBody, detail: o.failure.detail || 'The operation couldn’t be completed. (HassCore.HassLoginFlow.LoginError error 2.)', expanded: o.failure.expanded }));
    form.appendChild(LL.fields({ mode: mode, server: o.server, badServer: f === 'badaddress' || f === 'nothomeassistant', username: o.username, password: o.password, focus: o.focus, working: o.working, wrong: f === 'wrong', ax: ax }));
    if (f === 'wrong') form.appendChild(LL.inlineError(c.wrong));
    if (f === 'twostep') form.appendChild(LL.inlineError(c.twoStep));
    if (f === 'badaddress') form.appendChild(LL.inlineError(c.badAddress));
    if (f === 'nothomeassistant') form.appendChild(LL.inlineError(c.notHomeAssistant));
    form.appendChild(LL.signInButton({ title: title, working: o.working, disabled: !canSubmit && !o.working }));
    if (mode === 'welcome') { var l = h('button.ll-link', { type: 'button' }, c.different); if (o.working) l.disabled = true; form.appendChild(l); }
    var titlewrap = h('div.ll-titlewrap', LL.header({ mode: mode, name: o.name || 'Alex Morgan', first: o.first || 'Alex', icon: o.icon, lt: lt }));
    var formwrap = h('div.ll-formwrap', form, h('div.ll-sp', { style: { flex: '1 1 0', minHeight: '24px' } }), o.noFootnote ? null : h('p.ll-foot', c.footnote));
    var col = h('div.ll-col', h('div.ll-sp'), titlewrap, h('div', { style: { height: '32px', flex: 'none' } }), formwrap);
    root.appendChild(h('div.ll-scroll', col));
    if (o.intro != null) Mock.whenAttached(root, function () { LL.introAt(root, o.intro, ctx.reduceMotion); });
    return root;
  };
  /** The plain launch ground (LaunchBackground / SignInStyle.base), held over the first frame. */
  LL.launchGround = function () { return h('div.ll-launch', { 'aria-hidden': 'true', dataset: { ll: 'launch-ground' } }); };

  /* ---------------------------------------------------------------- Home, trimmed (for the flows) */
  function section(title, kids) { return h('div.ui-section', K.PageSectionHeader({ title: title }), kids); }
  /** A trimmed Home (HomeScreen): status rail, weather card, four cameras. o: {chips, weather, cams, connection, pending, profileName} */
  LL.homePage = function (ctx, o) {
    o = o || {};
    var cams = o.cams || ['live', 'live', 'live', 'live'], names = [['Front Door', 'front-door'], ['Driveway', 'driveway'], ['Upper Deck', 'upper-deck'], ['Lower Deck', 'lower-deck']];
    var chipProps = o.pending ? Mock.chips.home().map(function (cc) { return Object.assign({}, cc, { pending: true, isActive: false, tint: null }); }) : (o.chips || Mock.chips.home());
    var chips = K.ChipRail({ chips: chipProps, frame: { x: 0, w: ctx.splitGeometry ? ctx.splitGeometry.leading : ctx.contentW } });
    var wx = K.WeatherCard(Object.assign({ condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 }, o.pending ? { pending: true } : null, o.weather));
    var cam = section('Cameras', K.TileGrid({ min: 160, max: 4, equal: false, items: names.map(function (n, i) { return K.CameraTile({ title: n[0], scene: n[1], state: cams[i] }); }) }));
    var body = ctx.splitGeometry && ctx.hinge ? [Mock.split(ctx, { leading: [chips, wx], trailing: [cam] })] : [chips, wx, cam];
    return Mock.page(ctx, { title: 'Home', section: 'home', badge: o.badge === undefined ? 3 : o.badge, choresBadge: 2, connection: o.connection || 'live', body: body, profileName: o.profileName });
  };

  /* ---------------------------------------------------------------- location permission */
  var MSG_WIU = 'Home Assistant only hears from this phone while the app is open. To report arrivals and departures with the app closed, ';
  LL.locationStages = {
    'not-determined': { title: "Know When You're Home", message: 'This phone can tell Home Assistant when you arrive or leave, so Away mode, the front door reminder and the thermostat follow you.', action: 'Continue', footnote: 'Next, iOS asks to use your location. Choose Allow While Using App.', points: true, status: 'Not Set', symbol: 'location.circle.fill', tone: 'action', preAlert: true },
    'when-in-use': { title: 'Notice When You Leave', message: MSG_WIU + 'location needs to be on all the time.', action: 'Continue', footnote: 'Next, iOS asks to change location access. Choose Change to Always Allow.', points: true, status: 'While Using the App', symbol: 'location.circle.fill', tone: 'action', preAlert: true },
    'when-in-use-asked': { title: 'Notice When You Leave', message: MSG_WIU + 'choose Always in Settings.', action: 'Open Settings', points: false, status: 'While Using the App', symbol: 'location.circle.fill', tone: 'action' },
    'always': { title: 'Home and Away Are On', message: 'Home Assistant hears from this phone when you arrive at or leave a zone, and after you travel a long way.', action: null, points: false, status: 'Always', symbol: 'location.fill', tone: 'action' },
    'denied': { title: 'Location Is Off', message: "Home Assistant can't tell when you're home or away from this phone. In Settings, turn on Location and choose Always.", action: 'Open Settings', points: false, status: 'Off', symbol: 'location.slash.fill', tone: 'danger' },
    'reduced-accuracy': { title: 'Precise Location Is Off', message: "Approximate location can be miles off, so Home Assistant can't tell whether you're home. In Settings, turn on Precise Location.", action: 'Open Settings', points: false, status: 'Always, Approximate', symbol: 'scope', tone: 'warning' },
  };
  LL.locationPoints = [
    { symbol: 'figure.walk.arrival', title: 'Arrivals and Departures', detail: 'Your phone reports when you enter or leave a zone set up in Home Assistant.' },
    { symbol: 'lock.shield', title: 'Only to Your Server', detail: 'Your location goes only to your Home Assistant, never anywhere else.' },
    { symbol: 'battery.75percent', title: 'Light on Battery', detail: 'It listens for zone crossings and long moves instead of running GPS all the time.' },
  ];
  var TONE = { action: 'var(--ink-action)', danger: 'var(--ink-danger)', warning: 'var(--ink-warning)' };
  /** LocationPermissionView's content (inside the sheet's scroll view). */
  LL.locationContent = function (ctx, key) {
    var s = LL.locationStages[key];
    var node = h('div.ll-loc', { style: { '--ltsc': LL.scale(ctx, 'lt'), '--t2sc': LL.scale(ctx, 't2') } },
      h('div.intro', h('span.big', { 'aria-hidden': 'true', style: { color: TONE[s.tone] }, html: I(s.symbol, { fill: true, size: 'calc(56px * var(--ltsc))' }) }), h('h2', { role: 'heading', 'aria-level': '1' }, s.title), h('p.msg', s.message)),
      h('div.ll-stat', { role: 'group', 'aria-label': 'Location Access, ' + s.status }, h('span', 'Location Access'), h('span', { style: { color: s.tone === 'danger' ? 'var(--ink-danger)' : (s.tone === 'warning' ? 'var(--ink-warning)' : 'var(--ink-sheet-2)') } }, s.status)));
    if (s.points) node.appendChild(h('div', { style: { display: 'flex', flexDirection: 'column', gap: '16px' } }, LL.locationPoints.map(function (p) {
      return h('div.ll-pt', { role: 'group', 'aria-label': p.title + '. ' + p.detail }, h('span.g', { 'aria-hidden': 'true', html: I(p.symbol) }), h('div.tx', h('span.ti', p.title), h('span.de', p.detail)));
    })));
    if (s.footnote) node.appendChild(h('p', { style: { fontSize: 'var(--fs-foot)', color: 'var(--ink-sheet-2)' } }, s.footnote));
    if (s.action) node.appendChild(K.PrimaryButton({ title: s.action }));
    return node;
  };
  /** LocationPermissionSheet: hassSheet(.page, height: .full), dark by design, no Close and no swipe-dismiss while it is a pre-alert. */
  LL.locationSheet = function (ctx, key, o) {
    o = o || {}; var s = LL.locationStages[key];
    return Mock.sheet(ctx, { title: 'Location', detent: 'large', size: 'page', leading: 'none', trailing: s.preAlert ? 'none' : 'close', appearance: 'dark', content: LL.locationContent(ctx, key),
      presenter: o.noPresenter ? null : LL.homePage(ctx, { badge: 0 }) });
  };

  /* ---------------------------------------------------------------- Account sheet, Profile tab (for the sign-out flow) */
  var SUMMARY_TABS = [{ id: 'profile', title: 'Profile', symbol: 'person' }, { id: 'overdue', title: 'Overdue Chores', symbol: 'exclamationmark.circle', badge: 3 }, { id: 'upcoming', title: 'Upcoming Chores', symbol: 'checklist' }, { id: 'food', title: 'Expired Food', symbol: 'refrigerator', badge: 2 }];
  function cellRow(label, value, o) {
    o = o || {};
    return h('div.ll-cell', h('span', label), h('span.v', value));
  }
  /** YourSummarySheet's Profile tab: account header, People at Home, Location (phones), Sign Out. o: {location:'Always'|..., signOutBusy} */
  LL.profileList = function (ctx, o) {
    o = o || {};
    var avatar = Math.round(84 * LL.scale(ctx, 'lt'));
    var acc = h('div.ll-acc', { role: 'group', 'aria-label': 'Alex Morgan, ha.example.com' }, h('span.ll-avatar', { 'aria-hidden': 'true', style: { width: avatar + 'px', height: avatar + 'px', fontSize: Math.round(avatar * .4) + 'px' } }, 'AD'), h('p.nm', 'Alex Morgan'), h('p.sv', 'ha.example.com'));
    var people = h('section.ll-sec', h('p.hd', { role: 'heading', 'aria-level': '2' }, 'People at Home'),
      h('div.ll-card', [['Alex', 'AD', '#0022CC', 'Home', true], ['Sam', 'AD', '#B410AE', 'Away', false]].map(function (p) {
        return h('div.ll-cell', { style: { minHeight: 'max(44px, 52px)' } }, h('span.ll-avatar.ll-person', { 'aria-hidden': 'true', style: { background: p[2] } }, p[0] === 'Alex' ? 'AD' : 'SD'), h('span', p[0]), h('span.v', { style: { color: p[4] ? 'var(--ink-success)' : 'var(--ink-sheet-2)' } }, p[3]));
      })), h('div.ft', h('span', '1 of 2 Home')));
    var secs = [h('div', acc), people];
    if (o.location !== false) {
      secs.push(LL.locationSection(ctx, { stage: o.location || 'always' }));
    }
    var out = h('div.ll-cell.ll-signout', { role: 'button', tabIndex: 0, 'aria-label': 'Sign Out' }, 'Sign Out');
    secs.push(h('section.ll-sec', h('div.ll-card', out)));
    var list = h('div.ll-list', secs);
    return list;
  };
  /** LocationAccountSection: header, the Share Location row, warnings and the footer. o: {stage, link} */
  var WARN = { 'not-determined': "Location access isn't set, so nothing is sent. Open Share Location to allow it.", 'denied': 'Location access is off, so nothing is sent. Open Share Location to turn it on in Settings.', 'reduced-accuracy': "Precise Location is off, so Home Assistant can't tell whether you're home." };
  var LINK = { needsAdmin: 'Home Assistant lets only administrators add this iPhone to a person. Ask an administrator to add it to yours.', noPerson: "No person in Home Assistant uses your account yet, so it can't follow this iPhone. Ask an administrator to add one.", trackerMissing: "Home Assistant hasn't created this iPhone's device yet. It will try again at the next sign-in.", failed: "Couldn't add this iPhone to your person. It will try again at the next connection." };
  LL.linkNotices = LINK;
  LL.locationSection = function (ctx, o) {
    o = o || {}; var status = LL.locationStages[o.stage === 'when-in-use' ? 'when-in-use' : (o.stage || 'always')].status;
    var cell = h('button.ll-cell.wrap', { type: 'button', 'aria-label': 'Share Location, ' + status, style: { minHeight: 'max(44px, 52px)', cursor: 'pointer' } },
      h('span', { style: { display: 'inline-flex', alignItems: 'baseline', gap: '8px' } }, h('span', { 'aria-hidden': 'true', style: { color: 'var(--ink)' }, html: I('location.fill', { fill: true }) }), 'Share Location'),
      h('span.v', status), h('span', { 'aria-hidden': 'true', style: { color: 'var(--ink-sheet-2)', fontSize: 'var(--fs-foot)', opacity: .8 }, html: I('chevron.right', { weight: 2.4, size: '.8em' }) }));
    var foot = h('div.ft');
    if (WARN[o.stage]) foot.appendChild(K.InlineAlert({ message: WARN[o.stage] }));
    if (o.link && LINK[o.link]) foot.appendChild(K.InlineAlert({ message: LINK[o.link] }));
    foot.appendChild(h('span', 'Whenever location access is on, this iPhone reports to Home Assistant as its own device, and Home Assistant follows it for the person you sign in as.'));
    foot.style.margin = '8px 0 0';
    return h('section.ll-sec', h('p.hd', { role: 'heading', 'aria-level': '2' }, 'Location'), h('div.ll-card', cell), foot);
  };
  /** YourSummarySheet: hassSheet(.form, height: .full); title "Your Summary"; tab bar with Profile selected. */
  LL.accountSheet = function (ctx, o) {
    o = o || {};
    return Mock.sheet(ctx, { title: 'Your Summary', detent: 'large', size: 'form', trailing: 'close', content: LL.profileList(ctx, o), tabs: K.ModalTabBar({ tabs: SUMMARY_TABS, selected: 'profile', ctx: ctx }), presenter: LL.homePage(ctx), alert: o.alert });
  };
  /** HomeAssistantSettingsView (a full-screen cover; appearance inherited from the shell: drawn as a dark sheet, see the notes). */
  LL.haSettings = function (ctx, o) {
    o = o || {};
    function info(l, v, c) { return h('div.ll-cell.wrap', h('span', l), h('span.v', { style: c ? { color: c } : null }, v)); }
    function link(t, sub, sym) { return h('div.ll-cell', { style: { minHeight: '60px' } }, h('span', { 'aria-hidden': 'true', style: { color: 'var(--ink-sheet-2)', width: 'calc(28px * var(--sc))', display: 'grid', placeItems: 'center' }, html: I(sym) }), h('span', { style: { display: 'flex', flexDirection: 'column', gap: '2px' } }, h('span', t), h('span', { style: { fontSize: 'var(--fs-foot)', color: 'var(--ink-sheet-2)' } }, sub))); }
    var list = h('div.ll-list',
      h('section.ll-sec', h('p.hd', 'Server'), h('div.ll-card', [info('Address', 'ha.example.com'), info('Connection', o.connection || 'Connected'), o.connection ? null : info('Version', '2026.10.2')])),
      h('section.ll-sec', h('p.hd', 'Account'), h('div.ll-card', [info('Signed in as', 'Alex Morgan'), info('Role', 'Owner')])),
      h('section.ll-sec', h('p.hd', 'Home Assistant'), h('div.ll-card', [link('Settings', 'Devices, integrations, automations and system.', 'gearshape'), link('Profile', 'Language, theme and security for this account.', 'person')]), h('div.ft', h('span', "Opens Home Assistant's own pages, signed in as you."))),
      h('section.ll-sec', h('div.ll-card', h('div.ll-cell.ll-signout', { role: 'button', 'aria-label': 'Sign Out' }, 'Sign Out'))));
    return Mock.sheet(ctx, { title: 'Home Assistant', detent: 'large', size: 'form', trailing: 'close', appearance: 'dark', content: list, presenter: LL.homePage(ctx), alert: o.alert });
  };
  /**
   * SwiftUI's confirmationDialog, titleVisibility .visible: an action sheet over the bottom of a phone (the title, the message and the destructive
   * button in one card, Cancel apart), a popover on a regular width (anchored to the Sign Out button; drawn centred here). Cancel always present.
   */
  LL.confirmationDialog = function (ctx, o) {
    var head = h('div.hd', h('b', o.title), h('span', o.message));
    var dk = o.dark ? '.dk' : '';
    if (ctx.compact) return h('div.ll-actionsheet' + dk, { role: 'dialog', 'aria-label': o.title }, h('div.card', head, h('button.destructive', { type: 'button' }, o.destructive)), h('div.card', h('button.cancel', { type: 'button' }, 'Cancel')));
    return h('div.ll-popover' + dk, { role: 'dialog', 'aria-label': o.title }, head, h('button.destructive', { type: 'button' }, o.destructive), h('button', { type: 'button', style: { fontWeight: 600 } }, 'Cancel'));
  };

  /** K.Alert that follows accessibility sizes: the buttons stack and the alert widens (UIAlertController grows with the text). */
  LL.alert = function (o) {
    var ax = Mock.current && Mock.current.axSize, a = K.Alert(Object.assign({}, o, ax ? { stacked: true } : null));
    if (ax) { a.style.width = 'calc(100% - 32px)'; a.style.maxWidth = '100%'; }
    return a;
  };

  /* ---------------------------------------------------------------- component mockup helpers */
  /** A swatch on the sign-in ground for a component mockup (frame:false pages). */
  LL.swatch = function (caption, kids, o) {
    return h('div.k-swatch.ll-swatch', { style: { flex: (o && o.flex) || '1 1 300px', maxWidth: '100%' } }, h('div.k-cap', caption), h('div.in', kids));
  };
  LL.sheetSwatch = function (ctx, caption, kids, o) {
    return h('div.k-swatch.sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light'), { style: { flex: (o && o.flex) || '1 1 340px', maxWidth: '100%' } }, h('div.k-cap', ctx.appearance + ' sheet · ' + caption), h('div.in', kids));
  };
  LL.grid = function (kids) { return h('div.k-swatch-grid', kids); };

  /** Shared author-draft review rows. */
  LL.rev = {
    hig: {
      darkMode: { rule: 'Dark Mode: support both appearances, or declare one', verdict: 'pass', note: 'Always dark by design (direction-g Sign-in; preferredColorScheme(.dark)), so the system appearance never changes it.' },
      motion: { rule: 'Motion: make motion optional, brief and precise', verdict: 'pass', note: 'Moments only, tokens from MotionTokens; Reduce Motion cross-fades once over 0.35 s.' },
      targets: { rule: 'Touch targets: at least 44 x 44 pt', verdict: 'pass', note: 'Rows are 52 pt, the button 50 pt, the text button and the Details row 44 pt.' },
    },
  };
})();
