#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Canonical wake status

/// The modal subtitle and integration/command feedback shared by native and authored wake sheets.
@MainActor
final class UKWakeStatusView: UIStackView {
    private let controller: WakeLightController
    private let unavailableText: String?
    private let subtitle = UKDeviceText.subheadline("")
    private let alerts = UIStackView()
    private var alertSignature = ""
    private let bag = UKObservationBag()

    init(controller: WakeLightController, identifier: String = "wake", unavailableText: String? = nil) {
        self.controller = controller
        self.unavailableText = unavailableText
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.xl
        subtitle.accessibilityIdentifier = identifier + ".subtitle"
        alerts.axis = .vertical
        alerts.spacing = HassTokens.Spacing.m
        [subtitle, alerts].forEach(addArrangedSubview)
        bag.observe { [weak self] in self?.apply(identifier: identifier) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply(identifier: String) {
        let live = controller.live
        subtitle.text = !live.available && unavailableText != nil
            ? unavailableText : WakeLight.subtitle(controller.snapshot, modal: true)
        var views: [UIView] = []
        var key = ""
        if !live.compatible && live.contractVersion > 0 {
            views.append(UKInlineAlertView("Editing wake light alarms requires an integration update. Saved alarms remain available to view."))
            key += "compat"
        } else if !live.available {
            views.append(UKInlineAlertView(WakeLight.errorMessage("unavailable")))
            key += "unavailable"
        }
        if let error = controller.error {
            let alert = UKInlineAlertView(error, severity: .error)
            alert.accessibilityIdentifier = identifier + ".error"
            views.append(alert)
            key += "error:\(error)"
        }
        if key != alertSignature {
            alertSignature = key
            alerts.ukSetArranged(views)
            alerts.isHidden = views.isEmpty
        }
        ukRemeasureContainers(includingSelf: true)
    }
}
#endif
