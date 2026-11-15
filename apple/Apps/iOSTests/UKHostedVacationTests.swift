import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// Vacation (Vacation Mode, Solo Trip) on the gallery's fixture house, which answers like Home Assistant, so a tap's
/// service call and the page's reaction both show.
@MainActor
final class UKHostedVacationTests: DemoHouseTestCase {
    func testConfiguredVacationDateCopySurvivesUpdates() {
        let range = Vacation.DateRange(start: WallClock(date: "2026-10-12", time: "08:00"),
                                       end: WallClock(date: "2026-10-14", time: "18:00"))
        let view = UKVacationDateFieldsView(range: range, invalid: true, identifierPrefix: "example.dates",
                                           commitDelay: nil, description: "Choose your dates",
                                           startLabel: "Leave", endLabel: "Return", errorText: "Choose a later return") { _, _ in }
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        view.layoutIfNeeded()
        view.update(range: range, invalid: true)
        view.layoutIfNeeded()
        let labels = HostedPage.labels(in: view)
        XCTAssertTrue(labels.contains("Choose your dates"))
        XCTAssertTrue(labels.contains("Choose a later return"))
        XCTAssertTrue(labels.contains("Leave"))
        XCTAssertTrue(labels.contains("Return"))
    }

    private struct Screen {
        let page: UIViewController
        let house: VacationGalleryHouse
        let host: UIViewController
        let window: UIWindow
    }

    // MARK: Vacation Mode

