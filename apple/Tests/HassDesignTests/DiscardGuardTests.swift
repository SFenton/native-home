@testable import HassDesign
import Testing

/// The discard guard (`sheet-discard-guard`), the Close placement and the grabber rule (`sheet-close-chrome`).
@MainActor
struct DiscardGuardTests {
    @Test func copyIsTheDecidedWording() {
        #expect(DiscardChangesCopy.title == "Discard changes?")
        #expect(DiscardChangesCopy.discard == "Discard Changes")
        #expect(DiscardChangesCopy.keepEditing == "Keep Editing")
    }

    @Test func confirmsOnlyForAnEditedIdleForm() {
        #expect(DiscardGuard.needsConfirmation(hasChanges: true))
        #expect(!DiscardGuard.needsConfirmation(hasChanges: false))
        // A running save blocks the dismissal outright, so there is nothing to ask.
        #expect(!DiscardGuard.needsConfirmation(hasChanges: true, isBusy: true))
    }

    @Test func swipeDownIsBlockedWhileEditedOrSaving() {
        #expect(!DiscardGuard.blocksInteractiveDismissal(hasChanges: false))
        #expect(DiscardGuard.blocksInteractiveDismissal(hasChanges: true))
        #expect(DiscardGuard.blocksInteractiveDismissal(hasChanges: false, isBusy: true))
        #expect(DiscardGuard.blocksInteractiveDismissal(hasChanges: true, isBusy: true))
    }
}
