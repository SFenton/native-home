/* SF Symbol look-alikes, keyed by SF Symbol name (the names HassDesign/SymbolMap.swift returns).
 *
 * These are a STAND-IN: simple 24 x 24 outline drawings in the SF Symbols spirit, so a mockup reads like the app without
 * shipping Apple's glyphs (no fonts, no network: AUTHORING.md rule 4). Each entry is outline markup, or [outline, filled] when
 * `symbolVariant(.fill)` has a distinct drawing. Mock.icon('house', {fill:true}) and Mock.icon('house.fill') are the same glyph.
 * A name that is missing draws a dashed circle and is recorded in Mock.missingIcons so the lint banner names it.
 */
(function () {
  var C = 'cx', R = 'r';
  function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
  function p(d) { return '<path d="' + d + '"/>'; }
  function rc(x, y, w, h, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '" rx="' + (r || 0) + '"/>'; }
  var cloud = 'M7.5 18.5h9.2a4 4 0 0 0 .6-7.95A5.6 5.6 0 0 0 6.5 12 3.3 3.3 0 0 0 7.5 18.5z';
  var bulb = 'M12 3.2a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2v.2h5v-.2c0-.8.4-1.5 1-2A6 6 0 0 0 12 3.2z';
  var shield = 'M12 3 4.6 5.8v5.7c0 4.3 3 7.8 7.4 9.5 4.4-1.7 7.4-5.2 7.4-9.5V5.8z';
  var person = c(12, 8, 3.8) + p('M4.8 20.2c.3-3.6 3.3-5.9 7.2-5.9s6.9 2.3 7.2 5.9');
  var walk = c(13.5, 4.6, 1.9) + p('M12.2 9.5 9.4 11v3.2M12.2 9.5l3 3.3 2.9.5M12.2 9.5l.9 5.6-3.3 6.2M13.1 15.1l3 2.4.7 3.7');
  var S = {
    'house': [p('M3.4 11.2 12 4l8.6 7.2M5.6 9.7V20h12.8V9.7M10 20v-5.4h4V20'), p('M12 3.1 2.6 11a.8.8 0 0 0 .5 1.4h1.7v7.8a.8.8 0 0 0 .8.8H10v-5.6h4v5.6h4.4a.8.8 0 0 0 .8-.8v-7.8h1.7a.8.8 0 0 0 .5-1.4z')],
    'shield': [p(shield), p(shield)],
    'shield.slash': [p(shield) + p('M4 3.5l16 17'), p(shield) + p('M4 3.5l16 17')],
    'thermometer.medium': [p('M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z') + p('M12 8.5v7.2'), p('M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z')],
    'checklist': p('M3.8 6.6 5.2 8 8 5.2M3.8 12.6 5.2 14 8 11.2M3.8 18.6 5.2 20 8 17.2M11 7h9.2M11 13h9.2M11 19h9.2'),
    'gearshape': [p('M10.4 3.4h3.2l.5 2.3 1.6.9 2.2-.8 1.6 2.8-1.7 1.6v1.8l1.7 1.6-1.6 2.8-2.2-.8-1.6.9-.5 2.3h-3.2l-.5-2.3-1.6-.9-2.2.8-1.6-2.8 1.7-1.6v-1.8L4.5 8.2l1.6-2.8 2.2.8 1.6-.9z') + c(12, 12, 3)],
    'square.grid.2x2': [rc(4.5, 4.5, 6, 6, 1.6) + rc(13.5, 4.5, 6, 6, 1.6) + rc(4.5, 13.5, 6, 6, 1.6) + rc(13.5, 13.5, 6, 6, 1.6), rc(4, 4, 7, 7, 1.8) + rc(13, 4, 7, 7, 1.8) + rc(4, 13, 7, 7, 1.8) + rc(13, 13, 7, 7, 1.8)],
    'person': [person, c(12, 8, 4.3) + p('M4 21c0-4.2 3.6-6.8 8-6.8s8 2.6 8 6.8z')],
    'person.2': [c(9, 8.5, 3.3) + p('M2.8 19.5c.3-3.2 2.9-5.1 6.2-5.1s5.9 1.9 6.2 5.1M16 5.6a3.3 3.3 0 0 1 0 5.8M17.5 14.6c2 .5 3.5 2 3.7 4.9'), c(9, 8.5, 3.6) + p('M2.4 20c0-3.6 2.8-5.8 6.6-5.8s6.6 2.2 6.6 5.8z') + p('M16 5.2a3.6 3.6 0 0 1 0 6.6M17.6 14.4c2.2.6 3.8 2.3 3.9 5.6h-2.6')],
    'person.crop.circle.fill': [c(12, 12, 9.2) + c(12, 9.6, 3) + p('M6.2 18.2c1-2.3 3.2-3.6 5.8-3.6s4.8 1.3 5.8 3.6'), '<path fill-rule="evenodd" d="M12 2.6a9.4 9.4 0 1 0 0 18.8 9.4 9.4 0 0 0 0-18.8zm0 4.1a3.1 3.1 0 1 1 0 6.2 3.1 3.1 0 0 1 0-6.2zM6.8 17.6c.9-1.9 2.9-3 5.2-3s4.3 1.1 5.2 3A7.6 7.6 0 0 1 12 20.2a7.6 7.6 0 0 1-5.2-2.6z"/>'],
    'lightbulb': [p(bulb) + p('M9.8 19.2h4.4M10.6 21.6h2.8'), p(bulb) + p('M9.6 19h4.8v1.4H9.6zM10.6 21.2h2.8v1H10.6z')],
    'lightbulb.2': ['<g transform="translate(-3.200 1.600) scale(.84)">' + p(bulb) + p('M9.800 19.200h4.400M10.600 21.600h2.800') + '</g><g transform="translate(11.400 .6) scale(.56)">' + p(bulb) + p('M9.800 19.200h4.400') + '</g>'],
    'video': [rc(3, 6.5, 12.5, 11, 2.6) + p('M16 10.8 21 8v8l-5-2.8z'), rc(2.6, 6, 13.4, 12, 3) + p('M16.8 10.7 21.6 7.6v8.8l-4.8-3.1z')],
    'video.slash': [rc(3, 6.5, 12.5, 11, 2.6) + p('M16 10.8 21 8v8M3.5 3.5l17 17')],
    'camera': [p('M4 8.2h3l1.4-2h7.2l1.4 2h3V19H4z') + c(12, 13.4, 3.4), p('M4 8.2h3l1.4-2h7.2l1.4 2h3V19H4z')],
    'figure.walk': walk,
    'figure.walk.motion': walk + p('M3.6 8.2h2.4M2.8 11.8h2.6M3.6 15.4h2.4'),
    'figure.walk.departure': walk + p('M18.5 5.5h2.6v13'),
    'door.left.hand.closed': [rc(6.5, 3.5, 11, 17, 1) + c(14.6, 12.4, .5), rc(6.2, 3.2, 11.6, 17.6, 1.2)],
    'door.left.hand.open': [p('M6.5 3.8 15 5.6v12.8l-8.5 1.8z') + p('M15 5.6h2.5v12.8H15') + c(12, 12, .5)],
    'door.garage.closed': [p('M3 20.5V8.8L12 4l9 4.8v11.7M6.5 20.5V12h11v8.5M6.5 14.8h11M6.5 17.6h11')],
    'door.garage.open': [p('M3 20.5V8.8L12 4l9 4.8v11.7M6.5 11.2h11M6.5 20.5V11.2')],
    'lock': [rc(5, 10.5, 14, 10, 2.6) + p('M8 10.5V8a4 4 0 0 1 8 0v2.5'), '<path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><rect x="4.6" y="10.5" width="14.8" height="10.4" rx="2.8"/>'],
    'lock.open': [rc(5, 10.5, 14, 10, 2.6) + p('M8 10.5V8a4 4 0 0 1 7.6-1.7'), '<path d="M8 10.5V8a4 4 0 0 1 7.6-1.7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><rect x="4.6" y="10.5" width="14.8" height="10.4" rx="2.8"/>'],
    'lock.shield': [p(shield) + rc(9, 10.5, 6, 5, 1.2) + p('M10.2 10.5V9a1.8 1.8 0 0 1 3.6 0v1.5')],
    'exclamationmark.triangle': [p('M12 4.4 21.4 20H2.6z') + p('M12 10.2v4.4M12 17.2v.2'), '<path fill-rule="evenodd" d="M13.1 3.9a1.3 1.3 0 0 0-2.2 0L2.2 18.6A1.3 1.3 0 0 0 3.3 20.5h17.4a1.3 1.3 0 0 0 1.1-1.9zM11 9.4h2v5h-2zm0 6.3h2v2h-2z"/>'],
    'moon': [p('M20 14.6A8.4 8.4 0 0 1 9.4 4a8.4 8.4 0 1 0 10.6 10.6z')],
    'moon.zzz': [p('M17 12.600A6.800 6.800 0 0 1 9 5a6.800 6.800 0 1 0 8 7.600zM15 4h4l-4 4h4')],
    'exclamationmark.shield': [p(shield) + p('M12 8.500v4M12 15.300v.2')],
    'moon.stars': [p('M19.4 14.4A7.8 7.8 0 0 1 9.6 4.6a7.8 7.8 0 1 0 9.8 9.8z') + p('M17 3.5v3M15.5 5h3')],
    'wind': [p('M3 9h11.2a2.4 2.4 0 1 0-2.4-2.4M3 13h15.2a2.8 2.8 0 1 1-2.8 2.8M3 17h8')],
    'fan': ['<g>' + [0, 90, 180, 270].map(function (a) { return '<path transform="rotate(' + a + ' 12 12)" d="M12 10.800C10.600 7.800 11.200 4.600 13.600 3.400 15.800 5.200 14.600 8.600 12 10.800z"/>'; }).join('') + c(12, 12, 1.200) + '</g>'],
    'drop': [p('M12 3.6c3.4 4.1 5.6 7 5.6 10.1a5.6 5.6 0 0 1-11.2 0c0-3.1 2.2-6 5.6-10.1z'), p('M12 3.2c3.5 4.2 5.9 7.3 5.9 10.5a5.9 5.9 0 0 1-11.8 0c0-3.2 2.4-6.300 5.9-10.5z')],
    'humidity': [p('M12 3.6c3.4 4.1 5.6 7 5.6 10.1a5.6 5.6 0 0 1-11.2 0c0-3.1 2.2-6 5.6-10.1z') + p('M9.7 15.5l4.6-3.4')],
    'humidifier': [rc(5, 11, 14, 9, 3) + p('M9 7.5c0-1.6 1.2-1.6 1.2-3.1M13.5 7.5c0-1.6 1.2-1.6 1.2-3.1')],
    'flame': [p('M12 3.4c.6 3.2 5.6 5.6 5.6 10.4a5.6 5.6 0 0 1-11.2 0c0-2.2 1-3.4 2-4.5.3 1.2.9 1.9 1.7 2.1C9.4 8.100 10.700 5.400 12 3.400z')],
    'snowflake': [p('M12 3v18M4.2 7.5l15.6 9M19.8 7.500l-15.600 9M9.600 4.800 12 6.800l2.400-2M9.600 19.200 12 17.200l2.400 2')],
    'bolt.fill': ['<path d="M13.300 2.800 5.200 13.200h5.400l-1 8 8.200-10.800h-5.500z"/>'],
    'power': [p('M12 3.400v8.200M7.100 6.800a7.400 7.400 0 1 0 9.800 0')],
    'chevron.right': p('M9.200 5.200 15.800 12l-6.600 6.800'),
    'chevron.left': p('M14.800 5.200 8.200 12l6.600 6.800'),
    'chevron.up': p('M5.200 14.800 12 8.200l6.800 6.600'),
    'chevron.down': p('M5.200 9.200 12 15.800l6.800-6.600'),
    'xmark': p('M6 6l12 12M18 6 6 18'),
    'checkmark': p('M5 12.800 9.800 17.600 19 7'),
    'plus': p('M12 4.800v14.400M4.800 12h14.400'),
    'minus': p('M4.800 12h14.400'),
    'magnifyingglass': c(10.800, 10.800, 6.200) + p('M15.500 15.500 20.400 20.400'),
    'line.3.horizontal': p('M4 7h16M4 12h16M4 17h16'),
    'arrow.up.arrow.down': p('M8 20V5M4.500 8.500 8 5l3.500 3.500M16 4v15M12.500 15.500 16 19l3.500-3.500'),
    'line.3.horizontal.decrease': p('M4 7h16M7 12h10M10 17h4'),
    'tv': [rc(3, 5.500, 18, 12, 2.500) + p('M8.500 20.500h7'), rc(3, 5.200, 18, 12.400, 2.800) + rc(8, 20, 8, 1.200, .6)],
    'hifispeaker': [rc(6, 3.500, 12, 17, 2.800) + c(12, 9, 2.300) + c(12, 15.500, 1.700)],
    'gamecontroller': [rc(2.800, 7, 18.400, 10, 5) + p('M7.500 10v4M5.500 12h4M15.800 11.200v.1M18 13v.1')],
    'pc': [rc(3, 4.500, 18, 11.500, 2) + p('M9 20h6M12 16v4')],
    'display': [rc(3, 4.500, 18, 11.500, 2) + p('M9 20h6M12 16v4')],
    'laptopcomputer': [rc(5, 5.500, 14, 9.500, 1.500) + p('M2.500 18.500h19')],
    'robotic.vacuum': [c(12, 12.500, 8) + c(12, 12.500, 2.300) + p('M12 4.500V3')],
    'sprinkler.and.droplets': [p('M12 20v-7M9 13h6M12 13c0-3-4-3.500-4-7a4 4 0 0 1 8 0c0 3.500-4 4-4 7zM5 18c0 1.100-.8 1.800-.8 2.400a.8.800 0 0 0 1.600 0c0-.6-.8-1.300-.8-2.400zM19 18c0 1.100-.8 1.800-.8 2.400a.8.800 0 0 0 1.600 0c0-.6-.8-1.300-.8-2.400z')],
    'leaf': [p('M5 19c-1-9 4-14 15-14 0 9-4.500 15-13 14zM5 19c3-4 6-6.500 10-8.500')],
    'bed.double': [p('M3 19V6M3 15h18v4M21 15v-3.500a3 3 0 0 0-3-3h-7V15M6.500 12.500h.1')],
    'sofa': [p('M5 11V8.500A2.500 2.500 0 0 1 7.500 6h9A2.500 2.500 0 0 1 19 8.500V11M3 12.500a2 2 0 0 1 4 0V15h10v-2.500a2 2 0 0 1 4 0V18H3zM6 18v2M18 18v2')],
    'fork.knife': [p('M7 3v7.500M4.500 3v5a2.500 2.500 0 0 0 5 0V3M7 11v10M17 21V3c-2.200 1.500-3 4-3 7v3h3')],
    'refrigerator': [rc(5.500, 3, 13, 18, 2.500) + p('M5.500 10.500h13M8.500 6.500v1.500M8.500 13v3')],
    'cabinet': [rc(4.500, 3.500, 15, 17, 1.500) + p('M12 3.500v17M9.500 11v2M14.500 11v2')],
    'dumbbell': [p('M7 8v8M17 8v8M4.500 10v4M19.500 10v4M7 12h10')],
    'shower': [p('M5 9a7 7 0 0 1 14 0zM12 3v-.5M8 13v1.500M12 13v3M16 13v1.500M10 18.500v1.500M14 18.500v1.500')],
    'gauge.with.dots.needle.50percent': [c(12, 13.500, 8.500) + p('M12 13.500V8M6.500 11.200h.1M17.500 11.200h.1')],
    'wifi': [p('M3 9.200a13.500 13.500 0 0 1 18 0M6 12.700a9 9 0 0 1 12 0M9 16.200a4.500 4.500 0 0 1 6 0') + c(12, 19.300, .8)],
    'wifi.slash': [p('M3 9.200a13.500 13.500 0 0 1 8-3.300M6 12.700a9 9 0 0 1 3-1.900M9 16.200a4.500 4.500 0 0 1 3.500-1.100M18.200 11.200M3.500 3.500l17 17') + c(12, 19.300, .8)],
    'icloud.slash': [p(cloud) + p('M4 4l16.500 16.500')],
    'bell': [p('M6 17.500V11a6 6 0 0 1 12 0v6.500l1.500 1.500h-15zM10 21h4'), '<path d="M6 17.500V11a6 6 0 0 1 12 0v6.500l1.500 1.500h-15z"/>' + sg('M10 21h4', 2)],
    'bell.slash': [p('M6 17.500V11a6 6 0 0 1 9.600-4.800M18 11v6.500l1.500 1.500H4.500M10 21h4M4 4l16 16')],
    'clock': [c(12, 12, 8.800) + p('M12 7v5.200l3.400 2')],
    'calendar': [rc(3.500, 5, 17, 15.500, 3) + p('M3.500 10h17M8 3v4M16 3v4')],
    'timer': [c(12, 13.500, 7.500) + p('M12 13.500V9.500M9.500 3h5M18.500 6l1-1')],
    'mappin.and.ellipse': [p('M12 21c4.500-4.500 6.500-7.800 6.500-10.800a6.500 6.500 0 0 0-13 0C5.500 13.200 7.500 16.500 12 21z') + c(12, 10, 2.300)],
    'info.circle': [c(12, 12, 8.800) + p('M12 11v5.500M12 7.700v.2'), '<path fill-rule="evenodd" d="M12 2.800a9.200 9.200 0 1 0 0 18.400 9.200 9.200 0 0 0 0-18.400zM11 7.400h2v2h-2zm0 3.600h2v6h-2z"/>'],
    'checkmark.circle': [c(12, 12, 8.800) + p('M8 12.300l2.800 2.800L16.200 9.500'), '<path fill-rule="evenodd" d="M12 2.800a9.200 9.200 0 1 0 0 18.400 9.200 9.200 0 0 0 0-18.400zm4.200 6.600-5.300 6a.8.800 0 0 1-1.200 0l-2.200-2.300 1.100-1.100 1.700 1.700 4.700-5.300z"/>'],
    'exclamationmark.circle': [c(12, 12, 8.800) + p('M12 7.600v5.500M12 16.200v.2'), '<path fill-rule="evenodd" d="M12 2.800a9.200 9.200 0 1 0 0 18.400 9.200 9.200 0 0 0 0-18.400zM11 7h2v6h-2zm0 7.600h2v2h-2z"/>'],
    'questionmark.circle': [c(12, 12, 8.800) + p('M9.500 9.500a2.500 2.500 0 1 1 3.500 2.300c-.7.400-1 .8-1 1.700M12 16.300v.2')],
    'pencil': [p('M4.500 19.500l.8-4 10-10a2.100 2.100 0 0 1 3 3l-10 10zM13.800 7l3.200 3.200')],
    'trash': [p('M4.500 7h15M9.500 7V4.500h5V7M6.500 7l.8 12.500h9.400L17.500 7M10 10.500v6M14 10.500v6')],
    'record.circle': [c(12, 12, 8.800) + '<circle cx="12" cy="12" r="4.400" fill="currentColor" stroke="none"/>'],
    'speaker.wave.2': [p('M4 9.500h3l4.500-3.500v12L7 14.500H4zM15 9a4.200 4.200 0 0 1 0 6M17.500 6.500a8 8 0 0 1 0 11')],
    'speaker.slash': [p('M4 9.500h3l4.500-3.500v12L7 14.500H4zM16 9.500l4.500 5M20.500 9.500 16 14.500')],
    'mic': [rc(9, 3.500, 6, 11, 3) + p('M5.500 11.500a6.500 6.500 0 0 0 13 0M12 18v3')],
    'play.fill': ['<path d="M7.500 4.800v14.400a.8.800 0 0 0 1.200.7l11.800-7.200a.8.8 0 0 0 0-1.400L8.700 4.100a.8.800 0 0 0-1.200.7z"/>'],
    'pause.fill': ['<rect x="6.200" y="4.500" width="4" height="15" rx="1.200"/><rect x="13.800" y="4.500" width="4" height="15" rx="1.200"/>'],
    'stop.fill': ['<rect x="5.500" y="5.500" width="13" height="13" rx="2.500"/>'],
    'sun.max': [c(12, 12, 4.200) + p('M12 2.800v2.500M12 18.700v2.500M2.800 12h2.500M18.700 12h2.500M5.500 5.500l1.800 1.800M16.700 16.700l1.800 1.800M5.500 18.500l1.800-1.800M16.700 7.300l1.800-1.800')],
    'cloud': [p(cloud)],
    'cloud.sun': [p('M8 18.500h9a3.800 3.800 0 0 0 .5-7.500 5.200 5.200 0 0 0-9.600 1.500A3 3 0 0 0 8 18.500zM7.500 5l.8 1.500M3.500 8.500 5 9M12 3.500v1.500')],
    'cloud.rain': [p('M7.500 15h9.200a4 4 0 0 0 .6-7.950A5.600 5.600 0 0 0 6.500 8.500 3.300 3.300 0 0 0 7.500 15zM8 18l-.8 2.500M12 18l-.8 2.500M16 18l-.8 2.500')],
    'cloud.bolt': [p('M7.500 14.500h9.200a4 4 0 0 0 .6-7.950A5.600 5.600 0 0 0 6.500 8 3.300 3.300 0 0 0 7.500 14.500zM12.500 13l-2 3.500h3l-1.500 3.500')],
    'aqi.medium': [p('M3.500 9h10.500a2.500 2.500 0 1 0-2.500-2.500M3.500 13h14.500a2.800 2.800 0 1 1-2.800 2.800M3.500 17h7')],
    'photo': [rc(3.500, 5, 17, 14, 2.500) + c(9, 10, 1.700) + p('M4 17.500l4.500-4.500 3.500 3.500 3-3 5 4.500')],
    'ellipsis': ['<circle cx="5.500" cy="12" r="1.700"/><circle cx="12" cy="12" r="1.700"/><circle cx="18.500" cy="12" r="1.700"/>'],
    'ellipsis.circle': [c(12, 12, 8.800) + '<circle cx="8" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="16" cy="12" r="1" fill="currentColor"/>'],
    'arrow.clockwise': [p('M19.500 12a7.500 7.500 0 1 1-2.400-5.500M19.500 4.500v4.200h-4.200')],
    'arrow.uturn.left.circle': [c(12, 12, 8.800) + p('M9.500 9.500 8 11l1.500 1.500M8 11h5a2.500 2.500 0 0 1 0 5h-1.500')],
    'car.side': [p('M3.500 15v-3l2-4.500a2 2 0 0 1 1.800-1.200h9.400a2 2 0 0 1 1.800 1.200l2 4.500v3zM3.500 15v2.500h3.300V15M17.200 15v2.500h3.300V15M6 11.500h12') + c(7.500, 15, .6)],
    'airplane': [p('M3 13.500 21 6l-4.500 12-3.500-4.500zM13 13.500 21 6')],
    'sparkles': [p('M10 4l1.600 4.400L16 10l-4.400 1.600L10 16l-1.600-4.400L4 10l4.400-1.600zM18 14l.8 2.200L21 17l-2.200.8L18 20l-.8-2.200L15 17l2.200-.8z')],
    'paintpalette': [p('M12 3.500a8.500 8.500 0 1 0 0 17c1.600 0 2-1 1.400-2-.7-1.100.1-2.500 1.500-2.500H17a3.500 3.500 0 0 0 3.500-3.500c0-4.200-3.800-9-8.500-9z') + c(8, 11, .8) + c(11, 7.500, .8) + c(15.500, 8.500, .8)],
    'slider.vertical.3': [p('M6 3.500v17M12 3.500v17M18 3.500v17') + c(6, 14, 2) + c(12, 8, 2) + c(18, 15.500, 2)],
    'cart': [p('M3 4.500h2.500l2.200 10.500h10.500l1.800-7.500H6.200') + c(9, 19.200, 1.200) + c(17, 19.200, 1.200)],
    'cart.badge.plus': [p('M3 4.500h2.500l2.200 10.500h9.500l1-4M6 7.500h8') + c(9, 19.200, 1.200) + c(16, 19.200, 1.200) + p('M18 3v5M15.500 5.500h5')],
    'star': [p('M12 3.800l2.500 5.300 5.800.7-4.300 4 1.100 5.800L12 16.800 6.900 19.600 8 13.800 3.700 9.800l5.800-.7z')],
    'heart': [p('M12 20c-6-4.200-8.500-7.500-8.500-10.500a4.700 4.700 0 0 1 8.500-2.800 4.700 4.700 0 0 1 8.500 2.800C20.500 12.500 18 15.800 12 20z')],
    'location': [p('M20 4 4 11l7 2 2 7z')],
    'bed.double.fill': [p('M3 19V6M3 15h18v4M21 15v-3.500a3 3 0 0 0-3-3h-7V15')],
    'tray': [p('M3.500 13.500 6 5h12l2.500 8.500v5h-17zM3.500 13.500H9a3 3 0 0 0 6 0h5.500')],
    'doc.text': [p('M6 3.500h8l4 4v13H6zM14 3.500v4h4M9 12h6M9 15.500h6')],
    'link': [p('M10 14a4 4 0 0 0 5.600 0l3-3a4 4 0 0 0-5.600-5.600l-1 1M14 10a4 4 0 0 0-5.600 0l-3 3a4 4 0 0 0 5.600 5.600l1-1')],
    'hourglass': [p('M6.500 3.500h11M6.500 20.500h11M7.500 3.500v3.500l4.500 5-4.500 5v3.500M16.500 3.500v3.500L12 12l4.500 5v3.500')],
    'envelope': [rc(3, 5.500, 18, 13, 2.500) + p('M3.500 7.500 12 13.500l8.500-6')],
    'tag': [p('M3.500 12.500V4.500h8l9 9-8 8z') + c(8, 9, 1.300)],
    'rectangle.dashed': ['<rect x="4" y="5" width="16" height="14" rx="2.500" stroke-dasharray="3 3"/>'],
    'square.split.2x2': [rc(4, 4, 16, 16, 3) + p('M12 4v16M4 12h16')],
    'videoprojector': [rc(3, 8, 18, 9, 3) + c(15, 12.500, 2.500) + p('M6 17v2M18 17v2')],
    'guitars': [p('M10 14 19 5M17 3.500l3.500 3.500M8.500 12a4 4 0 1 0 3.500 3.500') + c(8.500, 15.500, 1)],
    'music.note': [p('M9 18V6l10-2v12') + c(6.500, 18, 2.500) + c(16.500, 16, 2.500)],
    'film': [rc(3.500, 4, 17, 16, 2) + p('M3.500 9h17M3.500 15h17M8 4v16M16 4v16')],
    'suitcase': [rc(3.500, 7.500, 17, 12.500, 2.500) + p('M9 7.500V5a1.500 1.500 0 0 1 1.500-1.500h3A1.500 1.500 0 0 1 15 5v2.500M3.500 12.500h17')],
    'testtube.2': [p('M9 3.500h4M10 3.500V16a3 3 0 1 0 6 0V3.500M13 3.500M6 8l-1.500 8.500a3 3 0 0 0 5 2')],
    'paintbrush': [p('M19.500 4.500 11 13M8.500 14a3 3 0 0 0-3 3c0 1.500-.8 2.500-2 3 3.500.8 7-1 7-4.200z')],
    'battery.75percent': [rc(2.500, 7.500, 17, 9, 2.500) + p('M21.500 10.500v3') + '<rect x="4.500" y="9.500" width="9.500" height="5" rx="1" fill="currentColor" stroke="none"/>'],
    'a.circle': [c(12, 12, 8.800) + p('M8.500 16l3.500-8 3.500 8M9.800 13.500h4.400')],
    'number': [p('M9 4 7.500 20M16.500 4 15 20M4.500 9h16M3.500 15h16')],
    'percent': [c(7.500, 7.500, 2.500) + c(16.500, 16.500, 2.500) + p('M18 5.500 6 18.500')],
    'smoke': [p('M3 15h8v4H3zM13 15h3v4h-3zM18 15h3v4h-3zM6 12c0-2 2-2 2-4M12 12c0-2 2-2 2-4')],
    'circle.lefthalf.filled': [c(12, 12, 8.500) + '<path d="M12 3.500a8.500 8.500 0 0 0 0 17z" fill="currentColor" stroke="none"/>'],
    'switch.2': [rc(3.500, 5, 17, 6, 3) + c(17.500, 8, 1.600) + rc(3.500, 13, 17, 6, 3) + c(6.500, 16, 1.600)],
    'person.badge.shield.checkmark': [p(shield) + p('M9 12l2 2 3.500-4')],
    'wrench.and.screwdriver': [p('M14.500 4.500a4 4 0 0 0-3.800 5.300L4 16.500a1.800 1.800 0 0 0 2.500 2.500l6.700-6.700a4 4 0 0 0 5.300-3.800l-2.400 2.400-2.400-.7-.7-2.400z')],
    'questionmark': [p('M9 9a3 3 0 1 1 4.300 2.700c-.9.500-1.300 1.100-1.300 2M12 17.500v.2')],
    'building.2': [rc(4.500, 3.500, 9, 17, 1) + rc(13.500, 9, 6, 11.500, 1) + p('M7.500 7h3M7.500 11h3M7.500 15h3M15.500 13h2M15.500 16.500h2')],
    'photo.on.rectangle': [rc(6, 3.500, 14, 12, 2) + p('M3.500 8v10a2 2 0 0 0 2 2h11') + c(11, 8, 1.400)],
  };
  /* ---- Extra symbols (second batch). Most were drawn by the mockup helpers (components/, modals/, pages/ `_*.js`) and are promoted here
   * verbatim; the rest are drawn in the same language. A name already in S above wins (the loop at the end never overwrites). */
  /** A stroked shape drawn inside a FILLED glyph (the filled root has stroke="none"). */
  function sg(d, w) { return '<path d="' + d + '" fill="none" stroke="currentColor" stroke-width="' + (w || 1.8) + '" stroke-linecap="round" stroke-linejoin="round"/>'; }
  /** Filled drawing: `body` (solid shapes) with `cut` (stroked shapes, 1.9 wide) knocked out of it, so it reads on any background. */
  function fm(id, body, cut) {
    return '<mask id="sym-' + id + '"><rect width="24" height="24" fill="#fff"/><g fill="none" stroke="#000" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">' + cut + '</g></mask><g mask="url(#sym-' + id + ')">' + body + '</g>';
  }
  /** Ring + glyph outline; filled = disc with the glyph knocked out. `cut` overrides the knock-out shapes when the glyph is itself solid. */
  function dc(id, shapes, cut) { return [c(12, 12, 8.8) + shapes, fm(id, '<circle cx="12" cy="12" r="9.2"/>', cut || shapes)]; }
  /** Battery with a charge bar `w` wide (the full bar is 13). */
  function battery(w) { return rc(2.5, 7.5, 17, 9, 2.5) + p('M21.5 10.5v3') + '<rect x="4.5" y="9.5" width="' + w + '" height="5" rx="1" fill="currentColor" stroke="none"/>'; }
  var appliance = '<rect x="4" y="3.5" width="16" height="17" rx="2"/>';
  var applianceTop = p('M4 8h16M7 5.8h.01M10 5.8h.01');
  var sunHalf = 'M6.8 19a5.2 5.2 0 0 1 10.4 0';
  var sunRays = 'M3 19h18M4.8 12.2l1.4 1.4M19.2 12.2l-1.4 1.4M2.6 15.6h1.8M19.6 15.6h1.8';
  var sunUp = 'M12 8.6V3.8M9.6 6.2 12 3.8l2.4 2.4';
  var sunDown = 'M12 3.8v4.8M9.6 6.2 12 8.6l2.4-2.4';
  var thermo = 'M7 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z';
  var eyeShape = 'M2.5 12C5 7.5 8.3 5.5 12 5.5s7 2 9.5 6.5c-2.5 4.5-5.8 6.5-9.5 6.5S5 16.5 2.5 12z';
  var board = 'M7 4.5h10a2 2 0 0 1 2 2v12.5a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2z';
  var clipLines = 'M8.5 11h.01M11.5 11h4.5M8.5 15h.01M11.5 15h4.5';
  var more = {
    'backward.fill': ['<path d="M11 6.300v11.400L3.800 12zM20.200 6.300v11.400L13 12z" stroke-linejoin="round"/>'],
    'forward.fill': ['<path d="M13 6.300v11.400L20.200 12zM3.800 6.300v11.400L11 12z" stroke-linejoin="round"/>'],
    'speaker.fill': ['<path d="M4 9.500h3.200l4.800-3.800v12.600l-4.800-3.800H4z"/>'],
    'speaker.wave.3.fill': ['<path d="M3.500 9.500h3l4.500-3.600v12.200l-4.500-3.600h-3z"/>', '<path d="M3.500 9.500h3l4.500-3.600v12.200l-4.500-3.600h-3z"/><path d="M14.200 9.200a4.200 4.200 0 0 1 0 5.600M16.800 6.800a7.600 7.600 0 0 1 0 10.400M19.300 4.600a10.800 10.800 0 0 1 0 14.800" fill="none" stroke="currentColor" stroke-width="1.800" stroke-linecap="round"/>'],
    'arrow.up.to.line': p('M12 20V9M7.500 13.500 12 9l4.500 4.500M5 4h14'),
    'arrow.uturn.down': p('M6 20V10a5 5 0 0 1 10 0v6M12.500 12.500 16 16l3.500-3.500'),
    'arrow.uturn.up': p('M6 4v10a5 5 0 0 0 10 0V8M12.500 11.500 16 8l3.500 3.500'),
    'lock.trianglebadge.exclamationmark': [rc(3.500, 10.500, 12.500, 10, 2.400) + p('M6.500 10.500V8a3.200 3.200 0 0 1 6.400 0v2.500') + p('M18.800 11.200 22.200 17.600H15.400zM18.800 13.600v1.900M18.800 16.800v.1')],
    'air.conditioner.horizontal': '<rect x="3" y="6" width="18" height="8" rx="2"/><path d="M6.5 10h11M7 17.5c0 1.3-.8 1.8-.8 2.8M12 17.5c0 1.3-.8 1.8-.8 2.8M17 17.5c0 1.3-.8 1.8-.8 2.8"/>',
    'air.purifier': '<rect x="6" y="3.5" width="12" height="17" rx="2.4"/><path d="M9 7.5h6"/><circle cx="12" cy="13.5" r="3.4"/><path d="M12 10.1v6.8M8.6 13.5h6.8"/>',
    'alarm': ['<circle cx="12" cy="13.4" r="7"/><path d="M12 9.6v4l2.6 1.6M4.6 5.2 2.8 7.2M19.4 5.2l1.8 2"/>', '<path fill-rule="evenodd" d="M12 6.2a7.2 7.2 0 1 0 0 14.4 7.2 7.2 0 0 0 0-14.4zM11.2 9.4h1.6v3.9l2.3 1.4-.8 1.4-3.1-1.9z"/><path d="M4.1 4.7 2.4 6.8l1.1.9 1.7-2.1zM19.9 4.7l1.7 2.1-1.1.9-1.7-2.1z"/>'],
    'alarm.waves.left.and.right': '<circle cx="12" cy="13" r="5.2"/><path d="M12 10.2v3l2 1.2M4.4 8.6a8.4 8.4 0 0 0-1.4 4.6M19.6 8.6a8.4 8.4 0 0 1 1.4 4.6M6.4 18.4 5 20M17.6 18.4 19 20"/>',
    'antenna.radiowaves.left.and.right': ['<path d="M12 12.5V20"/><circle cx="12" cy="10.5" r="1.6"/><path d="M8.2 6.8a5.4 5.4 0 0 0 0 7.4M15.8 6.8a5.4 5.4 0 0 1 0 7.4M5.4 4.2a9.4 9.4 0 0 0 0 12.6M18.6 4.2a9.4 9.4 0 0 1 0 12.6"/>'],
    'app.fill': ['<rect x="4.5" y="4.5" width="15" height="15" rx="4"/>', '<rect x="4" y="4" width="16" height="16" rx="4.4"/>'],
    'apple.logo': '<path d="M12 8.4c-1.4-1.3-4.7-1-5.9 1.7-1.2 2.8.4 7.3 2.4 8.9 1.1.9 2.1.4 3.5.4s2.4.5 3.5-.4c1.1-.9 2.1-2.5 2.4-3.8-1.8-.8-2.5-3.6-.4-5.1-1.2-1.4-3.4-1.1-4.4-.2zM13 7c.2-1.5 1-2.6 2.3-3.2"/>',
    'appletvremote.gen4': ['<rect x="7" y="2.5" width="10" height="19" rx="3"/><circle cx="12" cy="8.5" r="2.7"/><path d="M10 14.2h4M10.5 17.8h.01M13.5 17.8h.01"/>', '<path fill-rule="evenodd" d="M10 2h4a3 3 0 0 1 3 3v14a3 3 0 0 1-3 3h-4a3 3 0 0 1-3-3V5a3 3 0 0 1 3-3zm2 3.6a2.9 2.9 0 1 0 0 5.8 2.9 2.9 0 0 0 0-5.8zM10 13.6h4v1.5h-4zM10 17h1.6v1.6H10zm2.4 0H14v1.6h-1.6z"/>'],
    'arrow.counterclockwise': ['<path d="M4.5 12a7.5 7.5 0 1 0 2.4-5.5"/><path d="M4.5 4.5v4h4"/>'],
    'arrow.triangle.2.circlepath': '<path d="M5 12a7 7 0 0 1 12-4.9l2 1.9M19 5v4h-4M19 12a7 7 0 0 1-12 4.9l-2-1.9M5 19v-4h4"/>',
    'arrow.up.forward.app': '<path d="M13.4 3.8h6.8v6.8M20.2 3.8l-8.2 8.2M10 4.8H7.4A3.4 3.4 0 0 0 4 8.2v8.4A3.4 3.4 0 0 0 7.4 20h8.4a3.4 3.4 0 0 0 3.4-3.4V14"/>',
    'arrow.up.left.and.arrow.down.right': ['<path d="M14.5 3.5h6v6M20.5 3.5l-7 7M9.5 20.5h-6v-6M3.5 20.5l7-7"/>'],
    'arrow.up.right.square': '<path d="M13 4.5h6.5V11M19.5 4.5 11 13M17.5 14v4.5a1.5 1.5 0 0 1-1.5 1.5H5.5A1.5 1.5 0 0 1 4 18.5V8a1.5 1.5 0 0 1 1.5-1.5H10"/>',
    'arrowtriangle.down.fill': ['<path d="M5.5 8h13L12 18.5z"/>', '<path d="M4.5 7.5h15L12 19z"/>'],
    'barcode': ['<path d="M3.500 6v12M6.500 6v12M9.500 6v12M12.200 6v12M14.800 6v12M17.500 6v12M20.500 6v12"/>'],
    'barcode.viewfinder': ['<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><path d="M8 8.500v7M11 8.500v7M13.500 8.500v7M16 8.500v7"/>'],
    'basket': ['<path d="M3.5 10h17l-1.6 9a1.5 1.5 0 0 1-1.5 1.2H6.6A1.5 1.5 0 0 1 5.100 19z"/><path d="M8 10 11 4M16 10l-3-6M9 13.5v3.5M12 13.5v3.5M15 13.5v3.5"/>'],
    'bathtub': '<path d="M3 12h18v1.6A5.4 5.4 0 0 1 15.6 19H8.4A5.4 5.4 0 0 1 3 13.6zM6 12V6.8a2.2 2.2 0 0 1 4.1-1.1M7.5 19l-.8 1.8M16.5 19l.8 1.8"/>',
    'battery.0percent': ['<rect x="2.5" y="7.5" width="17" height="9" rx="2.5"/><path d="M21.5 10.5v3"/>'],
    'book': '<path d="M12 6.6C10.2 5.2 7.2 4.7 4 5.2v12.6c3.2-.5 6.2 0 8 1.4 1.8-1.4 4.8-1.9 8-1.4V5.2c-3.2-.5-6.2 0-8 1.4zM12 6.6v12.6"/>',
    'calendar.badge.checkmark': ['<rect x="3.5" y="5" width="17" height="15.5" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4M9 15l2.2 2.2L15.4 13"/>'],
    'calendar.badge.clock': ['<rect x="3.5" y="5" width="15" height="14.5" rx="3"/><path d="M3.5 10h15M8 3v4M14 3v4"/><circle cx="17.5" cy="17.5" r="4.2"/><path d="M17.5 15.4v2.3l1.4.9"/>'],
    'car': '<path d="M4.5 15.5V12l1.7-4.3A2 2 0 0 1 8 6.5h8a2 2 0 0 1 1.8 1.2L19.5 12v3.5zM4.5 15.5v2.5M19.5 15.5v2.5M7.5 12h9"/><circle cx="8" cy="14.2" r="0.6"/><circle cx="16" cy="14.2" r="0.6"/>',
    'carrot': '<path d="M13.4 6.6l4 4L5 19z"/><path d="M15.4 8.6 18 6M16.4 9.6l3-1.6M14.4 7.6 16 5"/><path d="M9.5 12.5l2 2M7.5 15.5l1.5 1.5"/>',
    'carseat.left': '<path d="M8.2 3.6c1.6 0 2.6 1 2.7 2.6l.4 6.8h5.4a2.6 2.6 0 0 1 2.6 2.6v3H8.4L6.8 15.2V6.4c0-1.6.6-2.8 1.4-2.8z"/><path d="M9 20.4h10.2"/>',
    'cart.circle.fill': ['<circle cx="12" cy="12" r="9.2"/><path d="M6.8 8h1.7l1.3 6.1h6.1l1.2-4.3H9.2"/><circle cx="10.4" cy="16.7" r=".6"/><circle cx="15.4" cy="16.7" r=".6"/>', '<circle cx="12" cy="12" r="9.4" fill="currentColor" stroke="none"/><g style="stroke:var(--fill,#000);fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round"><path d="M6.8 8h1.7l1.3 6.1h6.1l1.2-4.3H9.2"/><circle cx="10.4" cy="16.7" r=".6"/><circle cx="15.4" cy="16.7" r=".6"/></g>'],
    'character.bubble': '<path d="M5 5h14a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 19 16h-6.5L8 20v-4H5a1.5 1.5 0 0 1-1.5-1.5v-8A1.5 1.5 0 0 1 5 5z"/><path d="M9 13l2-5 2 5M9.8 11.5h2.4"/>',
    'chevron.up.chevron.down': ['<path d="M8 9.5 12 5.5l4 4M8 14.5l4 4 4-4"/>'],
    'circle': ['<circle cx="12" cy="12" r="8.8"/>'],
    'circle.circle': ['<circle cx="12" cy="12" r="8.6"/><circle cx="12" cy="12" r="3.4"/>'],
    'circle.fill': ['<circle cx="12" cy="12" r="7.5"/>', '<circle cx="12" cy="12" r="8"/>'],
    'clock.arrow.circlepath': ['<path d="M4.200 12a7.800 7.800 0 1 0 2.300-5.500M4 4.500v3.500h3.500M12 8.500v3.800l2.500 1.500"/>'],
    'cloud.heavyrain': ['<path d="M7.5 14.5h9.2a4 4 0 0 0 .6-7.95A5.6 5.6 0 0 0 6.5 8 3.3 3.3 0 0 0 7.5 14.5z"/><path d="M7.5 17.5l-1 2.5M12 17.5l-1 2.5M16.5 17.5l-1 2.5"/>'],
    'desktopcomputer': '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20h6M12 16.5V20"/>',
    'dial.medium': '<circle cx="12" cy="12" r="8.5"/><path d="M12 12l3.4-3.4M7.5 16.5h9"/>',
    'dot.radiowaves.left.and.right': ['<circle cx="12" cy="12" r="1.8"/><path d="M8.4 8.4a5 5 0 0 0 0 7.2M15.6 8.4a5 5 0 0 1 0 7.2M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8"/>'],
    'drop.triangle': ['<path d="M12 3.6c3.4 4.1 5.6 7 5.6 10.1a5.6 5.6 0 0 1-11.2 0c0-3.1 2.2-6 5.6-10.1z"/><path d="M12 12.2v3M12 17.5v.1"/>'],
    'ev.charger': ['<rect x="5" y="4.5" width="9" height="15.5" rx="1.8"/><path d="M3.5 20.5h12M14 9h2.2a1.8 1.8 0 0 1 1.8 1.8v4.4a1.5 1.5 0 0 0 3 0V9l-2.2-2.2M8.2 8.5 7 12.2h2.8L8.6 16"/>'],
    'figure.stand': '<circle cx="12" cy="4.5" r="1.9"/><path d="M12 8.5V15M8.3 10.3h7.4M12 15l-2.6 6M12 15l2.6 6"/>',
    'figure.walk.arrival': ['<circle cx="13.5" cy="4.6" r="1.9"/><path d="M12.2 9.5 9.4 11v3.2M12.2 9.5l3 3.3 2.9.5M12.2 9.5l.9 5.6-3.3 6.2M13.1 15.1l3 2.4.7 3.7"/><path d="M5.5 5.5H3v13"/>'],
    'folder': ['<path d="M3.5 7.5A1.5 1.5 0 0 1 5 6h4l2 2.2h8a1.5 1.5 0 0 1 1.5 1.5v8.8a1.5 1.5 0 0 1-1.5 1.5H5a1.5 1.5 0 0 1-1.5-1.5z"/>'],
    'frying.pan': '<circle cx="10" cy="13.5" r="6.5"/><circle cx="10" cy="13.5" r="3.4"/><path d="M15.4 9.2 21 5"/>',
    'gauge.with.dots.needle.33percent': ['<path d="M5.6 18.4A9 9 0 1 1 18.4 18.4"/><path d="M12 12 L7.98 8.10"/><circle cx="12" cy="12" r="1"/>'],
    'gauge.with.dots.needle.67percent': ['<path d="M5.6 18.4A9 9 0 1 1 18.4 18.4"/><path d="M12 12 L16.02 8.10"/><circle cx="12" cy="12" r="1"/>'],
    'gauge.with.dots.needle.100percent': ['<path d="M5.6 18.4A9 9 0 1 1 18.4 18.4"/><path d="M12 12 L15.96 15.96"/><circle cx="12" cy="12" r="1"/>'],
    'hammer.circle.fill': ['<circle cx="12" cy="12" r="9.2"/><path d="M7.6 16.4l5.6-5.6"/><path d="M11.6 7.6l2-1.6 3.6 3.6-1.6 2z"/>', '<circle cx="12" cy="12" r="9.4" fill="currentColor" stroke="none"/><g style="stroke:var(--fill,#000);fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round"><path d="M7.6 16.4l5.6-5.6"/><path d="M11.6 7.6l2-1.6 3.6 3.6-1.6 2z"/></g>'],
    'hand.raised': '<rect x="7" y="10.5" width="10" height="9" rx="3"/><path d="M8.8 10.5V6M11.1 10.5V4.5M13.4 10.5V5M15.7 10.5V7M7 14.2 5 12.4"/>',
    'heat.waves': '<path d="M4.5 6.5c1.5-1.5 1.5 1.5 3 0s1.5 1.5 3 0 1.5 1.5 3 0 1.5 1.5 3 0M4.5 12c1.5-1.5 1.5 1.5 3 0s1.5 1.5 3 0 1.5 1.5 3 0 1.5 1.5 3 0M4.5 17.5c1.5-1.5 1.5 1.5 3 0s1.5 1.5 3 0 1.5 1.5 3 0 1.5 1.5 3 0"/>',
    'hifireceiver': ['<rect x="2.5" y="7.5" width="19" height="9.5" rx="2"/><circle cx="7.5" cy="12.2" r="2.2"/><path d="M13 10.8h5.5M13 13.6h4"/>'],
    'keyboard': ['<rect x="2.5" y="6.5" width="19" height="11" rx="2.5"/><path d="M6 10h.01M9 10h.01M12 10h.01M15 10h.01M18 10h.01M6 13.5h.01M18 13.5h.01M9.5 14h5"/>'],
    'ladybug': ['<ellipse cx="12" cy="13.6" rx="5.6" ry="6.4"/><path d="M12 7.2v12.8M8.4 7.2a3.6 3.6 0 0 1 7.2 0M6.4 11H3.2M17.6 11h3.2M6.6 15.8H3.6M17.4 15.8h3M9.6 4.6 8 2.8M14.4 4.6 16 2.8"/>'],
    'leaf.circle': '<circle cx="12" cy="12" r="9"/><path d="M8 15.5c0-4 2.6-6.6 7.6-7-.2 4.8-2.8 7.4-6.4 7.4M8 16.3c1.2-2.8 3-4.4 5-5.5"/>',
    'lightbulb.slash': '<path d="M12 3.2a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2v.2h5v-.2c0-.8.4-1.5 1-2A6 6 0 0 0 12 3.2z"/><path d="M9.8 19.2h4.4M10.6 21.6h2.8M4 3.6l16 16.8"/>',
    'list.bullet': '<path d="M9 7h11.4M9 12h11.4M9 17h11.4"/><circle cx="4.6" cy="7" r="0.9"/><circle cx="4.6" cy="12" r="0.9"/><circle cx="4.6" cy="17" r="0.9"/>',
    'list.number': '<path d="M10 7h10.4M10 12h10.4M10 17h10.4M3.8 6.2 5.4 5v4.4M3.6 14.6c.2-1 2.7-1 2.7.2 0 1.2-2.7 1.8-2.8 3.2h2.9"/>',
    'location.circle': ['<circle cx="12" cy="12" r="9"/><path d="M16.6 7.4 7.4 11.2l4.4 1 1 4.4z"/>', '<path fill-rule="evenodd" d="M12 2.8a9.2 9.2 0 1 0 0 18.4 9.2 9.2 0 0 0 0-18.4zM16.6 7.4l-3.6 9.2-1.2-4.4-4.4-1.2z"/>'],
    'location.slash': ['<path d="M20 4 4 11l7 2 2 7z"/><path d="M3.5 3.5l17 17"/>', '<path d="M20 4 4 11l7 2 2 7z"/><path d="M3.5 3.5l17 17" stroke="currentColor" stroke-width="2"/>'],
    'lungs': '<path d="M12 4v8.4M9.6 9C7 10 5 14 4.5 18c-.1 1.4 1.2 2 2.4 1.5 1.4-.6 2.6-1.8 2.6-3.6V9zM14.4 9c2.6 1 4.6 5 5.1 9 .1 1.4-1.2 2-2.4 1.5-1.4-.6-2.6-1.8-2.6-3.6V9z"/>',
    'minus.circle.fill': ['<circle cx="12" cy="12" r="8.8"/><path d="M8 12h8"/>', '<path fill-rule="evenodd" d="M12 2.8a9.2 9.2 0 1 0 0 18.4 9.2 9.2 0 0 0 0-18.4zM7.6 11h8.8v2H7.6z"/>'],
    'paperclip': ['<path d="M20 11.4 12.2 19.2a5 5 0 0 1-7-7l8-8a3.3 3.3 0 0 1 4.7 4.7L10 16.8a1.7 1.7 0 0 1-2.4-2.4l7.1-7.1"/>'],
    'person.crop.circle': ['<circle cx="12" cy="12" r="9.2"/><circle cx="12" cy="9.6" r="3"/><path d="M6.2 18.2c1-2.3 3.2-3.6 5.8-3.6s4.8 1.3 5.8 3.6"/>', '<path fill-rule="evenodd" d="M12 2.6a9.4 9.4 0 1 0 0 18.8 9.4 9.4 0 0 0 0-18.8zm0 4.1a3.1 3.1 0 1 1 0 6.2 3.1 3.1 0 0 1 0-6.2zM6.8 17.6c.9-1.9 2.9-3 5.2-3s4.3 1.1 5.2 3A7.6 7.6 0 0 1 12 20.2a7.6 7.6 0 0 1-5.2-2.6z"/>'],
    'person.crop.circle.badge.exclamationmark': '<circle cx="11" cy="12.6" r="8.4"/><circle cx="11" cy="10.4" r="2.8"/><path d="M5.8 17.6c1-2 2.8-3 5.2-3s4.2 1 5.2 3"/><path d="M20 3.6v4.2M20 10v.2"/>',
    'scope': ['<circle cx="12" cy="12" r="6.2"/><circle cx="12" cy="12" r="1.6"/><path d="M12 2.8v3M12 18.2v3M2.8 12h3M18.2 12h3"/>'],
    'server.rack': '<rect x="4" y="4" width="16" height="5" rx="1.5"/><rect x="4" y="10" width="16" height="5" rx="1.5"/><rect x="4" y="16" width="16" height="4" rx="1.5"/><path d="M7 6.5h.01M7 12.5h.01M7 18h.01"/>',
    'puzzlepiece.extension': '<path d="M5 8.5h3.6a2.1 2.1 0 1 1 4.1 0H16v3.4a2.1 2.1 0 1 1 0 4.1V19.5H5z"/>',
    'arrow.down.circle': '<circle cx="12" cy="12" r="8.8"/><path d="M12 7.5v8.6M8.3 12.8 12 16.5l3.7-3.7"/>',
    'slider.horizontal.3': '<path d="M4 7h10M18 7h2M4 12h4M12 12h8M4 17h12M20 17h0"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="17" r="2"/>',
    'speaker.minus.fill': ['<path d="M3.5 9.5H7l4.5-3.7v12.4L7 14.5H3.5z"/><path d="M15 12h5"/>', '<path d="M3 9.3h4l4.8-3.9v13.2L7 14.7H3z"/><rect x="14.5" y="11.2" width="6" height="1.7" rx=".85"/>'],
    'speaker.plus.fill': ['<path d="M3.5 9.5H7l4.5-3.7v12.4L7 14.5H3.5z"/><path d="M15 12h5M17.5 9.5v5"/>', '<path d="M3 9.3h4l4.8-3.9v13.2L7 14.7H3z"/><rect x="14.5" y="11.2" width="6" height="1.7" rx=".85"/><rect x="16.65" y="9.05" width="1.7" height="6" rx=".85"/>'],
    'square.and.arrow.up': ['<path d="M12 15V3.5M8 7l4-3.8L16 7M7.5 10.5H6a1.5 1.5 0 0 0-1.5 1.5v7.5A1.5 1.5 0 0 0 6 21h12a1.5 1.5 0 0 0 1.5-1.5V12a1.5 1.5 0 0 0-1.5-1.5h-1.5"/>'],
    'square.and.pencil': ['<path d="M11 4.5H6.5a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V13"/><path d="M17.2 3.8a1.8 1.8 0 0 1 2.5 2.5l-7.4 7.4-3.4.9.9-3.4z"/>'],
    'stairs': '<path d="M3.5 20.5h4.5v-4.5h4.5v-4.5h4.5V7h3"/>',
    'stove': '<rect x="4" y="3.5" width="16" height="17" rx="2"/><path d="M4 9h16M8 6.3h.01M12 6.3h.01M16 6.3h.01"/><rect x="7.5" y="12" width="9" height="5.5" rx="1.2"/>',
    'sun.snow': '<circle cx="9" cy="9" r="3.2"/><path d="M9 2.8v1.4M9 13.8v1.4M2.8 9h1.4M13.8 9h1.4M17.5 13v8M14 15l7 4M21 15l-7 4"/>',
    'takeoutbag.and.cup.and.straw': '<path d="M4.5 9h9.5l-.9 11H5.4z"/><path d="M6.8 9V7a2.5 2.5 0 0 1 5 0v2"/><path d="M16.5 12h3.6l-.5 8h-2.6z M17.4 12V9.5l1.6-1"/>',
    'thermometer.and.liquid.waves': '<path d="M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z"/><path d="M12 8.6v7"/><path d="M16 12c.9-.9 1.7-.9 2.5 0s1.7.9 2.5 0M16 15.5c.9-.9 1.7-.9 2.5 0s1.7.9 2.5 0"/>',
    'thermometer.high': '<path d="M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z"/><path d="M12 6.2v9.5"/>',
    'thermometer.medium.slash': '<path d="M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z"/><path d="M12 8.6v7"/><path d="M4.5 3.5l15 17"/>',
    'thermometer.variable': '<path d="M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z"/><path d="M12 8.6v7"/><path d="M17.2 6.5h3M17.2 10h2M17.2 13.5h3"/>',
    'tray.circle.fill': ['<circle cx="12" cy="12" r="9.2"/><path d="M6.8 13.4h3l1 1.6h2.4l1-1.6h3M6.8 13.4l1.3-4.4h7.8l1.3 4.4v3.2H6.8z"/>', '<circle cx="12" cy="12" r="9.4" fill="currentColor" stroke="none"/><g style="stroke:var(--fill,#000);fill:none;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round"><path d="M6.8 13.4h3l1 1.6h2.4l1-1.6h3M6.8 13.4l1.3-4.4h7.8l1.3 4.4v3.2H6.8z"/></g>'],
    'tv.and.mediabox': ['<rect x="2.5" y="4" width="19" height="11" rx="2"/><rect x="7" y="17.5" width="10" height="3" rx="1"/>'],
    'tv.slash': ['<rect x="3" y="5.5" width="18" height="12" rx="2.5"/><path d="M8.500 20.500h7"/><path d="M3.5 3.5l17 17"/>'],
    'wand.and.stars': ['<path d="M4 20 14 10M12.5 8.5l3 3"/><path d="M18 3v4M16 5h4M20 11v2.4M18.8 12.2h2.4M8 3.5v2.4M6.8 4.7h2.4"/>'],
    'waveform.path.ecg': '<path d="M2.5 12.2h4l2-5.2 3.6 11 2.4-8 1.6 2.2h5.4"/>',
    'wifi.exclamationmark': '<path d="M3 9.5a14 14 0 0 1 18 0M6 12.8a9.6 9.6 0 0 1 12 0M9 16a5.2 5.2 0 0 1 6 0"/><circle cx="12" cy="19" r="0.9"/><path d="M20.6 14v3.2M20.6 19.6v.2"/>',
    'window.vertical.closed': '<rect x="5" y="3.5" width="14" height="17" rx="1.5"/><path d="M12 3.5v17M5 12h14"/>',
    'window.vertical.open': '<rect x="5" y="3.5" width="14" height="17" rx="1.5"/><path d="M12 3.5v17M5 12h7M12 6.2l5.5 2.2v7.2L12 17.8"/>',
    'windshield.front.and.heat.waves': '<path d="M3.4 17.6 6.2 7.2A2 2 0 0 1 8.1 5.8h7.8a2 2 0 0 1 1.9 1.4l2.8 10.4z"/><path d="M9 9.2c1 1 1 2.2 0 3.2M12 9.2c1 1 1 2.2 0 3.2M15 9.2c1 1 1 2.2 0 3.2"/><path d="M6 20.5h12"/>',
    'xmark.octagon.fill': [p('M8.600 3.600h6.800l5 5v6.800l-5 5H8.600l-5-5V8.600zM9 9l6 6M15 9l-6 6'), fm('octagon', p('M8.600 3.200h6.800l5.400 5.400v6.800l-5.400 5.400H8.600l-5.400-5.400V8.600z'), p('M9 9l6 6M15 9l-6 6'))],
    'zzz': '<path d="M4.5 5h5l-5 6.2h5M12 11.4h4.8L12 17.4h4.8M16.6 3.4h3.4l-3.4 4.1H20"/>',
    'dishwasher': [appliance + applianceTop + c(12, 14.2, 3.8) + p('M9.7 14.8c1 1 3 1 4.3-.4'), fm('dishwasher', appliance, p('M4 8h16M7 5.8h.01M10 5.8h.01') + '<circle cx="12" cy="14.2" r="3.8"/>' + '<path d="M9.7 14.8c1 1 3 1 4.3-.4"/>')],
    'washer': [appliance + applianceTop + c(12, 14.2, 4) + p('M9 14.5c1.5-1.5 4.5 1.5 6 0'), fm('washer', appliance, p('M4 8h16M7 5.8h.01M10 5.8h.01') + '<circle cx="12" cy="14.2" r="4"/>' + '<path d="M9 14.5c1.5-1.5 4.5 1.5 6 0"/>')],
    'dryer': [appliance + applianceTop + c(12, 14.2, 4) + p('M10 12.2a2.5 2.5 0 0 1 4 .1'), fm('dryer', appliance, p('M4 8h16M7 5.8h.01M10 5.8h.01') + '<circle cx="12" cy="14.2" r="4"/>' + '<path d="M10 12.2a2.5 2.5 0 0 1 4 .1"/>')],
    'battery.25percent': [battery(3.25)],
    'battery.50percent': [battery(6.5)],
    'battery.100percent': [battery(13)],
    'stop.circle': dc('stop', rc(9, 9, 6, 6, 1.4), '<rect x="9" y="9" width="6" height="6" rx="1.4" fill="#000"/>'),
    'pause.circle': dc('pause', p('M9.800 8.600v6.800M14.200 8.600v6.800')),
    'xmark.circle': dc('xmark', p('M9 9l6 6M15 9l-6 6')),
    'trash.circle': dc('trash', p('M8.600 9.400h6.800M10.200 9.400V8.200h3.600v1.200M9.400 9.400l.5 6.200h4.200l.5-6.200')),
    'thermometer.snowflake': [p(thermo) + p('M9 8.5v7.200') + p('M17.500 5v7M14.500 6.750l6 3.500M20.500 6.750l-6 3.500'), p(thermo) + sg('M17.500 5v7M14.500 6.750l6 3.500M20.500 6.750l-6 3.500')],
    'arrow.down.to.line': p('M12 4v11M7.500 10.500 12 15l4.500-4.500M5 20h14'),
    'scribble': [p('M3.500 16.500c1.800-4.800 3-9.500 5-9.500 2.200 0 .5 8.500 2.700 8.500 2.100 0 1.600-6.500 3.400-6.500 1.700 0 1 5.500 2.500 5.500.9 0 1.400-1 2-2'), sg('M3.500 16.500c1.800-4.800 3-9.500 5-9.500 2.200 0 .5 8.500 2.700 8.500 2.100 0 1.600-6.500 3.400-6.500 1.700 0 1 5.500 2.500 5.500.9 0 1.400-1 2-2', 2.300)],
    'water.waves': p('M3 7.500c1.500-1.600 3-1.600 4.500 0s3 1.600 4.500 0 3-1.600 4.500 0 3 1.600 4.500 0M3 12c1.500-1.600 3-1.600 4.500 0s3 1.600 4.500 0 3-1.600 4.500 0 3 1.600 4.500 0M3 16.500c1.500-1.600 3-1.600 4.500 0s3 1.600 4.500 0 3-1.600 4.500 0 3 1.600 4.500 0'),
    'bag': [p('M5.500 8h13l-1 11.500a1.500 1.500 0 0 1-1.500 1.500H8a1.500 1.500 0 0 1-1.500-1.500z') + p('M9 10.500V7a3 3 0 0 1 6 0v3.500'), '<path d="M5.500 8h13l-1 11.500a1.500 1.500 0 0 1-1.500 1.500H8a1.500 1.500 0 0 1-1.500-1.500z"/>' + sg('M9 10.500V7a3 3 0 0 1 6 0v3.500', 2)],
    'bolt.horizontal.fill': ['<g transform="rotate(90 12 12)"><path d="M13.300 2.800 5.200 13.200h5.400l-1 8 8.200-10.800h-5.500z"/></g>'],
    'circle.dashed': ['<circle cx="12" cy="12" r="8.800" stroke-dasharray="3.100 3.800"/>', '<circle cx="12" cy="12" r="8.800" fill="none" stroke="currentColor" stroke-width="1.800" stroke-linecap="round" stroke-dasharray="3.100 3.800"/>'],
    'list.clipboard': [p('M8.500 4.500H7a2 2 0 0 0-2 2V19a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V6.500a2 2 0 0 0-2-2h-1.500') + rc(8.500, 3, 7, 3.500, 1.300) + p(clipLines),
      fm('clipboard', '<path d="' + board + '"/>', p(clipLines) + '<rect x="8.500" y="3" width="7" height="3.500" rx="1.300"/>') + '<rect x="8.500" y="3" width="7" height="3.500" rx="1.300"/>'],
    'eye': [p(eyeShape) + c(12, 12, 3), '<path fill-rule="evenodd" d="M12 5.500c-3.700 0-7 2-9.500 6.500 2.500 4.500 5.800 6.500 9.500 6.500s7-2 9.500-6.500C19 7.500 15.700 5.500 12 5.500zM12 9a3 3 0 1 1 0 6 3 3 0 0 1 0-6z"/>'],
    'sunrise': [p(sunHalf + sunRays + sunUp), '<path d="' + sunHalf + 'z"/>' + sg(sunRays + sunUp)],
    'sunset': [p(sunHalf + sunRays + sunDown), '<path d="' + sunHalf + 'z"/>' + sg(sunRays + sunDown)],
    'location.north': [p('M12 3.200 18.400 20 12 16.200 5.600 20z'), '<path d="M12 3.200 18.400 20 12 16.200 5.600 20z" stroke="currentColor" stroke-width="1.600" stroke-linejoin="round"/>'],
    'gauge': [p('M5.600 18.400A9 9 0 1 1 18.400 18.400M12 12l3.400-4.200') + c(12, 12, 1)],
    'hammer': ['<g transform="rotate(45 12 12)">' + rc(6.500, 4.500, 11, 5, 1.400) + p('M12 9.500v11') + '</g>',
      '<g transform="rotate(45 12 12)"><rect x="6.500" y="4.500" width="11" height="5" rx="1.400"/>' + sg('M12 9.500v11', 2) + '</g>'],
  };
  // Extend an existing entry with a filled drawing (the outline is the kit's).
  S['robotic.vacuum'] = [S['robotic.vacuum'][0], '<path fill-rule="evenodd" d="M12 4.500a8 8 0 1 0 0 16 8 8 0 0 0 0-16zM12 10.200a2.300 2.300 0 1 1 0 4.600 2.300 2.300 0 0 1 0-4.600z"/><path d="M11.300 2.600h1.400v2.200h-1.400z"/>'];
  S['cart'] = [S['cart'][0], '<path d="M6.200 7.500 7.700 15h10.500l1.800-7.500z" stroke="currentColor" stroke-width="1.400" stroke-linejoin="round"/>' + sg('M3 4.500h2.500l2.200 10.500h10.500', 1.800) + c(9, 19.200, 1.500) + c(17, 19.200, 1.500)];
  S['clock'] = [S['clock'][0], '<path fill-rule="evenodd" d="M12 2.800a9.200 9.200 0 1 0 0 18.400 9.200 9.200 0 0 0 0-18.400zM11 7h2v4.900l2.900 1.700-1 1.700-3.900-2.300z"/>'];
  Object.keys(more).forEach(function (k) { if (!S[k]) S[k] = more[k]; });
  /** Alias names the app uses for the same glyph. */
  var alias = { 'house.fill': 'house', 'shield.fill': 'shield', 'lightbulb.fill': 'lightbulb', 'lock.fill': 'lock', 'video.fill': 'video', 'camera.fill': 'camera',
    'person.fill': 'person', 'drop.fill': 'drop', 'flame.fill': 'flame', 'moon.fill': 'moon', 'star.fill': 'star', 'heart.fill': 'heart', 'bell.fill': 'bell',
    'checkmark.circle.fill': 'checkmark.circle', 'info.circle.fill': 'info.circle', 'exclamationmark.circle.fill': 'exclamationmark.circle',
    'exclamationmark.triangle.fill': 'exclamationmark.triangle', 'gearshape.fill': 'gearshape', 'thermometer': 'thermometer.medium', 'lock.open.fill': 'lock.open',
    'sun.max.fill': 'sun.max', 'cloud.fill': 'cloud', 'tv.fill': 'tv', 'speaker.wave.2.fill': 'speaker.wave.2', 'mic.fill': 'mic', 'pencil.circle': 'pencil',
    'door.left.hand.closed.fill': 'door.left.hand.closed', 'lightbulb.max': 'lightbulb', 'figure.walk.circle': 'figure.walk', 'shield.lefthalf.filled': 'shield',
    'xmark.circle.fill': 'xmark', 'trash.fill': 'trash', 'refrigerator.fill': 'refrigerator', 'play.rectangle': 'film',
    'chevron.forward': 'chevron.right', 'chevron.backward': 'chevron.left', 'arrow.uturn.backward.circle': 'arrow.uturn.left.circle',
    'photo.on.rectangle.angled': 'photo.on.rectangle', 'paintbrush.pointed': 'paintbrush', 'speaker.slash.fill': 'speaker.slash',
    'location.fill': 'location', 'clock.fill': 'clock', 'cart.fill': 'cart', 'bag.fill': 'bag', 'hammer.fill': 'hammer', 'eye.fill': 'eye',
    'sunrise.fill': 'sunrise', 'sunset.fill': 'sunset', 'location.north.fill': 'location.north', 'list.clipboard.fill': 'list.clipboard',
    'dishwasher.fill': 'dishwasher', 'washer.fill': 'washer', 'dryer.fill': 'dryer' };
  /** Symbols that always draw their fill drawing (the app asks for the fill variant). */
  var solid = { 'bolt.fill': 1, 'play.fill': 1, 'pause.fill': 1, 'stop.fill': 1, 'ellipsis': 1 };

  Mock.symbols = S;
  Mock.missingIcons = {};
  /**
   * An inline SVG icon as an HTML string.
   * @param {string} name SF Symbol name (as in HassDesign/SymbolMap.swift)
   * @param {{fill?:boolean, cls?:string, size?:string, label?:string, weight?:number}} [o]
   *   fill: the `.fill` symbol variant (active tiles, selected tabs). label: sets role="img" and aria-label; otherwise aria-hidden.
   */
  Mock.icon = function (name, o) {
    o = o || {};
    var key = alias[name] || name;
    var wantFill = o.fill || /\.fill$/.test(name) || solid[key];
    var base = S[key];
    if (!base && /\.fill$/.test(key)) base = S[key.replace(/\.fill$/, '')];
    if (!base) { Mock.missingIcons[name] = true; return '<svg class="ui-sym" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-dasharray="3 3" aria-hidden="true"><circle cx="12" cy="12" r="8"/></svg>'; }
    var outline = Array.isArray(base) ? base[0] : base;
    var filled = Array.isArray(base) && base[1] ? base[1] : null;
    var a11y = o.label ? ' role="img" aria-label="' + Mock.esc(o.label) + '"' : ' aria-hidden="true"';
    var w = o.weight || 1.8;
    var st = o.size ? ' style="width:' + o.size + ';height:' + o.size + '"' : '';
    var cls = 'ui-sym' + (o.cls ? ' ' + o.cls : '');
    if (wantFill && filled) return '<svg class="' + cls + '" viewBox="0 0 24 24" fill="currentColor" stroke="none"' + a11y + st + '>' + filled + '</svg>';
    if (wantFill && !filled) return '<svg class="' + cls + '" viewBox="0 0 24 24" fill="currentColor" fill-opacity=".92" stroke="currentColor" stroke-width="' + (w + .3) + '" stroke-linecap="round" stroke-linejoin="round"' + a11y + st + '>' + outline + '</svg>';
    return '<svg class="' + cls + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + w + '" stroke-linecap="round" stroke-linejoin="round"' + a11y + st + '>' + outline + '</svg>';
  };
  /** Same, as a DOM node. */
  Mock.iconEl = function (name, o) { return Mock.html(Mock.icon(name, o)); };
  /** The names this kit can draw (for the README and the lint). */
  Mock.iconNames = function () { return Object.keys(S).concat(Object.keys(alias)).sort(); };
})();
