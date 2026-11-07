#if os(iOS)
import HassDesign
import UIKit

// MARK: - State message

/// An empty or error state (`StateMessage`): a glyph, a title, what it means and, for an error, one primary action. Plain
/// wrapping labels (never `ContentUnavailableView`, whose title clipped at large text). The container carries the
/// identifier, so the action keeps its own.
///
/// ```swift
/// let state = UKStateMessageView(symbol: "checklist", title: "No Chores Due", message: "Enjoy vacation!")
/// stateOverlay.show(state)            // centred in the space the page leaves (``UKStateMessageOverlay``)
/// ```
final class UKStateMessageView: UIView {
    let hasAction: Bool
    private let button: UKPrimaryButton?
    private var wrapLabels: [UILabel] = []

    /// - Parameters:
    ///   - symbol: The SF Symbol; decorative, hidden from VoiceOver.
    ///   - title: What is missing, in Title Case ("No Chores Due").
    ///   - message: What it means or what to do next.
    ///   - actionTitle: The one action (an error's "Try Again"), or nil for a state with none.
    ///   - actionIdentifier: The action button's own accessibility identifier (default `state.action`).
    ///   - action: What the action does; the button shows only with both this and `actionTitle`.
    ///   - actionBusyTitle: While non-nil the action is running: the button shows an inline arc and this title ("Trying Again").
    ///   - identifier: The state's accessibility identifier (default `state.message`).
    init(symbol: String, title: String, message: String? = nil, actionTitle: String? = nil, actionIdentifier: String? = nil,
         action: (() -> Void)? = nil, actionBusyTitle: String? = nil, identifier: String? = nil) {
        if let actionTitle, let action {
            let button = UKPrimaryButton(actionTitle, action: action)
            button.isBusy = actionBusyTitle != nil
            button.busyTitle = actionBusyTitle
            button.accessibilityIdentifier = actionIdentifier ?? "state.action"
            self.button = button
            hasAction = true
        } else {
            button = nil
            hasAction = false
        }
        super.init(frame: .zero)
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.largeTitle), scale: .large)))
        icon.tintColor = UKDesignInk.secondary
        icon.isAccessibilityElement = false
        let titleLabel = UILabel.uk(.title2, weight: .bold, ink: UKDesignInk.primary, alignment: .center)
        titleLabel.text = title
        titleLabel.accessibilityTraits = [.header, .staticText]
        let stack = UIStackView(arrangedSubviews: [icon, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = HassTokens.Spacing.s
        stack.setCustomSpacing(HassTokens.Spacing.s + HassTokens.Spacing.xs, after: icon)
        if let message {
            let body = UILabel.uk(.body, ink: UKDesignInk.secondary, alignment: .center)
            body.text = message
            stack.addArrangedSubview(body)
        }
        if let button {
            stack.setCustomSpacing(HassTokens.Spacing.m + HassTokens.Spacing.s, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 1])
            stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            // Centred, never stretched: a state taller than its content (a centred overlay) keeps its text together.
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: HassTokens.Spacing.xl),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -HassTokens.Spacing.xl),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HassTokens.Spacing.xl + HassTokens.Spacing.s),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(HassTokens.Spacing.xl + HassTokens.Spacing.s)),
        ])
        isAccessibilityElement = false
        accessibilityIdentifier = identifier ?? "state.message"
        wrapLabels = stack.arrangedSubviews.compactMap { $0 as? UILabel }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Title and message wrap within the page host's width (the overlay pins this view to it), not at their own last width.
        UKWrapWidth.set(wrapLabels, in: self, reserving: 2 * (HassTokens.Spacing.xl + HassTokens.Spacing.s))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A failed load's state with a Try Again button (``LoadFailure/stateMessage(identifier:retryIdentifier:retrying:retry:)``).
    convenience init(_ failure: LoadFailure, identifier: String, retryIdentifier: String, retrying: Bool, retry: @escaping () -> Void) {
        self.init(symbol: failure.symbol, title: failure.title, message: failure.message, actionTitle: AlertCopy.tryAgain,
                  actionIdentifier: retryIdentifier, action: retry, actionBusyTitle: retrying ? "Trying Again" : nil, identifier: identifier)
    }
}

/// A ``UKStateMessageView`` centred in a page of its own, scrolling once large text makes it taller than the page
/// (`CenteredStateMessage`). Touches fall through to whatever is behind it while it has no action and fits.
final class UKCenteredStateMessageView: UIScrollView {
    let state: UKStateMessageView

