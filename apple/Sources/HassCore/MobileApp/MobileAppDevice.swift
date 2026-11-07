import Foundation

/// The device facts `mobile_app` registration sends (contract v1, rule 2).
public struct MobileAppDevice: Equatable, Sendable {
    /// `app_version`: `"<marketing> (<build>)"`.
    public var appVersion: String
    /// `device_name`, already carrying ``PushApp/deviceNameSuffix``.
    public var deviceName: String
    /// `model`: the hardware identifier (`hw.machine`, e.g. `iPhone18,1`).
    public var model: String
    /// `os_version`.
    public var osVersion: String
    /// `device_id`: `identifierForVendor`.
    public var deviceID: String
    /// Which APNs gateway the token belongs to.
    public var apnsEnvironment: APNsEnvironment
    /// `app_id`: the running build's bundle identifier, so a build with another bundle id never claims the main app's.
    public var appID: String
    /// The device's own name, without the suffix.
    private var baseName: String
    /// Whether ``baseName`` is the system's generic name (or a marketing name standing in for it), not one the person chose.
    private var nameIsGeneric: Bool

    /// Creates a device description.
    /// - Parameters:
    ///   - marketingVersion: `CFBundleShortVersionString`.
    ///   - build: `CFBundleVersion`.
    ///   - name: The device's name (`UIDevice.name`); the Fenton suffix is added here.
    ///   - model: Hardware identifier.
    ///   - osVersion: System version.
    ///   - deviceID: `identifierForVendor`.
    ///   - apnsEnvironment: The token's gateway.
    ///   - appID: The running bundle identifier; defaults to ``PushApp/appID``.
    public init(marketingVersion: String, build: String, name: String, model: String, osVersion: String,
                deviceID: String, apnsEnvironment: APNsEnvironment, appID: String = PushApp.appID) {
        appVersion = "\(marketingVersion) (\(build))"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = trimmed.isEmpty ? "iPhone" : trimmed
        nameIsGeneric = Self.genericNames.contains(system)
        // A generic name says nothing about which phone this is; the model's marketing name does.
        baseName = nameIsGeneric ? (Self.marketingName(forModel: model) ?? system) : system
        self.appID = appID
        deviceName = baseName + PushApp.deviceNameSuffix
        self.model = model
        self.osVersion = osVersion
        self.deviceID = deviceID
        self.apnsEnvironment = apnsEnvironment
    }

    /// The device named for its Home Assistant user when the system gives only a generic name.
    ///
    /// Since iOS 16 `UIDevice.name` is "iPhone" or "iPad" without a special entitlement, so every phone would register
    /// as "iPhone · Morgan" and Home Assistant, which keeps one notify action per `device_name`, would reach only one
    /// of them (2026-11-02: three registrations, one name). A generic name becomes the model's marketing name (see
    /// ``marketingName(forModel:)``) and, with the user's first name, reads "Alex's iPhone Duo · Morgan". A name
    /// the person chose (with the entitlement) is kept.
    /// - Parameter userName: The Home Assistant user's display name.
    public func owned(by userName: String?) -> MobileAppDevice {
        let first = userName?.split(separator: " ").first.map(String.init) ?? ""
        guard !first.isEmpty, nameIsGeneric else { return self }
        var device = self
        device.deviceName = "\(first)'s \(baseName)" + PushApp.deviceNameSuffix
        return device
    }

    /// The names the system reports instead of the person's own.
    static let genericNames: Set<String> = ["iPhone", "iPad", "iPod touch"]

    /// The marketing names of the hardware identifiers (`hw.machine`, or `SIMULATOR_MODEL_IDENTIFIER` in the simulator)
    /// this app is known to run on. Only identifiers that are certain are listed.
    static let marketingNames: [String: String] = [
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPhone19,2": "iPhone 18 Pro", "iPhone19,4": "iPhone Duo",
    ]

    /// The marketing name for a hardware identifier, or nil when it isn't in the table.
    /// - Parameter model: `hw.machine`, e.g. `iPhone19,4`.
    public static func marketingName(forModel model: String) -> String? { marketingNames[model] }

    /// The registration body for `POST /api/mobile_app/registrations`.
    /// - Parameter appData: The push details to send.
    func registrationBody(appData: PushAppData) -> [String: Any] {
        [
            "app_id": appID,
            "app_name": PushApp.appName,
            "app_version": appVersion,
            "device_name": deviceName,
            "manufacturer": "Apple",
            "model": model,
            "os_name": "iOS",
            "os_version": osVersion,
            "device_id": deviceID,
            "supports_encryption": false,
            "app_data": appData.json,
        ]
    }

    /// The `update_registration` webhook body.
    /// - Parameter appData: The push details to send; ``PushAppData/cleared`` on sign-out.
    func updateBody(appData: PushAppData) -> [String: Any] {
        [
            "type": "update_registration",
            "data": [
                "app_data": appData.json,
                "app_version": appVersion,
                "device_name": deviceName,
                "manufacturer": "Apple",
                "model": model,
                "os_version": osVersion,
            ] as [String: Any],
        ]
    }
}
