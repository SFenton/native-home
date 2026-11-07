import XCTest

/// Test impact recording (spike). With `TEST_RUNNER_FENTON_IMPACT_DIR=DIR` (set by `tools/ios_uitest.sh --impact DIR`, which
/// also builds the app instrumented) every app launch writes its LLVM profile to `DIR/<Class>.<test>.<pid>.profraw`, so
/// `tools/test_impact.py extract` can say which source lines each test executed. Without the variable nothing here runs.
///
/// The bundle's principal class (`NSPrincipalClass`, set in `project.yml`) is created once when the bundle loads; it registers
/// the observer that learns the current test's name, so every class is covered, not only ``JourneyTestCase`` subclasses.
@objc(FentonImpactRecorder)
final class ImpactRecorder: NSObject, XCTestObservation {
    nonisolated(unsafe) private static var currentTest = "unknown"

    /// The directory profiles go to, or nil when recording is off.
    static var directory: String? {
        let value = ProcessInfo.processInfo.environment["FENTON_IMPACT_DIR"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    override init() {
        super.init()
        if Self.directory != nil { XCTestObservationCenter.shared.addTestObserver(self) }
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        // "-[ChoresSwipeJourneyTests testFoo]" -> "ChoresSwipeJourneyTests.testFoo"
        let raw = testCase.name.trimmingCharacters(in: CharacterSet(charactersIn: "-+[]"))
        Self.currentTest = raw.replacingOccurrences(of: " ", with: ".")
    }

    /// Points the app's profile at this test. `%p` is the app's pid (a relaunch gets its own file) and `%c` turns on continuous
    /// mode, so counters are mapped to the file as they change and an app XCUITest kills still leaves a usable profile.
    /// This only works because the run instruments with build settings and `-enableCodeCoverage NO`: under Xcode's own coverage
    /// (`-enableCodeCoverage YES`) Xcode overwrites `LLVM_PROFILE_FILE` for the app and writes elsewhere.
    static func apply(to app: XCUIApplication) {
        guard let directory else { return }
        app.launchEnvironment["LLVM_PROFILE_FILE"] = "\(directory)/\(currentTest).%p.%c.profraw"
    }
}
