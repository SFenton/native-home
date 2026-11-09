#if os(iOS)
import HassDesign
import UIKit

/// A page with a bar pinned to one edge (`pinnedBar`, `floatingActionBar`): hosts `content` full size and the bar on the safe
/// area's edge, and adds the bar's height to the content's safe area so its last row scrolls clear of the bar.
///
/// On iOS 26 the bar is given the system's scroll edge interaction, and the scroll view a soft edge under it (HIG: Scroll views
/// › Scroll edge effects), the `safeAreaBar` treatment. Before iOS 26 `barMaterial` puts the bar material behind a full-width
/// bar. The bar owns its whole rectangle for hit testing, so a tap in the gap around a control reaches the bar and never the
/// rows scrolled under it.
public final class UKPinnedBarViewController: UIViewController {
    public enum Edge { case top, bottom }

    public let content: UIViewController
    public let bar: UIView
    private let edge: Edge
    private let spacing: CGFloat
    private let scrollView: UIScrollView?
    private let material: UIVisualEffectView?
    private var lastHeight: CGFloat = -1

    /// - Parameters:
    ///   - content: The page.
    ///   - bar: The bar; its height comes from its own layout.
    ///   - scrollView: The page's scroll view, for the navigation bar's large-title tracking and the scroll edge effect.
    ///   - edge: The edge to pin to.
    ///   - spacing: Space between the page and the bar.
    ///   - barMaterial: Whether before iOS 26 the bar sits on the bar material.
    public init(content: UIViewController, bar: UIView, scrollView: UIScrollView? = nil, edge: Edge = .bottom, spacing: CGFloat = 0, barMaterial: Bool = false) {
        self.content = content
        self.bar = bar
        self.scrollView = scrollView
        self.edge = edge
        self.spacing = spacing
        if barMaterial, #unavailable(iOS 26) { material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial)) } else { material = nil }
        super.init(nibName: nil, bundle: nil)
        title = content.title
        navigationItem.title = content.navigationItem.title ?? content.title
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(content)
        view.addSubview(content.view)
        content.view.ukPin(to: view)
        content.didMove(toParent: self)
        if let material {
            view.addSubview(material)
            material.translatesAutoresizingMaskIntoConstraints = false
            let anchor = edge == .bottom ? material.bottomAnchor.constraint(equalTo: view.bottomAnchor) : material.topAnchor.constraint(equalTo: view.topAnchor)
            NSLayoutConstraint.activate([anchor, material.leadingAnchor.constraint(equalTo: view.leadingAnchor), material.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        }
        view.addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        let guide = view.safeAreaLayoutGuide
        // A bottom bar rides above the keyboard (SwiftUI's `safeAreaBar` does): the keyboard layout guide's top is the safe area's
        // bottom edge while no keyboard is up, so the same constraint serves both (owner, 2026-10-30: the search did not rise).
        NSLayoutConstraint.activate([
            edge == .bottom ? bar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor) : bar.topAnchor.constraint(equalTo: guide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: guide.leadingAnchor), bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
        if let material {
            NSLayoutConstraint.activate([
                edge == .bottom ? material.topAnchor.constraint(equalTo: bar.topAnchor) : material.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            ])
        }
        if let scrollView {
            setContentScrollView(scrollView)
            if #available(iOS 26, *) {
                let interaction = UIScrollEdgeElementContainerInteraction()
                interaction.scrollView = scrollView
                interaction.edge = edge == .bottom ? .bottom : .top
                bar.addInteraction(interaction)
                if edge == .bottom { scrollView.bottomEdgeEffect.style = .soft }
            }
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The part of the keyboard over the page (the guide's top is above the safe area's bottom while it is up) joins the bar's
        // height, so the last row scrolls clear of both.
        let lift = edge == .bottom ? max(0, view.safeAreaLayoutGuide.layoutFrame.maxY - view.keyboardLayoutGuide.layoutFrame.minY) : 0
        let height = bar.bounds.height + spacing + lift
        guard height != lastHeight else { return }
        lastHeight = height
        var insets = content.additionalSafeAreaInsets
        if edge == .bottom { insets.bottom = height } else { insets.top = height }
        content.additionalSafeAreaInsets = insets
    }
}
#endif
