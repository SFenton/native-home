import Foundation

// MARK: - Value-only room presentation

extension RoomCardDisplay {
    /// Shared by the feature binding and configured room primitives. State ownership stays with the caller.
    public static func resolve(_ card: RoomCard, entity: EntityState?, subtitle: String?, viewer: HouseholdResident? = nil) -> Self {
        let unavailable = RoomFormat.isUnavailable(entity)
        let disabled = entity.map { card.disabledStates.contains($0.state) } ?? false
        let active = entity.map { card.activeStates.contains($0.state) } == true || RoomFormat.isActive(entity)
        let muted = !unavailable && !active && RoomFormat.mutedWhenInactive.contains(card.kind)
        let semantics: RoomTileSemantics
        switch card.semantics {
        case .modal: semantics = .modal
        case .command: semantics = .command
        case .rule(let rule):
            switch rule.semantics(for: entity?.state) {
            case .toggle(let isOn): semantics = .toggle(isOn: isOn)
            case .selection(let selected): semantics = .selection(isSelected: selected)
            case .command: semantics = .command
            case .state: semantics = .state
            }
        case nil:
            switch card.action {
            case .flip: semantics = .toggle(isOn: active)
            case .remote: semantics = .command
            case nil: semantics = card.sheet == nil ? .state : .modal
            }
        }
        return Self(title: card.title(for: viewer), subtitle: subtitle, isUnavailable: unavailable,
                    isOff: unavailable || disabled || muted, isEnabled: card.hasInteraction && !unavailable && !disabled,
                    semantics: semantics, background: RoomFormat.background(card, entity, presence: nil))
    }
}
