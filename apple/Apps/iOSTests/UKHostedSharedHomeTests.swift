import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Home on an unfolded Duo in landscape (two columns on the hinge) and the hand-offs from its chips and camera cards.
@MainActor
final class UKHostedSharedHomeTests: DemoHouseTestCase {
    private func home(hinge: CGRect? = nil, cameras: Bool = true) -> (UKHomeViewController, UKShellEnvironment, GalleryServiceRecorder) {
        let store = HomeFixtures.store(environment: [:])
        let recorder = GalleryServiceRecorder(store: store)
        let shell = UKShellEnvironment()
        shell.windowHinge = hinge
        var context = UKGalleryChrome.context(store: store, caller: recorder)
        context.shell = shell
        var configuration = UKHomeConfiguration()
        if !cameras { configuration.parts.remove(.cameras) }
        configuration.weatherStore = WeatherForecastStore(requestTimeout: 3600)
        configuration.weatherCaller = WeatherFixtureCaller(mode: .normal)
        configuration.caller = recorder
        return (UKHomeViewController(context: context, configuration: configuration), shell, recorder)
    }

    private func first<T: UIView>(_ type: T.Type, in root: UIView) -> T? { HostedPage.descendants(of: root).first { $0 is T } as? T }

    func testAHingeSplitsHomeIntoChipsAndWeatherOnTheLeadingSideAndCamerasOnTheOther() {
        let hinge = CGRect(x: 500, y: 0, width: 24, height: 700)
        let (page, shell, _) = home(hinge: hinge)
        let window = HostedPage.show(page, size: CGSize(width: 1024, height: 700))
        defer { window.isHidden = true }
        window.traitOverrides.horizontalSizeClass = .regular
        page.view.setNeedsLayout()
        HostedPage.wait(0.4)
        HostedPage.layoutTracked()

        let weather = first(UKWeatherCardView.self, in: page.view)
        let cameras = first(UKCameraGridSectionView.self, in: page.view)
        XCTAssertNotNil(weather)
        XCTAssertNotNil(cameras)
        if let weather, let cameras {
            XCTAssertLessThanOrEqual(weather.convert(weather.bounds, to: nil).maxX, hinge.minX + 1, "weather stays left of the hinge")
            XCTAssertGreaterThanOrEqual(cameras.convert(cameras.bounds, to: nil).minX, hinge.maxX - 1, "cameras stay right of the hinge")
        }

        shell.windowHinge = nil
        HostedPage.wait(0.4)
        HostedPage.layoutTracked()
        if let weather, let cameras {
            XCTAssertEqual(weather.convert(weather.bounds, to: nil).minX, cameras.convert(cameras.bounds, to: nil).minX, accuracy: 40,
                           "without the hinge both sections share one column again")
        }
    }

    func testTappingACameraHandsItToTheViewerAndTheSecurityChipOpensTheAlarmSheet() {
        let (page, _, _) = home()
        let originalCamera = UKHomeHooks.cameraViewer
        let originalSecurity = UKHomeHooks.securitySystemSheet
        defer { UKHomeHooks.cameraViewer = originalCamera; UKHomeHooks.securitySystemSheet = originalSecurity }
        var opened: [String] = []
        UKHomeHooks.cameraViewer = { camera, _, _, _ in opened.append(camera.title) }
        var sheetBuilt = 0
        let sheet = UIViewController()
        sheet.title = "Alarm"
        UKHomeHooks.securitySystemSheet = { _, _ in sheetBuilt += 1; return sheet }

        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        HostedPage.wait(0.3)
        let tiles = HostedPage.descendants(of: page.view).compactMap { $0 as? UKCameraTileView }
        XCTAssertEqual(tiles.count, HomeConfig.cameras.count)
        tiles.first?.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened, ["Front Door"], "the tapped camera opens in the viewer")

        let chip = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "home.chip.security" } as? UKStatusChipView
        XCTAssertNotNil(chip)
        chip?.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until { sheet.presentingViewController != nil || sheet.view.window != nil },
                      "the Security chip presents the alarm controls")
        XCTAssertEqual(sheetBuilt, 1)
    }

    func testTheLightsChipOpensTheRoomOverview() {
        let (page, _, _) = home(cameras: false)
        let window = HostedPage.show(page)
        defer { window.isHidden = true }
        HostedPage.wait(0.3)
        let chip = HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == "home.chip.lights" } as? UKStatusChipView
        chip?.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until { page.presentedViewController != nil }, "the chip presents a sheet")
        HostedPage.wait(0.5)
        let labels = HostedPage.labels(in: page.presentedViewController?.view ?? UIView())
        XCTAssertTrue(labels.contains { $0.localizedCaseInsensitiveContains("light") }, "the sheet is the lights overview; saw \(labels.prefix(8))")
    }
}
