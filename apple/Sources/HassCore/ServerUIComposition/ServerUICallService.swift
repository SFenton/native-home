import Foundation

// MARK: - Authored service call

/// An authored Home Assistant service call: any `domain.service`, a target, data built from operands, optimistic feedback and an
/// optional confirmation. Home Assistant enforces what the signed-in user may call; the app keeps no allow list.
///
/// A call runs only on a user gesture (a tap, a control change, a menu choice, a confirmed alert). Nothing in the grammar can
/// fire it on appear, on a timer or on an entity change, which is what keeps Home Assistant the only place automation lives.
public struct ServerUICallService: Equatable, Sendable {
    /// The keys Home Assistant accepts in a target.
    public static let targetKeys = ["entity_id", "device_id", "area_id", "floor_id", "label_id"]

    /// A value shown for an entity until Home Assistant confirms it (feedback only, cleared on confirmation, failure or timeout).
    public struct Optimistic: Equatable, Sendable {
        /// The declared `ha-entity` source whose entity shows the value.
        public let sourceId: String
        /// The state shown.
        public let value: String
        public let revertAfterSeconds: Double
        public let failsOnTimeout: Bool

        /// Creates an optimistic value.
        public init(sourceId: String, value: String, revertAfterSeconds: Double, failsOnTimeout: Bool) {
            self.sourceId = sourceId
            self.value = value
            self.revertAfterSeconds = revertAfterSeconds
            self.failsOnTimeout = failsOnTimeout
        }
    }

    /// A call with every operand evaluated.
    public struct Resolved: Equatable, Sendable {
        public let domain: String
        public let service: String
        /// Service data, with the target keys merged in (Home Assistant accepts them there).
        public let data: [String: JSONValue]
    }

    public let domain: String
    public let service: String
    /// Operands for the target keys; each evaluates to an id or a list of ids.
    public let target: [String: ServerUIOperand]
    public let data: [String: ServerUIOperand]
    public let optimistic: [Optimistic]
    /// `policy` sends at once; `additional` asks first.
    public let confirmation: ServerUICompositionDocument.Confirmation
    /// Users who skip the confirmation (Home Assistant's `exemptions`).
    public let exemptUserIds: [String]
    /// Ask only while this holds (`sh.confirm-when@1`); `nil` always asks. A condition that cannot be answered asks.
    public let confirmWhen: ServerUIPredicate?

    /// Creates a call.
    public init(domain: String, service: String, target: [String: ServerUIOperand] = [:], data: [String: ServerUIOperand] = [:],
                optimistic: [Optimistic] = [], confirmation: ServerUICompositionDocument.Confirmation = .policy,
                exemptUserIds: [String] = [], confirmWhen: ServerUIPredicate? = nil) {
        self.domain = domain
        self.service = service
        self.target = target
        self.data = data
        self.optimistic = optimistic
        self.confirmation = confirmation
        self.exemptUserIds = exemptUserIds
        self.confirmWhen = confirmWhen
    }

    /// Every source id the call reads or shows optimistically.
    public var sourceIds: Set<String> {
        let operands = Array(target.values) + Array(data.values)
        return operands.reduce(into: Set(optimistic.map(\.sourceId)).union(confirmWhen?.sourceIds ?? [])) { $0.formUnion($1.sourceIds) }
    }

    /// Whether the confirmation is asked of `viewer`, from what the house says now: an `additional` question is asked unless the viewer
    /// is exempt or the `confirmWhen` rule answers no (``ServerUIControlRules/asksFirst(_:in:)``).
    public func asksConfirmation(of viewer: ServerUIViewer?, in environment: some ServerUIReading) -> Bool {
        guard case .additional = confirmation else { return false }
        if let id = viewer?.userId, exemptUserIds.contains(id) { return false }
        return ServerUIControlRules.asksFirst(confirmWhen, in: environment)
    }

    /// Evaluates the target and data now (at gesture time) and returns the call, or `nil` when anything it needs is not available.
    public func resolve(_ environment: some ServerUIReading) -> Resolved? {
        var merged: [String: JSONValue] = [:]
        for (key, operand) in data {
            guard let value = operand.evaluate(environment).json else { return nil }
            merged[key] = value
        }
        for (key, operand) in target {
            guard let value = operand.evaluate(environment).json, Self.isIdentifier(value) else { return nil }
            merged[key] = value
        }
        return Resolved(domain: domain, service: service, data: merged)
    }

    private static func isIdentifier(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let text): !text.isEmpty
        case .array(let items): !items.isEmpty && items.allSatisfy { if case .string(let text) = $0 { !text.isEmpty } else { false } }
        default: false
        }
    }
}
