#if os(iOS)
import HassCore
import HassTelemetry
import Observation
import UIKit

/// Binds UIKit to `@Observable` models (`EntityBox`, `EntityStore`, the screen models) the way SwiftUI's view graph does:
/// `apply` runs once now, records every observable property it reads, and runs again on the main actor after any of
/// them changes. Several changes in one run-loop turn cost one re-run, so a live update to one entity costs the views
/// that read its box one update and nothing else (AGENTS.md, "The main thread does not scale with the house").
///
/// Keep the returned token for as long as the binding should live (``UKObservationBag`` does this for a view or
/// controller); dropping it stops the updates.
@MainActor
public final class UKObservation {
    private let track: @MainActor () -> Void
    private let apply: (@MainActor () -> Void)?
    private var isScheduled = false
    private var isCancelled = false
    private var isPaused = false
    /// An input changed while the observation was paused, so it owes one run when it resumes.
    private var isStale = false

    /// Starts observing.
    /// - Parameter apply: Reads observable state and writes it into views. Runs now and after every change it read.
    public init(_ apply: @escaping @MainActor () -> Void) {
        track = apply
        self.apply = nil
        run()
    }

    /// Starts observing only what `track` reads; `apply` runs after it, outside the tracking scope.
    ///
    /// Use it when `apply` builds or rebuilds UIKit views. Reads UIKit makes while views are built and laid out are observable
    /// to Observation too, and UIKit mutates them on every layout pass: inside the tracking scope they re-run the rebuild on
    /// every frame, which tears the accessibility tree down about sixty times a second.
    /// - Parameters:
    ///   - track: Reads the observable state that should re-run `apply`, and nothing else.
    ///   - apply: Writes into views. Runs now and after every change `track` read.
    public init(track: @escaping @MainActor () -> Void, apply: @escaping @MainActor () -> Void) {
        self.track = track
        self.apply = apply
        run()
    }

    /// Stops the updates.
    public func cancel() { isCancelled = true }

    /// Holds the re-runs: an input that changes meanwhile is remembered, costs nothing more, and the observation runs once when
    /// ``resume()`` is called. Its tracking is not touched, so a change in the next instant is still heard.
    public func pause() { isPaused = true }

    /// Lets the observation run again, now and in this call when an input changed while it was paused: one catch-up run, in the
    /// caller's turn, so what it draws is current before the next frame.
    /// - Returns: Whether it ran.
    @discardableResult
    public func resume() -> Bool {
        guard isPaused else { return false }
        isPaused = false
        guard isStale, !isCancelled else { return false }
        isStale = false
        run()
        return true
    }

    private func run() {
        guard !isCancelled else { return }
        withObservationTracking { track() } onChange: { [weak self] in
            // `onChange` fires in the mutation's `willSet`, on whatever thread mutated: hop to the main actor and read the
            // new value on the next turn, once for any number of changes.
            Task { @MainActor [weak self] in self?.schedule() }
        }
        apply?()
    }

    private func schedule() {
        guard !isScheduled, !isCancelled else { return }
        // Paused: the change is remembered and the one catch-up run happens at ``resume()``; nothing is queued for it.
        if isPaused { isStale = true; return }
        isScheduled = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isScheduled = false
                if self.isPaused { self.isStale = true; return }
                self.run()
            }
        }
    }
}

/// Holds a view's or controller's observations; they end with it.
@MainActor
public final class UKObservationBag {
    private var observations: [UKObservation] = []
    /// Wraps every run of an observation made after it is set, the first and each re-run: a repeat's cell sets the item and index its
    /// expressions read here, so the same closure reads the same cell each time it runs. `nil` runs the closure as it is.
    public var around: (@MainActor (@MainActor () -> Void) -> Void)?
    /// Whether the closures observed through this bag evaluate authored logic (a node's rules, badges and expressions). Each of their runs, the
    /// first and every re-run, is counted, timed and signposted (`HassTelemetry.LogicCost`); a bag that draws no authored logic leaves it off.
    public var evaluatesAuthoredLogic = false
    /// The owner's count of those runs (`LogicCost.Tally`), in addition to the process-wide counters. Set it before the observations are made.
    public var logicTally: LogicCost.Tally?
    /// Whether the bag's observations rest (``pause()``): the first run of a new observation still happens, so its views are drawn from it.
    public private(set) var isPaused = false

    public init() {}

    /// Observes `apply` (``UKObservation``) for the bag's lifetime.
    public func observe(_ apply: @escaping @MainActor () -> Void) {
        add(UKObservation(wrapped(apply, holding: DerivedReaders())))
    }

    /// Observes what `track` reads and runs `apply` after it, outside the tracking scope (``UKObservation/init(track:apply:)``).
    public func observe(track: @escaping @MainActor () -> Void, apply: @escaping @MainActor () -> Void) {
        add(UKObservation(track: wrapped(track, holding: DerivedReaders()), apply: wrapped(apply, measured: false)))
    }

    private func add(_ observation: UKObservation) {
        if isPaused { observation.pause() }
        observations.append(observation)
    }

    // MARK: Resting

    /// Rests every observation of the bag, and any made later, until ``resume()``: a view that is not on screen is not re-drawn for each
    /// change, and nothing it read is evaluated again meanwhile.
    public func pause() {
        isPaused = true
        observations.forEach { $0.pause() }
    }

    /// Ends the rest. Each observation whose inputs changed meanwhile runs once, now and in this call, so the views are current when it returns.
    /// - Returns: How many observations caught up.
    @discardableResult
    public func resume() -> Int {
        isPaused = false
        return observations.reduce(0) { $0 + ($1.resume() ? 1 : 0) }
    }

    /// `run` inside the cell's scope; and, for the closure that evaluates (not the one that applies), inside the logic meter.
    /// - Parameter holding: Keeps the shared derived values the run reads alive until the observation's next run (``DerivedReaders``).
    private func wrapped(_ run: @escaping @MainActor () -> Void, measured: Bool = true,
                         holding readers: DerivedReaders? = nil) -> @MainActor () -> Void {
        let scoped: @MainActor () -> Void
        if let around { scoped = { around(run) } } else { scoped = run }
        let inner: @MainActor () -> Void
        if let readers { inner = { readers.run(scoped) } } else { inner = scoped }
        guard measured, evaluatesAuthoredLogic else { return inner }
        let tally = logicTally
        return { LogicCost.measure(in: tally, inner) }
    }

    /// Ends every observation, for a reused cell before it binds to another model.
    public func removeAll() {
        observations.forEach { $0.cancel() }
        observations.removeAll()
    }
}
#endif
