import HassTelemetry
import SwiftUI

/// The phases of a ``ContentGate``, ported from the web's recipe results region
/// (`ha-sfenton-react-dash@f5a7bf9:src/components/hass/recipes/useRecipeCollection.ts:47-49`) and its page load gate
/// (`ha-sfenton-react-dash@9ac2a46:src/components/shell/DashboardPageLoadGate.tsx`, `src/constants/loading.ts`).
@MainActor
@Observable
public final class ContentGateModel {
    /// Where the gate is.
    public enum Phase: Equatable, Sendable {
        /// Content is hidden; the spinner shows once ``Profile/spinnerDelay`` passes.
        case loading
        /// Content went from ready back to loading and is fading out.
        case exiting
        /// Everything is ready and the spinner is fading out.
        case spinnerExiting
        /// Content is fading (and rising) in.
        case entering
        /// Content shows; nothing is animating.
        case idle

        /// Content draws (possibly fading).
        public var showsContent: Bool { self == .entering || self == .idle || self == .exiting }
    }

    /// Transition timings of the web's recipe results region. Web values except the spinner delay, which keeps fast
    /// loads from flashing a spinner. ``Profile/results`` is built from these.
    public enum Timing {
        /// Before the spinner fades in.
        public static let spinnerDelay: Duration = .milliseconds(150)
        /// Spinner fade in.
        public static let spinnerEnter: Duration = .milliseconds(200)
        /// Spinner fade out (web `CRITERIA_SPINNER_EXIT_MS`).
        public static let spinnerExit: Duration = .milliseconds(140)
        /// Content fade in (web `CRITERIA_CONTENT_ENTER_MS`).
        public static let contentEnter: Duration = .milliseconds(170)
        /// Content fade out when reloading (web `CRITERIA_CONTENT_EXIT_MS`).
        public static let contentExit: Duration = .milliseconds(170)
        /// The longest the gate waits for reported content (images) after the data is ready.
        public static let childTimeout: Duration = .milliseconds(1500)
        /// The shared short fade for spinner exit and content entrance in a sheet.
        public static let sheetFade: Duration = .milliseconds(Int((MotionTokens.quickDuration * 1000).rounded()))
        /// How long a sheet arc stays visible, measured from the start of its fade-in.
        public static let sheetSpinnerMinimum: Duration = .milliseconds(500)
    }

    /// A full set of timings for one kind of load.
    public struct Profile: Equatable, Sendable {
        /// Before the spinner fades in.
        public var spinnerDelay: Duration
        /// Spinner fade in.
        public var spinnerEnter: Duration
        /// Spinner fade out.
        public var spinnerExit: Duration
        /// Content fade in (it rises 4 pt as it fades unless Reduce Motion is on).
        public var contentEnter: Duration
        /// Content fade out when reloading.
        public var contentExit: Duration
        /// The longest the gate waits for reported content (images) after the data is ready.
        public var childTimeout: Duration
        /// The least time a cold load keeps the spinner up from the moment it starts, even when the data arrives first.
        public var minimumLoading: Duration
        /// The longest a cold load waits for the data before showing the content anyway; nil waits for ever.
        public var loadTimeout: Duration?
        /// The content's rise in points, dropped under Reduce Motion.
        public private(set) var contentRise: CGFloat = 4
        /// The gate stays hidden until the system presentation finishes and reveals only once.
        public private(set) var waitsForPresentation = false

        /// Creates a profile.
        public init(
            spinnerDelay: Duration, spinnerEnter: Duration, spinnerExit: Duration, contentEnter: Duration,
            contentExit: Duration, childTimeout: Duration, minimumLoading: Duration = .zero, loadTimeout: Duration? = nil
        ) {
            self.spinnerDelay = spinnerDelay
            self.spinnerEnter = spinnerEnter
            self.spinnerExit = spinnerExit
            self.contentEnter = contentEnter
            self.contentExit = contentExit
            self.childTimeout = childTimeout
            self.minimumLoading = minimumLoading
            self.loadTimeout = loadTimeout
        }

        /// A results region that reloads in place (search, sort, filter): a quick 140 ms spinner exit and no minimum, so a
        /// fast reload shows no spinner at all.
        public static let results = Profile(
            spinnerDelay: Timing.spinnerDelay, spinnerEnter: Timing.spinnerEnter, spinnerExit: Timing.spinnerExit,
            contentEnter: Timing.contentEnter, contentExit: Timing.contentExit, childTimeout: Timing.childTimeout
        )

