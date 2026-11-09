@testable import HassDesign
import Testing

/// ``MotionAudit``: the registry of components that animate a state colour (`.agents/design/motion-components.md`).
@MainActor
struct MotionAuditTests {
    @Test func captureCollectsOnlyWhatDrewDuringTheBody() {
        let seen = MotionAudit.capture {
            MotionAudit.noteStateColor("A")
            MotionAudit.noteStateColor("B")
        }
        #if DEBUG
        #expect(seen == ["A", "B"])
        #else
        #expect(seen.isEmpty)
        #endif
        #expect(MotionAudit.capture {}.isEmpty)
    }

    @Test func enableCollectsComponentsAcrossCaptures() {
        MotionAudit.enable()
        MotionAudit.noteStateColor("Enabled-\(#line)")
        #if DEBUG
        #expect(MotionAudit.components.contains { $0.hasPrefix("Enabled-") })
        #endif
    }
}
