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

#endif