        /// A page's first load, as the web's `DashboardPageLoadGate`: the spinner fades in at once and stays at least 1 s
        /// (`DASHBOARD_MIN_LOADING_MS`), fades out over 500 ms (`DASHBOARD_LOADING_EXIT_MS`), and then the content fades
        /// in over 170 ms (`dashboardGateContentEnter`). A page whose data never arrives shows its content after 10 s
        /// (`DASHBOARD_PAGE_LOAD_TIMEOUT_MS`). A page that already has its data (a reopen) never gets here: the gate
        /// starts open.
        public static let page = Profile(
            spinnerDelay: .zero, spinnerEnter: .milliseconds(200), spinnerExit: .milliseconds(500),
            contentEnter: .milliseconds(170), contentExit: .milliseconds(170), childTimeout: Timing.childTimeout,
            minimumLoading: .milliseconds(1000), loadTimeout: .milliseconds(10_000)
        )

        /// A sheet's one-time reveal: the native slide first, then an opacity-only reveal with an arc only for a real wait.
        public static let sheet: Profile = {
            var profile = Profile(
                spinnerDelay: Timing.spinnerDelay, spinnerEnter: Timing.spinnerEnter, spinnerExit: Timing.sheetFade,
                contentEnter: Timing.sheetFade, contentExit: .zero, childTimeout: Timing.childTimeout, loadTimeout: .seconds(10)
            )
            profile.waitsForPresentation = true
            profile.contentRise = 0
            return profile
        }()
    }

    /// The current phase.
    public private(set) var phase: Phase
    /// Whether the spinner is visible (it fades in after ``Profile/spinnerDelay``).
    public private(set) var spinnerShown = false
    /// Content inside the gate reports here.
    public let tracker = ReadinessTracker()

    /// The page name for telemetry.
    @ObservationIgnored public let page: String
    /// Timings for the first load, and for loads after the content has shown once.
    @ObservationIgnored public let firstLoad: Profile
    @ObservationIgnored public let reload: Profile
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Bool
    @ObservationIgnored private let now: @MainActor () -> ContinuousClock.Instant
    @ObservationIgnored private var interval: Telemetry.Interval?
    @ObservationIgnored private var loadingStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var hasShownContent: Bool
    @ObservationIgnored private var childrenStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var spinnerStartedAt: ContinuousClock.Instant?
    @ObservationIgnored private var phaseStartedAt: ContinuousClock.Instant?

    private var profile: Profile { hasShownContent ? reload : firstLoad }

    /// Creates a model.
    /// - Parameters:
    ///   - page: Names the page in telemetry.
    ///   - isReady: Whether data is already there. A gate that starts ready never shows a spinner or fades
    ///     (a reopen from the disk snapshot must not look like a reload).
    ///   - firstLoad: Timings for the first load.
    ///   - reload: Timings for a load after the content has shown (defaults to `firstLoad`).
    ///   - sleep: Waits; returns `false` when cancelled. Tests pass an immediate one.
    ///   - now: The clock for ``Profile/minimumLoading`` and ``Profile/loadTimeout``.
    public init(
        page: String, isReady: Bool, firstLoad: Profile = .results, reload: Profile? = nil,
        sleep: @escaping @MainActor (Duration) async -> Bool = ContentGateModel.taskSleep,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
    ) {
        self.page = page
        self.firstLoad = firstLoad
        self.reload = reload ?? firstLoad
        self.sleep = sleep
        self.now = now
        let immediatelyVisible = isReady && !firstLoad.waitsForPresentation
        hasShownContent = immediatelyVisible
        phase = immediatelyVisible ? .idle : .loading
        if !firstLoad.waitsForPresentation {
            if isReady { Telemetry.count("gate.instant") }
            else {
                loadingStartedAt = now()
                interval = Telemetry.begin(Telemetry.Name.contentReady, page: page, page)
            }
        }
    }

    /// Starts a sheet reveal's time budget when the system slide has actually ended.
    public func presentationCompleted() {
        guard firstLoad.waitsForPresentation, loadingStartedAt == nil else { return }
        loadingStartedAt = now()
        interval = Telemetry.begin(Telemetry.Name.contentReady, page: page, page)
    }

    /// Ends the presentation's measurement when it is dismissed before the reveal completes.
    public func presentationDismissed() {
        guard firstLoad.waitsForPresentation, let interval else { return }
        Telemetry.end(interval, detail: "dismissed")
        self.interval = nil
    }

    /// The production sleeper.
    public static func taskSleep(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }

    /// Moves the gate toward `isReady`. The view calls it whenever the data or the reported content changes;
    /// a newer call cancels an older one mid-transition and picks up from the current phase.
    public func advance(isReady: Bool, reduceMotion: Bool = false) async {
        if firstLoad.waitsForPresentation {
            await advanceSheet(isReady: isReady)
        } else if isReady {
            await reveal()
        } else {
            await becomeLoading()
        }
    }

    // MARK: - One-time presentation

