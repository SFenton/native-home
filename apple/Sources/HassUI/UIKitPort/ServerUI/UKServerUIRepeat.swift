#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - The cell a repeat draws

/// The record and position one cell of a `repeat` reads (`item` and `index`, `sh.repeat@1`).
///
/// It is observable and each cell has its own, so a record that changes is one write to one scope: only the expressions of that cell run
/// again, and the page, the other cells and the views stay where they are. ``set(_:)`` writes only a different record, so a republish that
/// gives the same answer wakes nothing.
@MainActor
@Observable
final class UKServerUICellScope {
    /// The record this cell shows, or `nil` for a placeholder (it has no record, only an ``index``).
    private(set) var record: JSONValue?
    /// The cell's 0-based position.
    let index: Int

    /// Creates the scope of the cell at `index`.
    init(index: Int, record: JSONValue? = nil) {
        self.index = index
        self.record = record
    }

    /// Gives the cell a record; the same record is not a change.
    func set(_ new: JSONValue?) { if record != new { record = new } }
}

/// One cell of a repeat: the keyed views of one copy of the template, and the scope they read.
///
/// The host is not an accessibility element, so each part inside it speaks for itself and the cells read in order along the axis.
@MainActor
final class UKServerUICellHost: UIView, UKGridMeasuring {
    /// What the cell's views read.
    let scope: UKServerUICellScope
    /// The template's view for this cell.
    let content: UIView

