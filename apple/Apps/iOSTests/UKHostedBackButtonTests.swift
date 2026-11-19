@testable import HassCore
import HassDesign
import ObjectiveC.runtime
import UIKit
import XCTest
@testable import HassUI

/// Back is the system chevron with no title beside it, on every page class (`navigationItem.backButtonDisplayMode = .minimal`, set once in
/// ``UKPageViewController``; HIG, Navigation bars). The spoken name is read in the PageTitleJourneyTests accessibility journeys: a hosted test cannot see the label UIKit adds.
///
/// Every test runs on iPhone, iPhone Duo and iPad (the hosted pass runs once per family) and needs no environment.
@MainActor
final class UKHostedBackButtonTests: DemoHouseTestCase {
    private var scene: LogicScene?

    override func tearDown() async throws {
        scene?.close()
        scene = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    private func sheetContext() -> UKContext { UKGalleryChrome.context().with { $0.surface = .sheet } }

    /// Pages that build with no arguments beyond a context, one per way the base is reached.
    private func makePages() -> [(name: String, page: UKPageViewController)] {
        let context = UKGalleryChrome.context()
        return [
            ("UKPageViewController(context:)", UKPageViewController(context: context, title: "Climate")),
            ("UKPageViewController(sheetTitle:)", UKPageViewController(sheetTitle: "Details")),
            ("UKPageHost", UKPageHost(child: UIViewController(), context: context)),
            ("UKFormViewController", UKFormViewController()),
            ("UKSheetColumnViewController", UKSheetColumnViewController(maxWidth: 500)),
            ("UKSheetPinnedBarPage", UKSheetPinnedBarPage(content: UIViewController(), bar: nil)),
            ("UKHouseholdSheetContentController", UKHouseholdSheetContentController(content: UIView())),
            ("HostedScrollPage", HostedScrollPage(context: context, title: "Scroll")),
        ]
    }

    /// Every class in the HassUI image that descends from ``UKPageViewController``, by name.
    private func pageClassNames() -> Set<String> {
        var names: Set<String> = []
        for image in [Bundle(for: UKPageViewController.self)] {
            guard let path = image.executablePath else { continue }
            var count: UInt32 = 0
            guard let list = objc_copyClassNamesForImage(path, &count) else { continue }
            defer { free(UnsafeMutableRawPointer(mutating: list)) }
            for index in 0..<Int(count) {
                guard let cls = NSClassFromString(String(cString: list[index])), cls != UKPageViewController.self else { continue }
                var parent: AnyClass? = class_getSuperclass(cls)
                while let current = parent {
                    if current == UKPageViewController.self { names.insert(String(cString: class_getName(cls))); break }
                    parent = class_getSuperclass(current)
                }
            }
        }
        return names.union(["UKPageViewController"])
    }

    // MARK: Display mode

    func testEveryPageClassAsksForTheMinimalBackButton() {
        for (name, page) in makePages() {
            page.loadViewIfNeeded()
            XCTAssertEqual(page.navigationItem.backButtonDisplayMode, .minimal, "\(name) shows the chevron alone")
        }
    }

    func testEveryClassUnderThePageBaseIsNamedHere() {
        let covered: Set<String> = [
            "UKPageViewController", "UKPageHost", "UKFormViewController", "UKSheetColumnViewController", "UKSheetPinnedBarPage",
            "UKHouseholdSheetContentController", "HostedScrollPage", "UKServerUIPage",
            // Built with services this test does not own; they inherit `viewDidLoad` and set no display mode of their own.
            "UKHomeAssistantWebPageViewController", "UKCameraViewerViewController", "UKSetupStepPageViewController",
            "UKCustomLightSheetViewController", "UKLocationPermissionViewController", "UKDeviceSheetPage", "UKGrillPage",
            "UKNotificationSetupStepViewController", "UKTimeSensitiveSetupStepViewController", "UKScanItemViewController",
            "UKVacationSubpageViewController",
        ]
        let found = Set(pageClassNames().map { $0.split(separator: ".").last.map(String.init) ?? $0 }
            .filter { !$0.contains("Gallery") && !$0.hasPrefix("UKBackdropOnly") && !$0.hasPrefix("NSKVO") })
        let unnamed = found.subtracting(covered)
        XCTAssertTrue(unnamed.isEmpty, "a new page class needs a line here and a check that it keeps the base's mode: \(unnamed.sorted())")
    }

    func testAComposedServerPageAsksForTheMinimalBackButton() throws {
        var document = LogicDocument()
        document.sources = [("a0", LogicHouse.watched(0))]
        document.tabs = [.init(id: "a", nodes: [LogicDocument.stateText("a0", source: "a0")])]
        let made = try LogicScene(document: document, house: LogicHouse.entities(watched: 1))
        scene = made
        let page = try made.page("a")
        XCTAssertEqual(page.navigationItem.backButtonDisplayMode, .minimal)
    }
}
