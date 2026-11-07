import Foundation

/// The room-by-room sheets Home's status chips open, which the Security page and room pages reuse
/// (pattern: `.agents/patterns/room-overview-sheet.md`).
///
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/pages/AtAGlancePage.tsx:247-1077` (`LightsSheet`, `ClimateSheet`,
/// `OccupancySheet`, `ContactSheet`, `AirQualitySheet`).
public enum RoomOverviewKind: String, CaseIterable, Sendable, Hashable, Identifiable {
    case lights, climate, occupancy, contacts, airQuality
    public var id: String { rawValue }
}
