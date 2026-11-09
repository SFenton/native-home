import Foundation

/// Titles, sections, subtitles and colors for the room overview sheets, as the web computes them.
public enum RoomOverview {
    /// Reads an entity's current state.
    public typealias Read = (String) -> EntityState?

    // MARK: Data

    /// The rooms an overview lists, in web order. Air Quality lists ``airQualityRooms`` instead.
    public static func groups(_ kind: RoomOverviewKind) -> [RoomGroup] {
        switch kind {
        case .lights: RoomGroups.allLights
        case .climate: RoomGroups.allClimate
        case .occupancy: RoomGroups.allOccupancy
        case .contacts: RoomGroups.allContacts
        case .airQuality: []
        }
    }

    /// `AIR_QUALITY_ROOMS` (`atAGlance.ts:178`): the server's document.
    public static var airQualityRooms: [AirQualityRoom] {
        HouseConfigSource.active.read { $0.rooms.airQualityRooms } ?? []
    }


    /// Every light the Lights sheet controls, once each (web `ROOM_LIGHT_ENTITY_IDS`).
    public static var lightEntityIds: [String] { unique(RoomGroups.allLights.flatMap { $0.items.map(\.entityId) }) }
    /// Every contact sensor, once each (web `ROOM_CONTACT_ENTITY_IDS`).
    public static var contactEntityIds: [String] { unique(RoomGroups.allContacts.flatMap { $0.items.map(\.entityId) }) }

    // MARK: Sheet

    /// The sheet's title: "Lights (3 On)" or "Lights (All Off)" for Lights (web `lightsSheetTitle`), else the chip's name.
    public static func sheetTitle(_ kind: RoomOverviewKind, read: Read) -> String {
        switch kind {
        case .lights: "Lights (\(lightCountSummary(activeLightCount(read: read))))"
        case .climate: "Climate"
        case .occupancy: "Occupancy"
        case .contacts: "Contact Sensors"
        case .airQuality: "Air Quality"
        }
    }

    /// The sheet's name, without the web's count (direction G puts the count in ``sheetSubtitle(_:read:)``).
    public static func sheetName(_ kind: RoomOverviewKind) -> String {
        kind == .lights ? "Lights" : sheetTitle(kind) { _ in nil }
    }

    /// The one-line state under the sheet's name (`.agents/design/direction-g.md`, Sheets; mockup n2): "3 of 12 On",
    /// "2 Rooms Occupied", "2 Open". Nil where the sheet's tiles already carry the figures (Climate, Air Quality).
    public static func sheetSubtitle(_ kind: RoomOverviewKind, read: Read) -> String? {
        switch kind {
        case .lights:
            let on = activeLightCount(read: read)
            return on == 0 ? "All Off" : "\(on) of \(lightEntityIds.count) On"
        case .occupancy:
            let rooms = groups(.occupancy).count(where: { occupiedCount($0, read: read) > 0 })
            return rooms == 0 ? "All Clear" : "\(rooms) \(rooms == 1 ? "Room" : "Rooms") Occupied"
        case .contacts:
            return contactCountSummary(openContactCount(read: read))
        case .climate, .airQuality:
            return nil
        }
    }

    /// The overview's sections: Lights and Occupancy split rooms by state (active first, empty sections dropped);
    /// the rest list every room under "Rooms" (web `GroupedRoomOverview`, `RoomsHeader`).
    public static func sections(_ kind: RoomOverviewKind, read: Read) -> [RoomOverviewSection] {
        let all = groups(kind)
        let titles: (active: String, inactive: String)
        switch kind {
        case .lights: titles = ("Lights On", "Lights Off")
        case .occupancy: titles = ("Occupied", "Clear")
        case .climate, .contacts: return [RoomOverviewSection(title: "Rooms", groups: all)]
        case .airQuality: return [RoomOverviewSection(title: "Rooms", groups: [])]
        }
        let active = all.filter { isActive(kind, $0, read: read) }
        let inactive = all.filter { !isActive(kind, $0, read: read) }
        return [RoomOverviewSection(title: titles.active, groups: active), RoomOverviewSection(title: titles.inactive, groups: inactive)]
            .filter { !$0.groups.isEmpty }
    }

