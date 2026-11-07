import HassDesign
import Foundation
#if os(iOS)
import UIKit
#endif

// MARK: - Supported orientations

/// Interface orientations, platform-neutral so the policy compiles and tests on macOS.
/// Ported from FestivalNativeApps `App/Layout/OrientationPolicy.swift`.
public struct SupportedOrientations: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    /// Creates a set from raw bits.
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let portrait = SupportedOrientations(rawValue: 1 << 0)
    public static let portraitUpsideDown = SupportedOrientations(rawValue: 1 << 1)
    public static let landscapeLeft = SupportedOrientations(rawValue: 1 << 2)
    public static let landscapeRight = SupportedOrientations(rawValue: 1 << 3)
    public static let all: SupportedOrientations = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]

    /// Parses an Info.plist `UISupportedInterfaceOrientations` array; unknown names are ignored.
    public init(infoPlistValues: [String]) {
        var result: SupportedOrientations = []
        for value in infoPlistValues {
            switch value {
            case "UIInterfaceOrientationPortrait": result.insert(.portrait)
            case "UIInterfaceOrientationPortraitUpsideDown": result.insert(.portraitUpsideDown)
            case "UIInterfaceOrientationLandscapeLeft": result.insert(.landscapeLeft)
            case "UIInterfaceOrientationLandscapeRight": result.insert(.landscapeRight)
            default: break
            }
        }
        self = result
    }
}

// MARK: - Policy

/// Which orientations the app supports (owner, 2026-10-10).
///
/// The Info.plist stays the source of truth: iPhone is portrait-only, iPad allows all four. A device that
/// reports a hinge (iPhone Duo, detected through `onHingeChange` or the vertical bar, never by product name)
/// allows every orientation, folded or unfolded.
enum OrientationPolicy {
    /// Resolves the supported orientations.
    /// - Parameters:
    ///   - declared: The Info.plist declaration for this idiom; empty when missing.
    ///   - hasHinge: A hinge has been observed on this device.
    static func supported(declared: SupportedOrientations, hasHinge: Bool) -> SupportedOrientations {
        if hasHinge { return .all }
        return declared.isEmpty ? .portrait : declared
    }

    /// The Info.plist keys UIKit reads for an idiom, most specific first.
    static func infoPlistKeys(isPad: Bool) -> [String] {
        let base = "UISupportedInterfaceOrientations"
        return [base + (isPad ? "~ipad" : "~iphone"), base]
    }

    /// Reads the declaration for an idiom from an Info dictionary.
    static func declared(in info: [String: Any], isPad: Bool) -> SupportedOrientations {
        for key in infoPlistKeys(isPad: isPad) {
            if let values = info[key] as? [String] { return SupportedOrientations(infoPlistValues: values) }
        }
        return []
    }
}

// MARK: - Hinge presence

/// Remembers, for the life of the process, that this device has a hinge, and asks UIKit to re-read
/// supported orientations the first time one is seen. Later nil values never clear it.
@MainActor
public final class HingePresence {
    /// Process-wide instance read by the app delegate.
    public static let shared = HingePresence()

    /// A hinge has been observed on this device.
    public private(set) var hasHinge = false

    var onFirstHinge: @MainActor () -> Void

    init(onFirstHinge: @escaping @MainActor () -> Void = HingePresence.requestOrientationUpdate) {
        self.onFirstHinge = onFirstHinge
    }

    /// Records the latest observations.
    /// - Parameters:
    ///   - hinge: The latest `onHingeChange` value; nil on devices without a hinge.
    ///   - hasVerticalBar: The system vertical bar is in use (only iPhone Duo has one).
    func record(hinge: HingeState?, hasVerticalBar: Bool = false) {
        guard hinge != nil || hasVerticalBar, !hasHinge else { return }
        hasHinge = true
        DuoSheetPolicy.deviceHasHinge = true
        onFirstHinge()
    }

    /// Forgets that a hinge was seen (and ``DuoSheetPolicy/deviceHasHinge``). Tests only: the app never clears it.
    func resetForTests() {
        hasHinge = false
        DuoSheetPolicy.deviceHasHinge = false
    }

    static func requestOrientationUpdate() {
        #if os(iOS)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
        #endif
    }
}

#if os(iOS)
// MARK: - UIKit bridge

/// Supported orientations for the app delegate's `supportedInterfaceOrientationsFor`.
public enum FentonOrientationSupport {
    /// Every orientation once a hinge has been observed, else the Info.plist declaration for the idiom.
    @MainActor
    public static func mask(for window: UIWindow?) -> UIInterfaceOrientationMask {
        let idiom = window?.traitCollection.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom
        let declared = OrientationPolicy.declared(in: Bundle.main.infoDictionary ?? [:], isPad: idiom == .pad)
        return OrientationPolicy.supported(declared: declared, hasHinge: HingePresence.shared.hasHinge).interfaceOrientationMask
    }
}

extension SupportedOrientations {
    var interfaceOrientationMask: UIInterfaceOrientationMask {
        var mask: UIInterfaceOrientationMask = []
        if contains(.portrait) { mask.insert(.portrait) }
        if contains(.portraitUpsideDown) { mask.insert(.portraitUpsideDown) }
        if contains(.landscapeLeft) { mask.insert(.landscapeLeft) }
        if contains(.landscapeRight) { mask.insert(.landscapeRight) }
        return mask
    }
}
#endif
