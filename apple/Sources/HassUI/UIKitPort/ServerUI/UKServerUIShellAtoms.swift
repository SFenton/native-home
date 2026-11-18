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
        ukRemeasureContainers(includingSelf: true)
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
    /// The points taken from each side of every cell, so cells on a page stand apart (a `repeat`'s spacing is twice this).
    var cellInset: CGFloat = 0 { didSet { if cellInset != oldValue { cells.forEach { $0.inset = cellInset }; setNeedsLayout() } } }
    /// How many pages the row has, and the one on screen.
    var pageCount: Int { row?.pageCount ?? 0 }
    var currentPage: Int { row?.currentPage ?? 0 }
    /// The width of the indicator's marks (the dots, or the count), for a neighbour that sits beside them.
    var marksWidth: CGFloat { indicator?.marksWidth ?? 0 }
    /// Moves to a page, clamped to the pages there are.
    func show(page: Int) {
        guard let row, row.pageCount > 0 else { return }
        row.firstVisible = row.firstIndex(ofPage: max(0, min(row.pageCount - 1, page)))
    }
    /// The colour of the page indicator's current dot; `nil` is the app's ink on its dark ground. A repeat in a sheet that follows the system
    /// appearance passes the dynamic label colour, so the dots read in light as well.
    var ink: UIColor?
    /// Whether the row keeps the count its definition gives at an accessibility text size instead of one cell a page (a `repeat` says how
    /// many cells a page holds at each text size itself).
    var keepsAuthoredCount = false
    private var effectivePerPage: Int {
        guard let definition else { return 1 }
        return traitCollection.ukIsAccessibilitySize && !keepsAuthoredCount ? 1 : definition.perPage
    }
    /// Called when the page on screen or the number of pages changes.
    var onPageChange: (() -> Void)?
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
            let perPage = effectivePerPage
            // A cell whose view is still there keeps its wrapper, so a longer or shorter list leaves the others where they are.
            let kept = cells
            cells = children.map { child in
                let cell = kept.first { $0.content === child } ?? UKServerUIPagedCell(child, inset: cellInset)
                if cell.content.superview !== cell { cell.addSubview(cell.content) }
                return cell
            }
            if let row {
                // The scroll view stays: a count change does not replace it under a finger.
                configuredCount = perPage
                row.reload(itemCount: cells.count, perPage: perPage)
                row.firstVisible = first
            } else {
                let row = UKPagedRowView(itemCount: cells.count, perPage: perPage,
                    animatesPaging: !UKMotion.reduceMotion) { [weak self] index in
                        guard let self, cells.indices.contains(index) else { return UIView() }
                        return cells[index]
                    }
                self.row = row
                configuredCount = perPage
                row.firstVisible = first
                row.onFirstVisibleChange = { [weak self] in
                    guard let self, let row = self.row else { return }
                    indicator?.page = row.currentPage
                    onPageChange?()
                }
                addSubview(row)
            }
        }
        if indicator?.label != definition.pageLabel {
            indicator?.removeFromSuperview()
            let indicator = UKPageIndicator(page: row?.currentPage ?? 0, pageCount: row?.pageCount ?? 0,
                label: definition.pageLabel, identifier: definition.node.id + ".pages", ink: ink) { [weak self] page in
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
        let count = effectivePerPage
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
        row.animatesPaging = !UKMotion.reduceMotion
        let shows = definition.showsIndicator && row.pageCount > 1
        row.frame = .init(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - (shows ? 44 : 0)))
        indicator?.isHidden = !shows
        if indicator?.pageCount != row.pageCount { indicator?.pageCount = row.pageCount; onPageChange?() }
        indicator?.frame = .init(x: 0, y: row.frame.maxY, width: bounds.width, height: shows ? 44 : 0)
    }
}

/// Bridges width-measured composition children into the native pager's Auto Layout fitting contract.
@MainActor
final class UKServerUIPagedCell: UIView {
    let content: UIView
    var inset: CGFloat
    init(_ content: UIView, inset: CGFloat = 0) { self.content = content; self.inset = inset; super.init(frame: .zero); addSubview(content) }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func height(width fullWidth: CGFloat) -> CGFloat {
        let width = max(0, fullWidth - inset * 2)
        if let content = content as? any UKGridMeasuring { return content.gridHeight(forWidth: width) }
        return content.systemLayoutSizeFitting(.init(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    }
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontal: UILayoutPriority,
                                         verticalFittingPriority vertical: UILayoutPriority) -> CGSize {
        .init(width: targetSize.width, height: height(width: targetSize.width))
    }
    override func layoutSubviews() { super.layoutSubviews(); content.frame = bounds.insetBy(dx: inset, dy: 0) }
}
#endif
