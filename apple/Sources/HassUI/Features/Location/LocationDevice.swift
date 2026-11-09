#if canImport(UIKit)
import UIKit
#endif

/// Which kind of device the location screen speaks about, so its copy names the device ("This iPad") and an iPad,
/// which is never linked to the person, never promises that Away mode follows them (owner, 2026-10-27).
enum LocationDevice: Equatable {
    case iPhone
    case iPad

    /// The device for an idiom: an iPad is an iPad; everything else (iPhone, iPhone Duo) is an iPhone.
    static func resolve(isPad: Bool) -> LocationDevice { isPad ? .iPad : .iPhone }

    /// This device. The macOS host that runs the unit tests reads as an iPhone.
    @MainActor static var current: LocationDevice {
        #if os(iOS)
        resolve(isPad: UIDevice.current.userInterfaceIdiom == .pad)
        #else
        .iPhone
        #endif
    }

    /// The device's name as copy uses it: "iPhone" or "iPad".
    var name: String { self == .iPad ? "iPad" : "iPhone" }
}
