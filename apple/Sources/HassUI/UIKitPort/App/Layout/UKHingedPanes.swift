#if os(iOS)
import HassDesign
import UIKit

/// Two panes side by side that keep clear of the hinge: the UIKit counterpart of ``HingedPanes``. The leading pane takes the
/// whole width while ``showsTrailing`` is false; otherwise the columns are `SplitPolicy.columnWidths` (the hinge's band between them,
/// else an even split with `gutter` between).
final class UKHingedPanes: UIView {
    let leading: UIView
    let trailing: UIView
    private let shell: UKShellEnvironment?
    private let gutter: CGFloat
    private let bag = UKObservationBag()
    private var hinge: CGRect?

    var showsTrailing: Bool { didSet { if showsTrailing != oldValue { trailing.isHidden = !showsTrailing; setNeedsLayout() } } }

    init(leading: UIView, trailing: UIView, showsTrailing: Bool = true, gutter: CGFloat = 0, shell: UKShellEnvironment?) {
        self.leading = leading
        self.trailing = trailing
        self.showsTrailing = showsTrailing
        self.gutter = gutter
        self.shell = shell
        super.init(frame: .zero)
        addSubview(leading)
        addSubview(trailing)
        trailing.isHidden = !showsTrailing
        bag.observe { [weak self] in
            guard let self else { return }
            self.hinge = self.shell?.windowHinge
            self.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard showsTrailing, bounds.width > 0 else {
            leading.frame = bounds
            return
        }
        let global = convert(bounds, to: nil)
        let geometry = SplitPolicy.columnWidths(container: global, hinge: hinge, gutter: gutter)
        leading.frame = CGRect(x: 0, y: 0, width: geometry.leadingWidth, height: bounds.height)
        trailing.frame = CGRect(x: geometry.leadingWidth + geometry.bandWidth, y: 0, width: geometry.trailingWidth, height: bounds.height)
    }
}
#endif
