import Foundation

/// What a sensor update is for: why it runs, the permission it runs under, and the fix (with the zones) it
/// accompanies. The status source reads the device with it; ``SensorReporter`` adds the zone names to the place.
public struct SensorContext: Sendable {
    /// Why the update was sent: the Last Update Trigger sensor's state.
    public var trigger: LocationTrigger
    /// The fix the location update carries; nil for a sensors-only update, which has nothing to geocode.
    public var fix: LocationFix?
    /// The location permission now (SSID and BSSID need it).
    public var permission: LocationPermission
    /// The zones Home Assistant knows, for the geocoded location's "Zones" attribute.
    public var zones: [HAZone]

    /// Creates a context.
    public init(trigger: LocationTrigger, fix: LocationFix? = nil,
                permission: LocationPermission = .notDetermined, zones: [HAZone] = []) {
        self.trigger = trigger
        self.fix = fix
        self.permission = permission
        self.zones = zones
    }

    /// Names of the non-passive zones that contain ``fix``, smallest first (the official app's "Zones" attribute).
    public var zoneNames: [String] {
        guard let fix else { return [] }
        return zones.filter { !$0.isPassive && !$0.friendlyName.isEmpty && $0.distanceOutside(fix) <= 0 }
            .sorted { $0.radius < $1.radius }
            .map(\.friendlyName)
    }
}

/// Reads the device for the sensors. The app's implementation (`HassUI/App/Location`) uses UIKit, Network, Core
/// Location's geocoder and AVFoundation, so it stays out of `HassCore`; tests answer a fixed ``DeviceStatus``.
///
/// Implementations do their I/O (geocoding, Wi-Fi lookup) off the main thread, and bound it: a slow geocode must not
/// hold the sensors back for long. A part the device cannot read is left nil, and its sensor reports nothing.
public protocol DeviceStatusSource: Sendable {
    /// The device now. ``DeviceStatus/lastUpdateTrigger`` is set by the caller.
    func status(for context: SensorContext) async -> DeviceStatus
}

/// A source that answers one reading, for tests and previews.
public struct FixedDeviceStatusSource: DeviceStatusSource {
    private let status: DeviceStatus

    /// Creates a source.
    public init(_ status: DeviceStatus) { self.status = status }

    public func status(for context: SensorContext) async -> DeviceStatus { status }
}
