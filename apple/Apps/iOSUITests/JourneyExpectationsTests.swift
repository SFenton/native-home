import XCTest

/// The expectations layer itself: the DemoHouse table is complete, the shipped template matches it, a live run without the
/// private file skips, and a private file overrides only the keys it names. No app launches.
final class JourneyExpectationsTests: XCTestCase {
    private func templateData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("JourneyExpectations.template.json")
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw XCTSkip("The template is not readable from the test host")
        }
        return data
    }

    func testEveryKeyHasADemoValue() {
        for key in JourneyExpectations.Key.allCases {
            XCTAssertNotNil(JourneyExpectations.demoValues[key], key.rawValue)
        }
        XCTAssertEqual(JourneyExpectations.demoValues.count, JourneyExpectations.Key.allCases.count)
    }

    func testTemplateCarriesTheDemoValuesAndAComment() throws {
        let data = try templateData()
        XCTAssertEqual(try JourneyExpectations.decode(data), JourneyExpectations.demoValues)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let comments = try XCTUnwrap(object["comments"] as? [String: String])
        for key in JourneyExpectations.Key.allCases {
            XCTAssertFalse((comments[key.rawValue] ?? "").isEmpty, "\(key.rawValue) has no comment in the template")
        }
    }

    func testGalleryIsDemoWithoutAnyEnvironment() throws {
        let expectations = try JourneyExpectations.current(for: .gallery, environment: [:])
        XCTAssertTrue(expectations.isDemo)
        XCTAssertEqual(expectations[.climateHub], JourneyExpectations.demoValues[.climateHub])
    }

    func testSignedInWithoutTheFileOrTheTestInstanceSkips() {
        XCTAssertThrowsError(try JourneyExpectations.current(for: .signedIn, environment: ["FENTON_HASS_SERVER": "https://live.example"])) {
            XCTAssertTrue($0 is XCTSkip, "\($0)")
        }
    }

    func testSignedInOnTheTestInstanceUsesDemo() throws {
        let byServer = try JourneyExpectations.current(for: .signedIn, environment: ["FENTON_HASS_SERVER": "https://test.example", "HASS_TEST_SERVER": "https://test.example"])
        XCTAssertTrue(byServer.isDemo)
        let byFlag = try JourneyExpectations.current(for: .signedIn, environment: ["FENTON_JOURNEY_TARGET": "demo"])
        XCTAssertTrue(byFlag.isDemo)
    }

    /// An empty or unset `HASS_TEST_SERVER` must never equal the signed-in server, or the owner's house would read as the test instance.
    func testEmptyOrUnsetTestServerIsNotTheTestInstance() {
        for environment in [["FENTON_HASS_SERVER": "https://live.example", "HASS_TEST_SERVER": ""], ["FENTON_HASS_SERVER": "", "HASS_TEST_SERVER": ""], ["FENTON_HASS_SERVER": "https://live.example"], [:]] {
            XCTAssertFalse(JourneyExpectations.onTestInstance(environment), "\(environment)")
            XCTAssertThrowsError(try JourneyExpectations.current(for: .signedIn, environment: environment)) { XCTAssertTrue($0 is XCTSkip, "\($0)") }
        }
    }

    /// A private set answers only what it names; the DemoHouse table never fills a gap in it.
    func testPrivateSetDoesNotFallBackToDemoValues() throws {
        let file = Data(#"{"values": {"climateHub": "climate.demo_override"}}"#.utf8)
        let expectations = try JourneyExpectations.current(for: .signedIn, environment: [JourneyExpectations.fileVariable: "/private/file"], contents: { _ in file })
        XCTAssertEqual(expectations[.climateHub], "climate.demo_override")
        XCTAssertNil(expectations.values[.securityAlarm])
    }

    func testPrivateFileOverridesOnlyTheKeysItNames() throws {
        let file = Data(#"{"values": {"climateHub": "climate.demo_override", "unknownKey": "ignored"}}"#.utf8)
        let expectations = try JourneyExpectations.current(for: .signedIn, environment: [JourneyExpectations.fileVariable: "/private/file"], contents: { _ in file })
        XCTAssertFalse(expectations.isDemo)
        XCTAssertEqual(try expectations.value(.climateHub), "climate.demo_override")
        XCTAssertThrowsError(try expectations.value(.securityAlarm)) { XCTAssertTrue($0 is XCTSkip, "\($0)") }
    }

    func testUnreadablePrivateFileSkips() {
        XCTAssertThrowsError(try JourneyExpectations.current(for: .signedIn, environment: [JourneyExpectations.fileVariable: "/missing"], contents: { _ in nil })) {
            XCTAssertTrue($0 is XCTSkip, "\($0)")
        }
    }

    func testTintParsesAsAnRGBTriple() {
        let tint = JourneyExpectations.gallery.rgb(.choresFirstLinkTint)
        XCTAssertEqual([tint.0, tint.1, tint.2], [0, 96, 120])
    }
}
