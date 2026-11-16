#if os(iOS)
import HassCore
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Native media control

@MainActor
final class UKServerUIAttachments: UIView, PHPickerViewControllerDelegate {
    private let stack = UIStackView()
    private let session: any ServerUIAttachmentFormSession
    private weak var page: UIViewController?
    private let report: (any Error) -> Void
    private var shown: [AdminTodoUpload.Image]?

    init(session: any ServerUIAttachmentFormSession, page: UIViewController, report: @escaping (any Error) -> Void) {
        self.session = session; self.page = page; self.report = report
        super.init(frame: .zero)
        stack.axis = .vertical
        addSubview(stack); stack.ukPin(to: self)
        update()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update() {
        isUserInteractionEnabled = !session.isBusy
        guard shown != session.images else { return }
        shown = session.images
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, image) in session.images.enumerated() {
            stack.addArrangedSubview(UKAdminTodoImageRowView(image: image) { [weak self] in
                guard let self else { return }
                do {
                    var images = session.images
                    guard images.indices.contains(index), images[index] == image else { throw ServerUIRecordFailure.staleSelection }
                    images.remove(at: index)
                    try session.beginReadingImages()
                    try session.finishReadingImages(images, failure: nil)
                    update()
                } catch { report(error) }
            })
        }
        stack.addArrangedSubview(UKTodoButtonRow(title: session.images.isEmpty ? "Add Images" : "Choose Different Images",
            symbol: "photo.on.rectangle.angled", ink: UKDesignInk.action, identifier: "adminTodo.images") { [weak self] in self?.pick() })
    }

    private func pick() {
        guard let page else { return }
        do {
            try session.beginReadingImages()
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.filter = .images
            configuration.selectionLimit = AdminTodoUpload.maxImages
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            page.present(picker, animated: true)
        } catch { report(error) }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        Task { [self] in
            do {
                if results.isEmpty { try session.finishReadingImages(nil, failure: nil); return }
                var images: [AdminTodoUpload.Image] = []
                for (index, result) in results.enumerated() {
                    let provider = result.itemProvider
                    guard let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first(where: {
                        AdminTodoUpload.mimeTypes.contains($0.preferredMIMEType ?? "")
                    }), let mime = type.preferredMIMEType else {
                        throw ServerUIRecordFailure.unavailable("Choose PNG, JPEG, or WebP images.")
                    }
                    let data = try await Self.load(provider, type.identifier)
                    images.append(.init(data: data, filename: "image-\(index + 1).\(type.preferredFilenameExtension ?? "img")", mimeType: mime))
                }
                try session.finishReadingImages(images, failure: nil)
                update()
            } catch {
                if session.isBusy {
                    do { try session.finishReadingImages(nil, failure: error.localizedDescription) }
                    catch { report(error) }
                }
                report(error)
            }
        }
    }

    private static func load(_ provider: NSItemProvider, _ type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }
}
#endif
