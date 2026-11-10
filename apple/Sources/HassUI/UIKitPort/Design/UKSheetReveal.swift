#if os(iOS)
import HassDesign
import UIKit

/// How a modal's content appears when it opens (`.agents/design/sheet-reveal.md`).
enum UKModalReveal: Equatable {
    /// The content is there on the first frame of the slide (the default: motion.md §4.4).
    case none
    /// The content is hidden through the slide, then fades in all at once; a centred arc shows first only while it is not ready.
    case gate(ContentGateModel.Profile = .sheet)
}

/// A root page of a modal that really loads says when its content can draw. Read inside an observation: the reveal runs again
/// when what it reads changes. A root that does not conform is ready once the sheet has finished presenting and laid out.
@MainActor
protocol UKRevealReadiness {
    /// Whether the page's content is ready to fade in.
    var isContentReady: Bool { get }
}

/// Runs a modal's reveal on its root page: the page's `contentView` is the content, the page's `view` hosts the arc, and the arc
/// is centred on the page's safe area (below the bar, above the home indicator, inside the folded Duo's rail). One of these exists
/// per presentation, from the modal's first `viewWillAppear` until the content has shown.
///
/// The phases, timings, telemetry and tracker are ``ContentGateModel``'s; the drawing is ``UKContentGateDriver``'s. This type only
/// binds them to a page.
@MainActor
final class UKSheetRevealController {
    /// The least tall the page's content area is while the arc can show: the arc plus the large spacing above and below it.
    static let minimumContentHeight: CGFloat = ArcSpinner.Size.page.diameter + 2 * HassTokens.Spacing.xl

    let model: ContentGateModel
    private let driver: UKContentGateDriver
    private let readiness: UKRevealReadiness?
    private let bag = UKObservationBag()
    private var holdActive = false
    private var holdTask: Task<Void, Never>?
    /// The reveal has let go of the content.
    private(set) var isFinished = false
    /// Called once, on the main actor, after the content has shown.
    var onFinished: (() -> Void)?

    /// - Parameters:
    ///   - page: The modal's root page.
    ///   - profile: The reveal's timings (``ContentGateModel/Profile/sheet``).
    ///   - label: What VoiceOver says for the arc.
    ///   - readiness: The root's readiness, nil when it has none (ready once presented).
    ///   - name: Names the sheet in telemetry.
    init(page: UKPageViewController, profile: ContentGateModel.Profile, label: String, readiness: UKRevealReadiness?, name: String,
         model: ContentGateModel? = nil) {
        page.loadViewIfNeeded()
        let model = model ?? ContentGateModel(page: name, isReady: readiness?.isContentReady ?? true, firstLoad: profile)
        self.model = model
        self.readiness = readiness
        driver = UKContentGateDriver(
            model: model, content: page.contentView, arcHost: page.view, arcCenter: page.view.safeAreaLayoutGuide, label: label,
            isReady: readiness?.isContentReady ?? true)
        bag.observe { [weak self] in
            guard let self else { return }
            self.syncReadiness()
        }
        bag.observe { [weak self] in
            guard let self, self.model.phase == .idle, !self.isFinished else { return }
            self.finish()
        }
    }

    /// The sheet finished sliding up: the arc grace and the load timeout count from now.
    func presentationCompleted() {
        #if DEBUG
        // `FENTON_SHEET_REVEAL_HOLD_MS=<n>`: a journey keeps the content "not ready" for n ms after presentation to see the arc.
        if let raw = ProcessInfo.processInfo.environment["FENTON_SHEET_REVEAL_HOLD_MS"], let ms = Int(raw), ms > 0 {
            holdActive = true
            syncReadiness()
            holdTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(ms))
                guard !Task.isCancelled, let self else { return }
                self.holdActive = false
                self.syncReadiness()
            }
        }
        #endif
        driver.presentationCompleted()
    }

    /// The reveal is dropped with the sheet: nothing more is advanced and the arc goes.
    func cancel() {
        holdTask?.cancel()
        driver.cancel()
        bag.removeAll()
        isFinished = true
    }

    /// Whether the arc can still show (the content area keeps its minimum height until the reveal ends).
    var isLoading: Bool { !isFinished && model.phase != .idle }

    /// The arc while it exists.
    var arc: UKArcSpinnerView? { driver.arc }

    private func syncReadiness() {
        driver.isReady = !holdActive && (readiness?.isContentReady ?? true)
    }

    private func finish() {
        isFinished = true
        holdTask?.cancel()
        // Out of the observation that called this: it is the observation being ended.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.driver.settle()
            self.bag.removeAll()
            self.onFinished?()
        }
    }
}
#endif
