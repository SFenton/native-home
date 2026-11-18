@testable import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - The Version row the preferences provider builds

/// The About section of Settings reaches the screen through `UKServerUIPreferencesProvider`. This test builds the row the way the page
/// does, so a change to the provider's wiring (value, spoken value, hint, glyph, copy) fails here and not on a device.
@MainActor
final class ServerUIVersionWiringHostedTests: DemoHouseTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// The version control as a publication authors it.
    private func versionControl() -> ServerUISettingsControl {
        ServerUISettingsControl(node: .init(id: "app-version", title: "Version", span: 1), sourceId: "preferences", kind: .version,
                                item: "", subtitle: "",
                                icon: .init(name: "info.circle", rendering: .canonical, unavailable: .fallback), destination: nil)
    }

    /// UX and accessibility: the provider's Version row shows the build text, reads the spoken version, carries the copy hint and the
    /// `info.circle` glyph with no chevron, and a tap copies the build text.
    func testThePreferencesProviderBuildsTheVersionRowFromTheAboutModel() throws {
        var copied: [String] = []
        let about = AboutSettingsModel(info: ["CFBundleShortVersionString": "1.4.2", "CFBundleVersion": "318"], pasteboard: { copied.append($0) })
        let icons = AppIconPlatform(supportsAlternateIcons: { false }, currentName: { nil }, setName: { _ in })
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "version-wiring-\(UUID().uuidString)"))
        let provider = UKServerUIPreferencesProvider(id: "preferences", blur: BackdropBlurSettings(defaults: defaults),
                                                     icons: AppIconPickerModel(platform: icons), about: about, defaults: defaults,
                                                     isCurrentSession: { true })
        let (renderer, window, _) = try ServerUIRendererFixture.host()
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(renderer)
        let atom = UKServerUISettingsAtom()
        let made = try provider.make(versionControl(), host: atom, page: page)
        let row = try XCTUnwrap(made as? UKServerUIPreferenceRow)
        atom.install(row, identifier: "app-version")
        HostedPage.wait(0.05)
        XCTAssertEqual(row.value, about.text)
        XCTAssertEqual(row.accessibilityValue, about.spokenText, "VoiceOver reads the spoken version")
        XCTAssertEqual(row.accessibilityHint, AboutSettingsModel.copyHint)
        XCTAssertEqual(row.row.rowContent.symbol, "info.circle")
        XCTAssertFalse(row.row.rowContent.showsChevron)
        XCTAssertTrue(row.accessibilityTraits.contains(.button))
        row.onTap?()
        XCTAssertEqual(copied, [about.text], "a tap copies the build text, not the spoken form")
    }
}
