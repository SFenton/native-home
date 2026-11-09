import FentonActivityModel
import HassCore
import HassDesign
import HassTelemetry
import UIKit
import XCTest
@testable import HassUI

/// More of the Settings tab, hosted: what the list offers, the calls its rows make, and the Settings sheets.
extension UKHostedSettingsTests {
    private func settingsPage(signedIn: Bool = false) throws -> (UKSettingsViewController, UKContext, AppSession?) {
        if signedIn {
            let host = try FeatureHost.signedIn()
            var context = host.context
            context.push = host.session.push
            return (UKSettingsViewController(context: context), context, host.session)
        }
        let context = UKGalleryChrome.context()
        return (UKSettingsViewController(context: context), context, nil)
    }

    func testSettingsOffersEveryTopicInOrder() throws {
        let (page, _, _) = try settingsPage()
        let ids = page.sections().map(\.id)
        XCTAssertEqual(ids.first, "top")
        XCTAssertTrue(ids.contains("appearance"))
        XCTAssertEqual(ids.suffix(5), ["household", "homeAssistant", "performance", "feedback", "about"])
        let sections = page.sections()
        let topics = sections.first { $0.id == "household" }?.rows ?? []
        XCTAssertEqual(topics.count, HouseholdSettingsPage.allCases.count)
        XCTAssertEqual(sections.first { $0.id == "feedback" }?.rows.count, FeedbackKind.allCases.count)
    }

    func testAdminTodoIsHiddenFromSam() throws {
        let defaults = UserDefaults.standard
        let before = defaults.string(forKey: ChoresModel.viewerDefaultsKey)
        defer { defaults.set(before, forKey: ChoresModel.viewerDefaultsKey) }
        defaults.set(ChoresConfig.Resident.resident2.haUserId, forKey: ChoresModel.viewerDefaultsKey)
        let sam = try settingsPage().0
        let window = HostedPage.show(UKGalleryChrome.wrap(sam, context: UKGalleryChrome.context()))
        defer { window.isHidden = true }
        XCTAssertNil(UKSettingsListRow.find("todo", in: sam.sections()), "Sam does not see the admin To-Do")

        defaults.set(ChoresConfig.Resident.resident1.haUserId, forKey: ChoresModel.viewerDefaultsKey)
        FeatureHost.settle()
        XCTAssertNotNil(UKSettingsListRow.find("todo", in: sam.sections()), "Alex does")
        XCTAssertNotNil(FeatureHost.view("settings.todo", in: sam.view), "and the list redraws when the viewer changes")
    }

