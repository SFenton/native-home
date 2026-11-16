import Foundation
import Testing
@testable import HassUI

// MARK: - Device-bound fixture entry

@MainActor
struct GalleryFixtureLaunchTests {
    @Test func replacesOnlyFixtureVariables() throws {
        let configuration = GalleryFixtureLaunch.Configuration(id: "weather-empty", variables: [
            "FENTON_GALLERY": "weather", "FENTON_GALLERY_WEATHER_STATE": "empty",
        ])
        let plan = try GalleryFixtureLaunch.plan(configuration, environment: [
            "FENTON_GALLERY": "home", "FENTON_GALLERY_SCENARIO": "stale",
            "FENTON_BACKDROP_FIXTURE": "1", "FENTON_HASS_TOKEN": "untouched", "PATH": "/bin",
        ])
        #expect(plan.unset == ["FENTON_BACKDROP_FIXTURE", "FENTON_GALLERY_SCENARIO"])
        #expect(plan.set == configuration.variables)
    }

    @Test(arguments: ["FENTON_HASS_TOKEN", "FENTON_HASS_SERVER", "FENTON_LOCATION", "FENTON_PUSH", "PATH",
                      "FENTON_GALLERY_BAD=KEY", "FENTON_GALLERY_BAD\0KEY"])
    func refusesCredentialsAndLifecycleOverrides(_ key: String) throws {
        let configuration = GalleryFixtureLaunch.Configuration(id: "home", variables: [
            "FENTON_GALLERY": "home", key: "test-only",
        ])
        #expect(throws: GalleryFixtureLaunch.Failure.invalidConfiguration) {
            try configuration.validate()
        }
    }

    @Test func refusesMissingOrUnknownPagesAndMalformedValues() throws {
        for variables in [[:], ["FENTON_GALLERY": "not-a-page"],
                          ["FENTON_GALLERY": "home", "FENTON_GALLERY_SCENARIO": "a\0b"],
                          ["FENTON_GALLERY": "home", "FENTON_GALLERY_SCENARIO": String(repeating: "x", count: 1_025)]] {
            #expect(throws: GalleryFixtureLaunch.Failure.invalidConfiguration) {
                try GalleryFixtureLaunch.Configuration(id: "home", variables: variables).validate()
            }
        }

        #expect(throws: GalleryFixtureLaunch.Failure.invalidConfiguration) {
            try GalleryFixtureLaunch.Configuration(id: "../home", variables: ["FENTON_GALLERY": "home"]).validate()
        }
        #expect(throws: GalleryFixtureLaunch.Failure.oversizedConfiguration) {
            try GalleryFixtureLaunch.decode(Data(repeating: 32, count: 65_537))
        }
    }

    @Test(arguments: [-1.0, Double.infinity, Double.nan, 253_402_300_800.0])
    func refusesUnrepresentableReferenceTimes(_ time: TimeInterval) {
        #expect(throws: GalleryFixtureLaunch.Failure.invalidConfiguration) {
            try GalleryFixtureLaunch.Configuration(id: "home", variables: ["FENTON_GALLERY": "home"],
                                                   referenceTime: time).validate()
        }
    }

    @Test func malformedBootstrapRemovesOldSuccessReceiptBeforeFailing() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("GalleryFixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        let receipt = directory.appendingPathComponent("receipt.json")
        try Data(#"{"status":"prepared","fixtureID":"old"}"#.utf8).write(to: receipt)
        try Data(#"{"id":"invalid","variables":{"FENTON_HASS_TOKEN":"test-only"}}"#.utf8)
            .write(to: directory.appendingPathComponent("bootstrap.json"))
        #expect(throws: GalleryFixtureLaunch.Failure.invalidConfiguration) {
            try GalleryFixtureLaunch.prepare(at: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: receipt.path))
    }
}