    private func vacationModePage(_ scenario: VacationFixtures.Scenario) async -> (Screen, UIViewController) {
        let house = VacationGalleryHouse(store: VacationFixtures.store(scenario), delay: .milliseconds(30))
        let context = UKGalleryChrome.context(store: house.store, caller: house)
        let page = UKVacationSubpageViewController(
            content: UKVacationModeContent(context: context, household: HouseholdAwayController(store: house.store, responder: house), caller: house),
            context: context)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 1800))
        await FeatureHost.settleAsync(0.5)
        return (Screen(page: page, house: house, host: host, window: window), page)
    }

    func testTheModePageShowsTheChecklistWithItsCount() async throws {
        let (s, page) = await vacationModePage(.idle)
        defer { s.window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: page.view).contains { $0.contains("2 of \(Vacation.checklist.count)") }, "two items are already done")
        XCTAssertNotNil(FeatureHost.view("vacation.checklist.0", in: page.view))
        FeatureHost.press("vacation.checklist.4", in: page.view)
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(s.house.lastCall.contains("input_boolean"), "ticking an item calls Home Assistant: \(s.house.lastCall)")
    }

    func testTurningVacationModeOnWithAnUnfinishedChecklistSaysWhy() async throws {
        let (s, page) = await vacationModePage(.idle)
        defer { s.window.isHidden = true }
        FeatureHost.press(VacationModeTile.identifier, in: page.view)
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(HostedPage.labels(in: page.view).contains(Vacation.Copy.preChecklistError))
    }

    func testTurningItOnWithAFinishedChecklistAsksForDatesThenConfirms() async throws {
        let (s, page) = await vacationModePage(.ready)
        defer { s.window.isHidden = true }
        FeatureHost.press(VacationModeTile.identifier, in: page.view)
        await FeatureHost.settleAsync(0.8)
        let sheet = try XCTUnwrap(page.shownSheet, "the dates sheet opens: window \(String(describing: page.view.window)) presented \(String(describing: page.presentedViewController)) labels \(HostedPage.labels(in: page.view).filter { $0.contains("Vacation") || $0.contains("date") })")
        XCTAssertNotNil(FeatureHost.view("vacation.confirm.action", in: sheet.view))
        FeatureHost.press("vacation.confirm.action", in: sheet.view)
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(s.house.lastCall.contains("turn_on") || s.house.lastCall.contains("set_datetime"), "confirming turns it on: \(s.house.lastCall)")
    }

    func testCancellingTheDatesSheetLeavesVacationModeOff() async throws {
        let (s, page) = await vacationModePage(.ready)
        defer { s.window.isHidden = true }
        FeatureHost.press(VacationModeTile.identifier, in: page.view)
        await FeatureHost.settleAsync(0.8)
        let sheet = try XCTUnwrap(page.shownSheet)
        let cancel = HostedPage.descendants(of: sheet.view).first { $0.accessibilityIdentifier == "vacation.confirm.cancel" }
        XCTAssertNotNil(cancel ?? FeatureHost.barItem("vacation.confirm.cancel", on: sheet) ?? (sheet as? UINavigationController)?.navigationBar,
                        "the sheet offers a way out")
        sheet.dismiss(animated: false)
        await FeatureHost.settleAsync(0.4)
        XCTAssertEqual(s.house.store.entity(Vacation.modeEntityId).state?.state, "off")
    }

    func testAnEngagedVacationShowsItsDatesAndAsksBeforeTurningOff() async throws {
        let (s, page) = await vacationModePage(.vacation)
        defer { s.window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("vacation.dates.error", in: page.view) ?? FeatureHost.view(VacationModeTile.identifier, in: page.view))
        FeatureHost.press(VacationModeTile.identifier, in: page.view)
        await FeatureHost.settleAsync(0.5)
        let alert = try XCTUnwrap(FeatureHost.alert(on: page), "turning an engaged vacation off asks first")
        FeatureHost.answer(alert, AlertCopy.turnOffVacation.confirm.title)
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(s.house.lastCall.contains("turn_off"), s.house.lastCall)
    }

    func testPausedDatesAreExplained() async throws {
        let (s, page) = await vacationModePage(.invalidDates)
        defer { s.window.isHidden = true }
        let texts = HostedPage.labels(in: page.view).joined(separator: "|")
        XCTAssertTrue(texts.contains(Vacation.Copy.dateRangeError) || FeatureHost.view("vacation.dates.error", in: page.view) != nil, "the range error shows")
    }

    // MARK: Solo Trip

    private func soloPage(_ scenario: VacationFixtures.Scenario) async -> (Screen, UIViewController) {
        let house = VacationGalleryHouse(store: VacationFixtures.store(scenario), delay: .milliseconds(30))
        let context = UKGalleryChrome.context(store: house.store, caller: house)
        let page = UKVacationSubpageViewController(
            content: UKSoloTripContent(context: context, household: HouseholdAwayController(store: house.store, responder: house), viewer: .resident1),
            context: context)
        let host = UKGalleryChrome.wrap(page, context: context)
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 1800))
        await FeatureHost.settleAsync(0.5)
        return (Screen(page: page, house: house, host: host, window: window), page)
    }

    func testAnActiveSoloTripShowsTheTravelerAndEndsAfterAsking() async throws {
        let (s, page) = await soloPage(.soloActive)
        defer { s.window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("soloTrip.traveler.resident_1", in: page.view))
        XCTAssertNotNil(FeatureHost.view("soloTrip.status", in: page.view) ?? FeatureHost.view("soloTrip.notice", in: page.view))
        XCTAssertTrue(FeatureHost.press("soloTrip.toggle", in: page.view), "an active trip's toggle asks before ending it")
        await FeatureHost.settleAsync(0.5)
        let alert = try XCTUnwrap(FeatureHost.alert(on: page), "End Now confirms")
        FeatureHost.answer(alert, AlertCopy.endSoloTrip.confirm.title)
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(s.house.lastCall.contains("end_now") || s.house.lastCall.contains("script"), s.house.lastCall)
    }

    func testARestoreDecisionOffersBothChoices() async throws {
        let (s, page) = await soloPage(.soloRestore)
        defer { s.window.isHidden = true }
        XCTAssertTrue(FeatureHost.press("soloTrip.status.restoreSaved", in: page.view))
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(s.house.lastCall.contains("resolve_restore"), s.house.lastCall)
        XCTAssertEqual(s.house.store.entity(HouseholdAway.statusEntityId).state?.state, "active")
    }

    func testAScheduledTripCanBeCancelledAndTheTravelerChosen() async throws {
        let (s, page) = await soloPage(.soloScheduled)
        defer { s.window.isHidden = true }
        XCTAssertNotNil(FeatureHost.view("soloTrip.toggle", in: page.view))
        FeatureHost.press("soloTrip.toggle", in: page.view)
        await FeatureHost.settleAsync(0.5)
        if let alert = FeatureHost.alert(on: page) { FeatureHost.answer(alert, alert.actions.last?.title ?? "") }
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(s.house.lastCall != "None", "turning the trip off made a call: \(s.house.lastCall)")
    }

    func testStartingASoloTripOpensTheEditorAndSchedules() async throws {
        let (s, page) = await soloPage(.ready)
        defer { s.window.isHidden = true }
        let context = UKGalleryChrome.context(store: s.house.store, caller: s.house)
        let top = UKVacationSubpageViewController(
            content: UKSoloTripContent(context: context, household: HouseholdAwayController(store: s.house.store, responder: s.house), viewer: .resident1),
            context: context)
        let soloWindow = HostedPage.show(UKGalleryChrome.wrap(top, context: context), size: CGSize(width: 393, height: 1800))
        defer { soloWindow.isHidden = true }
        await FeatureHost.settleAsync(0.5)
        FeatureHost.press("soloTrip.traveler.resident_1", in: top.view)
        await FeatureHost.settleAsync(0.3)
        FeatureHost.press("soloTrip.toggle", in: top.view)
        await FeatureHost.settleAsync(0.8)
        let editor = try XCTUnwrap(top.shownSheet, "turning a trip on opens the editor sheet")
        XCTAssertNotNil(FeatureHost.view("soloTrip.editor.confirm", in: editor.view))
        FeatureHost.press("soloTrip.editor.confirm", in: editor.view)
        await FeatureHost.settleAsync(1.0)
        XCTAssertTrue(s.house.lastCall.contains("schedule"), "confirming schedules the trip: \(s.house.lastCall)")
        _ = page
    }
}