    func testBadgeToggleWritesTheDefault() throws {
        let (page, context, _) = try settingsPage()
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: AppIconBadgeSync.enabledKey)
        defer { if let before { defaults.set(before, forKey: AppIconBadgeSync.enabledKey) } else { defaults.removeObject(forKey: AppIconBadgeSync.enabledKey) } }
        defaults.set(true, forKey: AppIconBadgeSync.enabledKey)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.flip("settings.iconBadge", in: page.view))
        XCTAssertEqual(defaults.object(forKey: AppIconBadgeSync.enabledKey) as? Bool, false)
        FeatureHost.settle()
        XCTAssertEqual((FeatureHost.view("settings.iconBadge", in: page.view) as? UISwitch)?.isOn, false, "the list redraws with the new state")
    }

    func testBlurResetIsOffUntilTheSliderMoves() throws {
        var context = UKGalleryChrome.context()
        context.backdrop = HouseBackdropStore(
            server: HassServer(baseURL: URL(string: "https://gallery.invalid")!),
            directory: FileManager.default.temporaryDirectory.appending(path: "blur-\(UUID())"),
            blur: BackdropBlurSettings(defaults: UserDefaults(suiteName: "blur-\(UUID())")!),
            photos: { _ in AsyncStream { $0.finish() } })
        let page = UKSettingsViewController(context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        let blur = try XCTUnwrap(context.backdrop?.blur)
        blur.reset()
        FeatureHost.settle()
        XCTAssertEqual(UKSettingsListRow.find("blur.reset", in: page.sections())?.isEnabled, false)
        blur.sliderValue = 0.9
        FeatureHost.settle()
        let reset = try XCTUnwrap(UKSettingsListRow.find("blur.reset", in: page.sections()))
        XCTAssertTrue(reset.isEnabled, "Reset to Default turns on once the blur is off its default")
        reset.action?()
        XCTAssertTrue(blur.isDefault)
        FeatureHost.settle()
        XCTAssertEqual(UKSettingsListRow.find("blur.reset", in: page.sections())?.isEnabled, false)
    }

    func testVersionRowCopiesAndSaysSo() throws {
        let (page, context, _) = try settingsPage()
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        let row = try XCTUnwrap(UKSettingsListRow.find("version", in: page.sections()))
        row.action?()
        FeatureHost.settle()
        XCTAssertFalse(UIPasteboard.general.string?.isEmpty ?? true, "the version is on the clipboard")
        let footer = FeatureHost.view("settings.version.footer", in: page.view)
        XCTAssertNotNil(footer)
    }

    func testRowsPushMarkerPagesInTheGallery() throws {
        let (page, context, _) = try settingsPage()
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        UKSettingsListRow.find("vacation", in: page.sections())?.action?()
        FeatureHost.settle(0.8)
        let navigation = page.navigationController
        XCTAssertEqual(navigation?.viewControllers.count, 2, "Vacation pushed a page")
        XCTAssertNotNil(FeatureHost.view("settings.gallery.pushed", in: navigation!.topViewController!.view))
        navigation?.popViewController(animated: false)
        FeatureHost.settle(0.4)
        UKSettingsListRow.find("performance", in: page.sections())?.action?()
        FeatureHost.settle(0.8)
        XCTAssertEqual(navigation?.viewControllers.count, 2, "and so did Performance")
    }

    func testHomeAssistantAndFeedbackRowsOpenSheetsWhenSignedIn() throws {
        let (page, context, _) = try settingsPage(signedIn: true)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        UKSettingsListRow.find("homeAssistant", in: page.sections())?.action?()
        FeatureHost.settle(0.6)
        XCTAssertNotNil(page.shownSheet, "Home Assistant opens its modal")
    }

    func testFeedbackRowsOpenTheirFormsWhenSignedIn() throws {
        let (page, context, _) = try settingsPage(signedIn: true)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        UKSettingsListRow.find("feedback.bug", in: page.sections())?.action?()
        FeatureHost.settle(0.6)
        let presented = page.shownSheet
        XCTAssertNotNil(presented, "Report an Issue opens its sheet")
    }

    func testASplitWindowOpensPagesBesideTheList() throws {
        let (page, context, _) = try settingsPage()
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        window.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        FeatureHost.settle(0.8)
        XCTAssertTrue(page.columns.isWide, "an iPad-landscape window splits")
        XCTAssertNotNil(FeatureHost.view("settings.pane.placeholder", in: page.view), "the right column asks for a pick")
        UKSettingsListRow.find("performance", in: page.sections())?.action?()
        FeatureHost.settle(0.8)
        XCTAssertEqual(page.columns.entries.count, 1, "Performance opens in the right column")
        UKSettingsListRow.find("vacation", in: page.sections())?.action?()
        FeatureHost.settle(0.8)
        XCTAssertEqual(page.columns.entries.count, 1, "the first column's rows replace what is open")
    }

    func testNotificationRowsForEachPermission() {
        var opened: [URL] = []
        var turnedOn = 0
        func section(_ auth: PushAuthorization, _ sensitive: TimeSensitiveSetting) -> UKSettingsListSection {
            UKNotificationsSettings.section(authorization: auth, timeSensitive: sensitive, turnOn: { turnedOn += 1 }, openURL: { opened.append($0) })
        }
        let ask = section(.notDetermined, .notSupported)
        XCTAssertEqual(ask.rows.map(\.id), ["notifications.turnOn"])
        XCTAssertNotNil(ask.footer, "the unasked state keeps its reason")
        ask.rows[0].action?()
        XCTAssertEqual(turnedOn, 1)

        let denied = section(.denied, .notSupported)
        XCTAssertEqual(denied.rows.map(\.id), ["notifications.openSettings"])
        denied.rows[0].action?()
        XCTAssertEqual(opened.count, 1)

        let granted = section(.granted, .enabled)
        XCTAssertEqual(granted.rows.map(\.id), ["notifications", "notifications.timeSensitive"])
        XCTAssertNil(granted.footer)
        granted.rows.forEach { $0.action?() }
        XCTAssertEqual(opened.count, 3)
        XCTAssertEqual(section(.granted, .disabled).rows.count, 2)
        XCTAssertEqual(section(.granted, .notSupported).rows.map(\.id), ["notifications"], "no Time Sensitive row where the system has none")
    }

    func testNotificationsSectionShowsOnTheListWithAPushCoordinator() throws {
        let (page, context, _) = try settingsPage(signedIn: true)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context))
        defer { window.isHidden = true }
        XCTAssertTrue(page.sections().contains { $0.id == "notifications" })
        XCTAssertTrue(FeatureHost.identifiers(in: page.view).contains { $0.hasPrefix("settings.notifications") })
        let shared = UKNotificationsSettings.section(push: try XCTUnwrap(context.push))
        XCTAssertEqual(shared.id, "notifications")
    }
}

