import HassCore
import UIKit
import XCTest
@testable import HassUI

/// What the sign-in screen's column-to-split switch costs (`.agents/design/sign-in-layout.md`; `.agents/testing/apple/performance.md`,
/// Layout changes).
///
/// A regular window is resized between a narrow and a wide size, so the screen switches between one column and two regions: the same
/// views glide with `MotionTokens.standard` (`quick` under Reduce Motion). Each switch is one `LayoutChange` interval (page
/// `SignIn.layout`, which ends at the token's due time). Metrics: `XCTCPUMetric` and `XCTOSSignpostMetric` on `LayoutChange`. `tools/ios_motionperf.sh` runs it on each
/// family's simulator; the simulator's numbers are for comparison, not for hitches.
@MainActor
final class UKHostedSignInLayoutPerformanceTests: XCTestCase {
    private static let narrow = CGSize(width: 520, height: 800)
    /// Wide enough to split on every family, the Duo's 84 pt side strip included (each half must clear 360 pt): the Duo's landscape window.
    private static let wide = CGSize(width: 951, height: 669)
    private static let switchesPerIteration = 6

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        try await super.tearDown()
    }

    func testColumnSplitSwitchCost() throws { try measureSwitches(reduceMotion: false) }

    func testColumnSplitSwitchCostReduceMotion() throws { try measureSwitches(reduceMotion: true) }

    // MARK: Private

    private func measureSwitches(reduceMotion: Bool) throws {
        UKMotion.reduceMotionOverride = reduceMotion
        let defaults = UserDefaults(suiteName: "hosted.signin.perf.\(UUID().uuidString)")!
        let model = LoginModel(mode: .fresh, store: RememberedAccountStore(defaults: defaults), defaultServer: "https://ha.example.com")
        let environment = UKShellEnvironment()
        let page = UKLoginViewController(model: model, playsIntro: false, environment: environment, onIntroPlayed: {}, onUseDifferentAccount: {}, onSignedIn: { _, _ in })
        let window = HostedPage.show(page, size: Self.narrow)
        defer { window.isHidden = true; withExtendedLifetime(environment) {} }
        window.traitOverrides.horizontalSizeClass = .regular
        RunLoop.main.run(until: Date().addingTimeInterval(0.6)) // appeared: later switches animate
        page.view.layoutIfNeeded()
        func element(_ id: String) -> UIView? { HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == id } }
        /// The header beside the form (wide) or above it (narrow), the check the hosted login tests make.
        func isSplit() -> Bool? {
            guard let header = element("login.title")?.superview, let fields = element("login.fields") else { return nil }
            let headerBox = header.convert(header.bounds, to: page.view), fieldsBox = fields.convert(fields.bounds, to: page.view)
            if headerBox.maxX < fieldsBox.minX { return true }
            if headerBox.maxY < fieldsBox.minY + 1 { return false }
            return nil
        }
        var isWide = false

        func flip() {
            isWide.toggle()
            let size = isWide ? Self.wide : Self.narrow
            window.frame = CGRect(origin: .zero, size: size)
            page.view.frame = CGRect(origin: .zero, size: size)
            window.layoutIfNeeded()
            page.view.layoutIfNeeded()
            // The glide (0.3 s, 0.2 s under Reduce Motion) and the interval's end land within this wait.
            RunLoop.main.run(until: Date().addingTimeInterval(reduceMotion ? 0.35 : 0.5))
            XCTAssertEqual(isSplit(), isWide, "the flip to \(Int(size.width)) pt switched the layout: the header is \(isWide ? "beside" : "above") the form")
        }

        flip(); flip() // warm up
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let signpost = XCTOSSignpostMetric(subsystem: "com.sfenton.home", category: "Performance", name: "LayoutChange")
        measure(metrics: [XCTCPUMetric(), signpost], options: options) {
            for _ in 0..<Self.switchesPerIteration { flip() }
        }
    }
}
