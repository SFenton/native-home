import Foundation

/// The APNs environment a build's device token belongs to. The relay must send to the matching gateway.
public enum APNsEnvironment: String, Codable, Sendable {
    /// Xcode-installed builds and the simulator.
    case sandbox
    /// TestFlight and App Store builds.
    case production

    /// Reads the environment from the embedded provisioning profile's `aps-environment` entitlement. No profile
    /// means an App Store install (production) on a device, or the simulator (sandbox).
    /// - Parameters:
    ///   - provisioningProfile: `embedded.mobileprovision`, if the bundle has one.
    ///   - isSimulator: Running in the simulator.
    public static func detect(provisioningProfile: Data?, isSimulator: Bool) -> APNsEnvironment {
        if isSimulator { return .sandbox }
        guard let profile = provisioningProfile else { return .production }
        // The profile is a CMS envelope around a plain XML plist; the entitlement is readable as text.
        let text = String(decoding: profile, as: UTF8.self)
        guard let key = text.range(of: "<key>aps-environment</key>"),
              let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
              let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex)
        else { return .sandbox }
        return text[open.upperBound..<close.lowerBound] == "production" ? .production : .sandbox
    }
}