    private func advanceSheet(isReady: Bool) async {
        guard let presented = loadingStartedAt, let timeout = firstLoad.loadTimeout, phase != .idle, !Task.isCancelled else { return }
        if phase == .loading {
            if !isReady { childrenStartedAt = nil }
            if !isReady || !tracker.isSettled {
                if isReady, childrenStartedAt == nil { childrenStartedAt = now() }
                let loadDeadline = presented + timeout
                let deadline = childrenStartedAt.map { min(loadDeadline, $0 + firstLoad.childTimeout) } ?? loadDeadline
                if !spinnerShown {
                    let grace = presented + firstLoad.spinnerDelay
                    guard await wait(until: min(grace, deadline)) else { return }
                    if now() >= grace, grace < deadline {
                        spinnerStartedAt = now()
                        withAnimation(.easeIn(duration: firstLoad.spinnerEnter.seconds)) { spinnerShown = true }
                    }
                }
                guard await wait(until: deadline) else { return }
                Telemetry.count(isReady ? "gate.childTimeouts" : "gate.loadTimeouts")
            }
            if let shown = spinnerStartedAt {
                guard await wait(until: shown + Timing.sheetSpinnerMinimum) else { return }
                phaseStartedAt = now()
                withAnimation(.easeOut(duration: firstLoad.spinnerExit.seconds)) { phase = .spinnerExiting }
                Telemetry.count("sheetReveal.arc")
            } else {
                Telemetry.count("sheetReveal.ready")
            }
        }
        if phase == .spinnerExiting, let start = phaseStartedAt {
            guard await wait(until: start + firstLoad.spinnerExit) else { return }
        }
        if phase != .entering {
            phaseStartedAt = now()
            withAnimation(.easeOut(duration: firstLoad.contentEnter.seconds)) {
                phase = .entering
                spinnerShown = false
            }
        }
        if let start = phaseStartedAt, await wait(until: start + firstLoad.contentEnter) { finish() }
    }

    private func wait(until deadline: ContinuousClock.Instant) async -> Bool {
        let remaining = deadline - now()
        if remaining > .zero, !(await sleep(remaining)) { return false }
        return !Task.isCancelled
    }

    // MARK: - Reloadable content

    /// Shows the content: waits for reported content and the least loading time, fades the spinner out, then fades the
    /// content in.
    private func reveal() async {
        switch phase {
        case .idle:
            return
        case .loading, .exiting:
            if !tracker.isSettled {
                // The tracker settling cancels this wait and calls again.
                guard await sleep(profile.childTimeout) else { return }
                Telemetry.count("gate.childTimeouts")
            }
            if profile.minimumLoading > .zero, phase == .loading, let started = loadingStartedAt {
                // The data beat the least loading time: make sure the spinner is up, then hold it.
                if !spinnerShown { withAnimation(.easeIn(duration: profile.spinnerEnter.seconds)) { spinnerShown = true } }
                let remaining = profile.minimumLoading - (now() - started)
                if remaining > .zero { guard await sleep(remaining) else { return } }
            }
            if spinnerShown {
                withAnimation(.easeOut(duration: profile.spinnerExit.seconds)) { phase = .spinnerExiting }
                guard await sleep(profile.spinnerExit) else { return }
            }
            await enter()
        case .spinnerExiting:
            await enter()
        case .entering:
            finish()
        }
    }

    private func becomeLoading() async {
        if phase.showsContent {
            withAnimation(.easeOut(duration: profile.contentExit.seconds)) { phase = .exiting }
            guard await sleep(profile.contentExit) else { return }
        }
        if phase != .loading {
            phase = .loading
            spinnerShown = false
            loadingStartedAt = now()
            interval = Telemetry.begin(Telemetry.Name.contentReady, page: page, page)
        }
        if !spinnerShown {
            guard await sleep(profile.spinnerDelay) else { return }
            withAnimation(.easeIn(duration: profile.spinnerEnter.seconds)) { spinnerShown = true }
        }
        // Data that never arrives must not hold the page for ever (web `DASHBOARD_PAGE_LOAD_TIMEOUT_MS`).
        if let timeout = profile.loadTimeout, let started = loadingStartedAt {
            let remaining = timeout - (now() - started)
            if remaining > .zero { guard await sleep(remaining) else { return } }
            Telemetry.count("gate.loadTimeouts")
            await reveal()
        }
    }

    /// Fades the content in. Only opacity animates here: `ContentGate` drops its 4 pt rise when Reduce Motion is on,
    /// so these `withAnimation` blocks are cross-fades then, which Reduce Motion allows.
    private func enter() async {
        withAnimation(.easeOut(duration: profile.contentEnter.seconds)) {
            phase = .entering
            spinnerShown = false
        }
        guard await sleep(profile.contentEnter) else { return }
        finish()
    }

    private func finish() {
        phase = .idle
        hasShownContent = true
        if let interval {
            Telemetry.end(interval, detail: "cold")
            self.interval = nil
        }
    }
}

extension Duration {
    /// The duration in seconds, for SwiftUI animations.
    var seconds: Double { milliseconds / 1000 }
}