    // MARK: Room cards

    /// Whether a room card shows as active (colored rather than muted).
    public static func isActive(_ kind: RoomOverviewKind, _ group: RoomGroup, read: Read) -> Bool {
        switch kind {
        case .lights:
            let groupOn = group.entityId.map { RoomFormat.isActive(read($0)) } ?? false
            return groupOn || lightActiveCount(group, read: read) > 0
        case .occupancy: return occupiedCount(group, read: read) > 0
        case .contacts: return openCount(group, read: read) > 0
        case .climate, .airQuality: return true
        }
    }

    /// How many of a room's sensors have stopped answering. A dead contact or presence sensor otherwise reads as closed
    /// or empty, which misstates a security-relevant room.
    public static func unavailableCount(_ group: RoomGroup, read: Read) -> Int {
        group.items.filter { read($0.entityId)?.isUnavailable == true }.count
    }

    /// What VoiceOver reads as a room card's value: the subtitle, plus how many sensors are unavailable.
    public static func spokenSubtitle(_ kind: RoomOverviewKind, _ group: RoomGroup, read: Read) -> String {
        let subtitle = cardSubtitle(kind, group, read: read)
        let offline = unavailableCount(group, read: read)
        guard offline > 0, subtitle != "Unavailable" else { return subtitle }
        let note = "\(PluralCopy.count(offline, "sensor")) unavailable"
        return subtitle.isEmpty ? note : "\(subtitle), \(note)"
    }

    /// The state line a room card draws (owner, 2026-10-30): the contact sensors sheet drops "Door Closed" / "Window Open" (the glyph and
    /// fill already say it, and VoiceOver still reads ``spokenSubtitle(_:_:read:)``), but keeps "Unavailable", which the glyph cannot
    /// say. Every other sheet draws ``cardSubtitle(_:_:read:)``.
    public static func tileSubtitle(_ kind: RoomOverviewKind, _ group: RoomGroup, read: Read) -> String {
        let subtitle = cardSubtitle(kind, group, read: read)
        return kind == .contacts && subtitle != "Unavailable" ? "" : subtitle
    }

    /// A room card's subtitle in the overview.
    public static func cardSubtitle(_ kind: RoomOverviewKind, _ group: RoomGroup, read: Read) -> String {
        switch kind {
        case .lights: lightSubtitle(group, read: read)
        case .climate: climateSubtitle(group, read: read)
        case .occupancy:
            if allUnavailable(group, read: read) { "Unavailable" } else { occupiedCount(group, read: read) > 0 ? "Occupied" : "Not Occupied" }
        case .contacts:
            allUnavailable(group, read: read) ? "Unavailable" : RoomFormat.contactSummary(group, state: read)
        case .airQuality: ""
        }
    }

    /// Whether every sensor in a room has stopped answering: the card says "Unavailable" instead of a state (closed,
    /// empty) the sensors cannot vouch for. The card stays navigable; the detail page names each sensor.
    public static func allUnavailable(_ group: RoomGroup, read: Read) -> Bool {
        !group.items.isEmpty && unavailableCount(group, read: read) == group.items.count
    }

    /// The web group title the detail page shows: "Living Room Lights", "Gym Light", "Office Climate",
    /// "Hallway Occupancy", "Entryway Contact Sensors".
    public static func detailTitle(_ kind: RoomOverviewKind, _ group: RoomGroup) -> String {
        switch kind {
        case .lights: group.items.count == 1 ? "\(group.room) Light" : "\(group.room) Lights"
        case .climate: "\(group.room) Climate"
        case .occupancy: "\(group.room) Occupancy"
        case .contacts: "\(group.room) Contact Sensors"
        case .airQuality: group.room
        }
    }

