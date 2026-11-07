/* Mock.HW: local helpers for the home-weather batch (Home page, Weather card, Weather sheet and its panels, status chips and rail, guests, tile and colour reference).
 * Not part of the kit. Loaded with <script src="..."> after kit.js; nothing here edits the kit.
 *
 * PROMOTE TO KIT (notes in each mockup repeat these):
 *   - icons eye.fill, sunrise.fill, sunset.fill, location.north.fill, gauge.with.dots.needle.33percent (HW.icon draws them locally);
 *   - the weather card with the page indicator and Previous / Next (HW.card): the kit's WeatherCard shows six static hours, draws the hour time at 15 pt
 *     (the app: footnote 13 pt semibold) and the temperature at 15 pt (the app: body 17 pt medium), and its AX5 numeral is 118 pt (the app caps it at 96);
 *   - the "was" (main) header, HW.wasHeader;
 *   - the first-sign-in card: the app draws "--" and "Weather Unavailable" with static placeholder hours (HW.card {loading:true}), not pulsing bars;
 *   - the weather sheet panels (HW.sheetBody and the tiles).
 * Everything is sized with the kit's Dynamic Type variables (--fs-*, --sc); colours are the real tokens (WeatherSurface, WeatherBackdrop, WeatherRail).
 * Sources: apple/Sources/HassUI/Features/Home/Weather/*.swift; sample data is WeatherFixtures (Gallery), not the live house.
 */
