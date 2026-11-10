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
        /// One fade for a whole modal reveal (the arc out, the content in): ``MotionTokens/quickDuration``, so a component
        /// that reuses ``Profile/sheet`` also reuses the app's small-fade speed.
        public static let sheetFade: Duration = .milliseconds(Int((MotionTokens.quickDuration * 1000).rounded()))
        /// The least an arc that has started stays up, from the start of its fade-in (``Profile/sheet``).
        public static let spinnerMinimumShown: Duration = .milliseconds(500)
        /// The longest a first load waits for its data before showing the content anyway (web
        /// `DASHBOARD_PAGE_LOAD_TIMEOUT_MS`); ``Profile/page`` and ``Profile/sheet`` read it.
        public static let loadTimeout: Duration = .milliseconds(10_000)
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
        /// How far the content starts below its place and rises as it fades in, in points (dropped under Reduce Motion).
        public var contentRise: CGFloat
        /// Whether nothing happens (no arc timer, no load timeout) until ``ContentGateModel/presentationCompleted()``, and
        /// content that is ready at init stays hidden until then: a modal's slide-up.
        public var waitsForPresentation: Bool
        /// The least an arc that has shown stays up, from the start of its fade-in. Unlike ``minimumLoading`` it never
        /// forces an arc: it applies only once the arc has started.
        public var spinnerMinimumShown: Duration
        /// Whether the reveal runs once: after the content has shown, a later `advance(isReady: false)` is ignored.
        public var revealsOnce: Bool

        /// Creates a profile.
        public init(
            spinnerDelay: Duration, spinnerEnter: Duration, spinnerExit: Duration, contentEnter: Duration,
            contentExit: Duration, childTimeout: Duration, minimumLoading: Duration = .zero, loadTimeout: Duration? = nil,
            contentRise: CGFloat = 4, waitsForPresentation: Bool = false, spinnerMinimumShown: Duration = .zero,
            revealsOnce: Bool = false
        ) {
            self.contentRise = contentRise
            self.waitsForPresentation = waitsForPresentation
            self.spinnerMinimumShown = spinnerMinimumShown
            self.revealsOnce = revealsOnce
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
            minimumLoading: .milliseconds(1000), loadTimeout: Timing.loadTimeout
        )

        /// A modal's reveal (`.agents/design/sheet-reveal.md`): nothing until the sheet has finished sliding up; then ready
        /// content fades in at once (200 ms, no rise); content that is not ready gets an arc after a 150 ms grace, held at
        /// least 500 ms from the start of its fade-in, faded out over 200 ms, and then the content fades in. Runs once.
        public static let sheet = Profile(
            spinnerDelay: Timing.spinnerDelay, spinnerEnter: Timing.spinnerEnter, spinnerExit: Timing.sheetFade,
            contentEnter: Timing.sheetFade, contentExit: Timing.contentExit, childTimeout: Timing.childTimeout,
            minimumLoading: .zero, loadTimeout: Timing.loadTimeout, contentRise: 0, waitsForPresentation: true,
            spinnerMinimumShown: Timing.spinnerMinimumShown, revealsOnce: true
        )
    }

    /// The current phase.
    public private(set) var phase: Phase
    /// Whether the spinner is visible (it fades in after ``Profile/spinnerDelay``).
    public private(set) var spinnerShown = false
    /// Whether the host has finished presenting the content (always true unless ``Profile/waitsForPresentation``). Until it
    /// is, the gate does nothing; observe it to advance again once it flips.
    public private(set) var isPresented: Bool
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
    @ObservationIgnored private var spinnerShownAt: ContinuousClock.Instant?

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
        let waits = firstLoad.waitsForPresentation
        isPresented = !waits
        // A gate that waits for its presentation starts loading even when the data is there: the content stays hidden through
        // the slide and fades in once.
        let instant = isReady && !waits
        hasShownContent = instant
        loadingStartedAt = isReady || waits ? nil : now()
        phase = instant ? .idle : .loading
        if !isReady && !waits { interval = Telemetry.begin(Telemetry.Name.contentReady, page: page, page) }
        if instant { Telemetry.count("gate.instant") }
    }

    /// The host finished presenting the content (a sheet's first `viewDidAppear`). The arc grace and the load timeout count
    /// from here; the caller advances again (it observes ``isPresented``). Does nothing twice.
    public func presentationCompleted() {
        guard !isPresented else { return }
        isPresented = true
        loadingStartedAt = now()
        if interval == nil, phase != .idle { interval = Telemetry.begin(Telemetry.Name.contentReady, page: page, page) }
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
        guard isPresented else { return }
        // A reveal that runs once lets go of the content for good.
        if !isReady, phase == .idle, firstLoad.revealsOnce { return }
        if isReady {
            await reveal()
        } else {
            await becomeLoading()
        }
    }

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
                if !spinnerShown {
                    withAnimation(.easeIn(duration: profile.spinnerEnter.seconds)) { spinnerShown = true }
                    spinnerShownAt = now()
                }
                let remaining = profile.minimumLoading - (now() - started)
                if remaining > .zero { guard await sleep(remaining) else { return } }
            }
            if profile.spinnerMinimumShown > .zero, spinnerShown, let shownAt = spinnerShownAt {
                // An arc that has started always finishes its hold, whenever the data arrived: no pop.
                let remaining = profile.spinnerMinimumShown - (now() - shownAt)
                if remaining > .zero { guard await sleep(remaining) else { return } }
            }
            if profile.waitsForPresentation { Telemetry.count(spinnerShown ? "sheetReveal.arc" : "sheetReveal.ready") }
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
            spinnerShownAt = nil
            loadingStartedAt = now()
            interval = Telemetry.begin(Telemetry.Name.contentReady, page: page, page)
        }
        if !spinnerShown {
            guard await sleep(profile.spinnerDelay) else { return }
            withAnimation(.easeIn(duration: profile.spinnerEnter.seconds)) { spinnerShown = true }
            spinnerShownAt = now()
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