// MARK: - App icon

@MainActor
final class UKHostedAppIconTests: DemoHouseTestCase {
    private final class Recorder: @unchecked Sendable {
        var names: [String?] = []
        var current: String?
        var fail = false
    }

    private func model(_ recorder: Recorder) -> AppIconPickerModel {
        AppIconPickerModel(
            platform: AppIconPlatform(
                supportsAlternateIcons: { true }, currentName: { recorder.current },
                setName: { name in
                    recorder.names.append(name)
                    if recorder.fail { throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not allowed"]) }
                    recorder.current = name
                }),
            iconStore: ActivityAppIconStore(defaults: UserDefaults(suiteName: "appicon-\(UUID())")!))
    }

    func testPickerListsEveryIconAndMarksTheInstalledOne() throws {
        let recorder = Recorder()
        let page = UKAppIconPickerViewController(model: model(recorder))
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1400))
        defer { window.isHidden = true }
        let ids = FeatureHost.identifiers(in: page.view)
        for choice in AppIconChoice.allCases { XCTAssertTrue(ids.contains("appIcon.choice.\(choice.rawValue)"), "\(choice) is offered") }
        let installed = try XCTUnwrap(FeatureHost.view("appIcon.choice.\(AppIconChoice.default.rawValue)", in: page.view))
        XCTAssertTrue(installed.accessibilityTraits.contains(.selected))
        XCTAssertTrue(installed.accessibilityLabel?.hasSuffix("default") ?? false)
        XCTAssertTrue(HostedPage.labels(in: page.view).contains(UKAppIconPickerViewController.footerText))
    }

    func testChoosingAnIconInstallsIt() throws {
        let recorder = Recorder()
        let page = UKAppIconPickerViewController(model: model(recorder))
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1400))
        defer { window.isHidden = true }
        let other = try XCTUnwrap(AppIconChoice.allCases.first { !$0.isDefault })
        XCTAssertTrue(FeatureHost.tapRow("appIcon.choice.\(other.rawValue)", in: page.view))
        FeatureHost.settle(0.4)
        XCTAssertEqual(recorder.names, [other.alternateIconName])
        let chosen = FeatureHost.view("appIcon.choice.\(other.rawValue)", in: page.view)
        XCTAssertTrue(chosen?.accessibilityTraits.contains(.selected) ?? false, "the chosen icon is checked")
    }

    func testARefusedChangeExplainsItself() throws {
        let recorder = Recorder()
        recorder.fail = true
        let page = UKAppIconPickerViewController(model: model(recorder))
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1400))
        defer { window.isHidden = true }
        let other = try XCTUnwrap(AppIconChoice.allCases.first { !$0.isDefault })
        FeatureHost.tapRow("appIcon.choice.\(other.rawValue)", in: page.view)
        FeatureHost.settle(0.6)
        let alert = try XCTUnwrap(FeatureHost.alert(on: page))
        XCTAssertEqual(alert.title, "Couldn't Change Icon")
        XCTAssertTrue(alert.message?.contains("Not allowed") ?? false)
        FeatureHost.answer(alert, "OK")
        FeatureHost.settle()
    }

    func testPresentedFromTheSettingsRowUsesASheet() throws {
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        UKAppIconPickerViewController.present(model: model(Recorder()), from: host)
        FeatureHost.settle(0.6)
        XCTAssertNotNil(host.presentedViewController)
    }
}