    init(_ state: UKStateMessageView) {
        self.state = state
        super.init(frame: .zero)
        alwaysBounceVertical = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        state.translatesAutoresizingMaskIntoConstraints = false
        addSubview(state)
        let minHeight = state.heightAnchor.constraint(greaterThanOrEqualTo: frameLayoutGuide.heightAnchor)
        minHeight.priority = .required
        NSLayoutConstraint.activate([
            state.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor), state.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            state.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor), state.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            state.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor), minHeight,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !state.hasAction, contentSize.height <= bounds.height + 0.5 { return nil }
        return super.hitTest(point, with: event)
    }
}

/// A sheet page whose whole body is one ``UKStateMessageView`` (a route that no longer exists, a tab with nothing to show): a real
/// ``UKPageViewController`` with the sheet surface, so it keeps the standard header and rail inset (modal-sheet, "Modal standard").
final class UKStatePageViewController: UKPageViewController {
    private let state: UKStateMessageView

    init(title: String?, state: UKStateMessageView) {
        self.state = state
        super.init(sheetTitle: title)
        navigationItem.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        install(scrollView: UKCenteredStateMessageView(state))
    }
}

/// Centres a ``UKStateMessageView`` in the space a list or scroll view leaves free (`View.stateMessage(isPresented:below:_:)`):
/// from whatever the page draws above it (the navigation bar, and a header passed as `below`) to the bottom safe area.
/// An overlay, not a row, so it sits in the middle of the free space.
///
/// ```swift
/// let overlay = UKStateMessageOverlay(host: view, below: quickLinks)
/// overlay.show(model.isEmpty ? UKStateMessageView(symbol: "checklist", title: "No Chores Due") : nil)
/// ```
@MainActor
final class UKStateMessageOverlay {
    private weak var host: UIView?
    private let below: UIView?
    private let leadingOnHinge: Bool
    private var current: UIView?
    private var centredView: UKCenteredStateMessageView?

    /// The state on screen, if any.
    var shown: UKStateMessageView? { centredView?.state }
    /// The view that holds the state (its hinge region), for fades.
    var container: UIView? { current }

    /// - Parameters:
    ///   - host: The view the state is drawn over.
    ///   - below: A header the state must stay under; nil for none.
    ///   - leadingOnHinge: On a window with a hinge band, place the state in the leading region (`HingeAvoidance`). Off by default;
    ///     the house-layout container turns it on.
    init(host: UIView, below: UIView? = nil, leadingOnHinge: Bool = false) {
        self.host = host
        self.below = below
        self.leadingOnHinge = leadingOnHinge
    }

    /// Shows `state`, or removes the current one for nil.
    func show(_ state: UKStateMessageView?) {
        current?.removeFromSuperview()
        current = nil
        centredView = nil
        guard let host, let state else { return }
        let centred = UKCenteredStateMessageView(state)
        // On a window with a hinge band the message sits in the leading region, never across the band (`HingeAvoidance`).
        let region = UKHingeClearingView(content: centred, leadingOnly: true, active: leadingOnHinge)
        region.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(region)
        NSLayoutConstraint.activate([
            region.topAnchor.constraint(equalTo: below?.bottomAnchor ?? host.safeAreaLayoutGuide.topAnchor),
            region.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor),
            region.leadingAnchor.constraint(equalTo: host.leadingAnchor), region.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        current = region
        centredView = centred
    }
}

// MARK: - Transient failure

/// The caption under a slider or dial that says what failed (`FailureCaption`): one footnote line in the error ink, wrapping
/// at large text, with the error haptic and a VoiceOver announcement each time ``TransientFailure/show(_:)`` runs. It takes no
/// room while empty.
final class UKFailureCaptionView: UIView {
    private let label = UILabel.uk(.footnote, ink: UKDesignInk.error, alignment: .center)
    private let stack = UIStackView()
    private let bag = UKObservationBag()
    private var lastCount: Int

    init(_ failure: TransientFailure) {
        lastCount = failure.count
        super.init(frame: .zero)
        label.accessibilityIdentifier = "failureCaption"
        stack.axis = .vertical
        stack.addArrangedSubview(label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        bag.observe { [weak self] in
            guard let self else { return }
            let message = failure.message
            let count = failure.count
            self.label.text = message
            self.label.isHidden = message == nil
            if count != self.lastCount {
                self.lastCount = count
                if let message { UKFailureFeedback.fire(message) }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The error haptic and the spoken notice of a failure (`failureAnnouncement(_:_:)` and ``FailureCaption``).
@MainActor
enum UKFailureFeedback {
    /// Plays the error haptic and announces `message` without moving focus.
    static func fire(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        announceFailure(message)
    }
}
#endif
