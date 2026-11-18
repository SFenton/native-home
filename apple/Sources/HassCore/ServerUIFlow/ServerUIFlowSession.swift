import Foundation
import Observation

// MARK: - What a session needs from the app

/// What a ``ServerUIFlowSession`` reads and calls. The app builds one over its connection and entity store; a test builds one by hand.
@MainActor
public struct ServerUIFlowHost {
    /// The live feed, for a `ha-subscription` request.
    public var feed: (any ServerUIFlowFeed)?
    /// Calls a service with `return_response` and gives its response. `timeout` is the flow's own `timeoutSeconds`; the session ends the wait
    /// at that time whether or not the call has answered, so a call may use it to release what it holds.
    public var call: (_ domain: String, _ service: String, _ target: [String: JSONValue], _ data: [String: JSONValue], _ timeout: Duration) async throws -> JSONValue
    /// What the app holds about an entity. Read inside an observation, so a change to the entity runs the flow again.
    public var held: (_ entityId: String) -> ServerUIFlowSources.HeldEntity?
    /// The value of a declared source's field (a parameter's `read`), as the app's operand evaluator reads it.
    public var read: (_ sourceId: String, _ path: [String]) -> JSONValue?
    /// Whether the app has received its first entity states. Until it has, a flow over held entities waits instead of drawing them unavailable.
    public var statesReady: () -> Bool
    /// The viewer and the locale. Read inside an observation.
    public var environment: () -> (viewer: ServerUIViewer?, locale: Locale?)
    /// The app's ticking clock. Read only by a flow that reads `clock`, inside an observation of its own, so a minute that passes runs the flow
    /// again on the answer it already has. Reading it is what keeps the app's tick alive.
    public var clock: () -> ServerUIClock?
    /// Waits for `duration`; the session's timeout for a service call. A test passes one it finishes by hand.
    public var sleep: @MainActor (Duration) async throws -> Void

    /// Creates a host.
    public init(feed: (any ServerUIFlowFeed)? = nil,
                call: @escaping (String, String, [String: JSONValue], [String: JSONValue], Duration) async throws -> JSONValue = { _, _, _, _, _ in .null },
                held: @escaping (String) -> ServerUIFlowSources.HeldEntity? = { _ in nil },
                read: @escaping (String, [String]) -> JSONValue? = { _, _ in nil },
                statesReady: @escaping () -> Bool = { true },
                environment: @escaping () -> (viewer: ServerUIViewer?, locale: Locale?) = { (nil, nil) },
                clock: @escaping () -> ServerUIClock? = { nil },
                sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.feed = feed
        self.call = call
        self.held = held
        self.read = read
        self.statesReady = statesReady
        self.environment = environment
        self.clock = clock
        self.sleep = sleep
    }
}

// MARK: - Running off the main thread

/// Evaluates flows away from the main thread. One run at a time; the evaluator is pure and total, so the session decides which run is current.
public actor ServerUIFlowRunner {
    /// Creates a runner.
    public init() {}

    /// Runs `flow` on `response`.
    public func run(_ flow: ServerUIFlow, response: JSONValue, context: ServerUIFlowContext) -> ServerUIFlowRun {
        ServerUIFlowEvaluator.run(flow, response: response, context: context)
    }
}

extension ServerUIOperand {
    /// The `(source, path)` reads a flow parameter makes. A flow reads only through a parameter (the typing refuses any other), so only
    /// `read` and the operands that hold one are walked.
    var flowReads: [ServerUIFlowSession.ReadKey] {
        switch self {
        case .read(let id, let path, _): [.init(sourceId: id, path: path)]
        case .format(_, let args, _): args.values.flatMap(\.flowReads)
        case .map(let of, let cases, let otherwise): of.flowReads + cases.flatMap(\.then.flowReads) + otherwise.flowReads
        case .math(_, let args), .list(let args): args.flatMap(\.flowReads)
        case .object(let fields): fields.values.flatMap(\.flowReads)
        case .date(let from, let to), .progress(let from, let to), .secondsBetween(let from, let to): from.flowReads + to.flowReads
        case .choose(let cases, let otherwise): cases.flatMap { $0.then.flowReads } + otherwise.flowReads
        case .literal, .control, .viewer, .item, .index, .param, .clock, .rawState, .lastChanged, .listCount, .listIncludes: []
        }
    }
}

// MARK: - The session

/// Runs one Data Flow that provides the rows of a collection, or the records a `repeat` draws (`sh.repeat@1`).
///
/// A session asks for its data (a service's response, an entity's attribute, the held entities, or a pushed subscription), evaluates the
/// flow on the runner, and publishes one result to its ``ServerUIRowCollection`` per change. Everything it reads goes through the app's
/// stores inside an observation, so an entity's change runs the flow once more and nothing else does. A failure or a run over budget
/// leaves the last good rows showing (phase `stale`, or `failed` when there never were any); the feed's own resubscribe after a
/// reconnect brings the next push, which is then shown without the list blanking.
@MainActor
public final class ServerUIFlowSession {
    /// A declared source's field a parameter reads.
    struct ReadKey: Hashable, Sendable {
        let sourceId: String
        let path: [String]
    }

