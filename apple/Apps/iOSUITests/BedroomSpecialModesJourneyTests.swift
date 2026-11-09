import XCTest

/// The bed side sheet's Special Modes tab: Hot Flash and its audit.
@MainActor
final class BedroomSpecialModesJourneyTests: BedroomJourneyTestCase {
    // MARK: - Special modes

    func testHotFlashStartsAndCancels() {
        let app = launch(sheet: expectations[.bedFirstSheetId], tab: "special-modes")
        tap("bed.hotFlash", in: app)
        expectCall(startingWith: "input_button.press entity_id=\(expectations[.bedFirstHotFlashButton])", in: app)
        // The tile is an action tile: its body does what its disc shows, so a tap on the running tile cancels.
        tap("bed.hotFlash", in: app)
        expectCall(startingWith: "input_button.press entity_id=\(expectations[.bedFirstHotFlashCancelButton])", in: app)
    }

    // MARK: - Accessibility audits

    func testBedSpecialModesPassesAudit() throws { try audit(sheet: expectations[.bedSecondSheetId], tab: "special-modes", scenario: "hot-flash") }
    func testBedSpecialModesPassesAuditInIPadLandscape() throws { try audit(sheet: expectations[.bedSecondSheetId], tab: "special-modes", scenario: "hot-flash", pose: .iPadLandscape) }
}
