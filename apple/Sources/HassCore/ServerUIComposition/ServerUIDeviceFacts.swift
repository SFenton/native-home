import Foundation
import HassTelemetry

// MARK: - Degrade, never reject

/// One node the device drew with less than the document asked for. A device fact is never a reason to reject a publication;
/// the document stays valid and the node degrades (architecture.md, "Server-driven root", records the rule).
public struct ServerUIDegradation: Equatable, Sendable, CustomStringConvertible {
    /// What the device could not do.
    public enum Kind: String, Sendable {
        /// An SF Symbol this OS does not draw; the node draws ``ServerUIDeviceFacts/fallbackSymbol``.
        case symbol
        /// A chrome `priority` below the OS that honours it; the item acts as `normal`.
        case priority
        /// A `horizontalOnly` rail below the OS that honours it; the item acts as `eligible`.
        case rail
        /// A `shared` chrome group before glass; the group acts as `separate-circles`.
        case sharedGroup = "shared_group"
    }

    public let kind: Kind
    /// A JSON pointer into the document. Never document copy or an entity value.
    public let pointer: String

    /// Creates a server uidegradation.
    public init(_ kind: Kind, at pointer: String) {
        self.kind = kind
        self.pointer = pointer
    }

    public var description: String { "degraded_\(kind.rawValue) at \(pointer)" }
}

/// What this device can draw, and how a node degrades when it cannot.
///
/// The decisions are pure values so every gap is testable on any host. The UIKit layer builds the current device's facts once and
/// consults them wherever a node reads a symbol, a chrome priority, a rail or a group policy.
public struct ServerUIDeviceFacts: Sendable {
    /// Drawn in place of a symbol the OS lacks. Present since iOS 13.
    public static let fallbackSymbol = "questionmark.circle"

    /// Whether the OS draws shared-material bar groups (Liquid Glass).
    public var hasGlass: Bool
    /// Whether chrome items honour a visibility priority.
    public var supportsPriority: Bool
    /// Whether chrome items honour a horizontal-only axis.
    public var supportsHorizontalOnlyRail: Bool
    /// Whether the OS draws the named SF Symbol.
    public var drawsSymbol: @Sendable (String) -> Bool

    /// Creates a server uidevice facts.
    public init(hasGlass: Bool, supportsPriority: Bool, supportsHorizontalOnlyRail: Bool,
                drawsSymbol: @escaping @Sendable (String) -> Bool) {
        self.hasGlass = hasGlass
        self.supportsPriority = supportsPriority
        self.supportsHorizontalOnlyRail = supportsHorizontalOnlyRail
        self.drawsSymbol = drawsSymbol
    }

    /// A device that draws everything, for hosts that do not model OS gaps.
    public static let unrestricted = ServerUIDeviceFacts(hasGlass: true, supportsPriority: true,
                                                         supportsHorizontalOnlyRail: true, drawsSymbol: { _ in true })

    // MARK: Effective values

    /// The symbol to draw for `name`: the name itself, or the fallback when the OS cannot draw it.
    public func symbol(_ name: String) -> String { drawsSymbol(name) ? name : Self.fallbackSymbol }

    /// The priority the item acts with.
    public func priority(_ value: ServerUICompositionDocument.Priority) -> ServerUICompositionDocument.Priority { supportsPriority ? value : .normal }

    /// The rail the item acts with.
    public func rail(_ value: ServerUICompositionDocument.Rail) -> ServerUICompositionDocument.Rail { supportsHorizontalOnlyRail ? value : .eligible }

    /// The horizontal policy a group acts with.
    public func horizontal(_ value: ServerUICompositionDocument.Policy) -> ServerUICompositionDocument.Policy { value == .shared && !hasGlass ? .separateCircles : value }

    // MARK: Diagnostics

    /// The degrade for a symbol, or nil when the OS draws it.
    public func degradation(symbol name: String, at pointer: String) -> ServerUIDegradation? {
        drawsSymbol(name) ? nil : ServerUIDegradation(.symbol, at: pointer)
    }

    /// Every chrome degrade in `groups`, with its pointer. The symbols of items are the caller's.
    public func degradations(groups: [ServerUICompositionDocument.ChromeGroup], at pointer: String) -> [ServerUIDegradation] {
        var result: [ServerUIDegradation] = []
        for (index, group) in groups.enumerated() {
            let path = pointer + "/\(index)"
            if horizontal(group.horizontal) != group.horizontal { result.append(.init(.sharedGroup, at: path + "/horizontal")) }
            for (itemIndex, item) in group.items.enumerated() {
                guard case .button(let button) = item else { continue }
                let itemPath = path + "/items/\(itemIndex)"
                if priority(button.priority) != button.priority { result.append(.init(.priority, at: itemPath + "/priority")) }
                if rail(button.rail) != button.rail { result.append(.init(.rail, at: itemPath + "/rail")) }
            }
        }
        return result
    }
}

/// A tiny lock-guarded box for state read from any thread (the once-per-style telemetry set).
final class LockedState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}

extension ServerUIDegradation {
    /// Records the degrade for the diagnostic stream: the kind and pointer only.
    public func record() {
        Telemetry.event("serverui.degraded", detail: description)
    }
}
