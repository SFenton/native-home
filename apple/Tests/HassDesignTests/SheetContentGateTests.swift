import HassDesign
import Testing

// MARK: - The system presentation precedes the grouped reveal

@MainActor
struct SheetContentGateTests {
    @MainActor
    private final class Clock {
        var now = ContinuousClock.now
        var waits: [Duration] = []
        var stopAt: Duration?

        func sleep(_ duration: Duration) -> Bool {
            waits.append(duration)
            guard stopAt != duration else { return false }
            now += duration
            return true
        }
    }

    @Test(arguments: [false, true])
    func readyContentWaitsForPresentationAndNeverHidesAgain(reduceMotion: Bool) async {
        let clock = Clock()
        let gate = ContentGateModel(page: "Example", isReady: true, firstLoad: .sheet, sleep: { clock.sleep($0) }, now: { clock.now })
        await gate.advance(isReady: true, reduceMotion: reduceMotion)
        #expect(!gate.phase.showsContent)
        #expect(clock.waits.isEmpty)

        gate.presentationCompleted()
        await gate.advance(isReady: true, reduceMotion: reduceMotion)
        #expect(gate.phase == .idle)
        #expect(!gate.spinnerShown)
        #expect(clock.waits == [.milliseconds(200)])

        gate.presentationCompleted()
        await gate.advance(isReady: false, reduceMotion: reduceMotion)
        #expect(gate.phase == .idle)
        #expect(clock.waits == [.milliseconds(200)])
    }

    @Test
    func dataThatArrivesDuringTheArcEntranceStillWaitsForItsHoldAndExit() async {
        let clock = Clock()
        clock.stopAt = .milliseconds(9850)
        let gate = ContentGateModel(page: "Example", isReady: false, firstLoad: .sheet, sleep: { clock.sleep($0) }, now: { clock.now })
        gate.presentationCompleted()
        await gate.advance(isReady: false)
        #expect(clock.waits == [.milliseconds(150), .milliseconds(9850)])
        #expect(gate.spinnerShown)
        #expect(!gate.phase.showsContent)

        clock.now += .milliseconds(40)
        clock.stopAt = nil
        clock.waits.removeAll()
        await gate.advance(isReady: true)
        #expect(clock.waits == [.milliseconds(460), .milliseconds(200), .milliseconds(200)])
        #expect(gate.phase == .idle)
        #expect(!gate.spinnerShown)
    }

    @Test
    func repeatedLoadingReadsDoNotRestartTheGraceOrExtendTheTimeout() async {
        let clock = Clock()
        clock.stopAt = .milliseconds(150)
        let gate = ContentGateModel(page: "Example", isReady: false, firstLoad: .sheet, sleep: { clock.sleep($0) }, now: { clock.now })
        gate.presentationCompleted()
        await gate.advance(isReady: false)
        #expect(!gate.spinnerShown)

        clock.now += .milliseconds(100)
        clock.stopAt = nil
        clock.waits.removeAll()
        await gate.advance(isReady: false)
        #expect(clock.waits == [.milliseconds(50), .milliseconds(9850), .milliseconds(200), .milliseconds(200)])
        #expect(gate.phase == .idle)
    }
}