    /// The detail page's subtitle (web `roomDetailSubtitle`).
    public static func detailSubtitle(_ kind: RoomOverviewKind, _ group: RoomGroup, read: Read) -> String {
        switch kind {
        case .occupancy:
            let count = occupiedCount(group, read: read)
            return "\(count) sensor\(count == 1 ? "" : "s") occupied"
        default:
            return cardSubtitle(kind, group, read: read)
        }
    }

    /// The headed runs a room's detail page shows. `showsHeadings` is false on room pages, where the sheet's own
    /// title names the group (web `hideDirectHeader`); climate always heads its sensors and vents.
    public static func detailSections(_ kind: RoomOverviewKind, _ group: RoomGroup, showsHeadings: Bool = true) -> [RoomDetailSection] {
        let count = group.items.count
        switch kind {
        case .lights:
            return [RoomDetailSection(title: count == 1 ? "Light" : "Lights", items: group.items)]
        case .climate:
            let sensors = group.items.filter { !$0.entityId.hasPrefix("cover.") }
            let vents = group.items.filter { $0.entityId.hasPrefix("cover.") }
            let ventTitle = vents.count == 1 && vents[0].title != "Vents" ? "Vent" : "Vents"
            return [
                RoomDetailSection(title: sensors.count == 1 ? "Temperature Sensor" : "Temperature Sensors", items: sensors),
                RoomDetailSection(title: ventTitle, items: vents),
            ].filter { !$0.items.isEmpty }
        case .occupancy:
            return [RoomDetailSection(title: showsHeadings ? (count == 1 ? "Occupancy Sensor" : "Occupancy Sensors") : nil, items: group.items)]
        case .contacts:
            return [RoomDetailSection(title: showsHeadings ? (count == 1 ? "Contact Sensor" : "Contact Sensors") : nil, items: group.items)]
        case .airQuality:
            return []
        }
    }

    /// A multi-light room's group light, which its detail page shows as one brightness tile above the lights
    /// (web `RoomLightDetailHeader` `roomSliderEntityId`).
    public static func groupLightEntityId(_ group: RoomGroup) -> String? {
        guard group.items.count > 1, let id = group.entityId, id.hasPrefix("light.") else { return nil }
        return id
    }

    // MARK: Room colors

    /// The room's grid color (`AREA_ITEMS`), by its title.
    public static func roomColor(_ room: String) -> RoomColor? {
        RoomNavigation.items.first { $0.title == room }?.color
    }

    /// The room's grid icon (`AREA_ITEMS`), by its title.
    public static func roomIcon(_ room: String) -> String? {
        RoomNavigation.items.first { $0.title == room }?.icon
    }

    /// The color a room card or sensor tile is washed with while active (web `*GroupColor`, `LIGHT_ON_COLOR`).
    public static func cardColor(_ kind: RoomOverviewKind, _ group: RoomGroup, read: Read) -> RoomColor {
        switch kind {
        case .lights: return lightOnColor
        case .climate:
            return colorFromRgba(group.colorEntityId.flatMap { read($0)?.state })
                ?? roomColor(group.room) ?? RoomColor(25, 84, 130)
        case .occupancy: return roomColor(group.room) ?? RoomColor(46, 180, 120)
        case .contacts: return roomColor(group.room) ?? RoomColor(220, 92, 68)
        case .airQuality: return roomColor(group.room) ?? RoomColor(0, 150, 136)
        }
    }

    /// `LIGHT_ON_COLOR` (`LightCard.tsx:7`).
    public static let lightOnColor = RoomColor(150, 80, 28)

    // MARK: Lights

    /// How many of a room's lights are on.
    public static func lightActiveCount(_ group: RoomGroup, read: Read) -> Int {
        group.items.filter { RoomFormat.isActive(read($0.entityId)) }.count
    }

    /// "On", "3 On", else the group light's state with "Off" when it is missing (web `lightGroupSubtitle`).
    public static func lightSubtitle(_ group: RoomGroup, read: Read) -> String {
        let active = lightActiveCount(group, read: read)
        if active > 0 { return group.items.count == 1 ? "On" : "\(active) On" }
        guard let id = group.entityId, let entity = read(id) else { return "Off" }
        return RoomFormat.compact(entity)
    }

