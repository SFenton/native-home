#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// One stage row: an adjustable element named "<Stage> level", with its two step buttons.
@MainActor
final class UKStageRowView: UIView {
    private let controller: BedSideController
    private let phase: SchedulePhase
    private let row: UKBedroomRow
    private let down: UIButton
    private let up: UIButton
    private var element: UKAdjustableElement!
    private let bag = UKObservationBag()

    init(controller: BedSideController, phase: SchedulePhase, label: String? = nil) {
        self.controller = controller
        self.phase = phase
        let label = label ?? phase.label
        down = Self.stepButton("minus", label: "Lower \(label)", id: "bed.stage.\(phase.rawValue).down")
        up = Self.stepButton("plus", label: "Raise \(label)", id: "bed.stage.\(phase.rawValue).up")
        let steps = UIStackView(arrangedSubviews: [down, up])
        steps.axis = .horizontal
        steps.spacing = HassTokens.Spacing.s
        row = UKBedroomRow(symbol: phase.symbol, title: label, lines: [""], trailing: steps)
        super.init(frame: .zero)
        addSubview(row)
        row.ukPin(to: self)
        element = UKAdjustableElement(accessibilityContainer: self)
        self.element.accessibilityLabel = "\(label) level"
        self.element.accessibilityIdentifier = "bed.stage.\(phase.rawValue)"
        self.element.accessibilityTraits = .adjustable
        self.element.increment = { [weak self] in self?.step(up: true) }
        self.element.decrement = { [weak self] in self?.step(up: false) }
        down.addAction(UIAction { [weak self] _ in self?.step(up: false) }, for: .touchUpInside)
        up.addAction(UIAction { [weak self] _ in self?.step(up: true) }, for: .touchUpInside)
        isAccessibilityElement = false
        bag.observe { [weak self] in self?.apply() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func stepButton(_ symbol: String, label: String, id: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.bodyEmphasis())), for: .normal)
        button.tintColor = UKDesignInk.primary
        button.backgroundColor = UKDesignSurface.separator
        button.layer.cornerRadius = HassTokens.minTarget / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: HassTokens.minTarget),
            button.heightAnchor.constraint(equalToConstant: HassTokens.minTarget),
        ])
        button.accessibilityLabel = label
        button.accessibilityIdentifier = id
        return button
    }

    private func step(up: Bool) {
        guard controller.canStepStage(phase) else { return }
        controller.stepStage(phase, up: up)
    }

    private func apply() {
        let level = controller.stageLevel(phase)
        let enabled = controller.canStepStage(phase)
        let range = controller.stageRange(phase).range
        let text = controller.activePhase == phase ? "\(BedLevel.format(level)) · Now" : BedLevel.format(level)
        row.setLines([text])
        down.isEnabled = enabled && (level ?? range.lowerBound) > range.lowerBound
        up.isEnabled = enabled && (level ?? range.upperBound) < range.upperBound
        down.alpha = down.isEnabled ? 1 : 0.4
        up.alpha = up.isEnabled ? 1 : 0.4
        element.accessibilityValue = BedLevel.format(level)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshElementFrame()
    }

    /// The adjustable element covers the row up to the step buttons, which are elements of their own (an element over them would
    /// take their taps from assistive technologies). Read again whenever the elements are asked for: a frame set only from a
    /// layout pass stayed one point wide in a wide form sheet (the iPad audit's "Hit area is too small", 2026-11-02).
    private func refreshElementFrame() {
        row.layoutIfNeeded()
        let steps = down.superview.map { $0.convert($0.bounds, to: self) } ?? .zero
        let width = steps.minX > 1 ? steps.minX : bounds.width
        element.accessibilityFrameInContainerSpace = CGRect(x: 0, y: 0, width: max(width, HassTokens.minTarget), height: max(bounds.height, HassTokens.minTarget))
    }

    override var accessibilityElements: [Any]? {
        get {
            refreshElementFrame()
            return [element as Any, down, up]
        }
        set {}
    }
}

#endif