    /// The flow this session runs.
    public let flow: ServerUIFlow
    /// The collection it fills.
    public let collection: ServerUIRowCollection
    /// How many runs have been published, for tests.
    public private(set) var publications = 0

    private let host: ServerUIFlowHost
    private let runner = ServerUIFlowRunner()
    private var generation = 0
    private var hasGoodRows = false
    private var lastPush: JSONValue?
    private var cancelFeed: (@Sendable () -> Void)?
    private var feedTask: Task<Void, Never>?
    private var feedEnd: (() -> Void)?
    private var runTask: Task<Void, Never>?
    private var started = false
    /// The last answer of a service call, so a minute that passes runs the flow again without calling the service again.
    private var lastServiceResponse: JSONValue?
    /// Counts the observations taken: only the latest one's change runs the flow. A clock run publishes (``generation``) without taking a new
    /// observation, so it must not end the entity watch.
    private var observation = 0
    /// Set when the last fresh fetch or push failed; a run on data that is not newer (a clock tick) keeps the list `stale` until a fresh answer.
    private var degraded = false
    private var lastContext: ServerUIFlowContext?
    private var inFlight = false
    private var clockWatch = 0

    /// Creates a session. Nothing runs until ``start()``.
    public init(flow: ServerUIFlow, collection: ServerUIRowCollection, host: ServerUIFlowHost) {
        self.flow = flow
        self.collection = collection
        self.host = host
        collection.refresher = { [weak self] in await self?.refresh() }
    }

    deinit {
        cancelFeed?()
        feedTask?.cancel()
        runTask?.cancel()
    }

    // MARK: Lifecycle

    /// Begins: subscribes for a feed, or runs the flow once (`refresh.on` has `open`, and a flow without one runs on open).
    public func start() {
        guard !started else { return }
        started = true
        guard flow.givesList else {
            try? collection.apply(nil, phase: .unavailable)
            return
        }
        if let subscription = flow.subscription {
            guard let feed = host.feed else { fail(); return }
            let (stream, continuation) = AsyncStream<Result<JSONValue, Error>>.makeStream()
            feedEnd = { continuation.finish() }
            cancelFeed = feed.subscribe(subscription) { continuation.yield($0) }
            feedTask = Task { @MainActor [weak self] in
                for await result in stream {
                    guard let self else { return }
                    switch result {
                    case .success(let push): self.lastPush = push; self.evaluate()
                    case .failure: self.fail()
                    }
                }
            }
        } else {
            evaluate()
        }
        watchClock()
    }

    /// Ends the session: no run publishes after this.
    public func stop() {
        started = false
        generation += 1
        cancelFeed?()
        cancelFeed = nil
        clockWatch += 1
        feedEnd?()
        feedEnd = nil
        feedTask?.cancel()
        runTask?.cancel()
    }

    /// Pull to refresh: runs the flow again, and ends when its result is published. A feed has nothing to pull; it already follows.
    public func refresh() async {
        guard started, flow.refreshesManually || flow.refresh == nil else { return }
        evaluate()
        await runTask?.value
    }

    // MARK: Running

    /// The rows an `entities` or `entity-attribute` request, or a `none` request, hands the first step, or `nil` when the request needs a call.
    private func localResponse() -> JSONValue? {
        switch flow.request {
        case .entities(let ids, let attributes):
            return ServerUIFlowSources.entityRows(entityIds: ids, attributes: attributes, held: host.held)
        case .entityAttribute(let id, let path, _):
            guard let entity = host.held(id) else { return .null }
            return ServerUIOperand.value(at: path, in: .object(entity.attributes))
        case .none: return .null
        case .subscription: return lastPush
        case .serviceResponse: return nil
        }
    }

    /// Everything the run reads on the main actor, as plain values. Called inside an observation.
    private func snapshot(clock: ServerUIClock?) -> (context: ServerUIFlowContext, response: JSONValue?, waiting: Bool) {
        let ready = host.statesReady()
        let environment = host.environment()
        var values: [ReadKey: JSONValue] = [:]
        for key in flow.parameters.flatMap(\.value.flowReads) where values[key] == nil {
            if let value = host.read(key.sourceId, key.path) { values[key] = value }
        }
        let held = values
        let context = ServerUIFlowContext(clock: clock, viewer: environment.viewer, locale: environment.locale) { id, path in
            held[.init(sourceId: id, path: path)]
        }
        let waiting = !ready && flow.readsHeldEntities
        let response = waiting ? nil : localResponse()
        if case .serviceResponse = flow.request, flow.refresh?.on.contains(.entityChange) == true {
            for id in flow.watchedEntityIds { _ = host.held(id) }
        }
        return (context, response, waiting)
    }

