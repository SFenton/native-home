#if os(iOS)
import AVFoundation
import CoreLocation
import HassCore
import Intents
import Network
import NetworkExtension
import UIKit

/// Reads the phone for the sensors (``DeviceStatusSource``): battery, network path and Wi-Fi, audio route,
/// Focus, the app version and the reverse-geocoded address of the update's fix.
///
/// Every part is a reading the device can refuse (no entitlement, no permission, no network): then it is nil and its
/// sensor reports nothing. The geocode is the only slow part; it runs off the main thread, concurrently with the
/// other reads, and gives up after ``geocodeTimeout`` seconds so a bad connection cannot hold the sensors back.
/// iOS-only and not host-tested: the readings come from UIKit, Network and Core Location.
final class SystemDeviceStatusSource: DeviceStatusSource, @unchecked Sendable {
    /// How long the reverse geocode may take before the address is left out of this update.
    static let geocodeTimeout: TimeInterval = 10

    /// The app's version as the App Version sensor shows it: `0.1.0 (1)`.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private let monitor = NWPathMonitor()

    init() {
        monitor.start(queue: DispatchQueue(label: "com.sfenton.home.sensors.path", qos: .utility))
    }

    deinit { monitor.cancel() }

    func status(for context: SensorContext) async -> DeviceStatus {
        async let place = geocode(context.fix)
        async let battery = Self.battery()
        async let network = network(permission: context.permission)
        async let focused = Self.isFocused()
        return DeviceStatus(
            battery: await battery, network: await network, locationPermission: context.permission,
            appVersion: Self.appVersion, audioOutputs: Self.audioOutputs(),
            place: await place, isFocused: await focused
        )
    }

    // MARK: - Readings

    @MainActor
    private static func battery() -> DeviceStatus.Battery? {
        let device = UIDevice.current
        guard device.batteryLevel >= 0 else { return nil }
        let state: DeviceStatus.Battery.State = switch device.batteryState {
        case .charging: .charging
        case .full: .full
        case .unplugged: .notCharging
        default: .unknown
        }
        return DeviceStatus.Battery(level: Int((device.batteryLevel * 100).rounded()), state: state,
                                    isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    private func network(permission: LocationPermission) async -> DeviceStatus.Network {
        let path = monitor.currentPath
        let connection: DeviceStatus.Network.Connection =
            if path.status != .satisfied { .none }
            else if path.usesInterfaceType(.wifi) { .wifi }
            else if path.usesInterfaceType(.cellular) { .cellular }
            else if path.usesInterfaceType(.wiredEthernet) { .ethernet }
            else { .unknown }
        // SSID and BSSID need the Access Wi-Fi Information entitlement and a location permission.
        guard connection == .wifi, permission.isAuthorized else {
            return DeviceStatus.Network(connection: connection, canReadWiFi: permission.isAuthorized)
        }
        let current = await NEHotspotNetwork.fetchCurrent()
        return DeviceStatus.Network(connection: connection, ssid: current?.ssid, bssid: current?.bssid, canReadWiFi: true)
    }

    private static func audioOutputs() -> [String] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName)
    }

    /// Whether a Focus is on; nil unless the person allowed the app to share Focus status (this build never asks).
    private static func isFocused() async -> Bool? {
        guard INFocusStatusCenter.default.authorizationStatus == .authorized else { return nil }
        return INFocusStatusCenter.default.focusStatus.isFocused
    }

    // MARK: - Geocoding

    /// The address of `fix`, or nil when there is no fix, no network, or it takes longer than ``geocodeTimeout``.
    private func geocode(_ fix: LocationFix?) async -> GeocodedPlace? {
        guard let fix else { return nil }
        let location = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        return await withTaskGroup(of: GeocodedPlace?.self) { group in
            group.addTask { await Self.reverseGeocode(location) }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.geocodeTimeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // TODO: `CLGeocoder` is deprecated from iOS 26 in favor of MapKit's `MKReverseGeocodingRequest`. The deployment
    // target is iOS 17, so this stays on `CLGeocoder` (the departure is recorded in location.md); move to
    // `MKReverseGeocodingRequest` behind `#available(iOS 26, *)` when the target moves.
    private static func reverseGeocode(_ location: CLLocation) async -> GeocodedPlace? {
        nonisolated(unsafe) let geocoder = CLGeocoder()
        return await withTaskCancellationHandler {
            guard let placemarks = try? await geocoder.reverseGeocodeLocation(location), !placemarks.isEmpty else { return nil }
            return place(from: placemarks, fallback: location)
        } onCancel: {
            geocoder.cancelGeocode()
        }
    }

    /// The official app's choice for every field: the first non-empty value among the placemarks.
    private static func place(from placemarks: [CLPlacemark], fallback: CLLocation) -> GeocodedPlace {
        func best(_ keyPath: KeyPath<CLPlacemark, String?>) -> String? {
            let values = placemarks.compactMap { $0[keyPath: keyPath] }
            return values.first { !$0.isEmpty } ?? values.first
        }
        let coordinate = placemarks.compactMap(\.location).first?.coordinate ?? fallback.coordinate
        return GeocodedPlace(
            name: best(\.name), subThoroughfare: best(\.subThoroughfare), thoroughfare: best(\.thoroughfare),
            subLocality: best(\.subLocality), locality: best(\.locality),
            subAdministrativeArea: best(\.subAdministrativeArea), administrativeArea: best(\.administrativeArea),
            postalCode: best(\.postalCode), country: best(\.country), isoCountryCode: best(\.isoCountryCode),
            timeZone: placemarks.compactMap { $0.timeZone?.identifier }.first ?? TimeZone.current.identifier,
            inlandWater: best(\.inlandWater), ocean: best(\.ocean),
            areasOfInterest: placemarks.compactMap(\.areasOfInterest).first { !$0.isEmpty } ?? [],
            coordinate: [coordinate.latitude, coordinate.longitude]
        )
    }
}
#endif