    /// Lights on across the house, each light once.
    public static func activeLightCount(read: Read) -> Int {
        lightEntityIds.filter { RoomFormat.isActive(read($0)) }.count
    }

    /// "All Off" or "3 On" (web `lightCountSubtitle`).
    public static func lightCountSummary(_ count: Int) -> String {
        count == 0 ? "All Off" : "\(count) On"
    }

    // MARK: Occupancy and contacts

    /// How many of a room's presence sensors detect someone.
    public static func occupiedCount(_ group: RoomGroup, read: Read) -> Int {
        group.items.filter { RoomFormat.isOccupied(read($0.entityId)) }.count
    }

    /// How many of a room's contact sensors are open.
    public static func openCount(_ group: RoomGroup, read: Read) -> Int {
        group.items.filter { RoomFormat.isOpen(read($0.entityId)) }.count
    }

    /// Open contact sensors across the house, each once.
    public static func openContactCount(read: Read) -> Int {
        contactEntityIds.filter { RoomFormat.isOpen(read($0)) }.count
    }

    /// "2 Open" or "All Closed" (web `contactSensorStatusSubtitle`).
    public static func contactCountSummary(_ count: Int) -> String {
        count > 0 ? "\(count) Open" : "All Closed"
    }

    /// Every item in a contact group is a window (web `contactGroupKind`).
    public static func isWindowGroup(_ group: RoomGroup) -> Bool {
        !group.items.isEmpty && group.items.allSatisfy(RoomFormat.isWindow)
    }

    // MARK: Climate

    /// The room's range text with each number truncated to one decimal ("70.0 - 72.4°F"), or `nil` when the helper is
    /// missing, unknown or unavailable (web `normalizeClimateRangeText`).
    public static func normalizedRange(_ text: String?) -> String? {
        guard let text, !text.isEmpty, !EntityState.isUnavailable(text) else { return nil }
        let pattern = /-?\d+(?:\.\d+)?/
        return text.replacing(pattern) { match in
            truncatedOneDecimal(Double(match.output) ?? 0)
        }
    }

    /// The range helper's text, else the min–max of the room's temperature sensors, else "N sensors"
    /// (web `climateGroupSubtitle`).
    public static func climateSubtitle(_ group: RoomGroup, read: Read) -> String {
        if let range = normalizedRange(group.entityId.flatMap { read($0)?.state }) { return range }
        let readings = group.items.compactMap { reading(read($0.entityId)) }
        guard let first = readings.first else { return PluralCopy.count(group.items.count, "sensor") }
        let values = readings.map(\.value)
        let (low, high) = (values.min() ?? first.value, values.max() ?? first.value)
        if abs(low - high) < 0.05 { return truncatedOneDecimal(low) + first.unit }
        return "\(truncatedOneDecimal(low))\(first.unit) - \(truncatedOneDecimal(high))\(first.unit)"
    }

    /// A temperature sensor's tile text: one truncated decimal plus unit (`71.2°F`); a vent's state with its position
    /// (`Open · 50%`, the same rule as Climate's Advanced Controls, ``ClimateLogic/ventSubtitle(_:)``); else the compact
    /// state (web `formatClimateEntityState`).
    public static func climateText(_ entity: EntityState?) -> String {
        guard let entity else { return "Unavailable" }
        if entity.domain == "cover" { return ClimateLogic.ventSubtitle(entity) }
        if entity.domain == "sensor", let value = reading(entity) { return truncatedOneDecimal(value.value) + value.unit }
        return RoomFormat.compact(entity)
    }

    /// A climate tile's color: a vent's open/closed color, the sensor's color helper, the temperature gradient, else
    /// `fallback` (web `ClimateCard`).
    public static func climateColor(_ entity: EntityState?, colorEntity: EntityState?, fallback: RoomColor) -> RoomColor {
        if let entity, entity.domain == "cover" {
            if entity.state == "open" { return RoomColor(30, 136, 229) }
            if entity.state == "closed" { return RoomColor(128, 128, 128) }
        }
        return colorFromRgba(colorEntity?.state) ?? colorFromTemperature(reading(entity)?.value) ?? fallback
    }

