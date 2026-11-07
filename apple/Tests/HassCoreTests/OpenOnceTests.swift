import Foundation
@testable import HassCore
import Testing

/// Counts opens and holds each one suspended until released, so callers can pile up behind it.
@MainActor
private final class OpenGate {
    private(set) var opens = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func open() async -> Int {
        opens += 1
        let n = opens
        if !released { await withCheckedContinuation { waiters.append($0) } }
        return n
    }

    var isSuspended: Bool { !waiters.isEmpty }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
@Suite("Open once")
struct OpenOnceTests {
    @Test func concurrentCallersWhileSuspendedShareOneOpen() async {
        let gate = OpenGate()
        let once = OpenOnce<Int> { await gate.open() }
        let callers = (0..<5).map { _ in Task { @MainActor in await once.get() } }
        // Let every caller enter while the first open is still suspended.
        while !gate.isSuspended { await Task.yield() }
        for _ in 0..<50 { await Task.yield() }
        gate.release()
        var results: [Int] = []
        for caller in callers { results.append(await caller.value) }
        #expect(gate.opens == 1)
        #expect(results == [1, 1, 1, 1, 1])
    }

    @Test func laterCallReturnsCachedValueWithoutReopening() async {
        let gate = OpenGate()
        gate.release()
        let once = OpenOnce<Int> { await gate.open() }
        let first = await once.get()
        let second = await once.get()
        #expect(first == 1 && second == 1)
        #expect(gate.opens == 1)
    }

    @Test func valueIsNilUntilOpened() async {
        let gate = OpenGate()
        gate.release()
        let once = OpenOnce<Int> { await gate.open() }
        #expect(once.value == nil)
        _ = await once.get()
        #expect(once.value == 1)
    }
}
