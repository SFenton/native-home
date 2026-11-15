#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A tab's panel: a vertical stack that draws a snapshot of the state it shows and draws it again only when the snapshot changes.
@MainActor
class UKVacuumPanel<Snapshot: Equatable>: UIStackView {
    let controller: VacuumController
    let environment: UKTileEnvironment
    let bag = UKObservationBag()
    private var shown: Snapshot?

    init(controller: VacuumController, environment: UKTileEnvironment) {
        self.controller = controller
        self.environment = environment
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts following the state. Subclasses call it last in `init`.
    func start() {
        bag.observe { [weak self] in
            guard let self else { return }
            let next = self.snapshot()
            guard next != self.shown else { return }
            self.shown = next
            self.arrangedSubviews.forEach { self.removeArrangedSubview($0); $0.removeFromSuperview() }
            self.rebuild(next)
        }
    }

    /// Reads the observable state the panel draws.
    func snapshot() -> Snapshot { fatalError("subclasses override") }
    /// Draws `snapshot` into the arranged subviews.
    func rebuild(_ snapshot: Snapshot) {}
}

// MARK: - Controls

/// One row of the Info tab.
struct UKVacuumInfoRow: Equatable {
    var title: String
    var symbol: String
    var tint: UIColor
    var value: String
}

/// What the Info tab draws.
struct UKVacuumInfoSnapshot: Equatable {
    var bins: [UKVacuumInfoRow]
    var consumables: [UKVacuumInfoRow]
}

/// Bin state and consumables (`VacuumInfoTab`): rows with the value trailing, orange when it is soon and red when it is due.
@MainActor
final class UKVacuumInfoTab: UKVacuumPanel<UKVacuumInfoSnapshot> {
    typealias Row = UKVacuumInfoRow
    typealias Snapshot = UKVacuumInfoSnapshot

    override init(controller: VacuumController, environment: UKTileEnvironment) {
        super.init(controller: controller, environment: environment)
        spacing = HassTokens.Spacing.xl
        start()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func row(_ consumable: VacuumConfig.Consumable) -> Row {
        let entity = controller.store.entity(consumable.entityId).state
        let visual = VacuumVisual.consumable(consumable, state: entity?.state)
        let value = VacuumFormat.consumable(consumable, state: entity?.state, unit: entity?.attributes["unit_of_measurement"]?.string)
        return Row(title: consumable.title, symbol: UKVacuumStyle.symbol(visual.icon), tint: Self.tint(visual.tone), value: value)
    }

    override func snapshot() -> Snapshot {
        Snapshot(bins: controller.vacuum.consumables.filter { $0.valueKind == .status }.map(row),
                 consumables: controller.vacuum.consumables.filter { $0.valueKind == .duration }.map(row))
    }

    override func rebuild(_ s: Snapshot) {
        for (title, rows) in [("Bin State", s.bins), ("Consumables", s.consumables)] where !rows.isEmpty {
            let views = rows.map { item -> UIView in
                let value = UILabel.uk(.body, monospacedDigit: true, ink: item.tint, alignment: .right)
                value.text = item.value
                let view = UKRowView(.init(item.title, symbol: item.symbol, glyph: item.tint), accessory: value, surface: .sheet)
                view.isAccessibilityElement = true
                view.accessibilityLabel = item.title
                view.accessibilityValue = item.value
                view.accessibilityTraits = .staticText
                return view
            }
            addArrangedSubview(UKVacuumSection(title, content: [UKModuleListView(surface: .sheet, rows: views)]))
        }
    }

    /// Soon is orange and due is red; everything else, OK included, stays neutral.
    static func tint(_ tone: VacuumTone) -> UIColor {
        switch tone {
        case .warning, .danger: UKVacuumStyle.color(tone)
        default: UKDesignInk.secondary
        }
    }
}
#endif
