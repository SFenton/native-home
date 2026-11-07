import Foundation

/// One position reading, free of Core Location so the reporting rules are testable on any platform.
///
/// Fields follow `CLLocation`: a negative accuracy, speed or course means the value is invalid.
public struct LocationFix: Equatable, Sendable {
    /// Degrees north.
    public var latitude: Double
    /// Degrees east.
    public var longitude: Double
    /// Radius of uncertainty in meters; negative when the fix is invalid.
    public var horizontalAccuracy: Double
    /// Meters above sea level; meaningful only when ``verticalAccuracy`` is not negative.
    public var altitude: Double
    /// Altitude uncertainty in meters; negative when ``altitude`` is invalid.
    public var verticalAccuracy: Double
    /// Meters per second; negative when unknown.
    public var speed: Double
    /// Degrees clockwise from true north; negative when unknown.
    public var course: Double
    /// When the fix was taken.
    public var timestamp: Date

    /// Creates a fix. Unknown values default to Core Location's invalid marker, -1.
    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, altitude: Double = 0,
                verticalAccuracy: Double = -1, speed: Double = -1, course: Double = -1, timestamp: Date = .now) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }

    /// Whether the coordinate is real: a non-negative accuracy and a latitude and longitude in range.
    public var isValid: Bool {
        horizontalAccuracy >= 0 && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    /// Great-circle distance in meters to a coordinate (haversine on the mean Earth radius; within 0.5% of
    /// `CLLocation.distance(from:)`, far below fix accuracy).
    public func distance(toLatitude otherLatitude: Double, longitude otherLongitude: Double) -> Double {
        Self.distance(latitude, longitude, otherLatitude, otherLongitude)
    }

    /// Great-circle distance in meters to another fix.
    public func distance(to other: LocationFix) -> Double {
        distance(toLatitude: other.latitude, longitude: other.longitude)
    }

    static let earthRadius = 6_371_008.8

    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let φ1 = lat1 * .pi / 180, φ2 = lat2 * .pi / 180
        let Δφ = (lat2 - lat1) * .pi / 180, Δλ = (lon2 - lon1) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * earthRadius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}
