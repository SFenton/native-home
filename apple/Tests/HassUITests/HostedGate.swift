import Foundation
import Testing

/// A FIFO async lock, and the one every suite that opens a window shares (`AsyncLock.hosted`).
///
/// Hosted suites share the process's single main actor: each settles with `RunLoop.main.run`, and each accessibility
/// read walks a tree on it synchronously, so ~40 suites running together made every wait slower for all of them (and
/// their click timing flaky). A suite tagged `.hosted` takes the gate for its whole run, so one window is live
/// at a time. Core, Design and the model suites carry no tag and stay parallel.
///
/// Waiting suites are suspended, not blocked, so they cost nothing while they queue. The gate is a plain FIFO, so a
/// long suite cannot starve the others.
actor AsyncLock {
    /// The gate every hosted suite takes.
    static let hosted = AsyncLock()
    /// Guards the process-wide launch environment (`setenv`, `UserDefaults`) a `withLaunch` body sets.
    static let launch = AsyncLock()

    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !held {
            held = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            held = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Runs `body` holding the gate.
    func run<T>(_ body: () async throws -> T) async rethrows -> T {
        await acquire()
        do {
            let value = try await body()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }
}

/// Suite trait: the suite's tests run with `AsyncLock.hosted` held. Apply it to the outermost suite that opens windows;
/// it is not recursive, so nested suites do not take the gate a second time.
struct HostedSuiteTrait: SuiteTrait, TestScoping {
    var isRecursive: Bool { false }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        try await AsyncLock.hosted.run(function)
    }
}

extension Trait where Self == HostedSuiteTrait {
    /// Opens windows: run this suite alone among the hosted suites (`AsyncLock.hosted`).
    static var hosted: HostedSuiteTrait { HostedSuiteTrait() }
}

/// Whether the nightly-only tests run: the full gallery launch matrix is ~hundreds of window launches, so a PR's
/// `swift test` skips it. It runs when `FENTON_TIER` is `nightly` or `release`, when `FENTON_RUN_MATRIX=1`, or
/// under `swift test --enable-code-coverage` (`tools/apple_coverage.sh`, which the UX coverage gate needs it for;
/// SwiftPM sets `LLVM_PROFILE_FILE` for the test process then).
enum NightlyTier {
    static let isOn: Bool = {
        let env = ProcessInfo.processInfo.environment
        return ["nightly", "release"].contains(env["FENTON_TIER"] ?? "") || env["FENTON_RUN_MATRIX"] == "1" || env["LLVM_PROFILE_FILE"] != nil
    }()
}
