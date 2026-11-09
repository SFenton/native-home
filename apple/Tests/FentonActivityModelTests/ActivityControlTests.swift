@testable import FentonActivityModel
import Testing

struct ActivityControlTests {
    @Test func jobVerbsMayRunFromTheLockScreen() {
        for id in ["stop", "pause", "resume", "dock", "done", "try_again", "cancel", "cancel_timer"] {
            #expect(ActivityControl.isSafeFromLockScreen(id), "\(id)")
        }
    }

    @Test func otherControlIdsAreRefusedThere() {
        for id in ["", "unlock", "open_garage", "STOP"] {
            #expect(!ActivityControl.isSafeFromLockScreen(id), "\(id)")
        }
    }
}
