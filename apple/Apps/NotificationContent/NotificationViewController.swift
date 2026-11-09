import AVFoundation
import HassCore
import Observation
import UIKit
import UserNotifications
import UserNotificationsUI

/// The UIKit app's expanded camera notification (`fenton.camera`, `.agents/platforms/apple/push.md`): the same behaviour as
/// `Apps/NotificationContent/NotificationViewController.swift`, drawn with UIKit. The snapshot at once, then the camera
/// live over Home Assistant's streams (``CameraNotificationModel``, shared with the SwiftUI extension), with the
/// notification's own buttons.
final class NotificationViewController: UIViewController, @preconcurrency UNNotificationContentExtension {
    private let model = CameraNotificationModel()
    private let cameraView = CameraNotificationUIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        NSLayoutConstraint.activate([
            cameraView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            cameraView.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            cameraView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            cameraView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cameraView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            // The SwiftUI view is `.aspectRatio(16 / 9, contentMode: .fit)` in the extension's view.
            cameraView.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(.defaultHigh),
            cameraView.heightAnchor.constraint(equalTo: view.heightAnchor).withPriority(.defaultHigh),
            cameraView.widthAnchor.constraint(equalTo: cameraView.heightAnchor, multiplier: 16.0 / 9.0),
        ])
        cameraView.bind(to: model)
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        guard let payload = PushPayload(userInfo: content.userInfo) else {
            PushTrace.shared.record("content: no fenton payload")
            return
        }
        PushTrace.shared.record("content: \(content.categoryIdentifier), \(content.attachments.count) attachments, entity \(payload.entityID ?? "-")")
        // Buttons per notification: the camera category is fixed, so its actions are set here.
        extensionContext?.notificationActions = payload.actions.map(\.notificationAction)
        model.title = content.title
        if let url = content.attachments.first?.url, url.startAccessingSecurityScopedResource() {
            model.snapshot = UIImage(contentsOfFile: url.path)
            url.stopAccessingSecurityScopedResource()
        }
        if let entity = payload.entityID { model.start(entityID: entity) }
    }

    /// Every button goes to the app, which opens links and fires `mobile_app_notification_action`.
    func didReceive(_ response: UNNotificationResponse,
                    completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void) {
        model.stop()
        completion(.dismissAndForwardAction)
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

/// The snapshot, then the live player over it, with a Live badge once frames arrive: `CameraNotificationView` in UIKit.
@MainActor
final class CameraNotificationUIView: UIView {
    private let snapshotView = UIImageView()
    private let playerView = PlayerView()
    private let badge = BadgeView()
    #if DEBUG
    private let statusLabel = PaddedLabel()
    #endif
    private weak var model: CameraNotificationModel?
    private var attachedPlayer: AVPlayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        snapshotView.contentMode = .scaleAspectFit
        playerView.playerLayer.videoGravity = .resizeAspect
        playerView.alpha = 0
        [snapshotView, playerView, badge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            snapshotView.leadingAnchor.constraint(equalTo: leadingAnchor),
            snapshotView.trailingAnchor.constraint(equalTo: trailingAnchor),
            snapshotView.topAnchor.constraint(equalTo: topAnchor),
            snapshotView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 10),
        ])
        #if DEBUG
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        #endif
        isAccessibilityElement = true
        accessibilityTraits = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws the model now and again whenever anything it read changes (one pass per change).
    func bind(to model: CameraNotificationModel) {
        self.model = model
        render()
    }

    private func render() {
        guard let model else { return }
        let (snapshot, player, isLive, failed, title, status) = withObservationTracking {
            (model.snapshot, model.player, model.isLive, model.failed, model.title, model.status)
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        snapshotView.image = snapshot
        if player !== attachedPlayer {
            attachedPlayer = player
            playerView.playerLayer.player = player
        }
        playerView.isHidden = player == nil
        playerView.alpha = isLive ? 1 : 0
        badge.state = isLive ? .live : failed ? .unavailable : .loading
        accessibilityLabel = isLive ? "\(title), live camera"
            : failed ? "\(title), stream unavailable" : "\(title), camera snapshot"
        #if DEBUG
        statusLabel.text = status
        #else
        _ = status
        #endif
    }

    /// An `AVPlayerLayer` that fills its view (no transport controls, which a glance doesn't need).
    private final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        // swiftlint:disable:next force_cast
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    #if DEBUG
    /// `.caption2.monospaced()` white on black at 0.6, 4 pt padding.
    private final class PaddedLabel: UILabel {
        override init(frame: CGRect) {
            super.init(frame: frame)
            let base = UIFont.preferredFont(forTextStyle: .caption2)
            font = UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
            adjustsFontForContentSizeCategory = true
            textColor = .white
            backgroundColor = UIColor.black.withAlphaComponent(0.6)
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
        override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))) }
        override var intrinsicContentSize: CGSize {
            let size = super.intrinsicContentSize
            return CGSize(width: size.width + 8, height: size.height + 8)
        }
    }
    #endif

    /// The Live capsule, the "Stream unavailable" capsule, or a white spinner.
    private final class BadgeView: UIView {
        enum State { case loading, live, unavailable }

        var state: State = .loading { didSet { if state != oldValue { apply() } } }
        private let label = UILabel()
        private let icon = UIImageView()
        private let spinner = UIActivityIndicatorView(style: .medium)
        private let stack = UIStackView()
        private var insetConstraints: [NSLayoutConstraint] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .white
            icon.tintColor = .white
            icon.contentMode = .scaleAspectFit
            icon.setContentHuggingPriority(.required, for: .horizontal)
            stack.axis = .horizontal
            stack.spacing = 4
            stack.alignment = .center
            stack.addArrangedSubview(icon)
            stack.addArrangedSubview(label)
            spinner.color = .white
            stack.addArrangedSubview(spinner)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            insetConstraints = [
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            ]
            NSLayoutConstraint.activate(insetConstraints)
            // The container carries the label; the badge is not read separately (SwiftUI ignores children).
            isAccessibilityElement = false
            apply()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            layer.cornerRadius = state == .loading ? 0 : bounds.height / 2
        }

        private func apply() {
            let config = UIImage.SymbolConfiguration(font: label.font)
            switch state {
            case .live:
                icon.image = UIImage(systemName: "circle.fill", withConfiguration: config)
                label.text = "Live"
                backgroundColor = .systemRed
            case .unavailable:
                icon.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: config)
                label.text = "Stream unavailable"
                backgroundColor = UIColor.black.withAlphaComponent(0.7)
            case .loading:
                backgroundColor = .clear
            }
            // The spinner has no capsule or padding of its own, as in SwiftUI.
            let loading = state == .loading
            insetConstraints[0].constant = loading ? 0 : 8
            insetConstraints[1].constant = loading ? 0 : -8
            insetConstraints[2].constant = loading ? 0 : 4
            insetConstraints[3].constant = loading ? 0 : -4
            icon.isHidden = loading
            label.isHidden = loading
            spinner.isHidden = !loading
            if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
            setNeedsLayout()
        }
    }
}
