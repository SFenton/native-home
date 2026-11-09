import Foundation
#if os(iOS)
import CoreSpotlight
import HassCore
import UIKit

/// The UIKit app's entry point: the `FentonHome` target's scene delegate asks for its window's root here.
/// The UIKit counterpart of ``RootView`` (sign-in or the main tabs, scene phase, launch and arrival motion).
@MainActor
public enum UKApp {
    /// The root controller for a new window.
    /// - Parameter session: The app's one session, owned by the app delegate.
    public static func makeRootViewController(session: AppSession) -> UIViewController {
        UKRootViewController(session: session)
    }

    /// A URL opened into the app (the Live Activity's `fentonhome://liveactivity?url=…`).
    public static func open(_ url: URL, session: AppSession) {
        session.push.openLiveActivity(url)
    }

    /// A continued user activity (a tapped Spotlight result).
    public static func `continue`(_ activity: NSUserActivity, session: AppSession) {
        guard activity.activityType == CSSearchableItemActionType else { return }
        session.push.open(spotlightUserInfo: activity.userInfo)
    }
}
#endif

/// Upgrading over the SwiftUI app. iOS persists each `UISceneSession` with its configuration, delegate class included, so
/// a window the SwiftUI app left behind reconnects with SwiftUI's own scene delegate, never asking the app delegate for a
/// configuration; that delegate draws nothing here and the screen stays black. The app adopts such a scene instead.
public enum UKSceneUpgrade {
    /// The configuration name in `Info.plist` for the app's windows.
    public static let configurationName = "Default"

    /// Whether a connecting scene's delegate is not the app's own and so must be replaced.
    /// - Parameters:
    ///   - sceneDelegate: The delegate the scene connected with (nil when it has none).
    ///   - ours: The app's scene delegate class.
    public static func needsAdoption(sceneDelegate: AnyObject?, ours: AnyClass) -> Bool {
        guard let object = sceneDelegate as? NSObject else { return true }
        return !object.isKind(of: ours)
    }
}
