#if os(iOS) && DEBUG
import OSLog
import UIKit

/// Drives ``UKGalleryAutoOpen`` for one gallery page: starts from the page's `viewDidAppear`, presents once the page is in a window
/// and idle, and checks that the sheet came up, presenting again when it was dropped. One opener per page; a reset builds a new page.
@MainActor
final class UKGalleryAutoOpener {
    private var machine = UKGalleryAutoOpen()
    private var task: Task<Void, Never>?
    private var started = false
    private var isDone = false
    private let label: String
    private static let log = Logger(subsystem: "com.sfenton.home", category: "gallery-auto-open")

    /// - Parameter label: Names the page in the log.
    init(label: String) { self.label = label }

    /// Begins on the first call; later `viewDidAppear`s (the page showing again after its sheet closed) do nothing.
    /// - Parameters:
    ///   - page: The presenting page.
    ///   - present: Presents the sheet; called again only when the earlier present left no sheet up.
    func start(on page: UIViewController, present: @escaping () -> Void) {
        guard !started else { return }
        started = true
        turn(page, present)
    }

    /// Stops the retries when the page leaves the screen. A page that shows again before the sheet is up resumes on its next
    /// ``start(on:present:)``; one that finished does not (a sheet the person closed stays closed).
    func cancel() {
        task?.cancel()
        if !isDone { started = false }
    }

    private func turn(_ page: UIViewController, _ present: @escaping () -> Void) {
        let presented = page.presentedViewController
        let snapshot = UKGalleryAutoOpen.Snapshot(
            hasWindow: page.view.window != nil,
            isTransitioning: page.isBeingPresented || page.isMovingToParent || page.isMovingFromParent
                || page.transitionCoordinator != nil || page.navigationController?.transitionCoordinator != nil,
            isPresenting: presented != nil,
            isDismissing: presented?.isBeingDismissed == true)
        let delay: Double
        switch machine.step(snapshot) {
        case .stop:
            isDone = true
            return
        case .giveUp:
            isDone = true
            Self.log.error("\(self.label, privacy: .public): no sheet after \(self.machine.attempts) turns (presents retried: \(self.machine.retriedPresents))")
            return
        case .present:
            present()
            delay = UKGalleryAutoOpen.verifyInterval
        case .wait: delay = UKGalleryAutoOpen.retryInterval
        }
        task = Task { @MainActor [weak self, weak page] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let page else { return }
            self.turn(page, present)
        }
    }
}
#endif
