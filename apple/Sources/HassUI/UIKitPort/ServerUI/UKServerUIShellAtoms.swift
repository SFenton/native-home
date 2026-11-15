#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Canonical informational atoms

@MainActor
final class UKServerUIInfoBox: UKServerUIFittingView {
    private var key: [String]?
    private var content: UIView?
    func apply(_ value: ServerUICompositionDocument.InfoBox, bindings: UKServerUIBindings) {
        let message: String
        if case .ready(let text) = bindings.string(value.message) { message = text }
        else { message = value.unavailableText }
        let key = [value.node.title, message, value.tone.rawValue]
        guard self.key != key else { return }
        self.key = key
        content?.removeFromSuperview()
        let content = UKInfoBoxView(title: value.node.title, message: message.isEmpty ? nil : message,
                                   tone: value.tone == .success ? .success : .neutral)
        self.content = content
        addSubview(content); content.ukPin(to: self)
        ukRemeasureContainers()
    }
}

extension ServerUICompositionDocument.StatusPill.Tone {
    var native: StatusPill.Tone {
        switch self {
        case .neutral: .neutral
        case .ok: .ok
        case .active: .active
        case .warning: .warning
        case .danger: .danger
        case .unavailable: .unavailable
        }
    }
}

// MARK: - Keyed native paging

@MainActor
final class UKServerUIPagedRow: UIView, UKGridMeasuring {
    private var children: [UIView] = []
    private var cells: [UKServerUIPagedCell] = []
    private var row: UKPagedRowView?
    private var indicator: UKPageIndicator?
    private var definition: ServerUICompositionDocument.PagedRow?
    private var configuredCount = 0
    var blocksPublication: Bool { row?.isTracking == true || row?.isDragging == true || row?.isDecelerating == true }

    func needsReparent(_ views: [UIView]) -> Bool { children != views }
    func clear() { cells.forEach { $0.content.removeFromSuperview() } }

    func apply(_ definition: ServerUICompositionDocument.PagedRow, children: [UIView]) {
        let changed = self.children != children
        let oldIndex = row?.firstVisible ?? 0
        let oldFirst = self.children.indices.contains(oldIndex) ? self.children[oldIndex] : nil
        self.definition = definition
        self.children = children
        if changed || row == nil {
            let first = oldFirst.flatMap { children.firstIndex(of: $0) } ?? min(oldIndex, max(0, children.count - 1))
            let perPage = traitCollection.ukIsAccessibilitySize ? 1 : definition.perPage
            row?.removeFromSuperview()
            cells = children.map(UKServerUIPagedCell.init)
            let row = UKPagedRowView(itemCount: cells.count, perPage: perPage,
                animatesPaging: !UIAccessibility.isReduceMotionEnabled) { [weak self] index in
                    guard let self, cells.indices.contains(index) else { return UIView() }
                    return cells[index]
                }
            self.row = row
            configuredCount = perPage
            row.firstVisible = first
            row.onFirstVisibleChange = { [weak self] in
                guard let self, let row = self.row else { return }
                indicator?.page = row.currentPage
            }
            addSubview(row)
        }
        if indicator?.label != definition.pageLabel {
            indicator?.removeFromSuperview()
            let indicator = UKPageIndicator(page: row?.currentPage ?? 0, pageCount: row?.pageCount ?? 0,
                label: definition.pageLabel, identifier: definition.node.id + ".pages") { [weak self] page in
                    guard let row = self?.row else { return }
                    row.firstVisible = row.firstIndex(ofPage: page)
                }
            self.indicator = indicator
            addSubview(indicator)
        }
        setNeedsLayout()
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard let definition else { return 0 }
        let count = traitCollection.ukIsAccessibilitySize ? 1 : definition.perPage
        if configuredCount != count {
            configuredCount = count
            row?.reload(perPage: count)
        }
        let height = cells.map { $0.height(width: width / CGFloat(count)) }.max() ?? 0
        return height + (definition.showsIndicator && (row?.pageCount ?? 0) > 1 ? 44 : 0)
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let definition, let row else { return }
        _ = gridHeight(forWidth: bounds.width)
        row.animatesPaging = !UIAccessibility.isReduceMotionEnabled
        let shows = definition.showsIndicator && row.pageCount > 1
        row.frame = .init(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - (shows ? 44 : 0)))
        indicator?.isHidden = !shows
        if indicator?.pageCount != row.pageCount { indicator?.pageCount = row.pageCount }
        indicator?.frame = .init(x: 0, y: row.frame.maxY, width: bounds.width, height: shows ? 44 : 0)
    }
}

/// Bridges width-measured composition children into the native pager's Auto Layout fitting contract.
@MainActor
private final class UKServerUIPagedCell: UIView {
    let content: UIView
    init(_ content: UIView) { self.content = content; super.init(frame: .zero); addSubview(content) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func height(width: CGFloat) -> CGFloat {
        if let content = content as? any UKGridMeasuring { return content.gridHeight(forWidth: width) }
        return content.systemLayoutSizeFitting(.init(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    }
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontal: UILayoutPriority,
                                         verticalFittingPriority vertical: UILayoutPriority) -> CGSize {
        .init(width: targetSize.width, height: height(width: targetSize.width))
    }
    override func layoutSubviews() { super.layoutSubviews(); content.frame = bounds }
}
#endif