    /// Takes the snapshot under an observation that runs the flow again on the next change, then runs it.
    ///
    /// - Parameter clockOnly: The run was started by the clock, on data it already had.
    private func evaluate(clockOnly: Bool = false) {
        guard started else { return }
        // A feed's first push has not come: there is nothing to run on yet.
        if flow.subscription != nil, lastPush == nil { return }
        generation += 1
        observation += 1
        let mine = generation, watch = observation
        runTask?.cancel()
        // The clock is watched on its own (``watchClock()``): a tick must not call the service again.
        let clock = flow.readsClock ? host.clock() : nil
        let taken = withObservationTracking({ snapshot(clock: clock) }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.started, self.observation == watch else { return }
                // A feed's data is only as new as its last push: a change to what the flow reads reuses it.
                self.evaluate(clockOnly: self.flow.subscription != nil)
            }
        })
        inFlight = !taken.waiting
        if taken.waiting { return }
        lastContext = taken.context
        let flow = flow
        runTask = Task { @MainActor [weak self] in
            defer { if let self, self.generation == mine { self.inFlight = false } }
            var response = taken.response
            if response == nil {
                guard let call = ServerUIFlowEvaluator.serviceCall(flow, context: taken.context), let timeout = flow.timeout else {
                    self?.fail(mine); return
                }
                guard let self else { return }
                do { response = try await self.callService(call, timeout: timeout) } catch { self.fail(mine); return }
                guard self.generation == mine, !Task.isCancelled else { return }
                self.lastServiceResponse = response
            }
            guard let self, let response, self.generation == mine, !Task.isCancelled else { return }
            await self.run(response, context: taken.context, mine: mine, fresh: !clockOnly)
        }
    }

    private func run(_ response: JSONValue, context: ServerUIFlowContext, mine: Int, fresh: Bool) async {
        let run = await runner.run(flow, response: response, context: context)
        guard generation == mine, !Task.isCancelled else { return }
        publish(run, fresh: fresh)
    }

    // MARK: Service calls

    /// Why a service call did not answer in time.
    struct CallTimeout: Error, Equatable {}

    /// Calls the service and gives up after `timeout`: HAKit drops a command that was in flight when the socket closed without answering it,
    /// so a call must never wait for ever (a first open would stay on "Loading", and a pull would never end).
    private func callService(_ call: (domain: String, service: String, target: [String: JSONValue], data: [String: JSONValue]),
                             timeout: Duration) async throws -> JSONValue {
        let host = host
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            let once = SingleUse()
            let waiter = Task { @MainActor in
                try? await host.sleep(timeout)
                guard !Task.isCancelled, once.claim() else { return }
                continuation.resume(throwing: CallTimeout())
            }
            let calling = Task { @MainActor in
                do {
                    let answer = try await host.call(call.domain, call.service, call.target, call.data, timeout)
                    if once.claim() { waiter.cancel(); continuation.resume(returning: answer) }
                } catch {
                    if once.claim() { waiter.cancel(); continuation.resume(throwing: error) }
                }
            }
            // The wait ends at the timeout, or when the call answers. A stop or a newer run does not end it early: its result is discarded by
            // the generation check, and the timeout is at most 30 s.
            Task { @MainActor in
                _ = await waiter.result
                calling.cancel()
            }
        }
    }

    // MARK: The clock

    /// Watches the app's clock for a flow that reads it: when the minute moves, the flow runs again on what it last got. Re-armed on each change;
    /// reading the clock here is what keeps the app's tick running.
    private func watchClock() {
        guard flow.readsClock, started else { return }
        let watch = clockWatch
        withObservationTracking({ _ = host.clock() }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.started, self.clockWatch == watch else { return }
                self.clockMoved()
                self.watchClock()
            }
        })
    }

    /// The clock moved: runs the flow again without asking for its data again.
    private func clockMoved() {
        guard flow.givesList else { return }
        guard case .serviceResponse = flow.request else { evaluate(clockOnly: true); return }
        // A call in flight reads the clock when it runs; with no answer yet there is nothing to run on.
        guard !inFlight, let cached = lastServiceResponse, var context = lastContext else { return }
        context.clock = host.clock()
        lastContext = context
        generation += 1
        let mine = generation
        runTask?.cancel()
        runTask = Task { @MainActor [weak self] in await self?.run(cached, context: context, mine: mine, fresh: false) }
    }

    /// Publishes a run. A run on data that is not newer than what failed (`fresh` false, after a refused push or a call that timed out) keeps
    /// the list `stale`: only a real answer clears it.
    private func publish(_ run: ServerUIFlowRun, fresh: Bool) {
        publications += 1
        let phase: ServerUIRowCollection.Phase = !fresh && degraded ? .stale : .ready
        let published: Bool
        if run.status != .ok { published = false }
        else if flow.givesRecords { published = (try? collection.apply(records: run.records, phase: phase)) != nil }
        else { published = (try? collection.apply(run.rows, phase: phase)) != nil }
        if published {
            hasGoodRows = true
            if fresh { degraded = false }
        } else {
            fail()
        }
    }

    private func fail(_ run: Int? = nil) {
        if let run, run != generation { return }
        degraded = true
        try? collection.apply(nil, phase: hasGoodRows ? .stale : .failed)
    }
}
