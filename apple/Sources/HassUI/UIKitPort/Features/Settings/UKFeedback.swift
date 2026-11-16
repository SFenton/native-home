#if os(iOS)
import HassCore
import HassDesign
import PhotosUI
import QuickLook
import QuickLookThumbnailing
import UIKit
import UniformTypeIdentifiers

// MARK: - Form

/// Carries a picker result's item provider (which the picker hands over for exactly this use) into the import task.
struct ProviderBox: @unchecked Sendable {
    let provider: NSItemProvider
}

/// A multi-line text box (`TextEditor`) that reports its text and holds a minimum height.
final class UKFeedbackTextView: UITextView, UITextViewDelegate {
    var onChange: ((String) -> Void)?
    var minimumHeight: CGFloat = 0

    init() {
        super.init(frame: .zero, textContainer: nil)
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func textViewDidChange(_ textView: UITextView) {
        onChange?(textView.text)
        // The cell grows with the text: ask the list to measure it again.
        invalidateIntrinsicContentSize()
        if let list = superview(of: UICollectionView.self) {
            UIView.performWithoutAnimation {
                list.collectionViewLayout.invalidateLayout()
                list.layoutIfNeeded()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        let fitted = sizeThatFits(CGSize(width: bounds.width > 0 ? bounds.width : 320, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: UIView.noIntrinsicMetric, height: max(minimumHeight, ceil(fitted.height)))
    }
}

private extension UIView {
    func superview<T: UIView>(of type: T.Type) -> T? {
        var view = superview
        while let current = view {
            if let match = current as? T { return match }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Attachments

/// Attached media shown above Attach Media (``FeedbackAttachmentStrip``): a thumbnail per file that opens in the system viewer, with
/// a remove button. The app never plays or views media itself.
final class UKFeedbackAttachmentStrip: UIScrollView {
    init(attachments: [FeedbackAttachment], onOpen: @escaping (Int) -> Void, onRemove: @escaping (FeedbackAttachment) -> Void) {
        super.init(frame: .zero)
        showsHorizontalScrollIndicator = false
        accessibilityIdentifier = "feedback.attachments"
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = HassTokens.Spacing.m
        stack.alignment = .top
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for (index, attachment) in attachments.enumerated() {
            stack.addArrangedSubview(UKFeedbackAttachmentTile(attachment: attachment, position: index + 1,
                                                              onOpen: { onOpen(index) }, onRemove: { onRemove(attachment) }))
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: HassTokens.Spacing.xs),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.xs),
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            heightAnchor.constraint(equalTo: contentLayoutGuide.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isAccessibilityElement: Bool {
        get { false }
        set {}
    }
}

/// One thumbnail button plus its remove button, each at least 44 pt (``FeedbackAttachmentTile``).
final class UKFeedbackAttachmentTile: UIView {
    private let attachment: FeedbackAttachment
    private let thumbnail = UIImageView()
    private let placeholder = UIImageView()
    private var task: Task<Void, Never>?

    init(attachment: FeedbackAttachment, position: Int, onOpen: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.attachment = attachment
        super.init(frame: .zero)
        let side = FeedbackAttachmentMetrics.side
        let reach = FeedbackAttachmentMetrics.removeReach
        let inset = FeedbackAttachmentMetrics.thumbnailInset

        let open = UIButton(type: .custom)
        open.layer.cornerRadius = FeedbackAttachmentMetrics.cornerRadius
        open.layer.cornerCurve = .continuous
        open.clipsToBounds = true
        open.layer.borderWidth = 1 / UIScreen.main.scale
        open.layer.borderColor = UIColor.separator.cgColor
        open.backgroundColor = .quaternarySystemFill
        open.addAction(UIAction { _ in onOpen() }, for: .touchUpInside)
        open.accessibilityLabel = attachment.accessibilityLabel(position: position)
        open.accessibilityHint = "Opens in Quick Look"
        open.accessibilityIdentifier = "feedback.attachment.\(position)"
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.isUserInteractionEnabled = false
        thumbnail.frame = CGRect(x: 0, y: 0, width: side, height: side)
        placeholder.image = UIImage(systemName: attachment.isVideo ? "film" : "photo", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title2)))
        placeholder.tintColor = UKDesignInk.secondary
        placeholder.contentMode = .center
        placeholder.frame = thumbnail.frame
        open.addSubview(placeholder)
        open.addSubview(thumbnail)
        if attachment.isVideo {
            let badge = UIImageView(image: UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.footnote, bold: true))))
            badge.tintColor = .white
            badge.contentMode = .center
            badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            badge.layer.cornerRadius = 12
            badge.frame = CGRect(x: 10, y: side - 34, width: 24, height: 24)
            badge.isUserInteractionEnabled = false
            open.addSubview(badge)
        }
        open.frame = CGRect(x: 0, y: 2 + inset, width: side, height: side)
        addSubview(open)

        let remove = UIButton(type: .custom)
        var removeImage = UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.title3)))
        removeImage = removeImage?.applyingSymbolConfiguration(UIImage.SymbolConfiguration(paletteColors: [.white, UIColor.black.withAlphaComponent(0.7)]))
        remove.setImage(removeImage, for: .normal)
        remove.addAction(UIAction { _ in onRemove() }, for: .touchUpInside)
        remove.accessibilityLabel = "Remove \(attachment.filename)"
        remove.accessibilityIdentifier = "feedback.attachment.\(position).remove"
        // Centred on the thumbnail's top trailing corner, a 44 pt target.
        remove.frame = CGRect(x: side - HassTokens.minTarget / 2, y: 2 + inset - HassTokens.minTarget / 2, width: HassTokens.minTarget, height: HassTokens.minTarget)
        addSubview(remove)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side + inset + reach),
            heightAnchor.constraint(equalToConstant: side + 2 + inset),
        ])
        loadThumbnail()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { task?.cancel() }

    private func loadThumbnail() {
        let request = QLThumbnailGenerator.Request(
            fileAt: attachment.fileURL, size: CGSize(width: FeedbackAttachmentMetrics.side, height: FeedbackAttachmentMetrics.side),
            scale: UIScreen.main.scale, representationTypes: .thumbnail)
        task = Task { [weak self] in
            let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
            guard !Task.isCancelled, let image else { return }
            self?.thumbnail.image = image
            self?.placeholder.isHidden = true
        }
    }
}
#endif
