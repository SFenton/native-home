import HassCore
import HassDesign

// MARK: - Spec → item

/// HassDesign does not depend on HassCore, so the domain's ``TileActionSpec`` becomes the tile's presentational
/// ``TileActionItem`` here, field for field (pattern: `.agents/patterns/action-tiles.md`). The service call and the
/// optimistic intents stay with the spec; the feature view runs them.
extension TileActionItem {
    /// The item that draws `spec`.
    init(_ spec: TileActionSpec) {
        self.init(
            id: spec.id, verb: spec.verb, symbol: spec.symbol, isOn: spec.isOn, phase: Phase(spec.phase),
            feedback: Feedback(spec.feedback), isError: spec.isError, isEmphasized: spec.isEmphasized, label: spec.label,
            confirmation: spec.confirmation.map(TileActionConfirmation.init), selection: spec.selection.map(TileSelection.init)
        )
    }
}

extension TileActionConfirmation {
    /// The tile's question for a spec's.
    init(_ confirmation: TileActionSpec.Confirmation) {
        self.init(title: confirmation.title, message: confirmation.message, confirmVerb: confirmation.confirmVerb,
                  isDestructive: confirmation.isDestructive, style: confirmation.style == .dialog ? .dialog : .alert)
    }
}

extension TileSelection {
    /// The tile's selection for a spec's.
    init(_ selection: TileActionSpec.Selection) {
        switch selection {
        case let .single(isSelected): self = .single(isSelected: isSelected)
        case let .ordered(position): self = .ordered(position: position)
        }
    }
}

extension TileActionSpec.Confirmation {
    /// A spec's question in the app's one set of words (``AlertCopy``): a feature that already has an `AlertCopy.Spec` for the
    /// decision hands it here, so the tile and the sibling sites ask the same question.
    init(_ copy: AlertCopy.Spec, style: Style = .alert) {
        self.init(title: copy.title, message: copy.message, confirmVerb: copy.confirm.title,
                  isDestructive: copy.confirm.role == .destructive, style: style)
    }
}

extension TileActionItem.Phase {
    /// The tile's phase for a spec's.
    init(_ phase: TileActionSpec.Phase) {
        switch phase {
        case .ready: self = .ready
        case .inFlight: self = .inFlight
        case .unavailable: self = .unavailable
        }
    }
}

extension TileActionItem.Feedback {
    /// The tile's feedback kind for a spec's.
    init(_ feedback: TileActionSpec.Feedback) {
        switch feedback {
        case .momentary: self = .momentary
        case .optimistic: self = .optimistic
        case .tracked: self = .tracked
        }
    }
}

extension Sequence where Element == TileActionSpec {
    /// The items that draw these specs, in order.
    var items: [TileActionItem] { map(TileActionItem.init) }
}

// MARK: - Classification → behaviour

extension TileBehavior {
    /// The body behaviour for a classification: an action tile performs its primary, a navigation tile opens, a
    /// read-only tile is inert. HassCore decides the class once (``TileClassification``); this only renames it.
    /// - Parameters:
    ///   - classification: What the configured tile is.
    ///   - primary: The id of the action the body performs; an action tile with none is inert.
    init(_ classification: TileClassification, primary: TileActionSpec.ID?) {
        switch classification {
        case .action:
            if let primary { self = .perform(primary) } else { self = .inert }
        case .navigation:
            self = .navigate
        case .state:
            self = .inert
        }
    }
}

// MARK: - Running a spec

extension OptimisticActions {
    /// Runs `spec`'s service call, showing its optimistic values at once, or (tracked) its ``TileActionSpec/tracking`` values, the
    /// way a tapped lock shows "Unlocking…". Does nothing for a spec with no call.
    /// - Parameter failureKey: Where a rejected call with no optimistic value (previous, next) shows the failed face (``isFailed(_:)``).
    @discardableResult
    func perform(_ spec: TileActionSpec, failing failureKey: String? = nil) -> Task<Void, Never>? {
        guard let call = spec.call else { return nil }
        return perform(call, showing: spec.optimistic + spec.tracking, failing: failureKey)
    }
}

extension EntityState {
    /// This state with `value` over it (an optimistic value), or itself when `value` is nil or already the state. Providers
    /// are fed the *shown* state, so the view applies the overlay before asking.
    func showing(_ value: String?) -> EntityState {
        guard let value, value != state else { return self }
        return EntityState(entityId: entityId, state: value, attributes: attributes, lastChanged: lastChanged)
    }
}
