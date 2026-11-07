#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The caption under a slider or dial that says what failed (`FailureCaption`): one footnote line in the error ink, wrapping at
/// large text, with the error haptic and a VoiceOver announcement each time ``TransientFailure/show(_:)`` runs. It takes no room
/// while empty.
public final class UKFailureCaption: UIView {
    private let label = UILabel()
    private let failure: TransientFailure
    private let bag = UKObservationBag()
    private var lastCount: Int

    public init(_ failure: TransientFailure) {
        self.failure = failure
        lastCount = failure.count
        super.init(frame: .zero)
        label.font = UKFont.preferred(.footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(HassTokens.RGB.Ink.error)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.accessibilityIdentifier = "failureCaption"
        addSubview(label)
        label.ukPin(to: self)
        bag.observe { [weak self] in self?.sync() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func sync() {
        let message = failure.message
        let count = failure.count
        label.text = message
        label.isHidden = message == nil
        isHidden = message == nil
        if count != lastCount {
            lastCount = count
            if let message {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                announceFailure(message)
            }
        }
    }
}

/// A ``UKThermostatDial`` bound to one climate entity in the ``EntityStore`` (`ClimateThermostatDial`). Commits call
/// `climate.set_temperature` on that entity, or on `commitEntityIds` when set (the web sends the global virtual thermostat's range
/// to every room thermostat). A rejected call rolls the handles back to Home Assistant's setpoints and a caption says why
/// (pattern optimistic-actions, "Failure").
///
/// ```swift
/// let dial = UKClimateThermostatDial(context: context, entityId: "climate.demo_room", title: "Demo Room", size: .modal)
/// ```
public final class UKClimateThermostatDial: UIView {
    public let entityId: String
    public let title: String
    public var commitEntityIds: ((ThermostatTargets) -> [String])?
    /// Shown instead of the entity's `hvac_action` (the Whole Home dial always shows the global thermostat's).
    public var action: String? { didSet { sync() } }
    /// Where commits go; nil uses the context's connection.
    public var caller: (any HassServiceCalling)?

    private let dial: UKThermostatDial
    private let failure = TransientFailure()
    private let caption: UKFailureCaption
    private let box: EntityBox
    private let connection: HassConnection?
    private let bag = UKObservationBag()
    private var rejections = 0

    init(context: UKContext, entityId: String, title: String, size: UKThermostatDial.Size = .page, action: String? = nil,
                caller: (any HassServiceCalling)? = nil, commitEntityIds: ((ThermostatTargets) -> [String])? = nil) {
        self.entityId = entityId
        self.title = title
        self.action = action
        self.caller = caller ?? context.caller
        self.commitEntityIds = commitEntityIds
        box = context.store.entity(entityId)
        connection = context.connection
        dial = UKThermostatDial(ThermostatDialConfiguration(entity: box.state, title: title), size: size, surface: context.surface) { _ in }
        caption = UKFailureCaption(failure)
        super.init(frame: .zero)
        dial.onCommit = { [weak self] targets in self?.commit(targets) }
        let column = UIStackView(arrangedSubviews: [dial, caption])
        column.axis = .vertical
        addSubview(column)
        column.ukPin(to: self)
        // The dial follows its entity's box and nothing else.
        bag.observe { [weak self] in self?.sync() }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func sync() {
        var configuration = ThermostatDialConfiguration(entity: box.state, title: title)
        if let action { configuration.action = action }
        dial.configuration = configuration
    }

    /// Sends a commit to ``caller``, else the context's connection.
    @discardableResult
    func commit(_ targets: ThermostatTargets) -> Task<Void, Never>? {
        let data = targets.setTemperatureData(entityIds: commitEntityIds?(targets) ?? [entityId])
        guard let target: any HassServiceCalling = caller ?? connection else { return nil }
        return Task { @MainActor [weak self] in
            do {
                try await target.callService("climate", "set_temperature", data: data)
            } catch {
                guard let self else { return }
                rejections += 1
                dial.rejection = ThermostatRejection(targets: targets, count: rejections)
                failure.show(targets.failureMessage)
            }
        }
    }
}
#endif