    /// Creates a host around the cell's view.
    init(scope: UKServerUICellScope, content: UIView) {
        self.scope = scope
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The height of the cell at `width`.
    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        if let content = content as? any UKGridMeasuring { return content.gridHeight(forWidth: width) }
        return content.systemLayoutSizeFitting(.init(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    }

    /// The width the cell takes with all the room it wants, for a row that scrolls.
    func naturalWidth(limit: CGFloat) -> CGFloat {
        if let content = content as? any UKStackMeasuring { return min(limit, content.stackNaturalWidth) }
        return min(limit, ceil(content.sizeThatFits(.init(width: limit, height: .greatestFiniteMagnitude)).width))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() { super.layoutSubviews(); content.frame = bounds }
}

// MARK: - The repeat

/// A `repeat` (`sh.repeat@1`): its cells along an axis with spacing, a horizontal repeat in pages, and the words for no list.
///
/// It is the app's one paging row (``UKServerUIPagedRow`` and ``UKPageIndicator``) for pages, and a plain column or a scrolling row
/// otherwise; it holds values and closures only. The page builds the cells (one keyed copy of the template per record) and hands them
/// in with ``apply(_:cells:word:footnote:)``; the view lays them out, counts a page by the window and the text size
/// (``ServerUIRepeat/Paging/pageSize(isRegular:textStep:)``), and draws previous and next buttons at regular width when the paging asks.
@MainActor
final class UKRepeatView: UIView, UKGridMeasuring {
    /// The width from which a window counts as regular for paging (the Studio's value: an iPad, or a wide landscape window).
    static let regularWidth: CGFloat = 600
    private static let footer: CGFloat = 44
    /// A disabled previous or next button fades once, to 55%, and keeps 3:1 against the ground (`weather-chevron-contrast.md`, as the weather
    /// carousel does). The Studio's 0.3 (`repeat.css`) would be about 1.4:1 here; the departure is recorded in `weather-gen.md` (HIG, Accessibility,
    /// Color and contrast).
    static let disabledAlpha: CGFloat = 0.55
    /// The gap between a button and the dots (12 pt in the Studio's footer).
    private static let buttonGap: CGFloat = 12

    private var definition: ServerUIRepeat?
    private var cells: [UKServerUICellHost] = []
    private let pager = UKServerUIPagedRow()
    private let flow = UIScrollView()
    private let wordLabel = UILabel()
    private let footnote = UILabel()
    // A custom button draws its image as it is when disabled, so the one fade below is the only one (`weather-chevron-contrast.md`).
    private let previousButton = UIButton(type: .custom)
    private let nextButton = UIButton(type: .custom)
    private var pagerKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        flow.showsHorizontalScrollIndicator = false
        flow.alwaysBounceVertical = false
        flow.contentInsetAdjustmentBehavior = .never
        flow.clipsToBounds = false
        for label in [wordLabel, footnote] {
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            label.isHidden = true
        }
        wordLabel.font = UKFont.preferred(.body)
        wordLabel.textAlignment = .center
        footnote.font = UKFont.preferred(.footnote)
        for (button, symbol, label, forward) in [(previousButton, "chevron.left", "Previous page", false), (nextButton, "chevron.right", "Next page", true)] {
            // The chevron is a view of ours, not the button's own image: a button dims its own image when disabled, and this one fades once.
            let glyph = UIImageView(image: UIImage(systemName: symbol))
            glyph.tintColor = .label
            glyph.contentMode = .center
            glyph.isUserInteractionEnabled = false
            glyph.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(glyph)
            NSLayoutConstraint.activate([glyph.leadingAnchor.constraint(equalTo: button.leadingAnchor), glyph.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                                         glyph.topAnchor.constraint(equalTo: button.topAnchor), glyph.bottomAnchor.constraint(equalTo: button.bottomAnchor)])
            button.tintColor = .label
            button.accessibilityLabel = label
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                pager.show(page: pager.currentPage + (forward ? 1 : -1))
            }, for: .touchUpInside)
            button.isHidden = true
        }
        previousButton.accessibilityIdentifier = "repeat.previous"
        nextButton.accessibilityIdentifier = "repeat.next"
        pager.isHidden = true
        pager.keepsAuthoredCount = true
        pager.ink = .label
        pager.onPageChange = { [weak self] in self?.refreshButtons() }
        [pager, flow, wordLabel, footnote, previousButton, nextButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether the page must not be rebuilt now (a person is paging).
    var blocksPublication: Bool { pager.blocksPublication }

    /// The cells now drawn, in order.
    var drawnCells: [UKServerUICellHost] { cells }

    // MARK: Applying

    /// Draws the cells the page built, or the word when there are none.
    ///
    /// - Parameters:
    ///   - value: What the document says.
    ///   - cells: One host for each cell to draw (a record, or a placeholder while the flow has not answered).
    ///   - word: What shows with no cells, and under placeholders (the loading word); `nil` for none.
    ///   - footnote: The line under a kept list that is out of date; `nil` for none.
    func apply(_ value: ServerUIRepeat, cells: [UKServerUICellHost], word: String?, footnote note: String?) {
        definition = value
        let views = cells.map { ObjectIdentifier($0) }
        let changed = self.cells.map { ObjectIdentifier($0) } != views
        let departed = self.cells
        self.cells = cells
        wordLabel.text = word
        wordLabel.isHidden = word == nil
        footnote.text = note
        footnote.isHidden = note == nil
        if changed {
            pagerKey = nil
            // A cell that stays keeps its place in the tree (and so VoiceOver's focus on it); only the cells that left are taken out.
            let staying = Set(views)
            departed.filter { !staying.contains(ObjectIdentifier($0)) }.forEach { $0.removeFromSuperview() }
        }
        let paged = isPaged
        pager.isHidden = !paged
        flow.isHidden = paged || value.axis == .vertical || cells.isEmpty
        if !paged {
            let parent: UIView = value.axis == .vertical ? self : flow
            for cell in cells where cell.superview !== parent { parent.addSubview(cell) }
        }
        syncPager(width: bounds.width)
        updateElements()
        ukRemeasureContainers()
        setNeedsLayout()
    }

    private var isPaged: Bool { definition?.axis == .horizontal && definition?.paging != nil && !cells.isEmpty }

    private func isRegular(width: CGFloat) -> Bool { width >= Self.regularWidth }

    /// The cells one page holds at this width and text size.
    private func pageSize(width: CGFloat) -> Int {
        guard let paging = definition?.paging else { return 1 }
        let scale = UIFontMetrics(forTextStyle: .body).scaledValue(for: 1, compatibleWith: traitCollection)
        return paging.pageSize(isRegular: isRegular(width: width), textStep: ServerUIRepeat.textStep(scale: Double(scale)))
    }

    private var showsButtons: Bool {
        guard let paging = definition?.paging else { return false }
        return paging.buttons == .regularWidth && isRegular(width: bounds.width) && pager.pageCount > 1
    }

    /// Hands the pager the cells, and again when the page size or the label changes with the window or the text.
    private func syncPager(width: CGFloat) {
        guard isPaged, let definition, let paging = definition.paging else { return }
        let size = pageSize(width: width)
        let label = paging.label ?? definition.node.title
        let key = "\(size)|\(label)|\(paging.indicator)|\(definition.spacing.points)"
        guard key != pagerKey else { return }
        pagerKey = key
        pager.cellInset = definition.spacing.points / 2
        pager.apply(.init(node: definition.node, perPage: size, pageLabel: label, showsIndicator: paging.indicator), children: cells)
    }

    private func refreshButtons() {
        let show = showsButtons
        previousButton.isHidden = !show
        nextButton.isHidden = !show
        previousButton.isEnabled = pager.currentPage > 0
        nextButton.isEnabled = pager.currentPage < pager.pageCount - 1
        for button in [previousButton, nextButton] { Self.glyph(of: button)?.alpha = button.isEnabled ? 1 : Self.disabledAlpha }
        updateElements()
    }

    /// The order VoiceOver reads in: the cells along the axis (or the pages), then the previous and next buttons, then the words.
    private func updateElements() {
        var elements: [Any] = []
        if isPaged { elements.append(pager) } else if definition?.axis == .vertical { elements += cells } else if !cells.isEmpty { elements.append(flow) }
        if !previousButton.isHidden { elements += [previousButton, nextButton] }
        if !wordLabel.isHidden { elements.append(wordLabel) }
        if !footnote.isHidden { elements.append(footnote) }
        accessibilityElements = elements
    }

    /// The chevron a Previous or Next button draws (it carries the one fade).
    static func glyph(of button: UIButton) -> UIImageView? { button.subviews.compactMap { $0 as? UIImageView }.first }

    // MARK: Measuring

    /// A buttons-only footer needs its own row; with the indicator the buttons sit on the indicator's strip.
    private var footerHeight: CGFloat {
        guard showsButtons, definition?.paging?.indicator != true else { return 0 }
        return Self.footer
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard let definition else { return 0 }
        syncPager(width: width)
        let note = footnote.isHidden ? 0 : ceil(footnote.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude)).height) + 4
        let wordHeight = wordLabel.isHidden ? 0 : ceil(wordLabel.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude)).height)
        if cells.isEmpty { return wordHeight + note }
        let gap = CGFloat(definition.spacing.points)
        let body: CGFloat
        if isPaged {
            body = pager.gridHeight(forWidth: width) + footerHeight
        } else if definition.axis == .vertical {
            body = cells.reduce(0) { $0 + $1.gridHeight(forWidth: width) } + gap * CGFloat(max(0, cells.count - 1))
        } else {
            body = cells.map { $0.gridHeight(forWidth: $0.naturalWidth(limit: width)) }.max() ?? 0
        }
        return body + (wordHeight > 0 ? wordHeight + 4 : 0) + note
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let definition else { return }
        let width = bounds.width
        syncPager(width: width)
        let note = footnote.isHidden ? 0 : ceil(footnote.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude)).height)
        let wordHeight = wordLabel.isHidden ? 0 : ceil(wordLabel.sizeThatFits(.init(width: width, height: .greatestFiniteMagnitude)).height)
        var y: CGFloat = 0
        let gap = CGFloat(definition.spacing.points)
        if cells.isEmpty {
            wordLabel.frame = .init(x: 0, y: 0, width: width, height: wordHeight)
            y = wordHeight
        } else if isPaged {
            let height = pager.gridHeight(forWidth: width)
            pager.frame = .init(x: 0, y: 0, width: width, height: height)
            y = height
            refreshButtons()
            // The Studio's footer: previous, dots, next, centred as a group with a gap between (`repeat.tsx`, `sh-repeat-footer`).
            let rowY = y - (definition.paging?.indicator == true ? Self.footer : 0)
            let dots = definition.paging?.indicator == true ? pager.marksWidth : 0
            let gap = dots > 0 ? Self.buttonGap : Self.buttonGap / 2
            previousButton.frame = .init(x: width / 2 - dots / 2 - gap - Self.footer, y: rowY, width: Self.footer, height: Self.footer)
            nextButton.frame = .init(x: width / 2 + dots / 2 + gap, y: rowY, width: Self.footer, height: Self.footer)
            y += footerHeight
        } else if definition.axis == .vertical {
            for cell in cells {
                let height = cell.gridHeight(forWidth: width)
                cell.frame = .init(x: 0, y: y, width: width, height: height)
                y += height + gap
            }
            y -= gap
        } else {
            var x: CGFloat = 0
            let height = cells.map { $0.gridHeight(forWidth: $0.naturalWidth(limit: width)) }.max() ?? 0
            for cell in cells {
                let cellWidth = cell.naturalWidth(limit: width)
                cell.frame = .init(x: x, y: 0, width: cellWidth, height: height)
                x += cellWidth + gap
            }
            flow.frame = .init(x: 0, y: 0, width: width, height: height)
            flow.contentSize = .init(width: max(0, x - gap), height: height)
            y = height
        }
        if !cells.isEmpty, wordHeight > 0 {
            wordLabel.frame = .init(x: 0, y: y + 4, width: width, height: wordHeight)
            y += wordHeight + 4
        }
        if note > 0 { footnote.frame = .init(x: 0, y: y + 4, width: width, height: note) }
    }
}
#endif
