/* WeatherCard, WeatherCardHeader, WeatherGlyph: the Home weather summary card. apple/Sources/HassUI/Features/Home/Weather/WeatherCardContent.swift (+ WeatherSummaryCard, WeatherGlyph).
 * IN FLIGHT: the header layout is option D, decided 2026-10-22 (design/weather-card-header.md, proposals/weather-card-header): the glyph over the condition over H/L on the LEFT, the
 * Thin numeral with the chevron centred on it on the RIGHT. The numeral never truncates; the condition never wraps below accessibility sizes: a label too long for its column scrolls like a
 * ticker (30 pt/s, 1.5 s holds, soft fade at both edges, three passes then it rests; pauses on scroll, off screen and while the scene is inactive; an exception to motion.md 9.6 and 9.10).
 * Reduce Motion: no ticker, the condition wraps. Accessibility sizes stack: glyph, numeral and chevron on the top row, the condition under it at full width (wraps), H/L under that. "Was" (main):
 * the numeral could truncate to "4…" beside a long condition because layoutPriority sat inside the Button. The card is about 19 pt taller at the default size.
 * Card: a 26 pt thin module with the header, a daily briefing, a hairline, then the hourly row (Now, 11 AM, ...). Always dark styling (it sits on the wallpaper).
 * WeatherCardHeader props: {condition, temp, hi, lo, glyph?:'partly-cloudy'|'sunny'|'cloudy'|'rain'|'storm'|'snow'|'clear-night', ctx?}
 * WeatherCard props: header props + {brief?, hours?:[{t,g,d}] (default: 24 sample hours), page?:0 (which page of hours shows), narrow?:boolean (the half-width split pane: 6 per page), pending?:boolean, ctx?}
 * Hourly carousel (WeatherPagedCarousel): each page holds 6 whole hours (9 on regular width, 6 in the split pane), scaled to 0.8 at xxxLarge, 0.5 at AX1-2 and 0.34 at AX3-5 (never below two); more than
 * one page draws the page-dot indicator (current page an 18 x 7 capsule) and, on regular width, 44 pt Previous and Next circles either side of the strip. Hour time is 13 pt semibold, temperature 17 pt medium.
 * Pending (first sign-in, WeatherCardContent with no data): the numeral reads "--", the hours are WeatherCardHourPlaceholder (static capsules and a circle at 18% white; nothing pulses here), no briefing.
 * The numeral is capped at 96 pt at accessibility sizes (WeatherCardContent.maxNumeralSize).
 */
