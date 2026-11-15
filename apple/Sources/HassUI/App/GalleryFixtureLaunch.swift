import Foundation
#if DEBUG
import CryptoKit
#endif

// MARK: - Isolated gallery launch

/// Opens existing, network-isolated galleries through a device tool's launch arguments.
public enum GalleryFixtureLaunch {
    /// Fixture launches never restore the normal account or enable background house operations.
    public static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        arguments.contains("--gallery-fixture")
        #else
        false
        #endif
    }

    #if DEBUG
    struct Configuration: Codable, Equatable {
        let id: String
        let variables: [String: String]
        let referenceTime: TimeInterval?
        let pauseContinuousAnimations: Bool?

        init(id: String, variables: [String: String], referenceTime: TimeInterval? = nil,
             pauseContinuousAnimations: Bool? = nil) {
            self.id = id
            self.variables = variables
            self.referenceTime = referenceTime
            self.pauseContinuousAnimations = pauseContinuousAnimations
        }

        func validate() throws {
            if let referenceTime {
                guard referenceTime.isFinite, (0...253_402_300_799).contains(referenceTime) else {
                    throw Failure.invalidConfiguration
                }
            }
            guard !id.isEmpty, id.utf8.count <= 120, id.utf8.allSatisfy({
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                    || [45, 46, 95].contains($0)
            }), let page = variables["FENTON_GALLERY"], ComponentGallery.Page(rawValue: page) != nil,
                  variables.allSatisfy({ key, value in
                      GalleryFixtureLaunch.accepts(key) && key.utf8.count <= 128
                          && key.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) || $0 == 95 }
                          && value.utf8.count <= 1_024 && !value.contains("\0")
                  }) else { throw Failure.invalidConfiguration }
        }
    }

    enum Failure: Error {
        case oversizedConfiguration, invalidConfiguration, environmentUpdate
    }

    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("GalleryFixture", isDirectory: true)
    }

    private static func accepts(_ name: String) -> Bool {
        name == "FENTON_GALLERY" || name.hasPrefix("FENTON_GALLERY_") || name == "FENTON_BACKDROP_FIXTURE"
    }

    static func decode(_ data: Data) throws -> Configuration {
        guard data.count <= 65_536 else { throw Failure.oversizedConfiguration }
        let configuration = try JSONDecoder().decode(Configuration.self, from: data)
        try configuration.validate()
        return configuration
    }

    /// Uses the gallery reset's existing namespace; credentials and lifecycle overrides are never accepted.
    static func plan(_ configuration: Configuration, environment: [String: String]) throws -> GalleryReset.Plan {
        try configuration.validate()
        return GalleryReset.Plan(
            unset: environment.keys.filter { accepts($0) && configuration.variables[$0] == nil }.sorted(),
            set: configuration.variables)
    }

    /// Reads only this app's explicit fixture file. A bad fixture stays isolated and shows an error.
    @MainActor
    static func prepare(at directory: URL = GalleryFixtureLaunch.directory) throws {
        let receipt = directory.appendingPathComponent("receipt.json")
        if FileManager.default.fileExists(atPath: receipt.path) {
            try FileManager.default.removeItem(at: receipt)
        }
        let file = directory.appendingPathComponent("bootstrap.json")
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 65_536 else { throw Failure.oversizedConfiguration }
        let bytes = try Data(contentsOf: file)
        let configuration = try decode(bytes)
        let update = try plan(configuration, environment: ProcessInfo.processInfo.environment)
        for key in update.unset {
            guard unsetenv(key) == 0 else { throw Failure.environmentUpdate }
        }
        for (key, value) in update.set {
            guard setenv(key, value, 1) == 0 else { throw Failure.environmentUpdate }
        }
        GalleryFixtureClock.shared.setReferenceDate(configuration.referenceTime.map(Date.init(timeIntervalSince1970:)))
        #if os(iOS)
        UKDesign.animationsPaused = configuration.pauseContinuousAnimations == true
        #endif
        var record: [String: String] = [
            "status": "prepared",
            "fixtureID": configuration.id,
            "inputSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "launch": "--gallery-fixture",
            "continuousAnimationsPaused": String(configuration.pauseContinuousAnimations == true),
        ]
        record["referenceTime"] = configuration.referenceTime.map { String($0) }
        try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]).write(to: receipt, options: .atomic)
    }
    #endif
}