    /// `rgb(r, g, b)` / `rgba(r, g, b, a)` → color (web `colorFromRgba`); the alpha is ignored.
    public static func colorFromRgba(_ text: String?) -> RoomColor? {
        guard let text else { return nil }
        let pattern = /(?i)rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*[\d.]+)?\s*\)/
        guard let match = text.firstMatch(of: pattern),
              let red = Double(match.output.1), let green = Double(match.output.2), let blue = Double(match.output.3)
        else { return nil }
        return RoomColor(red.rounded(), green.rounded(), blue.rounded())
    }

    /// `rgb()`/`rgba()` or `#rrggbb` → color (web `parseCssColor`, the Air Quality room colors).
    public static func colorFromCss(_ text: String?) -> RoomColor? {
        if let color = colorFromRgba(text) { return color }
        guard let text, let match = text.wholeMatch(of: /#([0-9a-fA-F]{6})/) else { return nil }
        let hex = Array(match.output.1)
        func channel(_ index: Int) -> Double { Double(Int(String(hex[index...index + 1]), radix: 16) ?? 0) }
        return RoomColor(channel(0), channel(2), channel(4))
    }

    /// The web's temperature gradient: blue at 50° through green at 68° to red at 85° (`climateColor.ts`).
    public static func colorFromTemperature(_ value: Double?) -> RoomColor? {
        guard let value else { return nil }
        let stops: [(Double, (Double, Double, Double))] = [
            (50, (0, 110, 255)), (60, (128, 0, 255)), (68, (0, 200, 120)),
            (74, (255, 215, 0)), (80, (255, 165, 0)), (85, (255, 0, 0)),
        ]
        let bounded = min(max(value, stops[0].0), stops[stops.count - 1].0)
        for (start, end) in zip(stops, stops.dropFirst()) where bounded >= start.0 && bounded <= end.0 {
            let ratio = end.0 == start.0 ? 0 : (bounded - start.0) / (end.0 - start.0)
            func mix(_ a: Double, _ b: Double) -> Double { (a + (b - a) * ratio).rounded() }
            return RoomColor(mix(start.1.0, end.1.0), mix(start.1.1, end.1.1), mix(start.1.2, end.1.2))
        }
        let last = stops[stops.count - 1].1
        return RoomColor(last.0, last.1, last.2)
    }

    // MARK: Air quality

    /// A room's AQI card color from its helper, else teal (web `airQualityRoomArea`).
    public static func airQualityColor(_ room: AirQualityRoom, read: Read) -> RoomColor {
        colorFromCss(read(room.colorEntityId)?.state) ?? RoomColor(0, 150, 136)
    }

    /// "AQI 12 · PM2.5 3.1" (web `airQualityStatusSubtitle`).
    ///
    /// Both ranges come from the Air Quality status chip (``HomeConfig/statusChips``, so the house document's): the AQI range
    /// is its entity and the PM2.5 range its ``HomeConfig/StatusChip/detailEntityId``. A chip without that field shows no
    /// PM2.5 detail.
    public static func airQualityChipSummary(read: Read) -> String {
        let chip = HomeConfig.statusChips.first { $0.tone == .air }
        let detailId = chip?.detailEntityId
        let aqi = RoomFormat.compact(chip.flatMap { read($0.entityId) })
        let pm25 = RoomFormat.compact(detailId.flatMap(read))
        return "AQI \(aqi) · PM2.5 \(pm25)"
    }

    // MARK: Helpers

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func reading(_ entity: EntityState?) -> (value: Double, unit: String)? {
        guard let entity, entity.domain == "sensor", !entity.isUnavailable, let value = Double(entity.state), value.isFinite
        else { return nil }
        return (value, entity.attributes["unit_of_measurement"]?.string ?? "")
    }

    /// `Math.trunc(value * 10) / 10` with one decimal.
    static func truncatedOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", (value * 10).rounded(.towardZero) / 10)
    }
}
