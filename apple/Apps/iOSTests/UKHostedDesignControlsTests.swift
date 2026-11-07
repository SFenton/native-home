import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Small design controls used across pages: the controller picker and stepper, the page dots and the paged row, the schedule
/// date pickers' delayed commit, the percent slider's accessibility actions, the pending bar and the climate dial's commit path.
@MainActor
final class UKHostedDesignControlsTests: DemoHouseTestCase {
    private func host(_ view: UIView, size: CGSize = CGSize(width: 393, height: 600)) -> UIWindow {
        let controller = UIViewController()
        let window = HostedPage.show(controller, size: size)
        controller.view.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            view.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
        ])
        controller.view.layoutIfNeeded()
        return window
    }

    // MARK: Controller picker and stepper

    func testPickerShowsItsSelectionAndMenuSendsTheChosenOption() {
        var sent: [String] = []
        let picker = UKControllerPicker("Fan", options: ["auto", "on", "off"], optionTitle: { $0.capitalized }, selection: "auto") { sent.append($0) }
        let window = host(picker)
        defer { window.isHidden = true }
        XCTAssertEqual(picker.accessibilityLabel, "Fan")
        XCTAssertEqual(picker.accessibilityValue, "Auto")
        XCTAssertEqual(picker.configuration?.title, "Auto")
        let actions = picker.menu?.children.compactMap { $0 as? UIAction } ?? []
        XCTAssertEqual(actions.map(\.title), ["Auto", "On", "Off"])
        XCTAssertEqual(actions.map(\.state), [.on, .off, .off], "the current choice is ticked")
        (actions[1] as UIAction).performWithSender(nil, target: nil)
        XCTAssertEqual(sent, ["on"], "choosing sends the option")
        picker.show("off")
        XCTAssertEqual(picker.accessibilityValue, "Off")
        XCTAssertEqual((picker.menu?.children.compactMap { $0 as? UIAction } ?? []).map(\.state), [.off, .off, .on])
    }

    func testStepperShowsTheValueAndSendsTheRequestedOne() {
        var sent: [Int] = []
        let stepper = UKControllerStepper(value: 70, in: 50...90, step: 2, title: "Target", format: { "\($0)°" }) { sent.append($0) }
        let window = host(stepper)
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: stepper).contains("Target, 70°"))
        let control = HostedPage.descendants(of: stepper).compactMap { $0 as? UIStepper }.first
        XCTAssertEqual(control?.minimumValue, 50)
        XCTAssertEqual(control?.stepValue, 2)
        control?.value = 72
        control?.sendActions(for: .valueChanged)
        XCTAssertEqual(sent, [72])
        XCTAssertEqual(control?.value, 70, "the stepper snaps back until the controller echoes the request")
        stepper.show(74)
        XCTAssertTrue(HostedPage.labels(in: stepper).contains("Target, 74°"))
        XCTAssertEqual(control?.value, 74)
    }

    // MARK: Pending bar

    func testPendingBarBreathesOnScreenAndRestsWhenHidden() {
        let bar = UKPendingValueBar()
        let window = host(bar)
        defer { window.isHidden = true }
        XCTAssertFalse(bar.isAccessibilityElement, "the tile's value reads Loading instead")
        XCTAssertEqual(bar.intrinsicContentSize, bar.sizeThatFits(.zero))
        if UKDesign.reduceMotion {
            XCTAssertEqual(bar.layer.opacity, 0.65, accuracy: 0.001, "Reduce Motion holds the bar half way")
        } else {
            XCTAssertNotNil(bar.layer.animation(forKey: "breathe"), "one repeating opacity animation")
            XCTAssertEqual(bar.layer.animation(forKey: "breathe")?.duration ?? 0, PendingValueBar.period / 2, accuracy: 0.001)
        }
        bar.isHidden = true
        XCTAssertNil(bar.layer.animation(forKey: "breathe"), "a hidden bar stops animating")
    }

    // MARK: Percent slider

    func testPercentSliderIncrementsAndDecrementsInFiveStepsAndSendsThem() {
        var sent: [Double] = []
        let row = UKPercentSliderRow("Brightness", value: 40, identifier: "test.slider") { sent.append($0) }
        let window = host(row)
        defer { window.isHidden = true }
        XCTAssertEqual(row.accessibilityValue, "40 percent")
        XCTAssertTrue(row.accessibilityTraits.contains(.adjustable))
        XCTAssertNil(row.accessibilityElements, "the row is one element")
        row.accessibilityIncrement()
        row.accessibilityDecrement()
        row.accessibilityDecrement()
        XCTAssertEqual(sent, [45, 40, 35])
        XCTAssertEqual(row.accessibilityValue, "35 percent")
        row.isEnabled = false
        XCTAssertEqual(row.alpha, 0.5)
        row.accessibilityIncrement()
        XCTAssertEqual(sent.count, 3, "a disabled row ignores adjust actions")
        row.isEnabled = true
        row.value = 100
        row.accessibilityIncrement()
        XCTAssertEqual(sent.count, 3, "at the end of the range an increment sends nothing")
    }

    // MARK: Page dots and paged row

    func testPageIndicatorAdjustsPagesAndSwitchesToACountForManyPages() {
        var selected: [Int] = []
        let dots = UKPageIndicator(page: 1, pageCount: 3, label: "Suggestion page", identifier: "test.dots") { selected.append($0) }
        let window = host(dots)
        defer { window.isHidden = true }
        XCTAssertEqual(dots.accessibilityValue, "Page 2 of 3")
        dots.accessibilityIncrement()
        dots.accessibilityDecrement()
        XCTAssertEqual(selected, [2, 0])
        dots.page = 2
        dots.accessibilityIncrement()
        XCTAssertEqual(selected, [2, 0], "no page after the last")
        dots.ink = .red
        dots.pageCount = 20
        XCTAssertEqual(dots.accessibilityValue, "Page 3 of 20")
        XCTAssertTrue(HostedPage.labels(in: dots).contains("3 of 20"), "many pages read as a count")
    }

    func testPagedRowPagesByThreeFingerSwipeAndReportsTheFirstVisibleCell() {
        let row = UKPagedRowView(itemCount: 10, perPage: 4, animatesPaging: false) { index in
            let label = UILabel()
            label.text = "Cell \(index)"
            return label
        }
        var reported = 0
        row.onFirstVisibleChange = { reported += 1 }
        let window = host(row, size: CGSize(width: 400, height: 300))
        defer { window.isHidden = true }
        row.heightAnchor.constraint(equalToConstant: 60).isActive = true
        window.rootViewController?.view.layoutIfNeeded()
        XCTAssertEqual(row.pageCount, 3)
        XCTAssertEqual(row.firstIndex(ofPage: 1), 4)
        XCTAssertGreaterThan(row.intrinsicContentSize.height, 0)
        XCTAssertEqual(row.currentPage, 0)
        XCTAssertFalse(row.accessibilityScroll(.right), "no page before the first")
        XCTAssertTrue(row.accessibilityScroll(.left), "left moves forward one page")
        HostedPage.until { row.currentPage == 1 }
        XCTAssertEqual(row.currentPage, 1)
        HostedPage.until { row.firstVisible == 4 }
        XCTAssertEqual(row.firstVisible, 4, "the page the row settles on is reported as its first cell")
        XCTAssertGreaterThan(reported, 0)
        XCTAssertTrue(row.accessibilityScroll(.right), "right moves back")
        row.accessibilityElements = nil
        _ = row.accessibilityElements
    }

    // MARK: Schedule date fields

    private func field(_ value: Date, onChange: @escaping (Date) -> Void) -> ScheduleDateField {
        ScheduleDateField(label: "Starts", part: .dateAndTime, value: value, identifier: "test.starts", onChange: onChange)
    }

    private func datePicker(in fields: UKScheduleDateFields) -> UIDatePicker? {
        HostedPage.descendants(of: fields).compactMap { $0 as? UIDatePicker }.first
    }

    func testDelayedPickReportsOnceAfterTheWheelsStopAndRevertsWhenNeverEchoed() {
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        var sent: [Date] = []
        let fields = UKScheduleDateFields(fields: [field(saved) { sent.append($0) }], commitDelay: .milliseconds(100))
        let window = host(fields)
        defer { window.isHidden = true }
        let picker = datePicker(in: fields)
        XCTAssertNotNil(picker)
        let first = saved.addingTimeInterval(3600), second = saved.addingTimeInterval(7200)
        picker?.date = first
        picker?.sendActions(for: .valueChanged)
        picker?.date = second
        picker?.sendActions(for: .valueChanged)
        XCTAssertTrue(sent.isEmpty, "nothing is reported inside the quiet period")
        HostedPage.until(3) { !sent.isEmpty }
        XCTAssertEqual(sent, [second], "one adjustment is one report, with the last pick")
    }

    func testPickingTheSavedValueAgainCancelsThePendingReport() {
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        var sent: [Date] = []
        let fields = UKScheduleDateFields(fields: [field(saved) { sent.append($0) }], commitDelay: .milliseconds(150))
        let window = host(fields)
        defer { window.isHidden = true }
        let picker = datePicker(in: fields)
        picker?.date = saved.addingTimeInterval(3600)
        picker?.sendActions(for: .valueChanged)
        picker?.date = saved
        picker?.sendActions(for: .valueChanged)
        HostedPage.wait(0.5)
        XCTAssertTrue(sent.isEmpty, "going back to the saved value reports nothing")
    }

    func testLeavingInsideTheQuietPeriodReportsThePickInsteadOfLosingIt() {
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        var sent: [Date] = []
        let fields = UKScheduleDateFields(fields: [field(saved) { sent.append($0) }], commitDelay: .seconds(30))
        let window = host(fields)
        defer { window.isHidden = true }
        let pick = saved.addingTimeInterval(1800)
        datePicker(in: fields)?.date = pick
        datePicker(in: fields)?.sendActions(for: .valueChanged)
        XCTAssertTrue(sent.isEmpty)
        fields.removeFromSuperview()
        HostedPage.layoutTracked()
        // The pickers leave the window with their parent.
        XCTAssertEqual(sent, [pick], "the pick is reported when the screen closes")
    }

    func testAnEchoedValueDropsThePendingPick() {
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        var sent: [Date] = []
        let fields = UKScheduleDateFields(fields: [field(saved) { sent.append($0) }], commitDelay: .milliseconds(200))
        let window = host(fields)
        defer { window.isHidden = true }
        datePicker(in: fields)?.date = saved.addingTimeInterval(600)
        datePicker(in: fields)?.sendActions(for: .valueChanged)
        let moved = saved.addingTimeInterval(5000)
        fields.update(fields: [field(moved) { sent.append($0) }])
        HostedPage.wait(0.5)
        XCTAssertTrue(sent.isEmpty, "another device moved the value, so the old pick is dropped")
        XCTAssertEqual(datePicker(in: fields)?.date, moved)
    }

    // MARK: Fonts and scrolling lists

    func testScaledFontKeepsItsDesignSizeAndMonospacesDigitsOnRequest() {
        let plain = UKFont.scaled(size: 20, weight: .semibold, relativeTo: .body)
        XCTAssertEqual(plain.pointSize, UIFontMetrics(forTextStyle: .body).scaledValue(for: 20), accuracy: 0.5)
        let mono = UKFont.scaled(size: 20, weight: .regular, relativeTo: .body, monospacedDigit: true)
        XCTAssertEqual(mono.pointSize, plain.pointSize, accuracy: 0.5)
        XCTAssertNotEqual(mono.fontName, "", "a font came back")
    }

    func testTouchesCancelForTapControlsButNotForSlidersAndFields() {
        let list = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        XCTAssertTrue(list.touchesShouldCancel(in: UIButton()), "a drag that starts on a tile scrolls the page")
        XCTAssertTrue(list.touchesShouldCancel(in: UIView()))
        for control in [UISlider(), UISwitch(), UIStepper(), UITextField(), UITextView(), UIDatePicker()] as [UIView] {
            XCTAssertEqual(list.touchesShouldCancel(in: control), list.superTouchesShouldCancelForTests(control), "\(type(of: control)) keeps its drag")
        }
    }

    // MARK: Climate dial

    private func climateDial(caller: HostedCaller, ids: ((ThermostatTargets) -> [String])? = nil) -> (UKClimateThermostatDial, EntityStore, UIWindow) {
        let store = ClimateFixtures.store()
        let context = UKGalleryChrome.context(store: store, caller: caller)
        let dial = UKClimateThermostatDial(context: context, entityId: ClimateConfig.globalThermostatEntityId, title: "Whole Home", size: .modal,
                                           caller: caller, commitEntityIds: ids)
        return (dial, store, host(dial))
    }

    func testClimateDialCommitSendsSetTemperatureToTheEntityOrTheCommitTargets() async {
        let caller = HostedCaller()
        let (dial, _, window) = climateDial(caller: caller) { _ in ["climate.demo_test_a", "climate.demo_test_b"] }
        defer { window.isHidden = true }
        await dial.commit(.range(low: 68, high: 75))?.value
        XCTAssertEqual(caller.calls, ["climate.set_temperature"])
        XCTAssertEqual(caller.data.first?["entity_id"] as? [String], ["climate.demo_test_a", "climate.demo_test_b"])
        dial.commitEntityIds = nil
        await dial.commit(.single(70))?.value
        XCTAssertEqual(caller.calls.count, 2)
        XCTAssertNotNil(caller.data.last?["entity_id"])
    }

    func testClimateDialRefusalRollsBackAndSaysWhy() async {
        let caller = HostedCaller()
        caller.fails = true
        let (dial, _, window) = climateDial(caller: caller)
        defer { window.isHidden = true }
        await dial.commit(.range(low: 60, high: 80))?.value
        hostedSettle(0.2)
        let texts = HostedPage.labels(in: dial)
        XCTAssertTrue(texts.contains(ThermostatTargets.range(low: 60, high: 80).failureMessage), "a caption says the change failed; saw \(texts)")
        dial.action = "cooling"
        hostedSettle(0.1)
        XCTAssertEqual(dial.action, "cooling")
    }
}

private extension UKWidthAwareCollectionView {
    /// What `UIScrollView` itself answers for a view, so the test compares like with like.
    func superTouchesShouldCancelForTests(_ view: UIView) -> Bool {
        UIScrollView(frame: .zero).touchesShouldCancel(in: view)
    }
}
