#if os(iOS)
import HassDesign
import UIKit

/// A bar pinned to one edge of a ``UKPageViewController`` (the page-owned form of ``UKPinnedBarViewController``, for a sheet page that is
/// itself the page the modal shows): the bar sits in the page's `view` on the safe area's edge, outside the header-fade mask, and its
/// height joins the page's additional safe area so the content's last row scrolls clear of it. A bottom bar rides above the keyboard.
/// With a `scrollView` the bar gets the iOS 26 scroll edge interaction and the scroll view a soft edge under it; before iOS 26
/// `barMaterial` puts the bar material behind a full-width bar (`alwaysMaterial` on every OS: ``accessory(_:)``). The one pinned-bar component of the sheet pages (owner 2026-10-31): a
/// page that hosts a content controller uses it through ``UKSheetPinnedBarPage``.
///
/// ```swift
/// private var pinnedBar: UKPagePinnedBar?
/// override func viewDidLoad() { super.viewDidLoad(); pinnedBar?.install(in: self) }
/// override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); pinnedBar?.layoutChanged() }
/// ```
@MainActor
final class UKPagePinnedBar {
    let bar: UIView
    private let edge: UKPinnedBarViewController.Edge
    private let spacing: CGFloat
    private var scrollView: UIScrollView?
    private var edgeInteraction: Any?
    private let material: UIVisualEffectView?
    private weak var page: UKPageViewController?
    private var lastHeight: CGFloat = -1
    private var boundsObservation: NSKeyValueObservation?

    init(bar: UIView, edge: UKPinnedBarViewController.Edge = .bottom, spacing: CGFloat = 0, scrollView: UIScrollView? = nil, barMaterial: Bool = false,
         alwaysMaterial: Bool = false) {
        self.bar = bar
        self.edge = edge
        self.spacing = spacing
        self.scrollView = scrollView
        if alwaysMaterial {
            material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        } else if barMaterial, #unavailable(iOS 26) {
            material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        } else {
            material = nil
        }
    }

    /// The bar's bottom edge: the system's bottom safe area, kept apart from the inset this page adds for the bar (the keyboard guide
    /// and the safe area guide both include `additionalSafeAreaInsets`, so pinned to either the bar would chase its own inset).
    private var restingBottom = NSLayoutConstraint()

    /// Adds the bar to the page's view; call from `viewDidLoad` after `super`.
    func install(in page: UKPageViewController) {
        self.page = page
        let view = page.view!
        if let material {
            view.addSubview(material)
            material.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([material.leadingAnchor.constraint(equalTo: view.leadingAnchor), material.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        }
        view.addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        let guide = view.safeAreaLayoutGuide
        let keyboard = view.keyboardLayoutGuide
        keyboard.usesBottomSafeArea = false
        if edge == .bottom {
            // Above the keyboard while one is up (the guide's top is the view's bottom otherwise), else on the system's safe area.
            restingBottom = bar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            restingBottom.priority = .defaultHigh
            NSLayoutConstraint.activate([bar.bottomAnchor.constraint(lessThanOrEqualTo: keyboard.topAnchor), restingBottom])
        } else {
            bar.topAnchor.constraint(equalTo: guide.topAnchor).isActive = true
        }
        NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo: guide.leadingAnchor), bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor)])
        if let material {
            let bottomEdge = edge == .bottom
            NSLayoutConstraint.activate([
                bottomEdge ? material.bottomAnchor.constraint(equalTo: view.bottomAnchor) : material.topAnchor.constraint(equalTo: view.topAnchor),
                bottomEdge ? material.topAnchor.constraint(equalTo: bar.topAnchor) : material.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            ])
        }
        // A bar that changes height on its own (a section swap, a text size) asks for the inset again, one turn later (never from a layout pass).
        boundsObservation = bar.observe(\.bounds, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue?.height != change.newValue?.height else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layoutChanged() } }
        }
        follow(scrollView)
    }

    /// The scroll view whose content passes under the bar (the iOS 26 scroll edge interaction and the soft bottom edge). A page whose
    /// scroller changes (a rotation between one and two columns) hands the new one here.
    func follow(_ next: UIScrollView?) {
        if #available(iOS 26, *) {
            if let old = edgeInteraction as? UIScrollEdgeElementContainerInteraction {
                bar.removeInteraction(old)
                edgeInteraction = nil
            }
            if let next {
                let interaction = UIScrollEdgeElementContainerInteraction()
                interaction.scrollView = next
                interaction.edge = edge == .bottom ? .bottom : .top
                bar.addInteraction(interaction)
                edgeInteraction = interaction
                if edge == .bottom { next.bottomEdgeEffect.style = .soft }
            }
        }
        scrollView = next
    }

    /// Takes the bar's material out with it (a page replacing its accessory).
    func removeMaterial() { material?.removeFromSuperview() }

    func layoutChanged() {
        guard let page else { return }
        let view = page.view!
        let system = max(0, view.safeAreaInsets.bottom - (edge == .bottom ? page.additionalSafeAreaInsets.bottom : 0))
        if edge == .bottom, abs(restingBottom.constant + system) > 0.5 { restingBottom.constant = -system }
        let lift = edge == .bottom ? max(0, view.bounds.height - view.keyboardLayoutGuide.layoutFrame.minY - system) : 0
        // The height the bar will have, asked of its constraints: its own `bounds` still hold the last pass's height when a section swap or a
        // text size change resized it in this one, which left the content's last rows under the bar.
        let fitting = bar.systemLayoutSizeFitting(CGSize(width: max(0, view.safeAreaLayoutGuide.layoutFrame.width), height: UIView.layoutFittingCompressedSize.height),
                                                  withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let barHeight = fitting > 0 ? ceil(fitting) : bar.bounds.height
        let height = (bar.isHidden ? 0 : barHeight + spacing) + lift
        guard height != lastHeight else { return }
        lastHeight = height
        var insets = page.additionalSafeAreaInsets
        if edge == .bottom { insets.bottom = height } else { insets.top = height }
        page.additionalSafeAreaInsets = insets
    }
}
#endif
