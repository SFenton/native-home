#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A switch or input_boolean as a system switch, sending `homeassistant.toggle` (`ClimateToggleRow`). What it does goes under it in
/// the section footer, and VoiceOver reads it as the hint.
@MainActor
final class UKClimateToggleRowView: UKRowView {
    private let bag = UKObservationBag()
    private let toggle: UKActionToggle

    init(controller: ClimateController, entityId: String, title: String, icon: String, detail: String?) {
        toggle = UKActionToggle(isOn: controller.isOn(entityId)) { controller.toggle(entityId) }
        super.init(.init(title, symbol: ClimateStyle.symbol(icon), style: .form), surface: .sheet)
        toggle.accessibilityLabel = title
        toggle.accessibilityHint = detail ?? ""
        toggle.accessibilityIdentifier = "climate.toggle.\(entityId)"
        setAccessory(toggle)
        isTextAccessible = false
        bag.observe { [weak self] in
            guard let self else { return }
            toggle.show(controller.isOn(entityId))
            let available = !controller.isUnavailable(entityId)
            toggle.isEnabled = available
            alpha = available ? 1 : 0.4
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

@MainActor
enum UKClimateRows {
    /// `view` with the row's vertical padding, as a stack (a stack reports a finite fitted height; a bare holder view pinned
    /// around a stack reported an infinite one inside a list cell).
    static func padded(_ view: UIView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [view])
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.s, leading: 0, bottom: HassTokens.Spacing.s, trailing: 0)
        return stack
    }

    static func toggle(_ controller: ClimateController, entityId: String, title: String, icon: String, detail: String?) -> UKFormRowSpec {
        UKFormRowSpec(id: "toggle.\(entityId)") {
            UKClimateToggleRowView(controller: controller, entityId: entityId, title: title, icon: icon, detail: detail)
        }
    }

    static func toggleSection(_ controller: ClimateController, entityId: String, title: String, icon: String, detail: String, header: String? = nil) -> UKFormSectionSpec {
        UKFormSectionSpec(id: "section.\(entityId)", header: header, footer: detail,
                          rows: [toggle(controller, entityId: entityId, title: title, icon: icon, detail: detail)])
    }

    /// A row with a plain label.
    static func text(_ id: String, _ build: @escaping () -> UIView) -> UKFormRowSpec { UKFormRowSpec(id: id, build: build) }
}

// MARK: - Rooms

#endif