(function () {
  var h = Mock.h;
  var G = {
    'partly-cloudy': '<g stroke="#FFD93D" stroke-width="4.5" stroke-linecap="round"><path d="M40 6v6M55 13l-4 4M60 28h-6M24 13l4 4M55 43l-4-4"/></g><circle cx="40" cy="28" r="12" fill="#FFD93D"/><path d="M18 54h24a10 10 0 0 0 1.4-19.9A14 14 0 0 0 16.6 37 8.5 8.5 0 0 0 18 54z" fill="#fff"/>',
    'sunny': '<g stroke="#FFD93D" stroke-width="5" stroke-linecap="round" transform="translate(9.500 3.700) scale(.82)"><path d="M32 4v8M32 52v8M4 32h8M52 32h8M12 12l6 6M46 46l6 6M12 52l6-6M46 18l6-6"/></g><circle cx="36" cy="30" r="11" fill="#FFD93D"/>',
    'cloudy': '<path d="M16 48h30a11 11 0 0 0 1.500-21.900A16 16 0 0 0 16 29 9.500 9.500 0 0 0 16 48z" fill="#E4E8EE"/><path d="M12 42h22a9 9 0 0 0 1.200-17.900A13 13 0 0 0 12 26a8 8 0 0 0 0 16z" fill="#fff" transform="translate(10 4)"/>',
    'rain': '<path d="M18 40h26a10 10 0 0 0 1.400-19.900A14 14 0 0 0 16.600 23 8.500 8.500 0 0 0 18 40z" fill="#DDE3EA"/><g stroke="#5AB2FF" stroke-width="4" stroke-linecap="round"><path d="M22 46l-3 7M32 46l-3 7M42 46l-3 7"/></g>',
    'storm': '<path d="M18 38h26a10 10 0 0 0 1.400-19.900A14 14 0 0 0 16.600 21 8.500 8.500 0 0 0 18 38z" fill="#9AA5B5"/><path d="M33 38l-7 10h6l-3 8 10-12h-6l3-6z" fill="#FFD93D"/>',
    'snow': '<path d="M18 40h26a10 10 0 0 0 1.400-19.900A14 14 0 0 0 16.600 23 8.500 8.500 0 0 0 18 40z" fill="#E4E8EE"/><g fill="#fff"><circle cx="22" cy="48" r="2.600"/><circle cx="32" cy="52" r="2.600"/><circle cx="42" cy="48" r="2.600"/></g>',
    'clear-night': '<path d="M44 40A18 18 0 0 1 28 10a18 18 0 1 0 16 30z" fill="#E9E4FF"/><g fill="#fff"><circle cx="46" cy="14" r="1.800"/><circle cx="52" cy="26" r="1.300"/></g>',
  };
  /** Weather condition glyph (multicolour like Apple Weather): props {kind, size?} */
  function Glyph(p) { return Mock.html('<svg class="gl" viewBox="9.5 3.7 52.8 50.3" aria-hidden="true" style="' + (p.size ? 'width:' + p.size + 'px;height:' + p.size + 'px' : '') + '">' + (G[p.kind || 'partly-cloudy']) + '</svg>'); }
  Mock.register('WeatherGlyph', function (p) { return Glyph(p || {}); }, { source: 'apple/Sources/HassUI/Features/Home/Weather/WeatherGlyph.swift', props: '{kind, size}', variants: Object.keys(G).map(function (k) { return { id: k, label: k, props: { kind: k, size: 40 } }; }) });

  var CHEV = Mock.icon('chevron.right', { weight: 2.4 });
  function Header(p) {
    var ctx = p.ctx || Mock.current || {}, ax = !!ctx.axSize;
    if (p.pending && !p.pendingNumeral) p = Object.assign({}, p, { pendingNumeral: true, condition: p.condition || 'Weather Unavailable', glyph: p.glyph || 'cloudy', hi: null, lo: null });
    var g = Glyph({ kind: p.glyph });
    // WeatherFormat.degree(nil) is "--" (no degree sign); the H/L line holds its height blank until the daily forecast arrives.
    var num = h('span.num', { 'aria-label': p.pendingNumeral ? 'temperature unknown' : p.temp + ' degrees' }, p.pendingNumeral ? '--' : p.temp + '\u00b0'), chev = h('span.chev', { html: CHEV, 'aria-hidden': 'true' });
    var hl = h('span.hl', p.hi == null ? '\u00a0' : 'H:' + p.hi + '\u00b0  L:' + p.lo + '\u00b0');
    var el;
    if (ax) {
      el = h('div.ui-wxhdr.stack', { role: 'button', tabindex: 0, 'aria-label': p.condition + (p.pendingNumeral ? '' : ', ' + p.temp + ' degrees') }, h('div.r1', g, h('span.sp'), h('span.temp', num)), h('span.lab.wrap', p.condition), hl);
    } else {
      var tick = h('div.ui-tick', h('span.tk.lab', p.condition));
      el = h('div.ui-wxhdr', { role: 'button', tabindex: 0, 'aria-label': p.condition + (p.pendingNumeral ? '' : ', ' + p.temp + ' degrees') }, h('div.lc', g, tick, hl), h('div.temp', num));
      Mock.whenAttached(el, function () {
        var tk = tick.firstElementChild, over = tk.offsetWidth - (tick.clientWidth - 16);
        if (over > 1 && Mock.settings.reduceMotion) { tick.classList.remove('over'); tk.classList.remove('lab'); tk.classList.add('lab', 'wrap'); tk.style.whiteSpace = 'normal'; tick.style.overflow = 'visible'; tick.style.width = 'auto'; tick.style.marginLeft = 0; tick.style.paddingLeft = 0; }
        else Mock.anim.ticker(tick);
      });
      el.dataset.anim = 'weather-header';
    }
    return el;
  }
  Mock.register('WeatherCardHeader', Header, { source: 'apple/Sources/HassUI/Features/Home/Weather/WeatherCardContent.swift (option D, in flight)', props: '{condition, temp, hi, lo, glyph, ctx}',
    variants: [{ id: 'short', label: 'Partly Cloudy', props: { condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 } }, { id: 'long', label: 'Long label: ticker', props: { condition: 'Heavy Thunderstorm With Hail', temp: 48, hi: 58, lo: 38, glyph: 'storm' } }, { id: 'unavailable', label: 'Weather Unavailable', props: { condition: 'Weather Unavailable', temp: 48, hi: 58, lo: 38 } }] });

  /** The 24 hours the card scrolls through (the first six are the card's classic sample). */
  function sampleHours() {
    var rows = [['Now', 'partly-cloudy', 48], ['11 AM', 'sunny', 52], ['12 PM', 'sunny', 55], ['1 PM', 'partly-cloudy', 57], ['2 PM', 'cloudy', 58], ['3 PM', 'cloudy', 58], ['4 PM', 'cloudy', 57], ['5 PM', 'cloudy', 55], ['6 PM', 'rain', 52], ['7 PM', 'rain', 50],
      ['8 PM', 'cloudy', 49], ['9 PM', 'clear-night', 47], ['10 PM', 'clear-night', 46], ['11 PM', 'clear-night', 45], ['12 AM', 'clear-night', 44], ['1 AM', 'clear-night', 43], ['2 AM', 'clear-night', 42], ['3 AM', 'cloudy', 42], ['4 AM', 'cloudy', 41],
      ['5 AM', 'cloudy', 40], ['6 AM', 'partly-cloudy', 40], ['7 AM', 'partly-cloudy', 42], ['8 AM', 'sunny', 45], ['9 AM', 'sunny', 49]];
    return rows.map(function (r) { return { t: r[0], g: r[1], d: r[2] + '\u00b0' }; });
  }
  /** Hours per page (WeatherCarouselPaging.hoursPerPage): 6 compact, 9 regular (6 in the half-width split pane), scaled down with the text, never below two. */
  function perPage(ctx, narrow) {
    var base = ctx.regular && !narrow ? 9 : 6, f = ctx.ts === 'ax5' ? .34 : (ctx.ts === 'xxxl' ? .8 : 1);
    return Math.max(2, Math.round(base * f));
  }
  function hourCell(x, pending) {
    if (pending) return h('div.ph', { 'aria-hidden': 'true' }, h('i.c1'), h('i.c2'), h('i.c3'));   // WeatherCardHourPlaceholder: a 28 x 8 capsule, a 22 pt circle, a 24 x 8 capsule, 18% white, static
    return h('div.hr', h('span.ht', x.t), Glyph({ kind: x.g || x.glyph }), h('span.hd', x.d || x.temp));
  }
  /** The page-dot indicator (WeatherPagedCarousel.indicator): the current page a 18 x 7 capsule, the others 7 pt dots at 45%, in a 44 pt target. */
  function pager(pages, current) {
    var dots = []; for (var i = 0; i < pages; i++) dots.push(h('i' + (i === current ? '.cur' : '')));
    return h('div.ui-wxpages', { role: 'group', 'aria-label': '24-hour weather forecast pages', 'aria-valuetext': 'Page ' + (current + 1) + ' of ' + pages }, dots);
  }
  function ctrl(sym, label, disabled) {
    var b = h('button.ui-wxctl', { type: 'button', 'aria-label': label, html: Mock.icon(sym, { weight: 2.2 }) }); if (disabled) b.disabled = true; return b;
  }
  function WeatherCard(p) {
    var ctx = p.ctx || Mock.current || {}, hours = p.hours || sampleHours(), pending = !!p.pending, n = pending ? 24 : hours.length, per = perPage(ctx, p.narrow);
    var pages = Math.max(1, Math.ceil(n / per)), page = Math.min(pages - 1, Math.max(0, p.page || 0)), more = pages > 1;
    var show = pending ? new Array(per).join('.').split('.') : hours.slice(page * per, page * per + per);
    var controls = more && ctx.regular;   // Previous and Next only on wide layouts (the web shows them for pointer devices)
    var strip = h('div.ui-wxstrip' + (controls ? '.ctl' : ''), h('div.ui-hours', show.map(function (x) { return hourCell(x, pending); })),
      controls ? [h('div.prev', ctrl('chevron.left', 'Previous 24-hour weather forecast', page === 0)), h('div.next', ctrl('chevron.right', 'Next 24-hour weather forecast', page >= pages - 1))] : null);
    // pending (first sign-in, nothing saved): "--" for the numeral, the placeholder hours; no briefing (the card omits the unavailable sentence and its separator)
    var hdr = pending ? Header({ condition: 'Weather Unavailable', temp: '--', hi: null, lo: null, glyph: 'cloudy', ctx: ctx, pendingNumeral: true }) : Header(Object.assign({ ctx: ctx }, p));
    return h('section.ui-weather', { role: 'region', 'aria-label': 'Weather' }, hdr, h('hr'),
      pending ? null : [h('p.brief', p.brief || 'The day opens with full sun, shifts to a mix of sun and clouds, and settles into overcast skies.'), h('hr')],
      pending ? h('div', { 'aria-label': 'Loading 24-hour weather forecast', role: 'group' }, strip) : strip, more ? pager(pages, page) : null);
  }
  Mock.register('WeatherCard', WeatherCard, { source: 'apple/Sources/HassUI/Features/Home/Weather/WeatherSummaryCard.swift', props: 'WeatherCardHeader props + {brief, hours}',
    variants: [{ id: 'default', label: 'Default', props: { condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 } }, { id: 'long', label: 'Long condition (ticker)', props: { condition: 'Heavy Thunderstorm With Hail', temp: 48, hi: 58, lo: 38, glyph: 'storm' } }],
    states: [{ id: 'pending', label: 'First sign-in: "--" and static placeholder hours', props: { pending: true } }] });
})();
