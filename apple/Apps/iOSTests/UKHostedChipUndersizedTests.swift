import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A status chip never keeps a frame smaller than its own `sizeThatFits` (owner screenshot, 2026-11-05: the Occupancy chip on a room
/// page wrapped "Occupan-/cy" and clipped). The rail measures chips in its own layout pass, so anything that changes a chip's
/// measured size (a text-size change that reaches the chip after the rail has laid out, a new text while detached) must make the
/// rail measure again.
@MainActor
final class UKHostedChipUndersizedTests: XCTestCase {
    private func makeChips() -> [UKStatusChipView] {
        [("Lights", "3 On", "lightbulb.2"), ("Occupancy", "Clear", "person"), ("Climate", "72° · 68%", "thermometer.medium"),
         ("Contact Sensors", "All closed", "door.left.hand.closed")].map { title, summary, symbol in
            let chip = UKStatusChipView()
            chip.configure(title: title, summary: summary, symbol: symbol, family: nil, isActive: false, tint: nil, animated: false) {}
            return chip
        }
    }

    private func host(_ rail: UIView, width: CGFloat, category: UIContentSizeCategory?) -> (UIViewController, UIWindow) {
        let controller = UIViewController()
        controller.view.addSubview(rail)
        rail.frame = CGRect(x: 0, y: 0, width: width, height: 10)
        if let category { controller.traitOverrides.preferredContentSizeCategory = category }
        let window = HostedPage.show(controller, size: CGSize(width: width, height: 900))
        return (controller, window)
    }

    private func settle(_ rail: UIView) {
        for _ in 0..<3 { HostedPage.wait(0.05); rail.window?.layoutIfNeeded(); rail.layoutIfNeeded() }
    }

    /// Every chip is at least as wide and tall as it measures at its own width, and each label sits inside it.
    private func assertFit(_ name: String, _ chips: [UIControl], rail: UIView, file: StaticString = #filePath, line: UInt = #line) {
        for chip in chips {
            let unbounded = CGSize(width: 10_000, height: 10_000)
            let natural = chip.sizeThatFits(unbounded)
            let measured = chip.sizeThatFits(CGSize(width: chip.frame.width, height: unbounded.height))
            let label = chip.accessibilityLabel ?? ""
            XCTAssertGreaterThanOrEqual(chip.frame.height + 0.5, measured.height, "\(name): \(label) is tall enough for its text: \(chip.frame) vs \(measured)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(chip.frame.width + 0.5, min(natural.width, rail.bounds.width - 2 * HassTokens.Spacing.l), "\(name): \(label) is wide enough for its text: \(chip.frame) vs \(natural)", file: file, line: line)
            chip.layoutIfNeeded()
            for text in HostedPage.descendants(of: chip).compactMap({ $0 as? UILabel }) {
                let fitted = text.sizeThatFits(CGSize(width: text.frame.width, height: .greatestFiniteMagnitude))
                XCTAssertLessThanOrEqual(fitted.height, text.frame.height + 0.5, "\(name): \"\(text.text ?? "")\" is not clipped or re-wrapped inside \(chip.frame)", file: file, line: line)
                let textFrame = text.frame
                XCTAssertTrue(chip.bounds.insetBy(dx: -0.5, dy: -0.5).contains(textFrame), "\(name): \"\(text.text ?? "")\" \(textFrame) is inside its chip \(chip.bounds)", file: file, line: line)
            }
        }
    }

    func testChipsBuiltAtTheDefaultSizeFitWhenHostedAtLargerSizes() {
        for (category, label) in [(UIContentSizeCategory.extraExtraExtraLarge, "xxxLarge"), (.accessibilityMedium, "AX1"), (.accessibilityExtraExtraExtraLarge, "AX5")] {
            let rail = UKChipRailView()
            let chips = makeChips()
            rail.setChips(chips)
            let (_, window) = host(rail, width: 390, category: category)
            defer { window.isHidden = true }
            settle(rail)
            assertFit("hosted at \(label)", chips, rail: rail)
        }
    }

    func testChipsFitWhenTheTextSizeChangesWhileHosted() {
        for (from, to) in [(UIContentSizeCategory.large, UIContentSizeCategory.accessibilityExtraExtraExtraLarge),
                           (.large, .extraExtraExtraLarge), (.accessibilityExtraExtraExtraLarge, .large)] {
            let rail = UKChipRailView()
            let chips = makeChips()
            rail.setChips(chips)
            let (controller, window) = host(rail, width: 390, category: from)
            defer { window.isHidden = true }
            settle(rail)
            controller.traitOverrides.preferredContentSizeCategory = to
            settle(rail)
            assertFit("\(from.rawValue) to \(to.rawValue)", chips, rail: rail)
        }
    }

    func testAChipTextChangedWhileDetachedFitsOnceHosted() {
        let rail = UKChipRailView()
        let chips = makeChips()
        rail.setChips(chips)
        let (_, window) = host(rail, width: 390, category: .accessibilityMedium)
        defer { window.isHidden = true }
        settle(rail)
        let chip = chips[1]
        let parent = chip.superview
        chip.removeFromSuperview()
        chip.configure(title: "Occupancy sensors", summary: "Detected in Office", symbol: "person", family: nil, isActive: false, tint: nil, animated: false) {}
        parent?.addSubview(chip)
        settle(rail)
        assertFit("text changed while detached", chips, rail: rail)
    }

    func testAChipTextChangedWhileHostedRemeasuresTheRail() {
        let rail = UKChipRailView()
        let chips = makeChips()
        rail.setChips(chips)
        let (_, window) = host(rail, width: 390, category: .extraExtraExtraLarge)
        defer { window.isHidden = true }
        settle(rail)
        chips[1].configure(title: "Occupancy sensors", summary: "Detected in Office", symbol: "person", family: nil, isActive: false, tint: nil, animated: false) {}
        settle(rail)
        assertFit("text changed while hosted", chips, rail: rail)
    }

    // MARK: Room chips (UKRoomChipView, built by UKRoomCards.chip)

    private func roomChip(_ title: String, _ summary: String, symbol: String = "person", filled: Bool = false) -> UKRoomChipView {
        let chip = UKRoomChipView()
        configure(chip, title, summary, symbol: symbol, filled: filled)
        return chip
    }

    private func configure(_ chip: UKRoomChipView, _ title: String, _ summary: String, symbol: String = "person", filled: Bool = false) {
        chip.configure(title: title, summary: summary, symbol: symbol, family: filled ? .lights : nil, isActive: filled, tint: nil, action: {}, animated: false)
    }

    func testARoomChipConfiguredWithLongerTextWhileHostedGrowsToFit() {
        for filled in [false, true] {
            for category in [UIContentSizeCategory.large, .extraExtraExtraLarge, .accessibilityMedium] {
                let rail = UKChipRailView()
                let chips = [roomChip("Lights", "3 On", symbol: "lightbulb.2"), roomChip("Occ", "", filled: filled), roomChip("Climate", "72°", symbol: "thermometer.medium")]
                rail.setChips(chips)
                let (_, window) = host(rail, width: 390, category: category)
                defer { window.isHidden = true }
                settle(rail)
                configure(chips[1], "Occupancy", "Clear", filled: filled)
                settle(rail)
                assertFit("room chip grew at \(category.rawValue) filled=\(filled)", chips, rail: rail)
            }
        }
    }

    func testARoomChipFollowsATextSizeChangeWhileHosted() {
        for (from, to) in [(UIContentSizeCategory.large, UIContentSizeCategory.accessibilityExtraExtraExtraLarge), (.large, .extraExtraExtraLarge)] {
            let rail = UKChipRailView()
            let chips = [roomChip("Lights", "3 On", symbol: "lightbulb.2"), roomChip("Occupancy", "Clear")]
            rail.setChips(chips)
            let (controller, window) = host(rail, width: 390, category: from)
            defer { window.isHidden = true }
            settle(rail)
            controller.traitOverrides.preferredContentSizeCategory = to
            settle(rail)
            assertFit("room chips \(from.rawValue) to \(to.rawValue)", chips, rail: rail)
        }
    }

    func testARoomChipRestyledAfterTheRailLaidOutRemeasuresIt() {
        let rail = UKChipRailView()
        let chips = [roomChip("Lights", "3 On", symbol: "lightbulb.2"), roomChip("Occupancy", "Clear")]
        rail.setChips(chips)
        let (_, window) = host(rail, width: 390, category: .large)
        defer { window.isHidden = true }
        settle(rail)
        // The size category reaches the chips after the rail has measured them: the chip alone is told.
        chips[1].traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        settle(rail)
        assertFit("room chip restyled alone", chips, rail: rail)
    }

    // MARK: Wider windows and a fold column

    func testARoomChipGrowsInAWideRailAndInsideFoldColumns() {
        for width in [868, 1194] as [CGFloat] {
            for insideFold in [false, true] {
                let rail = UKChipRailView()
                let chips = [roomChip("Lights", "3 On", symbol: "lightbulb.2"), roomChip("Occ", ""), roomChip("Climate", "72°", symbol: "thermometer.medium")]
                rail.setChips(chips)
                let controller = UIViewController()
                let top: UIView
                if insideFold {
                    let fold = UKFoldColumns(spacing: HassTokens.Spacing.l)
                    fold.setSections([UKFoldColumns.Section(rail, side: .leading), UKFoldColumns.Section(UIView(), side: .trailing)])
                    top = fold
                } else {
                    top = rail
                }
                controller.view.addSubview(top)
                top.frame = CGRect(x: 0, y: 0, width: width, height: 200)
                controller.traitOverrides.horizontalSizeClass = .regular
                controller.traitOverrides.preferredContentSizeCategory = .extraExtraExtraLarge
                let window = HostedPage.show(controller, size: CGSize(width: width, height: 900))
                defer { window.isHidden = true }
                settle(top)
                configure(chips[1], "Occupancy", "Clear")
                settle(top)
                assertFit("room chip at \(width) fold=\(insideFold)", chips, rail: rail)
            }
        }
    }

    // MARK: Status pills

    private func hostPills(width: CGFloat) -> (UKDynamicGridView, [UKStatusPillView], UIViewController, UIWindow) {
        let pills = [UKStatusPillView(label: "Battery", value: "80%", symbol: "battery.100percent"),
                     UKStatusPillView(label: "Next", value: "Soon", symbol: "calendar")]
        let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: 150, maxColumns: 2, spacing: HassTokens.Spacing.s))
        grid.setItems(pills.map { UKGridItem($0) })
        let controller = UIViewController()
        controller.view.addSubview(grid)
        grid.frame = CGRect(x: 0, y: 0, width: width, height: 10)
        controller.traitOverrides.preferredContentSizeCategory = .extraExtraExtraLarge
        let window = HostedPage.show(controller, size: CGSize(width: width, height: 900))
        settle(grid)
        return (grid, pills, controller, window)
    }

    private func assertPillsFit(_ name: String, _ pills: [UKStatusPillView], grid: UKDynamicGridView, file: StaticString = #filePath, line: UInt = #line) {
        // A parent sizes the grid from its measure; a stale measure leaves the pills short.
        grid.frame.size.height = grid.gridHeight(forWidth: grid.bounds.width)
        grid.layoutIfNeeded()
        for pill in pills {
            let needed = pill.sizeThatFits(CGSize(width: pill.frame.width, height: .greatestFiniteMagnitude)).height
            XCTAssertGreaterThanOrEqual(pill.frame.height + 0.5, needed, "\(name): \(pill.accessibilityLabel ?? "") is tall enough: \(pill.frame) vs \(needed)", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(grid.frame.height + 0.5, (pills.map(\.frame.maxY).max() ?? 0), "\(name): the grid holds its pills", file: file, line: line)
    }

    func testAStatusPillWhoseValueWrapsGrowsItsGridWhileHosted() {
        let (grid, pills, _, window) = hostPills(width: 390)
        defer { window.isHidden = true }
        pills[0].configure(label: "Battery", value: "80% and charging from the solar panel", detail: "Last full at 4:15 pm yesterday", symbol: "battery.100percent")
        settle(grid)
        assertPillsFit("pill hosted", pills, grid: grid)
    }

    func testAStatusPillChangedWhileOffWindowIsMeasuredWhenTheyReturn() {
        let (grid, pills, controller, window) = hostPills(width: 390)
        defer { window.isHidden = true }
        grid.removeFromSuperview()
        pills[0].configure(label: "Battery", value: "80% and charging from the solar panel", detail: "Last full at 4:15 pm yesterday", symbol: "battery.100percent")
        controller.view.addSubview(grid)
        settle(grid)
        assertPillsFit("pill changed off-window", pills, grid: grid)
    }

    func testAChipChangedWhileItsRailWasOffWindowIsMeasuredWhenItReturns() {
        let rail = UKChipRailView()
        let chips = [roomChip("Lights", "3 On", symbol: "lightbulb.2"), roomChip("Occ", "")]
        rail.setChips(chips)
        let (controller, window) = host(rail, width: 390, category: .accessibilityMedium)
        defer { window.isHidden = true }
        settle(rail)
        rail.removeFromSuperview()
        configure(chips[1], "Occupancy", "Clear")
        controller.view.addSubview(rail)
        rail.frame = CGRect(x: 0, y: 0, width: 390, height: 10)
        settle(rail)
        assertFit("rail off-window", chips, rail: rail)
    }

    // MARK: Word-boundary wrapping (section-sides V1)

    /// A wrapped chip breaks between words only: every word of each label fits the label's width, so no line ends in a hyphen or
    /// a half word.
    private func assertNoMidWordBreak(_ name: String, _ chips: [UIControl], file: StaticString = #filePath, line: UInt = #line) {
        for chip in chips {
            chip.layoutIfNeeded()
            for label in HostedPage.descendants(of: chip).compactMap({ $0 as? UILabel }) where label.frame.width > 0 {
                let style = label.attributedText?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
                XCTAssertEqual(style?.hyphenationFactor, 0, "\(name): \"\(label.text ?? "")\" never hyphenates", file: file, line: line)
                XCTAssertEqual(style?.usesDefaultHyphenation, false, "\(name): \"\(label.text ?? "")\" does not use the default hyphenation", file: file, line: line)
                for word in (label.text ?? "").split(separator: " ") {
                    let width = (String(word) as NSString).size(withAttributes: [.font: label.font as Any]).width
                    XCTAssertLessThanOrEqual(width, label.frame.width + 0.5, "\(name): \"\(word)\" is not split across lines in \(label.frame)", file: file, line: line)
                }
            }
        }
    }

    func testChipsNeverBreakAWordInTheMiddleWhenTheyWrap() {
        for category in [UIContentSizeCategory.extraExtraExtraLarge, .accessibilityMedium] {
            let rail = UKChipRailView()
            let chips: [UIControl] = makeChips() + [roomChip("Occupancy", "Clear"), roomChip("Contact Sensors", "All closed")]
            rail.setChips(chips)
            let (_, window) = host(rail, width: 390, category: category)
            defer { window.isHidden = true }
            settle(rail)
            assertNoMidWordBreak("wrapped at \(category.rawValue)", chips)
        }
    }

    /// A word wider than the chip has to break somewhere (a label breaks it by character under `.byWordWrapping`); its paragraph style
    /// turns hyphenation off and the label keeps its own font and colour.
    func testAWordWiderThanTheChipKeepsTheNoHyphenationStyle() {
        let word = "Supercalifragilisticexpialidocious"
        let chips: [UIControl] = {
            let status = UKStatusChipView()
            status.configure(title: word, summary: "Clear", symbol: "person", family: nil, isActive: false, tint: nil, animated: false) {}
            return [status, roomChip(word, "Clear")]
        }()
        for chip in chips {
            chip.frame = CGRect(x: 0, y: 0, width: 150, height: 200)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            window.addSubview(chip)
            chip.layoutIfNeeded()
            defer { window.isHidden = true }
            guard let label = HostedPage.descendants(of: chip).compactMap({ $0 as? UILabel }).first(where: { $0.text == word }),
                  let attributed = label.attributedText else { return XCTFail("title label missing") }
            let storage = NSTextStorage(attributedString: attributed)
            storage.addAttribute(.font, value: label.font as Any, range: NSRange(location: 0, length: storage.length))
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: max(1, chip.bounds.width - 70), height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            manager.ensureLayout(for: container)
            XCTAssertGreaterThan(manager.numberOfGlyphs, 0)
            var lines = 0
            manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in lines += 1 }
            XCTAssertGreaterThan(lines, 1, "the word is wider than the chip, so it breaks")
            // Measured 2026-11-06: a standalone NSLayoutManager inserts a hyphen glyph at each forced break of a word wider than its
            // line whatever the paragraph style says (37 glyphs for 34 characters), so the hyphen of a too-long word cannot be
            // proven absent here. The chip's sizing keeps every word whole (`testChipsNeverBreakAWordInTheMiddleWhenTheyWrap`); this
            // case only pins the paragraph style and that the label keeps its colour.
            let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(style?.hyphenationFactor, 0)
            XCTAssertEqual(style?.usesDefaultHyphenation, false)
            XCTAssertNotEqual(label.textColor, UIColor.black, "the label keeps its own colour")
        }
    }
}