(function () {
  if (window.Mock && Mock.HW) return;
  var h = Mock.h, I = Mock.icon;
  var HW = Mock.HW = {};
  function K() { return Mock.components; }
  function rm() { return !!Mock.settings.reduceMotion; }

  /* ------------------------------------------------------------------ styles */
  var css = [
    /* WeatherSurface: translucent dark wash, 22 pt, 14% hairline, white ink. */
    '.hw-surface{padding:16px;border-radius:var(--radius-tile);background:rgba(0,0,0,.28);box-shadow:inset 0 0 0 1px rgba(255,255,255,.14);color:#fff;min-width:0;text-align:left}',
    '.hw-surface.tile{padding:12px}',
    '.hw-sheet{display:flex;flex-direction:column;gap:16px;color:#fff;font-family:var(--font);padding:0 0 8px}',
    '.hw-sheet h2,.hw-sheet h3{margin:0}',
    '.hw-hd{font:600 var(--fs-hd)/1.2 var(--font)}',
    '.hw-sec2{color:rgba(255,255,255,.85)}',
    '.hw-foot{font-size:var(--fs-foot)}',
    '.hw-hero{display:flex;flex-direction:column;align-items:center;gap:4px;padding:12px 0;text-align:center}',
    '.hw-hero .deg{font:200 calc(76 * var(--fs-lt) / 34)/1.1 var(--font-d);font-variant-numeric:tabular-nums;white-space:nowrap}',
    '.hw-hero .cond{font:600 var(--fs-t3)/1.2 var(--font)}',
    '.hw-hero .hl{font:600 var(--fs-sub)/1.2 var(--font);color:rgba(255,255,255,.85)}',
    /* briefing */
    '.hw-brief .top{display:flex;align-items:center;gap:12px}',
    '.hw-brief .lab{font:600 var(--fs-foot)/1.2 var(--font);color:rgba(255,255,255,.85)}',
    '.hw-brief .head{font:700 var(--fs-t3)/1.2 var(--font)}',
    '.hw-brief ul{list-style:none;margin:12px 0 0;padding:0;display:flex;flex-direction:column;gap:8px}',
    '.hw-brief li{display:flex;gap:8px;font-size:var(--fs-sub);line-height:1.3}',
    '.hw-brief .ic{flex:none;width:32px;height:32px;display:grid;place-items:center;font-size:var(--fs-t1)}',
    '.hw-brief .ic .ui-sym{width:1em;height:1em}',
    '.hw-brief .ic svg.gl{width:min(calc(32px * var(--sc)),64px);height:min(calc(32px * var(--sc)),64px)}',
    '.hw-brief .ic{width:auto;min-width:32px}',
    /* panels */
    '.hw-ph{display:flex;align-items:center;justify-content:space-between;gap:8px}',
    '.hw-ph.ax{flex-direction:column;align-items:flex-start}',
    '.hw-modes{display:flex;background:rgba(0,0,0,.22);border-radius:999px}',
    '.hw-modes button{width:44px;height:44px;border:0;border-radius:999px;background:none;color:#fff;display:grid;place-items:center;cursor:pointer;padding:0;font-size:var(--fs-body)}',
    '.hw-modes button[aria-checked="true"]{background:rgba(255,255,255,.24)}',
    '.hw-modes svg{width:1.05em;height:1.05em}',
    '.hw-msg{min-height:44px;display:flex;align-items:center;font-size:var(--fs-sub);color:rgba(255,255,255,.85)}',
    '.hw-mainbody{transition:opacity var(--t-quick) var(--ease-quick)}',
    '.hw-mainbody.sw{opacity:0}',
    /* carousel */
    '.hw-carwrap{position:relative;display:flex;flex-direction:column;gap:4px}',
    '.hw-carwrap.ctl .hw-car{margin:0 52px}',
    '.hw-car{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;scrollbar-width:none;outline-offset:2px}',
    '.hw-car::-webkit-scrollbar{display:none}',
    '.hw-car>*{flex:0 0 calc(100% / var(--pp));min-width:0;scroll-snap-align:start}',
    '.hw-dots{display:flex;justify-content:center;align-items:center;gap:6px;min-height:44px}',
    '.hw-dots i{display:block;height:7px;width:7px;border-radius:99px;background:rgba(255,255,255,.45);transition:width var(--t-quick) var(--ease-quick),background var(--t-quick) var(--ease-quick)}',
    '.hw-dots i.on{width:18px;background:#fff}',
    '.hw-nav{position:absolute;top:calc(50% - 22px - 24px);width:44px;height:44px;border-radius:50%;background:rgba(0,0,0,.35);box-shadow:inset 0 0 0 1px rgba(255,255,255,.25);border:0;color:#fff;display:grid;place-items:center;cursor:pointer;padding:0;transition:opacity var(--t-quick) var(--ease-quick)}',
    '.hw-nav[disabled]{opacity:.55;cursor:default}',   // one fade (owner 2026-10-27, weather-chevron-contrast A)
    '.hw-nav.p{left:0}.hw-nav.n{right:0}',
    '.hw-nav svg{width:18px;height:18px}',
    /* hours: card and sheet */
    '.hw-hc{min-height:72px;padding:4px 0;display:flex;flex-direction:column;align-items:center;gap:4px;text-align:center}',
    '.hw-hc .t{font:600 var(--fs-foot)/1.2 var(--font);white-space:nowrap}',
    '.hw-hc .d{font:500 var(--fs-body)/1.2 var(--font);font-variant-numeric:tabular-nums}',
    '.hw-hc svg.gl{width:min(calc(22px * var(--sc)),44px);height:min(calc(22px * var(--sc)),44px);display:block}',
    '.hw-hs{min-height:112px;padding:4px 0;display:flex;flex-direction:column;align-items:center;gap:8px;text-align:center}',
    '.hw-hs .t{font-size:var(--fs-sub);color:rgba(255,255,255,.85);white-space:nowrap}',
    '.hw-hs .d{font:700 var(--fs-sub)/1.2 var(--font);font-variant-numeric:tabular-nums;white-space:nowrap}',
    '.hw-hs .d2{font-size:var(--fs-c1);color:rgba(255,255,255,.85);font-variant-numeric:tabular-nums;white-space:nowrap}',
    '.hw-hs .v{display:grid;place-items:center;height:30px}',
    '.hw-hs svg.gl{width:min(calc(30px * var(--sc)),60px);height:min(calc(30px * var(--sc)),60px);display:block}',
    '.hw-hs .v{height:auto;min-height:30px}',
    '.hw-hs .ui-sym{width:26px;height:26px}',
    '.hw-ph0{display:flex;flex-direction:column;align-items:center}',
    '.hw-skel{background:rgba(255,255,255,.16);border-radius:99px;display:block}',
    /* daily rows */
    '.hw-day{display:flex;align-items:center;gap:8px;min-height:44px;padding:4px 0;font-size:var(--fs-sub)}',
    '.hw-day.ax{flex-direction:column;align-items:flex-start;gap:4px}',
    '.hw-day .dn{font-weight:700;width:calc(48px * var(--sc));flex:none}',
    '.hw-day.ax .dn{width:auto}',
    '.hw-day .dt{display:flex;align-items:center;gap:8px;flex:1;min-width:0;width:100%}',
    '.hw-day .ic{width:32px;flex:none;display:grid;place-items:center}',
    '.hw-day .ic svg.gl{width:min(calc(26px * var(--sc)),52px);height:min(calc(26px * var(--sc)),52px)}',
    '.hw-day .vl{font-weight:700;min-width:calc(40px * var(--sc));text-align:right;font-variant-numeric:tabular-nums}',
    '.hw-day .vl.w{font-weight:400;min-width:calc(54px * var(--sc))}',
    '.hw-day .wr{font-weight:700;font-variant-numeric:tabular-nums}',
    '.hw-sep{height:1px;background:rgba(255,255,255,.14);border:0;margin:0}',
    /* rails */
    '.hw-rail{position:relative;height:12px;min-width:48px;flex:none;width:100%;border-radius:99px;background:rgba(255,255,255,.22)}',
    '.hw-day .hw-rail{flex:1;width:auto}',
    '.hw-rail .fill{position:absolute;top:0;bottom:0;border-radius:99px;transition:left var(--t-standard) var(--ease-standard),width var(--t-standard) var(--ease-standard)}',
    '.hw-rail .mk{position:absolute;top:0;width:12px;height:12px;border-radius:50%;background:#fff;box-shadow:inset 0 0 0 1.5px rgba(0,0,0,.45);transition:left var(--t-standard) var(--ease-standard)}',
    '.k-reduce-motion .hw-rail .fill,.k-reduce-motion .hw-rail .mk{transition:none}',
    /* tiles */
    '.hw-tile .hdr{display:flex;align-items:center;gap:6px;font:600 var(--fs-foot)/1.2 var(--font);color:rgba(255,255,255,.85);margin-bottom:8px}',
    '.hw-tile .hdr .ui-sym{width:1.15em;height:1.15em}',
    '.hw-tile .val{font:700 var(--fs-t2)/1.15 var(--font);font-variant-numeric:tabular-nums}',
    '.hw-tile .val.big{font-size:var(--fs-t1)}',
    '.hw-tile .row{display:flex;align-items:baseline;gap:8px;flex-wrap:wrap}',
    '.hw-tile .st{font-size:var(--fs-foot);color:rgba(255,255,255,.85)}',
    '.hw-tile.big .st{font-size:var(--fs-sub)}',
    '.hw-tile .stack{display:flex;flex-direction:column;gap:8px}',
    '.hw-tile .na{font-size:var(--fs-sub);color:rgba(255,255,255,.85)}',
    '.hw-tile .dim{color:rgba(255,255,255,.35);font-size:var(--fs-t1)}',
    '.hw-tile .dim .ui-sym{width:1em;height:1em}',
    '.hw-wind{display:flex;align-items:center;gap:12px;justify-content:space-between}',
    '.hw-wind.ax{flex-direction:column;align-items:flex-start}',
    '.hw-wind .kv{display:flex;flex-direction:column;gap:8px}',
    '.hw-wind .kv span{display:block;font-size:var(--fs-foot);color:rgba(255,255,255,.85)}',
    '.hw-wind .kv b{display:block;font:600 var(--fs-hd)/1.2 var(--font);font-variant-numeric:tabular-nums}',
    '.hw-compass{width:min(calc(104px * var(--sc)),160px);aspect-ratio:1;flex:none}',
    '.hw-compass .nd{transform-origin:52px 52px;transition:transform var(--t-standard) var(--ease-standard)}',
    '.k-reduce-motion .hw-compass .nd{transition:none}',
    '.hw-gauge{position:relative;aspect-ratio:1.4;width:100%;max-width:200px}',
    '.hw-gauge svg{position:absolute;inset:0;width:100%;height:100%}',
    '.hw-gauge .tx{position:absolute;left:0;right:0;top:56%;transform:translateY(-50%);margin-top:4px;text-align:center;display:flex;flex-direction:column;align-items:center}',
    '.hw-gauge .tx b{font:600 var(--fs-t3)/1.1 var(--font);font-variant-numeric:tabular-nums}',
    '.hw-gauge .tx i{font-style:normal;font-size:var(--fs-c2);color:rgba(255,255,255,.85)}',
    '.hw-sunarc{width:100%;max-width:200px;aspect-ratio:100/48;display:block}',
    /* bar chart */
    '.hw-chart{display:flex;gap:4px;align-items:flex-start}',
    '.hw-chart .y{display:flex;flex-direction:column;justify-content:space-between;align-items:flex-end;height:76px;font-size:var(--fs-c2);color:rgba(255,255,255,.85);white-space:nowrap}',
    '.hw-chart .pl{flex:1;min-width:0;display:flex;flex-direction:column;gap:4px}',
    '.hw-chart .bars{position:relative;height:76px;display:flex;align-items:flex-end;gap:2px}',
    '.hw-chart .gl3{position:absolute;inset:0;display:flex;flex-direction:column;justify-content:space-between;pointer-events:none}',
    '.hw-chart .gl3 i{display:block;height:1px;background:rgba(255,255,255,.14)}',
    '.hw-chart .bars b{flex:1;border-radius:2px;display:block;position:relative}',
    '.hw-chart .xa{display:flex;gap:2px}',
    '.hw-chart .xa span{flex:1;position:relative;height:1.3em;font-size:var(--fs-c2);color:rgba(255,255,255,.85)}',
    '.hw-chart .xa span i{font-style:normal;position:absolute;left:0;white-space:nowrap}',
    /* grid */
    '.hw-grid .ui-grid{width:100%}',
    '.hw-grid .ui-grid>.hw-tile{min-width:0}',
    /* backdrop */
    '.hw-bd{position:absolute;inset:0;overflow:hidden;z-index:0}',
    '.hw-bd .dec{position:absolute;inset:0;pointer-events:none}',
    '.hw-bd .dec i{position:absolute;display:block}',
    '.k-reduce-transparency .hw-bd .dec{display:none}',
    '.hw-bd .rain i{width:1px;height:26px;background:rgba(255,255,255,.16);transform:skewX(-10deg);top:calc(var(--p) * (100% + 26px) - 26px);animation:hw-fall var(--dur) linear var(--dly) infinite}',
    '.hw-bd .snow i{width:2.5px;height:5px;border-radius:2px;background:rgba(255,255,255,.3);top:calc(var(--p) * (100% + 5px) - 5px);animation:hw-fall5 var(--dur) linear var(--dly) infinite}',
    '@keyframes hw-fall{from{top:-26px}to{top:100%}}',
    '@keyframes hw-fall5{from{top:-5px}to{top:100%}}',
    '.k-reduce-motion .hw-bd .rain i,.k-reduce-motion .hw-bd .snow i{animation:none}',
    /* weather swatch surfaces (component pages) */
    '.hw-wsw{padding:14px;border-radius:16px;color:#fff;min-width:0;position:relative;overflow:hidden}',
    '.hw-wsw>.k-cap{position:relative;z-index:1;font:600 11px var(--mono);letter-spacing:.04em;margin-bottom:8px;opacity:.65}',
    '.hw-wsw>.in{position:relative;z-index:1}',
    '.hw-win{display:flex;flex-direction:column;gap:12px;padding:0 16px;box-sizing:border-box}',
    '.hw-win.flush{padding:0}',
    '.hw-note{font:12px var(--font);opacity:.7;margin-top:8px;max-width:420px}',
    /* the card */
    '.hw-card{color:#fff}',
    '.ts-ax5 .hw-card,.ts-ax5.hw-card{--wx-num:96px}',
    '.hw-card .brief{margin:0;font-size:var(--fs-body);line-height:1.3}',
    '.hw-card hr{border:0;height:1px;background:rgba(255,255,255,.14);margin:12px 0}',
    '.hw-card .msg{min-height:72px;display:flex;align-items:center;font-size:var(--fs-foot);color:rgba(255,255,255,.85)}',
    /* the main (was) header */
    '.hw-was{align-items:center;gap:12px}',
    '.hw-was .hero{display:flex;align-items:center;gap:12px;min-height:44px;flex:none}',
    '.hw-was .sp{flex:1;min-width:8px}',
    '.hw-was .tr{display:flex;flex-direction:column;align-items:flex-end;gap:2px;min-width:0}',
    '.hw-was .lr{display:flex;align-items:center;gap:4px}',
    '.hw-was .lab{font:600 var(--fs-hd)/1.25 var(--font);text-align:right;white-space:normal}',
    '.hw-was .hl{font-size:var(--fs-body)}',
    '.hw-was.ax{flex-direction:column;align-items:stretch;gap:8px}',
    '.hw-was.ax .hero{flex-direction:column;align-items:flex-start;gap:4px}',
    '.hw-was.ax .tr{align-items:flex-start}',
    '.hw-was.ax .lab{text-align:left}',
    '.hw-was.bug .hero{flex:0 1 auto;min-width:0}',
    '.hw-was.bug .num{min-width:0;overflow:hidden;text-overflow:ellipsis}',
    '.hw-was.bug .tr{flex:none}',
    /* chip variants */
    '.hw-inert{pointer-events:none}',
  ].join('\n');
  document.head.appendChild(h('style', { id: 'hw-style' }, css));

  /* ------------------------------------------------------------------ icons the kit lacks (promote to kit) */
  var LI = {
    'eye.fill': '<path fill-rule="evenodd" d="M12 5.5C6 5.5 2.5 12 2.5 12S6 18.5 12 18.5 21.5 12 21.5 12 18 5.5 12 5.5zm0 4.7a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6z"/>',
    'sunset.fill': '<path d="M6.8 16.5a5.2 5.2 0 0 1 10.4 0z"/><path d="M3 19.5h18M12 3.5v4M5 8l2 2M19 8l-2 2M9 5.8l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" transform="translate(0 2)"/>',
    'sunrise.fill': '<path d="M6.8 16.5a5.2 5.2 0 0 1 10.4 0z"/><path d="M3 19.5h18M12 3v4M5 8l2 2M19 8l-2 2M9 5.5 12 2.500l3 3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" transform="translate(0 2)"/>',
    'location.north.fill': '<path d="M12 3 18.5 20.5 12 17 5.500 20.500z"/>',
    'gauge.with.dots.needle.33percent': '<path d="M5.500 18a8.500 8.500 0 1 1 13 0" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M12 13.500 8.500 9.500" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="13.500" r="1.600"/>',
  };
  /** Mock.icon, plus the few symbols the kit lacks. Returns an SVG string. */
  HW.icon = function (name, o) {
    if (LI[name]) {
      o = o || {};
      return '<svg class="ui-sym" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"' + (o.size ? ' style="width:' + o.size + ';height:' + o.size + '"' : '') + '>' + LI[name] + '</svg>';
    }
    return I(name, o);
  };

  /* ------------------------------------------------------------------ fixtures (Gallery/WeatherFixtures.swift) */
  var GL = { rainy: 'rain', pouring: 'rain', cloudy: 'cloudy', partlycloudy: 'partly-cloudy', sunny: 'sunny', 'clear-night': 'clear-night', 'lightning-rainy': 'storm', lightning: 'storm', snowy: 'snow' };
  function r(x) { return Math.floor(x + .5); }
  function hr12(hr) { var h12 = hr % 12 || 12; return h12 + (hr % 24 < 12 ? ' AM' : ' PM'); }
  /** 24 hours from the 9 AM hour: rain easing to cloud, then clear (the gallery's `hourly`). preset 'home' is the Home page sample (partly cloudy, 48 to 58). */
  HW.hours = function (preset) {
    var out = [], conds = ['rainy', 'rainy', 'pouring', 'rainy', 'cloudy', 'cloudy', 'partlycloudy', 'partlycloudy', 'sunny', 'sunny', 'clear-night', 'clear-night'];
    var homeT = [48, 52, 55, 57, 58, 58, 57, 55, 52, 50, 49, 48], homeG = ['partlycloudy', 'sunny', 'sunny', 'partlycloudy', 'cloudy', 'cloudy', 'cloudy', 'partlycloudy', 'clear-night', 'clear-night', 'clear-night', 'clear-night'];
    for (var i = 0; i < 24; i++) {
      var wet = i < 5, lab = i === 0 ? 'Now' : hr12((preset === 'home' ? 10 : 9) + i);
      var cond = preset === 'home' ? homeG[i % 12] : conds[Math.floor(i / 2) % 12];
      out.push({ t: lab, cond: cond, g: GL[cond] || 'cloudy', temp: preset === 'home' ? homeT[i % 12] : r(72 - (i % 12) * .8), prob: wet ? 80 - i * 8 : 5, amt: wet ? .04 + i * .01 : 0, hum: 58 + (i % 6) * 3, cloud: wet ? 90 : 40,
        wind: 8 + (i % 5), gust: 14 + (i % 5) * 2, bearing: 250 + i * 4 });
    }
    return out;
  };
  /** Seven days from today (the gallery's `daily`). */
  HW.days = function () {
    var names = ['Today', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu'], conds = ['rainy', 'partlycloudy', 'sunny', 'sunny', 'cloudy', 'pouring', 'lightning-rainy'];
    return names.map(function (n, i) { return { n: n, cond: conds[i], g: GL[conds[i]], hi: 78 + (i % 4) * 3, lo: 58 + (i % 3) * 2, prob: i === 0 ? 70 : i >= 5 ? 60 : 10, amt: (i === 0 || i >= 5) ? .3 : 0, wind: 8 + i, gust: 15 + i * 2, bearing: 220 + i * 20 }; });
  };
  /** Current conditions (the gallery's weather entity): 72 F, feels 75, wind 9 mph gusting 14 from 250 degrees, 29.92 inHg, 10 mi, AQI 72. */
  HW.current = { temp: 72, feels: 75, hum: 58, wind: 9, gust: 14, bearing: 250, pressure: '29.92', pressureUnit: 'inHg', pressurePct: 54, vis: '10 mi', aqi: 72, uv: 7 };

  /* ------------------------------------------------------------------ backdrops (WeatherBackdrop.colors, WeatherDecoration) */
  function rgb(a, b, c) { return 'rgb(' + Math.round(a * 255) + ',' + Math.round(b * 255) + ',' + Math.round(c * 255) + ')'; }
  HW.scenes = {
    sunny: { label: 'Clear (sunny)', top: rgb(.13, .40, .78), bottom: rgb(.05, .17, .40), cond: 'Sunny', g: 'sunny' },
    night: { label: 'Night', top: rgb(.07, .09, .27), bottom: rgb(.02, .03, .10), cond: 'Clear Night', g: 'clear-night' },
    clouds: { label: 'Clouds', top: rgb(.28, .36, .46), bottom: rgb(.11, .15, .22), cond: 'Partly Cloudy', g: 'partly-cloudy' },
    fog: { label: 'Fog', top: rgb(.34, .39, .44), bottom: rgb(.15, .18, .22), cond: 'Fog', g: 'cloudy' },
    rain: { label: 'Rain', top: rgb(.20, .28, .40), bottom: rgb(.07, .11, .19), cond: 'Rain', g: 'rain' },
    storm: { label: 'Storm', top: rgb(.19, .16, .33), bottom: rgb(.06, .05, .13), cond: 'Lightning', g: 'storm' },
    snow: { label: 'Snow', top: rgb(.30, .40, .52), bottom: rgb(.12, .18, .28), cond: 'Snow', g: 'snow' },
    wind: { label: 'Wind', top: rgb(.14, .40, .46), bottom: rgb(.05, .16, .20), cond: 'Windy', g: 'cloudy' },
    exceptional: { label: 'Exceptional', top: rgb(.45, .25, .12), bottom: rgb(.17, .09, .05), cond: 'Exceptional', g: 'cloudy' },
    neutral: { label: 'Neutral', top: rgb(.22, .30, .42), bottom: rgb(.08, .11, .18), cond: 'Cloudy', g: 'cloudy' },
  };
  HW.gradient = function (scene) { var s = HW.scenes[scene] || HW.scenes.neutral; return 'linear-gradient(180deg,' + s.top + ',' + s.bottom + ')'; };
  /** The gradient plus its decoration. opts.decorated (default true): the sheet's scrolling page draws it, the presentation background does not. */
  HW.backdrop = function (scene, o) {
    var el = h('div.hw-bd', { 'aria-hidden': 'true', style: { background: HW.gradient(scene) }, dataset: { scene: scene } });
    if (o && o.decorated === false) return el;
    var dec = h('div.dec');
    if (scene === 'night') {
      for (var i = 0; i < 34; i++) {
        var x = (i * 0.6180339887) % 1, y = ((i * 0.3247179572 + 0.17) % 1) * 0.7, s = i % 7 === 0 ? 2.4 : i % 3 === 0 ? 1.8 : 1.2, op = i % 7 === 0 ? .5 : .24 + (i % 4) * .04;
        dec.appendChild(h('i', { style: { left: (x * 100) + '%', top: (y * 100) + '%', width: s + 'px', height: s + 'px', borderRadius: '50%', background: 'rgba(255,255,255,' + op + ')' } }));
      }
    } else if (scene === 'clouds' || scene === 'fog' || scene === 'wind' || scene === 'neutral' || scene === 'exceptional') {
      [[-.1, .08, .7], [.4, .22, .8], [-.05, .42, .65], [.5, .6, .7], [0, .78, .75]].forEach(function (b, i) {
        dec.appendChild(h('i', { style: { left: (b[0] * 100) + '%', top: (b[1] * 100) + '%', width: (b[2] * 100) + '%', height: '16%', borderRadius: '999px', background: 'rgba(255,255,255,' + (scene === 'fog' ? .07 : .045 + (i % 2) * .015) + ')' } }));
      });
    } else if (scene === 'rain' || scene === 'storm' || scene === 'snow') {
      var snow = scene === 'snow', n = snow ? 30 : 36;
      dec.classList.add(snow ? 'snow' : 'rain');
      for (var j = 0; j < n; j++) {
        var seed = j * 0.618033988, px = seed % 1, speed = .12 + (j % 5) * .03, prog = (seed * 3) % 1, dur = 1 / speed;
        dec.appendChild(h('i', { style: { left: (px * 100) + '%', '--p': prog.toFixed(4), '--dur': dur.toFixed(2) + 's', '--dly': (-prog * dur).toFixed(2) + 's' } }));
      }
    } else if (scene === 'sunny') {
      dec.appendChild(h('i', { style: { left: '10%', top: '-4%', width: '90%', paddingTop: '90%', borderRadius: '50%', background: 'radial-gradient(circle at 100% 0, rgba(255,255,255,.16), rgba(255,255,255,0) 55%)' } }));
    }
    el.appendChild(dec);
    return el;
  };

  /* ------------------------------------------------------------------ small builders */
  HW.perPage = function (ctx, compact, regular) {
    var base = ctx.regular ? regular : compact, f = ctx.ts === 'ax5' ? .34 : (ctx.ts === 'xxxl' ? .8 : 1);
    return Math.max(2, Math.round(base * f));
  };
  HW.surface = function (cls, kids, attrs) { return h('div.hw-surface' + (cls ? '.' + cls : ''), attrs || {}, kids); };

  /** A horizontally paging row (WeatherPagedCarousel): cells snap to pages, a page indicator, and Previous / Next on regular layouts. o: {count, perPage, cell(i), label, id} */
  HW.carousel = function (ctx, o) {
    var pp = o.perPage, pages = Math.ceil(o.count / pp), regular = ctx.regular && pages > 1;
    var row = h('div.hw-car', { style: { '--pp': pp }, role: 'group', 'aria-label': o.label, tabindex: 0, dataset: { id: o.id || '' } });
    for (var i = 0; i < o.count; i++) row.appendChild(o.cell(i));
    var wrap = h('div.hw-carwrap' + (regular ? '.ctl' : ''), row);
    var dots = null, prev = null, next = null;
    function page() { return Math.max(0, Math.min(pages - 1, Math.round(row.scrollLeft / Math.max(1, row.clientWidth)))); }
    function sync() {
      var p = page();
      if (dots) Array.prototype.forEach.call(dots.children, function (d, k) { d.classList.toggle('on', k === p); });
      if (dots) dots.setAttribute('aria-valuetext', 'Page ' + (p + 1) + ' of ' + pages);
      if (prev) prev.disabled = p === 0;
      if (next) next.disabled = p >= pages - 1;
    }
    function go(p) { p = Math.max(0, Math.min(pages - 1, p)); row.scrollTo({ left: p * row.clientWidth, behavior: rm() ? 'auto' : 'smooth' }); }
    if (pages > 1) {
      dots = h('div.hw-dots', { role: 'slider', tabindex: 0, 'aria-label': o.label + ' pages', 'aria-valuemin': 1, 'aria-valuemax': pages, 'aria-valuenow': 1 });
      for (var k = 0; k < pages; k++) dots.appendChild(h('i' + (k === 0 ? '.on' : '')));
      dots.addEventListener('keydown', function (e) { if (e.key === 'ArrowRight' || e.key === 'ArrowUp') { go(page() + 1); e.preventDefault(); } if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { go(page() - 1); e.preventDefault(); } });
      dots.addEventListener('click', function (e) { var rc = dots.getBoundingClientRect(); go(e.clientX > rc.left + rc.width / 2 ? page() + 1 : page() - 1); });
      wrap.appendChild(dots);
      row.addEventListener('scroll', function () { var p = page(); dots.setAttribute('aria-valuenow', p + 1); sync(); });
    }
    if (regular) {
      prev = h('button.hw-nav.p', { type: 'button', 'aria-label': 'Previous ' + o.label, html: I('chevron.left', { weight: 2.4 }) });
      next = h('button.hw-nav.n', { type: 'button', 'aria-label': 'Next ' + o.label, html: I('chevron.right', { weight: 2.4 }) });
      prev.addEventListener('click', function () { go(page() - 1); }); next.addEventListener('click', function () { go(page() + 1); });
      wrap.appendChild(prev); wrap.appendChild(next);
    }
    sync();
    wrap.goTo = go;
    return wrap;
  };

  /** WeatherRail: a track, an optional coloured span and an optional marker. tone: temperature feels precipitation visibility uv aqi. range: {marker, size, start} in percent. */
  var TONES = {
    temperature: ['#5CCCFF', '#FFD94D', '#FF8C33'], feels: ['#5CCCFF', '#D9E0EB', '#FF8C33'], precipitation: ['#59B3FF', '#59B3FF'], visibility: ['#BFCCDB', '#FFFFFF'],
    uv: ['#4DD973', '#FFD940', '#FF8C33', '#F24D4D', '#B366F2'], aqi: ['#4DD973', '#FFD940', '#FF8C33', '#F24D4D', '#B366F2', '#A63352'],
  };
  HW.rail = function (tone, range) {
    range = range || {};
    var scale = tone === 'aqi' || tone === 'feels' || tone === 'uv', start = scale ? 0 : (range.start || 0), size = scale ? 100 : Math.min(range.size || 0, 100 - start);
    var el = h('div.hw-rail', { 'aria-hidden': 'true' });
    el.appendChild(h('span.fill', { style: { left: start + '%', width: size + '%', opacity: size > 0 ? 1 : 0, background: 'linear-gradient(90deg,' + TONES[tone].join(',') + ')' } }));
    if (range.marker != null) el.appendChild(h('span.mk', { style: { left: 'calc((100% - 12px) * ' + (Math.max(0, Math.min(100, range.marker)) / 100) + ')' } }));
    return el;
  };

  /** The wind compass (WeatherCompass): 48 ticks, north marker, letters, needle that points where the wind blows to, dot at the side it comes from. */
  HW.compass = function (source) {
    var c = 52, R = 52, ticks = '';
    for (var i = 1; i < 48; i++) {
      var long = i % 2 === 0, th = i * Math.PI * 2 / 48 - Math.PI / 2, a = R * .92, b = R * (long ? .80 : .85);
      ticks += '<line x1="' + (c + Math.cos(th) * a).toFixed(2) + '" y1="' + (c + Math.sin(th) * a).toFixed(2) + '" x2="' + (c + Math.cos(th) * b).toFixed(2) + '" y2="' + (c + Math.sin(th) * b).toFixed(2) + '" stroke="rgba(255,255,255,.55)" stroke-width="1.2"/>';
    }
    var fs = Math.max(10, R * .2);
    function L(t, x, y) { return '<text x="' + (c + R * x) + '" y="' + (c + R * y) + '" fill="#fff" font-size="' + fs + '" font-weight="600" text-anchor="middle" dominant-baseline="central" font-family="ui-rounded,-apple-system,sans-serif">' + t + '</text>'; }
    var s = 104, needle = '<g class="nd" style="transform:rotate(' + (source == null ? 0 : source) + 'deg)' + (source == null ? ';display:none' : '') + '"><path d="M' + s * .45 + ' ' + s * .5 + 'L' + s * .55 + ' ' + s * .5 + 'L' + s * .5 + ' ' + s * .74 + 'Z" fill="#FFD14D"/><path d="M' + s * .45 + ' ' + s * .5 + 'L' + s * .55 + ' ' + s * .5 + 'L' + s * .52 + ' ' + s * .32 + 'L' + s * .48 + ' ' + s * .32 + 'Z" fill="rgba(255,255,255,.55)"/><circle cx="' + s * .5 + '" cy="' + s * .29 + '" r="' + s * .035 + '" fill="#fff"/></g>';
    return Mock.html('<svg class="hw-compass" viewBox="0 0 104 104" aria-hidden="true">' + ticks + '<path d="M52 ' + (c - R * .94) + 'L' + (c + R * .06) + ' ' + (c - R * .84) + 'L' + (c - R * .06) + ' ' + (c - R * .84) + 'Z" fill="#fff"/>' + L('N', 0, -.58) + (source != null ? L('E', .58, 0) + L('W', -.58, 0) : '') + L('S', 0, .58) + needle + '</svg>');
  };
  /** The barometer (WeatherPressureGauge): 49 ticks over a 250 degree arc, the current reading's tick lit; the value is real text in the dial. */
  HW.gauge = function (pct, value, unit) {
    var cx = 70, cy = 56, R = 70, t = '';
    function tick(p, a, b) { var an = (145 + Math.min(100, Math.max(0, p)) / 100 * 250) * Math.PI / 180; return [cx + Math.cos(an) * R * a, cy + Math.sin(an) * R * a, cx + Math.cos(an) * R * b, cy + Math.sin(an) * R * b]; }
    for (var i = 0; i < 49; i++) { var q = tick(i / 48 * 100, .78, .92); t += '<line x1="' + q[0].toFixed(2) + '" y1="' + q[1].toFixed(2) + '" x2="' + q[2].toFixed(2) + '" y2="' + q[3].toFixed(2) + '" stroke="rgba(255,255,255,.5)" stroke-width="1.4"/>'; }
    var cur = tick(pct, .70, .98);
    return h('div.hw-gauge', { 'aria-hidden': 'true' }, Mock.html('<svg viewBox="0 0 140 100">' + t + '<line x1="' + cur[0].toFixed(2) + '" y1="' + cur[1].toFixed(2) + '" x2="' + cur[2].toFixed(2) + '" y2="' + cur[3].toFixed(2) + '" stroke="#FFD14D" stroke-width="3" stroke-linecap="round"/></svg>'),
      h('div.tx', h('b', value), unit ? h('i', unit) : null));
  };
  /** The daylight arc (WeatherSunArc) with the sun at its progress (percent), or no marker at night. */
  HW.sunArc = function (pct) {
    var m = '';
    if (pct != null) { var n = pct / 100, x = 8 + n * 84, y = 40 - 72 * n * (1 - n); m = '<circle cx="' + x.toFixed(2) + '" cy="' + y.toFixed(2) + '" r="5" fill="#FFD94D"/>'; }
    return Mock.html('<svg class="hw-sunarc" viewBox="0 0 100 48" aria-hidden="true"><path d="M4 40H96" stroke="rgba(255,255,255,.35)" stroke-width="1" fill="none"/><path d="M8 40Q50 4 92 40" stroke="rgba(255,255,255,.6)" stroke-width="2" fill="none" stroke-linecap="round" stroke-dasharray="3 4"/>' + m + '</svg>');
  };
  /** A plain bar chart (WeatherBarChart): bars scaled to a nice domain, a three-level y axis and a thinned hour axis. values null = no data (a 2 pt grey bar). */
  HW.barChart = function (values, domain, axis, labels, tint) {
    var bars = h('div.bars', h('div.gl3', h('i'), h('i'), h('i')));
    values.forEach(function (v) {
      var p = v == null ? 0 : Math.min(100, Math.max(0, v / domain * 100));
      bars.appendChild(h('b', { style: { height: v == null ? '2px' : Math.max(p > 0 ? 2 : 0, 76 * p / 100) + 'px', background: v == null ? 'rgba(255,255,255,.18)' : tint, transition: 'background var(--t-state) var(--ease-state)' } }));
    });
    var xa = h('div.xa'); labels.forEach(function () { xa.appendChild(h('span', h('i'))); });
    var el = h('div.hw-chart', { 'aria-hidden': 'true' }, h('div.y', h('span', axis[0]), h('span', axis[1]), h('span', axis[2])), h('div.pl', bars, xa));
    Mock.whenAttached(el, function () {   // WeatherPrecipitationTimeline.labelCadence
      var plot = bars.clientWidth, widest = Math.max.apply(null, labels.map(function (l) { return l.length; })) * 6.6 * Math.min(2.5, parseFloat(getComputedStyle(el.closest('.screen,.k-swatch,.k-plain') || el).getPropertyValue('--sc')) || 1);
      var count = labels.length, cap = Math.max(1, Math.floor(plot / (widest + 6))), cad = plot <= 0 ? Math.ceil(count / 4) : Math.max(1, Math.ceil(count / cap));
      Array.prototype.forEach.call(xa.children, function (s, i) { s.firstChild.textContent = i % cad === 0 ? labels[i] : ''; });
    });
    return el;
  };

  /* ------------------------------------------------------------------ weather sheet pieces */
  function tileShell(title, icon, content, o) {
    o = o || {};
    return h('div.hw-surface.tile.hw-tile' + (o.big ? '.big' : ''), { role: 'group', 'aria-label': o.label || title, dataset: { tile: o.id || '' } }, h('div.hdr', h('span', { html: HW.icon(icon) }), h('span', title)), content);
  }
  var AQI = [[50, 'Good'], [100, 'Moderate'], [150, 'Unhealthy for Sensitive Groups'], [200, 'Unhealthy'], [300, 'Very Unhealthy'], [500, 'Hazardous']], AQIMIN = [0, 51, 101, 151, 201, 301];
  function aqiRead(v) {
    var i = 0; while (i < AQI.length - 1 && v > AQI[i][0]) i++;
    var lo = AQIMIN[i], hi = AQI[i][0], p = (Math.min(hi, Math.max(lo, v)) - lo) / Math.max(1, hi - lo);
    return { cat: AQI[i][1], pct: (i + p) / 6 * 100 };
  }
  HW.aqiRead = aqiRead;
  HW.tiles = {
    aqi: function (v) {
      var na = v == null, rd = na ? { cat: 'Unavailable', pct: null } : aqiRead(v);
      return tileShell('Air Quality', 'aqi.medium', h('div.stack', h('div.row', h('span.val.big', na ? '--' : String(v)), h('span.st', rd.cat)), HW.rail('aqi', { marker: rd.pct })), { big: true, id: 'aqi', label: na ? 'Outdoor air quality unavailable' : 'Outdoor air quality ' + v + ', ' + rd.cat });
    },
    /** delta: degrees warmer (+) or cooler (-) than the 72 F reading; the rail spans -12 to +12 */
    feels: function (delta) {
      delta = delta == null ? 3 : delta; var v = (72 + delta) + '°F';
      return tileShell('Feels Like', 'thermometer.medium', h('div.stack', h('div.row', h('span.val', v)), HW.rail('feels', { marker: Math.max(0, Math.min(100, (delta + 12) / 24 * 100)) })), { id: 'feels', label: 'Feels Like ' + v });
    },
    uv: function (v) {
      v = v == null ? 7 : v; var cat = v < 3 ? 'Low' : v < 6 ? 'Moderate' : v < 8 ? 'High' : v < 11 ? 'Very High' : 'Extreme';
      return tileShell('UV Index', 'sun.max.fill', h('div.stack', h('div.row', h('span.val', String(v)), h('span.st', cat)), HW.rail('uv', { marker: Math.min(100, v / 11 * 100) })), { id: 'uv', label: 'UV Index ' + v + ' ' + cat });
    },
    /** pct: daylight progress 0 to 100, or null at night (no marker; the title reads Sunrise) */
    sun: function (night, pct) {
      pct = pct === undefined ? 22 : pct;
      return tileShell(night ? 'Sunrise' : 'Sunset', night ? 'sunrise.fill' : 'sunset.fill', h('div.stack', h('div.row', h('span.val', night ? '7:20 AM' : '6:19 PM')), HW.sunArc(night ? null : pct)), { id: 'sun', label: (night ? 'Sunrise 7:20 AM' : 'Sunset 6:19 PM') });
    },
    visibility: function (miles) {
      miles = miles == null ? 10 : miles; var pct = Math.min(100, miles / 10 * 100), val = (Math.round(miles * 10) / 10) + ' mi';
      return tileShell('Visibility', 'eye.fill', h('div.stack', h('div.row', h('span.val', val)), HW.rail('visibility', { marker: pct > 0 ? pct : null, size: pct, start: 0 })), { id: 'visibility', label: 'Visibility ' + val });
    },
    pressure: function (inHg) {
      inHg = inHg == null ? 29.92 : inHg; var pct = Math.max(0, Math.min(100, (inHg * 33.8638866667 - 970) / 80 * 100));
      return tileShell('Pressure', 'gauge.with.dots.needle.33percent', HW.gauge(pct, inHg.toFixed(2), 'inHg'), { id: 'pressure', label: 'Pressure ' + inHg.toFixed(2) + ' inHg' });
    },
    unavailable: function (title, icon, id) { return tileShell(title, icon, h('div.stack', h('span.val', '--'), h('span.dim', { html: HW.icon(icon) })), { id: id, label: title + ' Unavailable' }); },
    wind: function (ctx, o) {
      o = o || {}; var calm = o.calm, src = calm ? null : (o.bearing == null ? 250 : o.bearing);
      var pts = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'], card = src == null ? '' : pts[Math.round(src / 22.5) % 16];
      var kv = h('div.kv', h('div', h('span', 'Wind'), h('b', calm ? '0 mph' : '9 mph')), h('div', h('span', 'Gusts'), h('b', calm ? '2 mph' : '14 mph')), h('div', h('span', calm ? 'Direction' : 'From'), h('b', calm ? 'Calm' : card + ' · ' + src + '°')));
      var c = HW.compass(src);
      return tileShell('Wind', 'wind', h('div.hw-wind' + (ctx.axSize ? '.ax' : ''), kv, c), { big: true, id: 'wind', label: calm ? 'Wind 0 mph; Gusts 2 mph; Direction Calm' : 'Wind 9 mph; Gusts 14 mph; From ' + card + ', ' + src + ' degrees' });
    },
    chart: function (kind, ok) {
      var P = HW.hours().slice(0, 6), labels = P.map(function (x) { return x.t; });
      if (kind === 'chance') {
        return tileShell('Precipitation', 'cloud.rain.fill', ok === false ? h('span.na', 'Unavailable') : HW.barChart(P.map(function (x) { return x.prob; }), 80, ['80%', '40%', '0%'], labels, '#73C7FF'),
          { id: 'precip', label: ok === false ? 'Precipitation Unavailable' : 'Hourly precipitation chance over 6 hours, peaking at 80%' });
      }
      if (kind === 'accumulation') {
        var cum = 0, vals = P.map(function (x) { cum += x.amt; return Math.round(cum * 100) / 100; });
        return tileShell('Accumulation', 'cloud.rain.fill', ok === false ? h('span.na', 'Unavailable') : HW.barChart(vals, .3, ['0.3 in', '0.15 in', '0 in'], labels, '#8CD9FF'),
          { id: 'accumulation', label: ok === false ? 'Accumulation Unavailable' : 'Cumulative precipitation through 6 hours, totaling 0.3 in' });
      }
      if (kind === 'humidity') return tileShell('Humidity', 'humidity.fill', ok === false ? h('span.na', 'Unavailable') : HW.barChart(P.map(function (x) { return x.hum; }), 80, ['80%', '40%', '0%'], labels, '#66D9CC'), { id: 'humidity', label: ok === false ? 'Humidity Unavailable' : 'Hourly Humidity over 6 hours, ranging from 58% to 73%' });
      return tileShell('Cloud Cover', 'cloud.fill', ok === false ? h('span.na', 'Unavailable') : HW.barChart(P.map(function (x) { return x.cloud; }), 90, ['90%', '45%', '0%'], labels, '#CCDBF2'), { id: 'cloud', label: ok === false ? 'Cloud Cover Unavailable' : 'Hourly Cloud Cover over 6 hours, ranging from 40% to 90%' });
    },
  };

  /** The Highlights panel on DynamicGridLayout: wide tiles span two tracks, the rest one. o: {aqi: boolean|'none', night, nodata, calm} */
  HW.highlightsPanel = function (ctx, o) {
    o = o || {};
    var T = HW.tiles, items = [], span = {};
    function add(n, wide) { if (wide) span[items.length] = 2; items.push(n); }
    var nd = !!o.nodata;
    if (o.aqi !== false) add(T.aqi(o.aqi === 'unavailable' ? null : HW.current.aqi), true);
    add(T.chart('chance', !nd), true); add(T.chart('accumulation', !nd), true); add(T.chart('humidity', !nd), true); add(T.chart('cloud', !nd), true);
    add(T.feels(), false); add(T.uv(), false); add(T.wind(ctx, o), true); add(T.sun(o.night), false); add(T.visibility(), false); add(T.pressure(), false);
    return h('div.hw-grid', { role: 'group', 'aria-label': 'Weather highlights', style: { display: 'flex', flexDirection: 'column', gap: '12px' } }, h('h3.hw-hd', 'Highlights'), K().TileGrid({ items: items, span: span, min: 150, max: 4, equal: false }));
  };

  /** One hour of the sheet's carousel in a mode. */
  function modalHour(x, i, mode) {
    var v, a, b;
    if (mode === 'condition') { v = K().WeatherGlyph({ kind: x.g }); a = x.temp + '°F'; }
    else if (mode === 'precipitation') { v = h('span', { style: { color: '#73C7FF' }, html: I('drop.fill', { size: '26px' }) }); a = x.prob + '%'; b = x.amt ? x.amt.toFixed(2) + ' in' : null; }
    else { v = h('span', { html: HW.icon('location.north.fill', { size: '24px' }) }); v.firstChild.style.transform = 'rotate(' + ((x.bearing + 180) % 360) + 'deg)'; a = x.wind + ' mph'; b = x.gust + ' mph'; }
    var label = x.t + ' ' + (mode === 'condition' ? (x.cond === 'rainy' ? 'Rain' : x.cond === 'pouring' ? 'Heavy Rain' : x.cond === 'partlycloudy' ? 'Partly Cloudy' : x.cond === 'clear-night' ? 'Clear Night' : x.cond[0].toUpperCase() + x.cond.slice(1)) + ' ' + a : mode === 'precipitation' ? 'precipitation ' + a : 'wind ' + x.wind + ' mph gusts ' + x.gust + ' mph');
    return h('div.hw-hs', { role: 'img', 'aria-label': label }, h('span.t', x.t), h('span.v', v), h('span.d', a), b ? h('span.d2', b) : null);
  }
  var SUBHEAD = { condition: 'Temperature (F)', precipitation: 'Precipitation chance (%)', wind: 'Speed (mph) · Gusts' };
  var MODEIC = { condition: 'cloud.fill', precipitation: 'drop.fill', wind: 'wind' }, MODELAB = { condition: 'Conditions', precipitation: 'Precipitation', wind: 'Wind' };
  var MODEHINT = { condition: 'Shows the hourly condition and temperature.', precipitation: 'Shows precipitation chance and expected accumulation.', wind: 'Shows wind speed, direction and gusts.' };

  function dayRow(ctx, d, i, all, mode) {
    var minLow = Math.min.apply(null, all.map(function (x) { return x.lo; })), maxHigh = Math.max.apply(null, all.map(function (x) { return x.hi; })), spread = maxHigh - minLow, ax = ctx.axSize, det;
    if (mode === 'condition') {
      det = h('div.dt', h('span.ic', K().WeatherGlyph({ kind: d.g })), h('span.vl', d.lo + '°'), HW.rail('temperature', { start: (d.lo - minLow) / spread * 100, size: (d.hi - d.lo) / spread * 100, marker: i === 0 ? (72 - minLow) / spread * 100 : null }), h('span.vl', d.hi + '°'));
    } else if (mode === 'precipitation') {
      det = h('div.dt', h('span.ic', { style: { color: '#73C7FF' }, html: I('drop.fill') }), HW.rail('precipitation', { start: 0, size: d.prob, marker: d.prob > 0 ? d.prob : null }), h('span.vl.w', d.amt ? d.amt.toFixed(2) + ' in' : '0.00 in'), h('span.vl', d.prob + '%'));
    } else {
      var ic = h('span.ic', { html: HW.icon('location.north.fill', { size: '22px' }) }); ic.firstChild.style.transform = 'rotate(' + ((d.bearing + 180) % 360) + 'deg)';
      det = h('div.dt', ic, h('span.wr', d.wind + '-' + d.gust + ' mph'));
    }
    var label = mode === 'condition' ? d.n + ' ' + d.cond + ' H:' + d.hi + '°  L:' + d.lo + '°' : mode === 'precipitation' ? d.n + ' precipitation ' + (d.amt ? d.amt.toFixed(2) : '0.00') + ' in ' + d.prob + '%' : d.n + ' wind ' + d.wind + '-' + d.gust + ' mph';
    return h('div.hw-day' + (ax ? '.ax' : ''), { role: 'img', 'aria-label': label }, h('span.dn', d.n), det);
  }

  /** The Conditions and Next Seven Days panels share one mode, so they are built together. Returns {hourly, daily, setMode}. o: {mode, phase: ready|loading|error|empty|stale} */
  HW.hourlyDaily = function (ctx, o) {
    o = o || {}; var phase = o.phase || 'ready', mode = o.mode || 'condition', hrs = HW.hours(), days = HW.days(), ax = ctx.axSize;
    var hBody = h('div.hw-mainbody'), dBody = h('div.hw-mainbody'), sub = h('p.hw-foot.hw-sec2', { style: { margin: 0 } }, SUBHEAD[mode]);
    function msgH() { return phase === 'error' ? 'Unable to load Pirate Weather hourly forecast.' : 'No hourly forecast data returned by Pirate Weather.'; }
    function msgD() { return phase === 'error' ? 'Unable to load Pirate Weather forecast.' : 'No forecast data returned by Pirate Weather.'; }
    function fill() {
      hBody.innerHTML = ''; dBody.innerHTML = ''; sub.textContent = SUBHEAD[mode];
      if (phase === 'loading') {
        hBody.appendChild(HW.carousel(ctx, { count: 24, perPage: HW.perPage(ctx, 5, 7), label: '24-hour conditions', cell: function () { return h('div.hw-ph0', { style: { gap: '12px', minHeight: '112px', padding: '4px 0' } }, h('span.hw-skel', { style: { width: '36px', height: '10px' } }), h('span.hw-skel', { style: { width: '30px', height: '30px', borderRadius: '50%' } }), h('span.hw-skel', { style: { width: '32px', height: '10px' } })); } }));
        hBody.setAttribute('aria-label', 'Loading 24-hour conditions');
        var rows = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px' }, role: 'img', 'aria-label': 'Loading seven-day weather forecast' });
        for (var k = 0; k < 7; k++) rows.appendChild(h('span.hw-skel', { style: { height: '44px', borderRadius: '16px', background: 'rgba(255,255,255,.1)', width: '100%' } }));
        dBody.appendChild(rows);
      } else if (phase === 'error' || phase === 'empty') {
        hBody.appendChild(h('div.hw-msg', msgH())); dBody.appendChild(h('div.hw-msg', msgD()));
      } else {
        hBody.appendChild(HW.carousel(ctx, { count: hrs.length, perPage: HW.perPage(ctx, 5, 7), label: '24-hour conditions', id: 'hours', cell: function (i) { return modalHour(hrs[i], i, mode); } }));
        if (phase === 'stale') hBody.appendChild(h('div.hw-msg', msgH().replace('No hourly forecast data returned', 'Unable to load Pirate Weather hourly forecast').replace(/ by weather service\.$/, '.')));
        var list = h('div');
        days.forEach(function (d, i) { if (i) list.appendChild(h('hr.hw-sep')); list.appendChild(dayRow(ctx, d, i, days, mode)); });
        dBody.appendChild(list);
      }
    }
    var btns = [];
    var picker = h('div.hw-modes', { role: 'radiogroup', 'aria-label': 'Hourly detail' });
    ['condition', 'precipitation', 'wind'].forEach(function (m) {
      var b = h('button', { type: 'button', role: 'radio', 'aria-checked': String(m === mode), 'aria-label': MODELAB[m], title: MODEHINT[m], dataset: { mode: m }, html: I(MODEIC[m], { fill: true }) });
      b.addEventListener('click', function () { setMode(m); }); btns.push(b); picker.appendChild(b);
    });
    var running = false;
    function setMode(m, instant) {
      if (m === mode) return Promise.resolve();
      mode = m; btns.forEach(function (b) { b.setAttribute('aria-checked', String(b.dataset.mode === m)); });
      if (instant || rm() || !hBody.animate) { fill(); return Promise.resolve(); }
      /* the mode switch is a content change on `quick` (0.2 s easeOut), not a slide */
      return Promise.all([hBody, dBody].map(function (el) { return el.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 100, fill: 'forwards' }).finished; })).then(function () {
        fill(); return Promise.all([hBody, dBody].map(function (el) { return el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 100, easing: 'cubic-bezier(0,0,.2,1)', fill: 'forwards' }).finished; }));
      }).then(function () { [hBody, dBody].forEach(function (el) { el.getAnimations().forEach(function (a) { a.cancel(); }); }); });
    }
    fill();
    var head = h('div.hw-ph' + (ax ? '.ax' : ''), h('h3.hw-hd', 'Conditions'), picker);
    var hourly = h('section.hw-surface', { 'aria-label': '24-hour weather conditions', style: { display: 'flex', flexDirection: 'column', gap: '12px' } }, head, sub, hBody);
    var daily = h('section.hw-surface', { 'aria-label': 'Seven-day weather forecast', style: { display: 'flex', flexDirection: 'column', gap: '12px' } }, h('h3.hw-hd', 'Next Seven Days'), dBody);
    return { hourly: hourly, daily: daily, setMode: setMode };
  };

  /** The Today briefing panel. o: {phase, briefing: {headline, sentences[], hazard?:{icon, severity}}, night, glyph} */
  HW.briefing = function (ctx, o) {
    o = o || {}; var b = o.briefing, ic;
    if (b && b.hazard) { var col = { alert: '#FF9940', caution: '#FFD14D', notable: '#fff', calm: '#fff' }[b.hazard.severity] || '#fff'; ic = h('span.ic', { style: { color: col }, html: HW.icon(b.hazard.icon, { fill: true }) }); }
    else ic = h('span.ic', K().WeatherGlyph({ kind: o.glyph || 'rain' }));
    var head = b ? b.headline : (o.condition || 'Rain'), sents = b ? b.sentences : ["Today's outlook appears once Pirate Weather returns forecast data."];
    return h('section.hw-surface.hw-brief', { 'aria-label': 'Today' }, h('div.top', ic, h('div', h('div.lab', 'Today'), h('div.head', { role: 'heading', 'aria-level': 2 }, head))),
      h('ul', sents.map(function (s) { return h('li', h('span', { 'aria-hidden': 'true' }, '•'), h('span', s)); })));
  };
  HW.BRIEFS = {
    rain: { headline: 'Rain', sentences: ['The day opens with steady rain, then eases into a mix of sun and clouds.', 'Look for rain through the morning, with chances near 80% and about 0.3 in adding up.', 'Highs reach 78° before falling back to 58° overnight.', 'Winds out of the west-southwest near 9 mph gust to 14 mph.'] },
    storm: { headline: 'Severe Storms', hazard: { icon: 'cloud.bolt.fill', severity: 'alert' }, sentences: ['Expect thunderstorms on and off through the day, with chances near 70% and about 0.3 in adding up.', 'Highs reach 84° before falling back to 62° overnight.', 'Winds out of the southwest near 14 mph gust to 31 mph.'] },
    air: { headline: 'Poor Air Quality', hazard: { icon: 'aqi.medium', severity: 'caution' }, sentences: ['Conditions look mixed, with limited hourly detail from Pirate Weather.', 'Temperatures hold steady between 61° and 74° all day.'] },
    clear: { headline: 'Sunny', sentences: ['Expect full sun for most of the day.', 'No meaningful rain is expected.', 'Highs reach 78° before falling back to 58° overnight.', 'Winds stay light all day.'] },
  };

  /** The sheet's scrolling content (the VStack in WeatherSheet). o: {scene, phase, mode, brief:'rain'|..., aqi, night, glyph, cond, temp, hl} */
  HW.sheetBody = function (ctx, o) {
    o = o || {}; var phase = o.phase || 'ready', sc = HW.scenes[o.scene || 'rain'], loadingLike = phase === 'loading' || phase === 'error' || phase === 'empty';
    var hero = h('div.hw-hero', { role: 'group', 'aria-label': (o.cond || sc.cond) + ', ' + (o.temp == null ? 72 : o.temp) + '°' }, h('div.deg', (o.temp == null ? 72 : o.temp) + '°'), h('div.cond', o.cond || sc.cond), loadingLike ? null : h('div.hl', o.hl || 'High: 78°  Low: 58°'));
    var brief = HW.briefing(ctx, { briefing: loadingLike ? null : HW.BRIEFS[o.brief || 'rain'], glyph: o.glyph || sc.g, condition: o.cond || sc.cond });
    var hd = HW.hourlyDaily(ctx, { mode: o.mode, phase: phase });
    var body = h('div.hw-sheet', hero, brief, hd.hourly, hd.daily, HW.highlightsPanel(ctx, { aqi: o.aqi, night: o.night, nodata: loadingLike, calm: o.calm }));
    body.setMode = hd.setMode; body.parts = hd;
    return body;
  };

  /** The Home page behind the sheet (trimmed: chips and the weather card). */
  HW.presenter = function (ctx, o) {
    o = o || {};
    return Mock.page(ctx, { title: 'Home', section: 'home', badge: 3, choresBadge: 2, connection: o.connection || 'live', body: [K().ChipRail({ chips: Mock.chips.home(), ctx: ctx }), HW.card(ctx, Object.assign({ preset: 'home', narrow: false }, o.card))] });
  };
  /** The Weather sheet over Home: hassSheet(.page, height: .full, appearance: .dark); the condition gradient is the sheet's background. */
  HW.sheet = function (ctx, o) {
    o = o || {};
    var body = HW.sheetBody(ctx, o);
    var host = Mock.sheet(ctx, { title: 'Weather', detent: o.detent || 'large', size: 'page', trailing: 'close', appearance: 'dark', content: body, presenter: o.presenterNode || (o.noPresenter ? null : HW.presenter(ctx, o)) });
    var panel = host.querySelector('.ui-sheet'), modal = panel.querySelector('.ui-modal');
    panel.style.background = HW.gradient(o.scene || 'rain');
    panel.insertBefore(HW.backdrop(o.scene || 'rain', { decorated: true }), panel.firstChild);
    modal.style.position = 'relative'; modal.style.zIndex = 1;
    host.dataset.scene = o.scene || 'rain';
    host.body = body;
    return host;
  };

  /** Mock.presentDemo for the Weather sheet (its gradient and decoration need HW.sheet): the stage's page presents the sheet, it holds, then dismisses. */
  HW.presentDemo = function (stage, o, hold) {
    var ctx = Mock.current, page = stage.querySelector('.ui-page');
    if (!page || !ctx) return Promise.resolve();
    var parent = page.parentNode, next = page.nextSibling;
    var host = HW.sheet(ctx, Object.assign({}, o, { presenterNode: page }));
    parent.insertBefore(host, next);
    return Mock.anim.sheet(host, 'in').then(function () { return Mock.sleep(hold || 1100); }).then(function () { return Mock.anim.sheet(host, 'out'); }).then(function () {
      page.style.transform = ''; parent.insertBefore(page, host); host.remove();
    });
  };

  /* ------------------------------------------------------------------ the Home weather card */
  /** The header on main today (before option D): glyph and numeral lead, the condition with its chevron and today's range trail. p: {condition, temp, hi, lo, glyph, ctx, bug} */
  HW.wasHeader = function (ctx, p) {
    var ax = ctx && ctx.axSize, g = K().WeatherGlyph({ kind: p.glyph || 'partly-cloudy' });
    var num = h('span.num', { 'aria-hidden': 'true' }, p.temp == null ? '--' : p.temp + '°');
    var hl = p.hi == null ? h('span.hl', { 'aria-hidden': 'true' }, ' ') : h('span.hl', { 'aria-label': 'Today ' + p.condition + ' H:' + p.hi + '°  L:' + p.lo + '°' }, 'H:' + p.hi + '°  L:' + p.lo + '°');
    var label = 'Open seven-day weather forecast. ' + p.condition + ', ' + (p.temp == null ? '--' : p.temp + '°F');
    return h('div.ui-wxhdr.hw-was' + (ax ? '.ax' : '') + (p.bug ? '.bug' : ''), { dataset: { header: 'was' } },
      h('div.hero', { role: 'button', tabindex: 0, 'aria-label': label }, g, num), ax ? null : h('div.sp'),
      h('div.tr', h('div.lr', { 'aria-hidden': 'true' }, h('span.lab', p.condition), h('span.chev', { html: I('chevron.right', { weight: 2.4 }) })), hl));
  };
  /**
   * The Home weather card: header (option D, in flight, or the main "was" header), the day's first briefing sentence, then 24 hours in a paging carousel.
   * p: {header:'d'|'was', condition, temp, hi, lo, glyph, brief, hours, preset:'home'|'rain', loading, hourly:'ready'|'error'|'empty', narrow, bug, night, ctx}
   */
  HW.card = function (ctx, p) {
    p = Object.assign({ condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38, header: 'd', preset: 'home' }, p);
    var load = !!p.loading;
    if (load) { p.condition = 'Weather Unavailable'; p.temp = null; p.hi = null; p.lo = null; }
    var head = p.header === 'was' ? HW.wasHeader(ctx, p) : K().WeatherCardHeader({ condition: p.condition, temp: p.temp == null ? '--' : p.temp, hi: p.hi, lo: p.lo, glyph: p.glyph, ctx: ctx });
    if (p.header !== 'was' && p.temp == null) { var nm = head.querySelector('.num'); if (nm) nm.textContent = '--'; }
    if (p.header !== 'was' && p.hi == null) { var hlx = head.querySelector('.hl'); if (hlx) hlx.textContent = ' '; }
    var hrs = p.hours || HW.hours(p.preset), per = HW.perPage(ctx, 6, p.narrow ? 6 : 9), kids = [head, h('hr')];
    var brief = load || p.brief === null ? null : (p.brief || 'The day opens with full sun, shifts to a mix of sun and clouds, and settles into overcast skies.');
    if (brief) kids.push(h('p.brief', { 'data-id': 'briefing' }, brief), h('hr'));
    if (load) kids.push(HW.carousel(ctx, { count: 24, perPage: per, label: '24-hour weather forecast', cell: function () { return h('div.hw-hc', { 'aria-hidden': 'true' }, h('span.hw-skel', { style: { width: '28px', height: '8px', opacity: .9 } }), h('span.hw-skel', { style: { width: '22px', height: '22px', borderRadius: '50%' } }), h('span.hw-skel', { style: { width: '24px', height: '8px' } })); } }));
    else if (p.hourly === 'error') kids.push(h('div.msg', 'Unable to load Pirate Weather hourly forecast.'));
    else if (p.hourly === 'empty') kids.push(h('div.msg', 'No hourly forecast data returned by Pirate Weather.'));
    else kids.push(HW.carousel(ctx, { count: hrs.length, perPage: per, label: '24-hour weather forecast', id: 'card-hours', cell: function (i) { var x = hrs[i]; return h('div.hw-hc', { role: 'img', 'aria-label': x.t + ' ' + x.cond + ' ' + x.temp + '°F' }, h('span.t', x.t), K().WeatherGlyph({ kind: p.night && x.g === 'sunny' ? 'clear-night' : x.g }), h('span.d', x.temp + '°')); } }));
    return h('section.ui-weather.hw-card', { role: 'region', 'aria-label': 'Weather', dataset: { header: p.header } }, kids);
  };

  /* ------------------------------------------------------------------ swatches for the component pages */
  /**
   * A grid of labelled samples. items: [{cap, node|fn(ctx), note?, surface:'page'|'sheet'|<scene key>, width?}]. A sheet swatch follows the Sheet appearance control.
   * fn(ctx) builds the node when the swatch is made, so ctx (device, text size) reaches it.
   */
  HW.swatches = function (ctx, items) {
    var grid = h('div.k-swatch-grid');
    items.forEach(function (it) {
      var s = it.surface || 'page', node = typeof it.node === 'function' ? it.node(ctx) : it.node, box;
      if (s === 'page') box = h('div.k-swatch.page.g-dark');
      else if (s === 'sheet') box = h('div.k-swatch.sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light'));
      else box = h('div.k-swatch.hw-wsw.g-dark', { style: { background: HW.gradient(s) } }, HW.backdrop(s, { decorated: true }));
      if (s !== 'page' && s !== 'sheet') { box.firstChild.style.zIndex = 0; }
      box.style.flex = it.width ? 'none' : '1 1 300px'; box.style.maxWidth = '100%';
      if (it.width) box.style.width = it.width + 'px';
      box.appendChild(h('div.k-cap', it.cap)); box.appendChild(h('div.in', node)); if (it.note) box.appendChild(h('div.hw-note', it.note));
      grid.appendChild(box);
    });
    return grid;
  };
  /** The window column a component lives in: as wide as the device's content, with the page's 16 pt margins. */
  HW.win = function (ctx, kids, o) {
    o = o || {}; var w = o.width || (o.narrow && ctx.splitGeometry ? ctx.splitGeometry.leading : ctx.contentW);
    return h('div.hw-win' + (o.flush ? '.flush' : ''), { style: { width: Math.min(w, o.max || 99999) + 'px' } }, kids);
  };
})();
