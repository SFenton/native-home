import Foundation
import Observation

// MARK: - What a session needs from the app

/// What a ``ServerUIFlowSession`` reads and calls. The app builds one over its connection and entity store; a test builds one by hand.
@MainActor
public struct ServerUIFlowHost {
    /// The live feed, for a `ha-subscription` request.
    public var feed: (any ServerUIFlowFeed)?
    /// Calls a service with `return_response` and gives its response.
    public var call: (_ domain: String, _ service: String, _ target: [String: JSONValue], _ data: [String: JSONValue]) async throws -> JSONValue
    /// What the app holds about an entity. Read inside an observation, so a change to the entity runs the flow again.
    public var held: (_ entityId: String) -> ServerUIFlowSources.HeldEntity?
    /// The value of a declared source's field (a parameter's `read`), as the app's operand evaluator reads it.
    public var read: (_ sourceId: String, _ path: [String]) -> JSONValue?
    /// Whether the app has received its first entity states. Until it has, a flow over held entities waits instead of drawing them unavailable.
    public var statesReady: () -> Bool
    /// The clock, the viewer and the locale. Read inside an observation.
    public var environment: () -> (clock: ServerUIClock?, viewer: ServerUIViewer?, locale: Locale?)

    /// Creates a host.
    public init(feed: (any ServerUIFlowFeed)? = nil,
                call: @escaping (String, String, [String: JSONValue], [String: JSONValue]) async throws -> JSONValue = { _, _, _, _ in .null },
                held: @escaping (String) -> ServerUIFlowSources.HeldEntity? = { _ in nil },
                read: @escaping (String, [String]) -> JSONValue? = { _, _ in nil },
                statesReady: @escaping () -> Bool = { true },
                environment: @escaping () -> (clock: ServerUIClock?, viewer: ServerUIViewer?, locale: Locale?) = { (nil, nil, nil) }) {
        self.feed = feed
        self.call = call
        self.held = held
        self.read = read
        self.statesReady = statesReady
        self.environment = environment
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
        case .date(let from, let to): from.flowReads + to.flowReads
        case .choose(let cases, let otherwise): cases.flatMap { $0.then.flowReads } + otherwise.flowReads
        case .literal, .control, .viewer, .item, .param, .clock, .rawState, .listCount, .listIncludes: []
        }
    }
}

// MARK: - The session

/// Runs one Data Flow that provides the rows of a collection.
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
    private var runTask: Task<Void, Never>?
    private var started = false

    /// Creates a session. Nothing runs until ``start()``.
    public init(flow: ServerUIFlow, collection: ServerUIRowCollection, host: ServerUIFlowHost) {
        self.flow = flow
        self.collection = collection
        self.host = host
        collection.refresher = { [weak self] in await self?.refresh() }
    }

    deinit {
        cancelFeed?()
    }

    // MARK: Lifecycle

    /// Begins: subscribes for a feed, or runs the flow once (`refresh.on` has `open`, and a flow without one runs on open).
    public func start() {
        guard !started else { return }
        started = true
        guard flow.givesRows else {
            try? collection.apply(nil, phase: .unavailable)
            return
        }
        if let subscription = flow.subscription {
            guard let feed = host.feed else { fail(); return }
            let (stream, continuation) = AsyncStream<Result<JSONValue, Error>>.makeStream()
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
    }

    /// Ends the session: no run publishes after this.
    public func stop() {
        started = false
        generation += 1
        cancelFeed?()
        cancelFeed = nil
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
    private func snapshot() -> (context: ServerUIFlowContext, response: JSONValue?, waiting: Bool) {
        let ready = host.statesReady()
        let environment = host.environment()
        var values: [ReadKey: JSONValue] = [:]
        for key in flow.parameters.flatMap(\.value.flowReads) where values[key] == nil {
            if let value = host.read(key.sourceId, key.path) { values[key] = value }
        }
        let held = values
        let context = ServerUIFlowContext(clock: environment.clock, viewer: environment.viewer, locale: environment.locale) { id, path in
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
    private func evaluate() {
        guard started else { return }
        // A feed's first push has not come: there is nothing to run on yet.
        if flow.subscription != nil, lastPush == nil { return }
        generation += 1
        let mine = generation
        runTask?.cancel()
        let taken = withObservationTracking({ snapshot() }, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.started, self.generation == mine else { return }
                self.evaluate()
            }
        })
        if taken.waiting { return }
        let flow = flow, host = host
        runTask = Task { @MainActor [weak self] in
            var response = taken.response
            if response == nil {
                guard let call = ServerUIFlowEvaluator.serviceCall(flow, context: taken.context) else { self?.fail(mine); return }
                do { response = try await host.call(call.domain, call.service, call.target, call.data) } catch { self?.fail(mine); return }
            }
            guard let self, let response, self.generation == mine, !Task.isCancelled else { return }
            let run = await self.runner.run(flow, response: response, context: taken.context)
            guard self.generation == mine, !Task.isCancelled else { return }
            self.publish(run)
        }
    }

    private func publish(_ run: ServerUIFlowRun) {
        publications += 1
        if run.status == .ok, (try? collection.apply(run.rows, phase: .ready)) != nil {
            hasGoodRows = true
        } else {
            fail()
        }
    }

    private func fail(_ run: Int? = nil) {
        if let run, run != generation { return }
        try? collection.apply(nil, phase: hasGoodRows ? .stale : .failed)
    }
}