// MARK: - Performance

@MainActor
final class UKHostedPerformanceTests: DemoHouseTestCase {
    override func setUp() {
        super.setUp()
        // The framework's own telemetry log (the test bundle's HassTelemetry is a separate copy): scroll three pages through the monitor.
        let monitor = FrameMonitor.shared
        for (page, frames) in [("Home", [8.0, 8, 8, 8]), ("Rooms", [30.0, 30, 30, 8]), ("Food", [90.0, 8])] {
            monitor.beginScroll(page: page)
            for frame in frames { monitor.record(frameMs: frame, budgetMs: 16.7) }
            monitor.endScroll(page: page)
        }
    }

    private func page() -> (UKPerformanceViewController, UIWindow) {
        let context = UKGalleryChrome.context()
        let page = UKPerformanceViewController(context: context)
        let window = HostedPage.show(UKGalleryChrome.wrap(page, context: context), size: CGSize(width: 393, height: 3200))
        FeatureHost.settle(0.6)
        return (page, window)
    }

    func testShowsMeasuredRowsWithTheirTone() throws {
        let (page, window) = page()
        defer { window.isHidden = true }
        let texts = HostedPage.labels(in: page.view).joined(separator: "|")
        XCTAssertTrue(texts.contains("Home"), "scroll rows name their page")
        XCTAssertTrue(texts.contains("Deliveries"))
        let sections = page.sections()
        XCTAssertEqual(sections.map(\.id), ["recording", "scrolling", "loading", "navigation", "live", "actions", "images", "export"])
        XCTAssertNotNil(UKSettingsListRow.find("scroll.2", in: sections), "three pages scrolled")
    }

    func testRecordingToggleSwitchesTelemetry() throws {
        let (page, window) = page()
        defer { window.isHidden = true }
        let key = Telemetry.enabledDefaultsKey
        let before = UserDefaults.standard.object(forKey: key)
        defer { if let before { UserDefaults.standard.set(before, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        XCTAssertTrue(FeatureHost.flip("performance.recording", in: page.view))
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, false, "Record Telemetry off is remembered")
        XCTAssertTrue(FeatureHost.flip("performance.recording", in: page.view))
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, true)
    }

    func testResetAsksFirstThenClearsTheMeasurements() throws {
        let (page, window) = page()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.tapRow("performance.reset", in: page.view))
        FeatureHost.settle(0.4)
        let alert = try XCTUnwrap(FeatureHost.alert(on: page), "Reset Measurements confirms first")
        XCTAssertEqual(alert.title, AlertCopy.resetMeasurements.title)
        FeatureHost.answer(alert, AlertCopy.resetMeasurements.confirm.title)
        FeatureHost.settle(0.6)
        XCTAssertTrue(HostedPage.labels(in: page.view).contains("Scroll a page to measure it."))
    }

    func testClearImageCacheAndRefreshAndExport() throws {
        let (page, window) = page()
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.tapRow("performance.clearImages", in: page.view))
        FeatureHost.settle(0.5)
        XCTAssertNotNil(FeatureHost.view("performance.export", in: page.view), "the export row appears once the file is written")
        XCTAssertTrue(FeatureHost.tapRow("performance.export", in: page.view))
        FeatureHost.settle(0.6)
        FeatureHost.expectSystemPresentation(page.shownSheet, "Export opens the share sheet")
        let refresh = try XCTUnwrap(page.navigationItem.leftBarButtonItem)
        XCTAssertEqual(refresh.accessibilityIdentifier, "performance.refresh")
        _ = refresh.primaryAction?.title
    }
}
