import Foundation
import HassCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Gathers ``FeedbackDiagnostics`` from the device, the window and the Home Assistant connection when a
/// report is sent. Reads only what the issue shows: no token, server address or password.
@MainActor
struct FeedbackDiagnosticsCollector {
    /// Settings read from the sheet's environment.
    struct Traits {
        var dynamicTypeSize: DynamicTypeSize
        var colorScheme: ColorScheme
        var regularWidth: Bool
        var voiceOver: Bool
        var reduceMotion: Bool
    }

    var platform: FeedbackPlatform
    var traits: Traits

    /// Collects diagnostics; the integration adds the Home Assistant user from the request's own sign-in.
    func collect(connection: HassConnection) -> FeedbackDiagnostics {
        Self.diagnostics(
            platform: platform, traits: traits,
            homeAssistant: HomeAssistantSettingsView.version(connection.status).map { "\($0), \(HomeAssistantSettingsView.statusText(connection.status).lowercased())" }
                ?? HomeAssistantSettingsView.statusText(connection.status)
        )
    }

    /// Builds diagnostics from explicit values plus the process (unit-tested).
    static func diagnostics(platform: FeedbackPlatform, traits: Traits, homeAssistant: String) -> FeedbackDiagnostics {
        let window = windowSize
        return FeedbackDiagnostics(
            app: FeedbackDiagnostics.appVersion(Bundle.main.infoDictionary, buildDate: buildDate),
            system: systemVersion,
            device: "\(familyName(platform)) (\(hardwareModel))",
            window: FeedbackDiagnostics.windowText(width: window.width, height: window.height, regularWidth: traits.regularWidth),
            homeAssistant: homeAssistant,
            accessibility: accessibilityText(traits),
            locale: "\(Locale.current.identifier), \(TimeZone.current.identifier)"
        )
    }

    /// For example "Text xLarge, VoiceOver off, Reduce Motion off, Dark".
    static func accessibilityText(_ traits: Traits) -> String {
        let size = String(describing: traits.dynamicTypeSize)
        return [
            "Text \(size)",
            "VoiceOver \(traits.voiceOver ? "on" : "off")",
            "Reduce Motion \(traits.reduceMotion ? "on" : "off")",
            traits.colorScheme == .dark ? "Dark" : "Light",
        ].joined(separator: ", ")
    }

    static func familyName(_ platform: FeedbackPlatform) -> String {
        switch platform {
        case .ios: "iPhone"
        case .ipados: "iPad"
        case .iphoneDuo: "iPhone Duo"
        }
    }

    /// The hardware identifier, for example `iPhone19,3`; a simulator reports the model it simulates.
    static var hardwareModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) Simulator"
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// "iOS 27.1".
    static var systemVersion: String {
        #if canImport(UIKit)
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #endif
    }

    /// The key window's size, or zero when there is none (hosted tests).
    static var windowSize: CGSize {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        return window?.bounds.size ?? .zero
        #else
        return .zero
        #endif
    }

    /// When the app's executable was built, from its modification date.
    static var buildDate: Date? {
        guard let url = Bundle.main.executableURL else { return nil }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
