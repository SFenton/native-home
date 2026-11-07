import Foundation

/// One `update_location` command: a fix, the battery level, and the zone result when a zone event caused it.
///
/// Home Assistant's schema wants whole numbers (`cv.positive_int` for accuracy, speed, course and vertical
/// accuracy), so values are rounded, and anything Core Location marks invalid is left out rather than sent as -1.
public struct LocationReport: Equatable, Sendable {
    /// The position.
    public var fix: LocationFix
    /// Battery percentage, 0–100.
    public var batteryLevel: Int?
    /// `home`, `not_home` or a zone name; nil lets Home Assistant compute the zone from the coordinates.
    public var locationName: String?

    /// Creates a report.
    /// - Returns: nil when the fix is invalid (negative accuracy or an out-of-range coordinate).
    public init?(fix: LocationFix, batteryLevel: Int? = nil, locationName: String? = nil) {
        guard fix.isValid else { return nil }
        self.fix = fix
        self.batteryLevel = batteryLevel.flatMap { (0...100).contains($0) ? $0 : nil }
        self.locationName = locationName
    }

    /// The command's `data`.
    public var webhookData: [String: Any] {
        var data: [String: Any] = [
            "gps": [fix.latitude, fix.longitude],
            "gps_accuracy": Int(fix.horizontalAccuracy.rounded()),
        ]
        data["battery"] = batteryLevel
        if fix.speed >= 0 { data["speed"] = Int(fix.speed.rounded()) }
        if fix.course >= 0 { data["course"] = Int(fix.course.rounded()) }
        // Altitude can be below sea level; it is invalid only when its accuracy is.
        if fix.verticalAccuracy >= 0 {
            data["altitude"] = Int(fix.altitude.rounded())
            data["vertical_accuracy"] = Int(fix.verticalAccuracy.rounded())
        }
        data["location_name"] = locationName
        return data
    }

    /// The whole command.
    public var webhookBody: [String: Any] { ["type": "update_location", "data": webhookData] }
}
