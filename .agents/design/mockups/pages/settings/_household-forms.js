/* household-forms batch helper: the Household Settings pages, the presence and auto-reset sheets and the form-control swatches.
 *
 * Loaded with <script src> after kit.js by every mockup in the household-forms batch (pages/settings/household-*, modals/settings/{auto-reset-sheet,presence-*},
 * components/{settings,forms,controls}/...). It adds nothing to the kit: everything here is `window.HF` plus a few local icon drawings and a small stylesheet.
 * Promote to kit: the missing icons (HF.icons), HF.optionRow (SelectableOptionRow with tint, disabled, selected border), HF.percentRow (PercentSliderRow),
 * HF.contentUnavailable (ContentUnavailableView), HF.surfaces (swatches on the page and sheet surface with real state).
 *
 * Sources it mirrors (apple/Sources): HassUI/Features/Settings/Household/{HouseholdSettingsPage,AdminSettingsContent}.swift, HassCore/Config/HouseholdSettingsConfig.swift,
 * HassCore/Settings/{HouseholdSettingsController,PresenceOverrideState}.swift, HassDesign/{SettingsSection,PrimaryButton,ScheduleDateFields,FloatingActionBar}.swift.
 */
(function () {
  'use strict';
  var h = Mock.h, K = Mock.components, I = Mock.icon;
  var HF = window.HF = {};

  /* ---------------------------------------------------------------- icons the kit lacks (SymbolMap names) */
  function p(d) { return '<path d="' + d + '"/>'; }
  function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
  function rc(x, y, w, hh, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + hh + '" rx="' + (r || 0) + '"/>'; }
  var bulb = 'M12 3.2a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2v.2h5v-.2c0-.8.4-1.5 1-2A6 6 0 0 0 12 3.2z';
  HF.icons = {
    'arrow.triangle.2.circlepath': p('M20 12a8 8 0 0 0-13.7-5.6L4 8.6M4 4v4.6h4.6M4 12a8 8 0 0 0 13.7 5.6L20 15.4M20 20v-4.6h-4.6'),
    'air.purifier': rc(6, 3.5, 12, 17, 2.6) + p('M9 7.5h6M9 10.5h6') + c(12, 15.5, 2.2) + p('M12 13.3v4.4M9.8 15.5h4.4'),
    'ev.charger': rc(4.5, 4, 9, 16.5, 1.6) + p('M3 20.5h12M13.5 9H16a1.6 1.6 0 0 1 1.6 1.6v5a1.7 1.7 0 0 0 3.4 0V8L18.6 6.2') + p('M9.8 8.2 8 12h3l-1.8 3.8'),
    'carseat.left': p('M8.2 3.6c1.6 0 2.6 1 2.7 2.6l.4 6.8h5.4a2.6 2.6 0 0 1 2.6 2.6v3H8.4L6.8 15.2V6.4c0-1.6.6-2.8 1.4-2.8z') + p('M9 20.4h10.2'),
    'windshield.front.and.heat.waves': p('M3.4 17.6 6.2 7.2A2 2 0 0 1 8.1 5.8h7.8a2 2 0 0 1 1.9 1.4l2.8 10.4z') + p('M9 9.2c1 1 1 2.2 0 3.2M12 9.2c1 1 1 2.2 0 3.2M15 9.2c1 1 1 2.2 0 3.2') + p('M6 20.5h12'),
    'lightbulb.slash': p(bulb) + p('M9.8 19.2h4.4M10.6 21.6h2.8M4 3.6l16 16.8'),
    'pause.circle': c(12, 12, 9) + p('M9.8 8.6v6.8M14.2 8.6v6.8'),
    'basket': p('M3.4 10h17.2l-1.8 9.6H5.2z') + p('M7.8 10l3.2-6M16.2 10 13 4') + p('M9.2 13.4v3.4M12 13.4v3.4M14.8 13.4v3.4'),
    'list.bullet': p('M9 7h11.4M9 12h11.4M9 17h11.4') + c(4.6, 7, .9) + c(4.6, 12, .9) + c(4.6, 17, .9),
    'list.number': p('M10 7h10.4M10 12h10.4M10 17h10.4M3.8 6.2 5.4 5v4.4M3.6 14.6c.2-1 2.7-1 2.7.2 0 1.2-2.7 1.8-2.8 3.2h2.9'),
    'person.crop.circle.badge.exclamationmark': c(11, 12.6, 8.4) + c(11, 10.4, 2.8) + p('M5.8 17.6c1-2 2.8-3 5.2-3s4.2 1 5.2 3') + p('M20 3.6v4.2M20 10v.2'),
    'wifi.exclamationmark': p('M3 9.5a14 14 0 0 1 18 0M6 12.8a9.6 9.6 0 0 1 12 0M9 16a5.2 5.2 0 0 1 6 0') + c(12, 19, .9) + p('M20.6 14v3.2M20.6 19.6v.2'),
    'barcode.viewfinder': p('M3.6 8V5.6A2 2 0 0 1 5.6 3.6H8M16 3.6h2.4a2 2 0 0 1 2 2V8M20.4 16v2.4a2 2 0 0 1-2 2H16M8 20.4H5.6a2 2 0 0 1-2-2V16') + p('M7.6 8.6v6.8M10.2 8.6v6.8M13 8.6v6.8M15.4 8.6v6.8M17 8.6v6.8'),
    'clock': c(12, 12, 9) + p('M12 7v5.2l3.4 2'),
    'slider.horizontal.3': p('M4 7h10M18 7h2M4 12h4M12 12h8M4 17h12M20 17h0') + c(16, 7, 2) + c(10, 12, 2) + c(18, 17, 2),
    'battery.25percent': rc(2.6, 7.4, 17, 9.6, 2.4) + p('M20.6 10.6v3.2') + rc(4.6, 9.4, 4, 5.6, .8),
    'checkmark.circle': c(12, 12, 9) + p('M8 12.4l2.7 2.7L16.2 9.6'),
  };
  Object.keys(HF.icons).forEach(function (k) { if (!Mock.symbols[k]) Mock.symbols[k] = HF.icons[k]; });
  if (!Mock.symbols['speaker.slash.fill']) Mock.symbols['speaker.slash.fill'] = Mock.symbols['speaker.slash'];

  /* ---------------------------------------------------------------- local styles (promote to kit) */
  var css = [
    '.hf-col{max-width:840px;margin:0 auto;display:flex;flex-direction:column;gap:var(--sp-xl,24px);width:100%;box-sizing:border-box;min-width:0}',
    /* kit bug: the atlas furniture rule `.k-wrap h3` (16 px) beats `.ui-settings h3`, so a SettingsSection title never reaches title3 (20 pt, 49 pt at AX5). Promote the fix to kit.css. */
    '.k-wrap .ui-settings h3{font:600 var(--fs-t3)/1.2 var(--font-d,var(--font));margin:0;color:var(--ink,#fff)}',
    /* kit bug: .ui-grid tracks use minmax(max(min*scale, ...), 1fr) with no cap at the container width, so at AX5 (scale 3.1) a 240 pt minimum overflows a 370 pt column. DynamicGridLayout always keeps one column. Promote to kit.css. */
    '.k-wrap .ui-grid{grid-template-columns:repeat(auto-fill,minmax(min(100%,max(calc(var(--min,150px) * var(--sc)),calc((100% - (var(--max,6) - 1) * var(--gap,12px)) / var(--max,6)))),1fr))}',
    '.hf-note{font-size:var(--fs-foot);color:var(--g-secondary-on-wallpaper,rgba(255,255,255,.7));margin:0}',
    '.in-sheet .hf-note{color:var(--ink-sheet-2)}',
    /* ContentUnavailableView look: glyph, bold title, secondary description, actions; page ink on the wallpaper, sheet ink in a sheet */
    '.hf-cuv{--hf-1:#fff;--hf-2:var(--g-secondary-on-wallpaper,rgba(255,255,255,.7));display:flex;flex-direction:column;align-items:center;text-align:center;gap:8px;padding:24px 16px;color:var(--hf-1);min-width:0}',
    '.in-sheet .hf-cuv{--hf-1:var(--ink);--hf-2:var(--ink-sheet-2)}',
    '.hf-cuv .sym{font-size:calc(var(--fs-t1)*1.45);line-height:1;color:var(--hf-2);margin-bottom:4px}.hf-cuv .sym .ui-sym{width:1em;height:1em}',
    '.hf-cuv .ti{font:700 var(--fs-t2)/1.2 var(--font-d,var(--font));margin:0;color:var(--hf-1);overflow-wrap:anywhere}',
    '.hf-cuv .ds{font-size:var(--fs-sub);margin:0;color:var(--hf-2);max-width:34em}',
    '.hf-cuv .act{margin-top:12px;display:flex;justify-content:center;width:100%}.hf-cuv .act .ui-primary{width:auto;min-width:140px}',
    '.hf-cuv .act .plain{font:500 var(--fs-body)/1.2 var(--font);color:var(--ink-action,#409CFF);background:none;border:0;min-height:44px;padding:0 12px}',
    '.hf-cuv.stack{padding:48px 16px 24px;gap:12px}.hf-cuv.stack .ti{font-weight:700}',
    /* SelectableOptionRow additions: tint, selected border, disabled */
    '.hf-opt{transition:box-shadow var(--t-state) var(--ease-state),opacity var(--t-quick) var(--ease-quick)}',
    '.hf-opt.sel{box-shadow:inset 0 0 0 2px var(--hf-tint)}.hf-opt .gl{color:var(--hf-icon);transition:color var(--t-state) var(--ease-state)}',
    '.hf-opt.sel .gl{color:var(--hf-tint)}.hf-opt .ck{color:var(--hf-tint)}.hf-opt[disabled]{opacity:.5;cursor:default}',
    '.hf-opt .ti{font-weight:600}.hf-opt .tx{display:flex;flex-direction:column;gap:4px}',
    /* percent slider row (PercentSliderRow) */
    '.hf-pct{display:flex;flex-direction:column;gap:8px;padding:4px 0}.hf-pct .r{display:flex;justify-content:space-between;align-items:baseline;gap:8px;font-size:var(--fs-body)}',
    '.hf-pct .r .v{font-variant-numeric:tabular-nums;color:var(--ink-sheet-2);flex:none}.hf-pct .r span:first-child{flex:1 1 0;min-width:0;overflow-wrap:anywhere}.hf-pct[aria-disabled="true"]{opacity:.5}',
    '.hf-plain-frame{display:flex;justify-content:center;padding:8px 0}',
    /* Rollout S (2026-10-28): the switches are action tiles (text, disc). The tinted face carries the tint as the glyph colour, so a disc on a filled tile restates its ink (as proposals/tile-rollout-settings-more). */
    '.ui-tile.hf-act.tinted .disc:not(.on){background:rgba(0,0,0,.18);color:#fff}',
    '.ui-tile.hf-act.tinted .disc.on{background:#fff;color:var(--glyph)}',
    '.ui-tile.hf-act.error .disc{background:rgba(0,0,0,.18);color:#fff}',
    '.ui-tile.hf-act.off .disc{background:rgba(255,255,255,.16);color:var(--tile-glyph)}',
    '.ui-tile.unavail .disc{opacity:.5}',
  ].join('\n');
  var st = document.createElement('style'); st.id = 'hf-style'; st.textContent = css; document.head.appendChild(st);

  /* ---------------------------------------------------------------- copy and fixtures (HouseholdSettingsConfig.swift, PresenceOverrideState.swift) */
  var GREEN = '#43A047', CONTROL = '#4B7ED2';
  HF.GREEN = GREEN; HF.CONTROL = CONTROL;
  var COPY = {
    security: { title: 'Security Controls', p: ['Enables automatic locking of the front door. Turn this off temporarily when contractors are over or people are frequently entering and leaving the home.'] },
    power: { title: 'Living Room Power Recovery', p: ['If the living room switch loses power and comes back with the relay off, run this to temporarily couple the top paddle, unlock the relay, turn power back on, relock it, and return the paddle to decoupled mode.'] },
    relay: { title: 'Relay Control Mode', p: ['Couples every smart-bulb wall switch to its own relay, so the paddles keep working even if Home Assistant, Zigbee2MQTT, or the host is down. This turns on automatically while Vacation Mode is active, so house-sitters always have a way to get light.', 'While this is on, turning lights off at the wall cuts power to those bulbs, so presence-based lighting can\'t bring them back until the paddle is switched on again.'] },
    presence: { title: 'Presence-Based Light Overrides', p: ['Choose whether each room\'s presence lighting is Enabled, Disabled, Paused, or Quieted. Paused stays fail-dark until resumed; Quieted rearms after the room clears.'] },
    show: { title: 'Show Specific Controls', p: ['Shows the outdoor faucets in our Home Assistant pages. Useful to disable during the winter, when we aren\'t using them.'] },
    reset: { title: 'Automatic Presence Setting Overrides', p: ['Sometimes, we disable automatic presence-based lighting in rooms that we\'d otherwise want to wake up and have that presence-based lighting active.', 'If a toggle here is enabled, it means that in the morning, before we usually wake up, if the room has been cleared for a sufficient amount of time during the night, we\'ll re-enable presence-based lighting in that room.'] },
    aqi: { title: 'High AQI Mode', p: ['Toggling High AQI Mode sets all air purifiers in the house to their highest setting to ward off smoke and other inhalation hazards.'] },
    guests: { title: 'Guest Controls', p: ['When guests stay over, toggle these controls on based on the rooms they\'re staying in to disable automations (like automatic vacuuming in the studio) and ensure that rooms are tracked for temperature monitoring and vent control.'] },
    warning: 'Guest Room guest mode is active. Turning off Relay Control Mode keeps the Guest Room on direct wall control and Guest Bathroom presence lighting off. Turn off Guest Room in Guest Controls to restore normal behavior.',
  };
  HF.COPY = COPY;
  HF.PAGES = {
    admin: { title: 'Admin', row: 'Admin Controls', sub: 'Presence-Based Toggles, Automation Overrides, and More', symbol: 'person.badge.shield.checkmark' },
    'special-device-modes': { title: 'Special Device Modes', row: 'Special Device Modes', sub: 'Allows enabling special device modes, such as High AQI Mode.', symbol: 'slider.vertical.3' },
    guests: { title: 'Guest Controls', row: 'Guest Controls', sub: 'Toggle automations when guests stay over.', symbol: 'person.2' },
    'mach-e': { title: 'Car', row: 'Car', sub: 'Controls for the car.', symbol: 'car.side' },
  };
  var MODES = {
    enabled: { label: 'Enable Presence-Based Lighting', summary: 'Enabled', detail: 'Presence and occupancy can control the lights.', icon: 'lightbulb', tint: '#43A047' },
    off: { label: 'Disable Presence-Based Lighting', summary: 'Disabled', detail: 'Presence-Based Lighting is disabled for this room.', icon: 'lightbulb.slash', tint: '#546E7A' },
    paused: { label: 'Paused', summary: 'Paused', detail: 'Lights stay in their current state until explicitly resumed.', icon: 'pause.circle', tint: '#E69A25' },
    quieted: { label: 'Quieted', summary: 'Quieted', detail: 'Stay dark, then rearm after the room clears.', icon: 'speaker.slash.fill', tint: '#755BB4' },
    unavailable: { label: 'Unavailable', summary: 'Unavailable', detail: 'Home Assistant state is unavailable.', icon: 'exclamationmark.circle', tint: '#546E7A' },
  };
  HF.MODES = MODES;
  HF.CHOICES = ['enabled', 'off', 'paused', 'quieted'];
  /* The 14 rooms in the web's order, with a fixture mode each (fixture data, not the house). */
  HF.ROOMS = [
    ['Living Room', 'enabled'], ['Kitchen', 'enabled'], ['Hallway', 'enabled'], ['Gym', 'quieted'], ['Guest Bathroom', 'off'], ['Guest Room', 'paused'], ['Office', 'enabled'],
    ['Bedroom 1', 'paused'], ['Bathroom 1', 'enabled'], ['Dining Room', 'enabled'], ['Media Room', 'off'], ['Downstairs Hallway', 'enabled'], ['Studio', 'unavailable'], ['Upper Deck', 'enabled'],
  ];

  /* ---------------------------------------------------------------- tiles */
  function discSymbol(node, on, o) { return o && o.lock ? (on ? 'lock.fill' : 'lock.open') : 'power'; }
  function setTile(node, on, title, symbol, o) {
    node.classList.toggle('tinted', on); node.classList.toggle('off', !on); node.dataset.face = on ? 'tinted' : 'off';
    node.setAttribute('aria-pressed', on ? 'true' : 'false');
    var g = node.querySelector('.glyph'); if (g) g.innerHTML = I(symbol, { fill: on });
    var s = node.querySelector('.st'); if (s) s.textContent = o && o.guest ? (on ? 'Guests staying' : 'No guests') : (on ? 'On' : 'Off');
    var d = node.querySelector('.disc');
    if (d) { d.classList.toggle('on', on); var name = discSymbol(node, on, o); d.innerHTML = I(name, { fill: name !== 'power' }); d.setAttribute('aria-label', (on ? 'Turn Off ' : 'Turn On ') + title); }
    node.setAttribute('aria-label', title + ', ' + (o && o.guest ? (on ? 'Guests staying' : 'No guests') : (on ? 'On' : 'Off')));
  }
  /** A household switch (HouseholdActionTile, rollout S): an action tile, text and a power disc (a lock for Front Door Auto-Lock), body and disc both flip it. `kind: 'command'` is the
   *  momentary power recovery tile (bolt disc); `navigate` is an opener. o: {title, symbol, on, unavailable, lock, guest, disc, onflip, live} */
  HF.tile = function (o) {
    var kind = o.kind || 'toggle', un = !!o.unavailable, on = !un && !!o.on;
    if (kind === 'navigate') return K.GlassTile({ title: o.title, symbol: o.symbol, tint: o.tint || GREEN, isActive: true, isUnavailable: un, kind: 'navigate' });
    var props;
    if (kind === 'command') {
      props = { title: o.title, symbol: o.symbol, tint: o.tint || GREEN, isActive: true, kind: 'command', behavior: 'perform',
        actions: [{ id: 'power_recovery', symbol: 'bolt.fill', label: 'Run power recovery' }] };
    } else {
      props = { title: o.title, symbol: o.symbol, isActive: on, isUnavailable: un, kind: 'toggle', behavior: 'perform',
        subtitle: un ? 'Unavailable' : (o.guest ? (on ? 'Guests staying' : 'No guests') : (on ? 'On' : 'Off')),
        actions: [{ id: 'power', symbol: discSymbol(null, on, o), label: (on ? 'Turn Off ' : 'Turn On ') + o.title, on: on, dim: un }] };
      if (o.guest) props.family = 'occupancy'; else props.tint = o.tint || GREEN;
    }
    if (o.subtitle !== undefined) props.subtitle = o.subtitle;
    var node = K.GlassTile(props); node.dataset.sym = o.symbol; node.classList.add('hf-act'); node._hf = o;
    if (kind === 'toggle' && !un && o.live !== false) {
      node.addEventListener('click', function () { setTile(node, !node.classList.contains('tinted'), o.title, o.symbol, o); if (o.onflip) o.onflip(node.classList.contains('tinted')); });
    }
    return node;
  };
  HF.setTile = setTile;
  /** Read-only state tile (GlassStateTile): the tile face with no button role and no hit testing. */
  HF.stateTile = function (o) {
    var un = !!o.unavailable;
    return K.GlassTile({ title: o.title, subtitle: un ? 'Unavailable' : o.subtitle, symbol: o.symbol, tint: CONTROL, isActive: !un && !!o.active, isUnavailable: un, kind: 'state' });
  };
  /** Car Doors (MachEDoorsTile, rollout S item 25): an action tile in the Settings blue with the lock disc, the Security page tile's states. state: locked | unlocking | unlocked | jammed. */
  HF.doorsTile = function (o) {
    o = o || {}; var un = !!o.unavailable, st = o.state || 'locked';
    var m = { locked: ['Locked', false, 'lock.fill', 'Unlock'], unlocking: ['Unlocking', true, 'lock.open', 'Lock'], unlocked: ['Unlocked', true, 'lock.open', 'Lock'],
      jammed: ['Jammed', true, 'lock.trianglebadge.exclamationmark', 'Lock'] }[st];
    var node = K.GlassTile({ title: 'Doors', subtitle: un ? 'Unavailable' : m[0], symbol: 'lock', tint: CONTROL, isActive: !un && st !== 'locked', isUnavailable: un, isError: !un && st === 'jammed',
      kind: 'toggle', behavior: 'perform', actions: [{ id: 'lock', symbol: un ? 'lock.fill' : m[2], label: m[3] + ' Doors', on: !un && m[1] && st !== 'jammed', dim: un, busy: st === 'unlocking' }] });
    node.classList.add('hf-act'); return node;
  };
  /** HouseholdTileGrid: DynamicGridLayout(minCellWidth: min, maxColumns: max). */
  HF.grid = function (items, min, max) { return K.TileGrid({ items: items, min: min || 200, max: max || 6 }); };

  function section(key, content) { return K.SettingsSection({ title: COPY[key].title, paragraphs: COPY[key].p, content: content }); }
  HF.section = section;

  /* ---------------------------------------------------------------- page bodies */
  /** o: {on:{door,relay,faucets,xmas}, unavailable, guestRoomOn, live} */
  HF.adminBody = function (o) {
    o = o || {}; var on = Object.assign({ door: true, relay: false, faucets: true, xmas: false }, o.on), un = !!o.unavailable;
    var warn = K.InlineAlert({ message: COPY.warning });
    warn.id = 'hf-relay-warning';
    function warnVisible(relayOn) { warn.hidden = !(relayOn && o.guestRoomOn && !un); }
    var relayTile = HF.tile({ title: 'Relay Control Mode', symbol: 'switch.2', on: on.relay, unavailable: un, onflip: function (v) { warnVisible(v); } });
    warnVisible(on.relay);
    return [
      section('security', HF.grid([HF.tile({ title: 'Front Door Auto-Lock', symbol: 'lock.shield', on: on.door, unavailable: un, lock: true })], 240, 2)),
      section('power', HF.grid([HF.tile({ title: 'Attempt to turn power back on', symbol: 'bolt.fill', kind: 'command' })], 240, 2)),
      section('relay', [HF.grid([relayTile], 240, 2), warn]),
      section('presence', HF.grid([HF.tile({ title: 'Open Presence-Based Overrides', symbol: 'lightbulb.max', kind: 'navigate' })], 240, 2)),
      section('show', HF.grid([HF.tile({ title: 'Outdoor Faucets', symbol: 'drop', on: on.faucets, unavailable: un }), HF.tile({ title: 'Holiday Lights', symbol: 'sparkles', on: on.xmas, unavailable: un })], 200, 2)),
      section('reset', HF.grid([HF.tile({ title: 'Open Presence-Based Auto-Reset Configuration', symbol: 'arrow.triangle.2.circlepath', kind: 'navigate' })], 240, 2)),
    ];
  };
  /** o: {aqi:boolean, unavailable} */
  HF.specialBody = function (o) {
    o = o || {};
    return [section('aqi', HF.grid([HF.tile({ title: 'High AQI Mode', symbol: 'air.purifier', on: !!o.aqi, unavailable: !!o.unavailable })], 240, 2))];
  };
  /** o: {rooms:{guest,music,theater}, unavailable} */
  HF.guestsBody = function (o) {
    o = o || {}; var r = Object.assign({ guest: true, music: false, theater: false }, o.rooms), un = !!o.unavailable;
    return [section('guests', HF.grid([
      HF.tile({ title: 'Guest Room', symbol: 'bed.double', on: r.guest, unavailable: un, guest: true }),
      HF.tile({ title: 'Studio', symbol: 'guitars', on: r.music, unavailable: un, guest: true }),
      HF.tile({ title: 'Media Room', symbol: 'videoprojector', on: r.theater, unavailable: un, guest: true })], 150, 6))];
  };
  /** Car has no SettingsSection: a title3 header over the tiles, 8 pt apart (MachEContent). Doors is the one action tile. o: {unavailable, long, doors} */
  HF.machEBody = function (o) {
    o = o || {}; var un = !!o.unavailable;
    var tiles = [
      { title: 'Charge Status', symbol: 'ev.charger', subtitle: o.long ? 'Plugged In, Scheduled Charging Waiting For Off-Peak Window' : 'Plugged In', active: false },
      { title: 'Doors', symbol: 'lock', subtitle: 'Locked', active: false },
      { title: 'Driver\'s Seat', symbol: 'carseat.left', subtitle: 'Off', active: false },
      { title: 'Passenger Seat', symbol: 'carseat.left', subtitle: 'Heat', active: true },
      { title: 'Climate', symbol: 'windshield.front.and.heat.waves', subtitle: '72', active: false },
    ];
    var sec = h('section.ui-settings', { style: { gap: '8px' } }, h('h3', { role: 'heading', 'aria-level': '2' }, 'Charge Status'),
      HF.grid(tiles.map(function (t) { return t.title === 'Doors' ? HF.doorsTile({ state: o.doors, unavailable: un }) : HF.stateTile({ title: t.title, symbol: t.symbol, subtitle: t.subtitle, active: t.active, unavailable: un }); }), 150, 4));
    return [sec];
  };
  HF.bodies = { admin: HF.adminBody, 'special-device-modes': HF.specialBody, guests: HF.guestsBody, 'mach-e': HF.machEBody };

  /** The page column: ScrollView content, readable width 840 pt, 24 pt between sections. */
  HF.col = function (kids) { return h('div.hf-col', kids); };

  /** A household page pushed from the Settings tab (a NavigationStack push: Back, Quick Links, Profile; the Settings tab stays selected). */
  HF.page = function (ctx, key, o) {
    o = o || {};
    return Mock.page(ctx, { title: HF.PAGES[key].title, section: 'settings', back: 'Settings', connection: o.connection, badge: o.badge === undefined ? 3 : o.badge, choresBadge: 2,
      body: [HF.col(HF.bodies[key](o))] });
  };

  /** A trimmed Settings list (the page the household topics push from; the full list belongs to the settings-account batch). */
  HF.settingsList = function (ctx, o) {
    o = o || {};
    var rows = Object.keys(HF.PAGES).map(function (k) { return { title: HF.PAGES[k].row, subtitle: HF.PAGES[k].sub, symbol: HF.PAGES[k].symbol, chevron: true }; });
    var body = [h('p.hf-note', { style: { margin: '0 4px' } }, 'Household'), K.ModuleList({ rows: rows, density: 'thin' })];
    return Mock.page(ctx, { title: 'Settings', section: 'settings', badge: 3, choresBadge: 2, connection: o.connection, body: [HF.col(body)] });
  };

  /* ---------------------------------------------------------------- sheets */
  function room(name, mode, onclick) {
    var m = MODES[mode];
    var t = K.GlassTile({ title: name, subtitle: m.summary, symbol: 'lightbulb', tint: m.tint, isActive: mode !== 'unavailable', kind: 'navigate' });
    if (onclick) t.addEventListener('click', onclick);
    return t;
  }
  /** The room grid (HouseholdTileGrid min 150, max 4, 16 pt padding). o: {unavailable (every room), modes:{name:mode}, onopen} */
  HF.presenceGrid = function (o) {
    o = o || {};
    var items = HF.ROOMS.map(function (r) { return room(r[0], o.unavailable ? 'unavailable' : ((o.modes && o.modes[r[0]]) || r[1]), o.onopen ? function () { o.onopen(r[0]); } : null); });
    return h('div', { style: { padding: '8px 0 0' } }, HF.grid(items, 150, 4));
  };
  /** SelectableOptionRow with the app's tint, selected border and disabled dimming. */
  HF.optionRow = function (modeKey, selected, disabled) {
    var m = MODES[modeKey];
    var n = K.SelectableOptionRow({ icon: m.icon, label: m.label, description: m.detail, selected: selected });
    n.classList.add('hf-opt'); n.style.setProperty('--hf-tint', m.tint); n.style.setProperty('--hf-icon', 'var(--ink-sheet-2)');
    var ic = n.querySelector('.ui-sym'); if (ic && ic.parentNode) ic.parentNode.classList.add('gl');
    n.setAttribute('aria-label', m.label); n.setAttribute('aria-description', m.detail);
    if (disabled) n.disabled = true;
    return n;
  };
  /** A room's four modes (DynamicGridLayout min 300, max 2) and, while unavailable, the explanation below. */
  HF.presenceDetail = function (modeKey, o) {
    o = o || {}; var un = modeKey === 'unavailable';
    var rows = HF.CHOICES.map(function (k) { return HF.optionRow(k, modeKey === k, un); });
    if (!un && o.live !== false) rows.forEach(function (r, i) {
      r.addEventListener('click', function () { rows.forEach(function (x, j) { x.classList.toggle('sel', i === j); x.setAttribute('aria-pressed', i === j ? 'true' : 'false'); x.querySelector('.ck').style.opacity = i === j ? 1 : 0; }); });
    });
    return h('div', { style: { padding: '8px 0 0' } }, K.TileGrid({ items: rows, min: 300, max: 2, equal: false, fill: 'none' /* option rows keep one size (duo-widths rule 4) */ }), un ? h('p.hf-note', { style: { margin: '12px 0 0' } }, MODES.unavailable.detail) : null);
  };
  /** The auto-reset toggles, one per room. o: {on: n rooms on, unavailable} */
  HF.autoResetGrid = function (o) {
    o = o || {}; var on = { 'Living Room': 1, 'Kitchen': 1, 'Bedroom 1': 1, 'Bathroom 1': 1, 'Office': 1, 'Hallway': 1 };
    var tiles = HF.ROOMS.map(function (r) { return HF.tile({ title: r[0], symbol: 'arrow.triangle.2.circlepath', on: !!on[r[0]], unavailable: !!o.unavailable || r[0] === 'Studio' && o.oneMissing }); });
    return h('div', { style: { padding: '8px 0 0' } }, HF.grid(tiles, 150, 4));
  };

  HF.presenter = function (ctx, o) { o = o || {}; return HF.page(ctx, 'admin', { connection: o.connection, on: { door: true, relay: false, faucets: true, xmas: false } }); };
  HF.presenceSheet = function (ctx, o) {
    o = o || {};
    return Mock.sheet(ctx, { title: 'Presence-Based Overrides', detent: 'large', size: 'page', trailing: 'close', content: HF.presenceGrid(o), presenter: o.noPresenter ? null : HF.presenter(ctx, o), alert: null });
  };
  HF.detailSheet = function (ctx, o) {
    o = o || {};
    return Mock.sheet(ctx, { title: o.room || 'Kitchen', detent: 'large', size: 'page', leading: 'back', trailing: 'close', content: HF.presenceDetail(o.mode || 'enabled', o), presenter: o.noPresenter ? null : HF.presenter(ctx, o) });
  };
  HF.autoResetSheet = function (ctx, o) {
    o = o || {};
    return Mock.sheet(ctx, { title: 'Presence Auto-Reset', detent: o.detent || 'fitted', size: 'page', trailing: 'close', content: HF.autoResetGrid(o), presenter: o.noPresenter ? null : HF.presenter(ctx, o) });
  };

  /* ---------------------------------------------------------------- swatch surfaces (component mockups) */
  /** Draw `items` ([{label, node(ctx)}]) on the page surface (dark, over the gradient) and the sheet surface (follows the appearance control), like Mock.componentConfig. */
  HF.surfaces = function (ctx, items, o) {
    o = o || {}; var surf = o.surfaces || ['page', 'sheet'], out = h('div', { style: { display: 'flex', flexDirection: 'column', gap: '18px' } });
    surf.forEach(function (s) {
      var grid = h('div.k-swatch-grid');
      items.forEach(function (it) {
        if (it.only && it.only !== s) return;
        var box = h('div.k-swatch.' + (s === 'page' ? 'page.g-dark' : 'sheet.in-sheet.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light')), { style: { flex: it.wide ? '1 1 100%' : '1 1 ' + (o.basis || 280) + 'px', maxWidth: '100%', minWidth: 0 } },
          h('div.k-cap', s + ' · ' + it.label), h('div.in', it.node(ctx)), it.note ? h('div', { style: { font: '12px var(--font)', opacity: .7, marginTop: '8px' } }, it.note) : null);
        grid.appendChild(box);
      });
      out.appendChild(grid);
    });
    return out;
  };

  /* ---------------------------------------------------------------- ContentUnavailableView and the plain-stack variants */
  /** o: {symbol, title, description?, action?:{title, plain?}, stack?, label} */
  HF.contentUnavailable = function (o) {
    var n = h('div.hf-cuv' + (o.stack ? '.stack' : ''), { role: 'group', 'aria-label': o.title },
      h('div.sym', { html: I(o.symbol) }), h('h3.ti', { role: 'heading', 'aria-level': '2' }, o.title), o.description ? h('p.ds', o.description) : null,
      o.action ? h('div.act', o.action.plain ? h('button.plain', { type: 'button' }, o.action.title) : K.PrimaryButton({ title: o.action.title, inline: true })) : null);
    return n;
  };

  /** PercentSliderRow: label and value, then a 0 to 100 slider in steps of 5, one adjustable element for VoiceOver. */
  HF.percentRow = function (label, value, o) {
    o = o || {}; var v = value, dis = !!o.disabled;
    var row = h('div.hf-pct', { role: 'slider', tabindex: dis ? -1 : 0, 'aria-label': label, 'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': v, 'aria-valuetext': v + ' percent', 'aria-disabled': dis ? 'true' : 'false' },
      h('div.r', h('span', label), h('span.v', v + '%')), K.Slider({ value: v / 100, label: label }));
    return row;
  };

  /* ---------------------------------------------------------------- shared review and a11y text */
  HF.a11yTile = [
    { rule: 'Toggle tile', note: 'One button named "<title>, <On|Off>" with the toggle trait (selected when on) and the identifier household.tile.<entity id>; the glyph is decorative. State is the words On and Off and the filled glyph and tinted rim, not green alone.' },
    { rule: 'Unavailable', note: 'The tile reads "<title>, Unavailable", is dimmed and does nothing when tapped (flip is ignored while the entity is unavailable).' },
    { rule: '44 pt targets', note: 'Tiles are at least 72 pt tall in a row layout; at accessibility sizes they stack (glyph above text) and grow with the text.' },
  ];
  HF.reducedMotionNote = 'Reduce Motion shortens the colour cross-fade to 0.2 s; nothing slides or springs on these pages.';

  /* ---------------------------------------------------------------- shared state / motion / transition sets for the four pages */
  /** The states every household page has. `o.base` = options for the default render; `o.long` = options for the long-text state; `o.extra` = {key: {title, note, opts}}. */
  HF.pageStates = function (key, o) {
    o = o || {};
    function r(opts) { return function (ctx) { return HF.page(ctx, key, Object.assign({}, o.base, opts)); }; }
    var s = {
      'default': { title: o.defaultTitle || 'Signed in, house online', render: r() },
    };
    Object.keys(o.extra || {}).forEach(function (k) { var e = o.extra[k]; s[k] = { title: e.title, note: e.note, override: e.override, render: r(e.opts) }; });
    s.error = { title: 'Entities unavailable', note: o.errorNote || 'every tile reads Unavailable, dims and ignores taps (command and opener tiles are not entity-bound and stay live)', render: r({ unavailable: true }) };
    s.offline = { title: 'No network', note: 'values stay as last known; offline chip under the header and the cloud badge on Profile; a tap still sends and reverts after 2 s if nothing confirms', render: r({ connection: 'offline' }) };
    s.reconnecting = { title: 'Connection down 2 s+ (arc)', note: 'the arc left of Quick Links', render: r({ connection: 'reconnecting' }) };
    s['long-text'] = { title: o.longTitle || 'Largest copy at xxxLarge', note: o.longNote || 'paragraphs and tile titles wrap; nothing truncates', override: { ts: 'xxxl' }, render: r(o.long) };
    s.ax5 = { title: 'Accessibility 5 text size', override: { ts: 'ax5' }, render: r(o.ax5 || o.long) };
    return s;
  };
  function firstToggle(stage) { return stage.querySelector('.ui-tile[aria-pressed]'); }
  HF.pageMotion = function (key, toggles) {
    var m = [];
    if (toggles) {
      m.push({ id: 'tile-colour', what: 'A toggle tile switches: the face fills in the tint, the glyph fills, the subtitle changes from Off to On', token: 'state 0.6 s ease-in-out, colour only (0.2 s reduced)', state: 'default',
        source: 'HassDesign/GlassTile.swift stateColorTransition("GlassTile"); HouseholdActionTile; design/motion.md section 6', reduce: 'still cross-fades (colour is not motion), shortened to 0.2 s',
        play: function (stage) { var t = firstToggle(stage); if (!t) return Promise.resolve(); var title = t.getAttribute('aria-label').split(',')[0], sym = t.dataset.symbol; var on = t.classList.contains('tinted');
          HF.flipByTitle(t, title); return Mock.sleep(Mock.anim.ms.state() + 500).then(function () { HF.flipByTitle(t, title); return Mock.sleep(Mock.anim.ms.state() + 300); }); } });
      m.push({ id: 'optimistic-revert', what: 'A tap shows the new value at once; if Home Assistant has not confirmed after 2 s the tile gives way and reverts', token: 'optimistic window 2 s (web DEFAULT_OPTIMISTIC_REVERT_MS), then the same state cross-fade back',
        state: 'default', source: 'HassCore/Settings/HouseholdSettingsController.swift revertAfter; OptimisticOverlay', reduce: 'same timing; the revert cross-fades at 0.2 s',
        play: function (stage) { var t = firstToggle(stage); if (!t) return Promise.resolve(); var title = t.getAttribute('aria-label').split(',')[0];
          HF.flipByTitle(t, title); return Mock.sleep(2000).then(function () { HF.flipByTitle(t, title); return Mock.sleep(Mock.anim.ms.state() + 300); }); } });
    } else {
      m.push({ id: 'value-colour', what: 'A read-only tile follows the car: Passenger Seat goes from Heat (active, tinted) to Off, or the reverse', token: 'state 0.6 s ease-in-out, colour only (0.2 s reduced)', state: 'default',
        source: 'HassDesign/GlassTile.swift via GlassStateTile; MachEContent; design/motion.md section 6 (live value change)', reduce: 'still cross-fades, shortened to 0.2 s',
        play: function (stage) {
          var t = stage.querySelector('.ui-tile[aria-label^="Passenger Seat"]'); if (!t) return Promise.resolve();
          var on = t.classList.contains('tinted'); t.classList.toggle('tinted', !on); t.classList.toggle('off', on); t.querySelector('.st').textContent = on ? 'Off' : 'Heat';
          return Mock.sleep(Mock.anim.ms.state() + 500).then(function () { t.classList.toggle('tinted', on); t.classList.toggle('off', !on); t.querySelector('.st').textContent = on ? 'Heat' : 'Off'; return Mock.sleep(Mock.anim.ms.state() + 300); }); } });
    }
    return m;
  };
  /** Flip a tile built by HF.tile without a click (used by Play). */
  HF.flipByTitle = function (node, title) { setTile(node, !node.classList.contains('tinted'), title, node.dataset.sym || 'lightbulb', node._hf); };
  /** Push demo: the Settings list on the stage, the household page slides in over it (system push; Reduce Motion cross-fades). */
  HF.pushDemo = function (stage, hold) {
    var ctx = Mock.current, pg = stage.querySelector('.ui-page'); if (!pg) return Promise.resolve();
    var s = HF.settingsList(ctx); pg.parentNode.insertBefore(s, pg);
    var p = Mock.anim.push(s, pg);
    return p.then(function () { return Mock.sleep(hold || 800); }).then(function () { return Mock.anim.push(pg, s, { back: true }); }).then(function () { s.remove(); Mock.anim.reset(stage); });
  };
  /** Push inside the sheet's own NavigationStack: the grid shifts left and dims, the room's detail slides in (Reduce Motion cross-fades); then back. */
  HF.pushInSheet = function (stage, roomName, mode, o) {
    o = o || {};
    var panel = stage.querySelector('.ui-sheet'), a = panel && panel.querySelector('.ui-modal'); if (!a) return Promise.resolve();
    var b = K.HassModal({ title: roomName, leading: 'back', trailing: 'close', content: HF.presenceDetail(mode || 'enabled') });
    b.style.position = 'absolute'; b.style.inset = '0'; b.style.background = 'var(--sheet-ground)'; b.style.zIndex = 6; b.style.display = 'flex'; b.style.flexDirection = 'column';
    a.style.position = 'relative'; panel.appendChild(b);
    return Mock.anim.push(a, b).then(function () { return Mock.sleep(o.hold || 900); }).then(function () { if (o.stay) return null; return Mock.anim.push(b, a, { back: true }).then(function () { b.remove(); Mock.anim.reset(panel); }); });
  };
  /** The reverse view for the detail mockup: the sheet shows a room's modes; the grid is laid under it and the modes push in over it, then pop. */
  HF.pushFromGrid = function (stage, o) {
    o = o || {};
    var panel = stage.querySelector('.ui-sheet'), d = panel && panel.querySelector('.ui-modal'); if (!d) return Promise.resolve();
    var g = K.HassModal({ title: 'Presence-Based Overrides', trailing: 'close', content: HF.presenceGrid() });
    g.style.position = 'absolute'; g.style.inset = '0'; g.style.background = 'var(--sheet-ground)'; g.style.display = 'flex'; g.style.flexDirection = 'column';
    d.style.position = 'relative'; d.style.background = 'var(--sheet-ground)'; d.style.zIndex = 6; d.style.height = '100%';
    panel.insertBefore(g, d);
    return Mock.anim.push(g, d).then(function () { return Mock.sleep(o.hold || 900); }).then(function () { return Mock.anim.push(d, g, { back: true }); }).then(function () { g.remove(); Mock.anim.reset(panel); });
  };
  /** A room tile changes mode: the rim, glyph and subtitle cross-fade to the new tint (`state`). */
  HF.retint = function (tile, mode) {
    var m = MODES[mode]; tile.style.setProperty('--glyph', m.tint); tile.style.setProperty('--glyph-light', m.tint);
    tile.querySelector('.st').textContent = m.summary;
    tile.setAttribute('aria-label', tile.querySelector('.ti').textContent + ', ' + m.summary);
  };
  HF.pageTransitions = function (key, extra) {
    var t = [{ from: 'Settings', to: HF.PAGES[key].row, kind: 'push', state: 'default', note: 'The row is a value on the Settings tab\'s own path (navigationDestination(for: HouseholdSettingsPage)): the system push, with Back to Settings and the interactive edge swipe. The page\'s content is there in its first frame, no entrance animation (motion.md section 4.2). Reduce Motion cross-fades.',
      play: function (stage) { return HF.pushDemo(stage, 900); } }];
    return t.concat(extra || []);
  };
})();
