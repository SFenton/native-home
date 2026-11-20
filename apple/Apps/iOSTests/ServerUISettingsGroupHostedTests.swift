@testable import HassCore
import HassDemoHouse
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Settings groups: one list per module-list section

/// Hosted checks for `pl-setlist` (`.agents/patterns/module-list.md`, `.agents/patterns/settings-section.md`, `build/design/pl-setlist/spec.md`): a
/// `module-list` section is one group the list draws, and a settings row inside it is content, padding and a wash, never a card.
///
/// The Settings page is built from its real parts: a `UKServerUISection` per section with the settings links and the preferences
/// provider's blur, reset, badge and version rows. Every case hosts in a window of one family's own width (`HostedPage.show` with the
/// raw size, outside the scene): folded Duo 350 and 466, iPhone 390, iPad 744 and unfolded Duo 868 points.
@MainActor
final class ServerUISettingsGroupHostedTests: DemoHouseTestCase {
    private static let sizes = [CGSize(width: 350, height: 4000), CGSize(width: 390, height: 4000), CGSize(width: 466, height: 4000),
                                CGSize(width: 744, height: 4000), CGSize(width: 868, height: 4000)]
    private static let large = UIContentSizeCategory.large
    private static let ax3 = UIContentSizeCategory.accessibilityExtraLarge
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Building the page

    /// One hosted Settings page: its sections, the window and what to ask each list.
    @MainActor
    private struct Page {
        let window: UIWindow
        let sections: [UKServerUISection]
        let links: [String: UKServerUISettingsLink]
        let atoms: [String: UKServerUISettingsAtom]
        var lists: [UKModuleListView] {
            sections.compactMap { HostedPage.descendants(of: $0).compactMap { $0 as? UKModuleListView }.first }
        }
    }

    private func control(_ kind: ServerUISettingsControl.Kind, id: String, title: String) -> ServerUISettingsControl {
        ServerUISettingsControl(node: .init(id: id, title: title, span: 1), sourceId: "preferences", kind: kind, item: "", subtitle: "",
                                icon: .init(name: "gearshape", rendering: .canonical, unavailable: .fallback), destination: nil)
    }

    private func link(_ title: String, _ subtitle: String, symbol: String = "gearshape") -> UKServerUISettingsLink {
        let link = UKServerUISettingsLink()
        link.cell.kind = .link
        link.cell.show(UKRowView.settingsLink(title: title, subtitle: subtitle, symbol: symbol, showsChevron: !subtitle.isEmpty))
        link.cell.makeElement(label: UKRowView.accessibilityLabel(title: title, subtitle: subtitle), hint: nil, traits: .button,
                              identifier: "settings-" + title.lowercased().replacingOccurrences(of: " ", with: "-"))
        link.cell.setAction {}
        return link
    }

    private func section(_ id: String, header: String = "", style: ServerUICompositionDocument.Section.Style = .moduleList,
                         children: [UIView], surface: TileSurface = .page) -> UKServerUISection {
        let value = ServerUICompositionDocument.Section(node: .init(id: id, title: header, span: 1), header: header, footer: "", style: style,
                                                        density: .thin, hasGlyphs: false, spacing: .points(8), children: [])
        let section = UKServerUISection()
        section.apply(value, children: children, surface: surface)
        return section
    }

    /// The six sections of the published Settings page, at one family's width and one text size.
    private func settingsPage(size: CGSize, category: UIContentSizeCategory = ServerUISettingsGroupHostedTests.large,
                              appIcon: Bool = true) throws -> Page {
        let (renderer, rendererWindow, _) = try ServerUIRendererFixture.host()
        rendererWindow.isHidden = true
        let page = try ServerUIRendererFixture.root(renderer)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "settings-group-\(UUID().uuidString)"))
        let about = AboutSettingsModel(info: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"], pasteboard: { _ in })
        let provider = UKServerUIPreferencesProvider(
            id: "preferences", blur: BackdropBlurSettings(defaults: defaults),
            icons: AppIconPickerModel(platform: AppIconPlatform(supportsAlternateIcons: { true }, currentName: { nil }, setName: { _ in })),
            about: about, defaults: defaults, isCurrentSession: { true })
        var atoms: [String: UKServerUISettingsAtom] = [:]
        func atom(_ kind: ServerUISettingsControl.Kind, _ id: String, _ title: String) throws -> UKServerUISettingsAtom {
            let atom = UKServerUISettingsAtom()
            try atom.bind(control(kind, id: id, title: title), provider: provider, page: page)
            atoms[id] = atom
            return atom
        }
        var links: [String: UKServerUISettingsLink] = [:]
        func make(_ title: String, _ subtitle: String, symbol: String = "gearshape") -> UKServerUISettingsLink {
            let made = link(title, subtitle, symbol: symbol)
            links[title] = made
            return made
        }
        let sections = [
            section("top", children: [make("Vacation", "Vacation Mode and Solo Trip", symbol: "airplane"),
                                      make("To-Do", "An admin panel for to-do tasks.", symbol: "checklist")]),
            section("appearance", header: "Appearance", children: [
                try atom(.blur, "settings-blur", "Background Blur"), try atom(.resetBlur, "settings-reset", "Reset to Default"),
                try atom(.badge, "settings-badge", "Show count on app icon"),
            ] + (appIcon ? [make("App Icon", "")] : [])),
            section("household", header: "Household", children: [
                make("Admin Controls", "Presence-based toggles"), make("Rooms", "Room controls"),
                make("Guests", "Guest access"), make("Locks", "Door locks"),
            ]),
            section("system", header: "Home Assistant", children: [make("Server", "Server and account"), make("Performance", "Frame rate")]),
            section("feedback", header: "Feedback", children: [make("Report a Bug", "Send a report"), make("Suggest a Feature", "Send an idea")]),
            section("about", header: "About", children: [try atom(.version, "settings-version", "Version")]),
        ]
        let controller = UIViewController()
        let column = UKColumnView(spacing: HassTokens.Spacing.xl,
                                  insets: UIEdgeInsets(top: 60, left: HassTokens.Spacing.l, bottom: 0, right: HassTokens.Spacing.l))
        column.setViews(sections)
        column.frame = CGRect(origin: .zero, size: size)
        controller.view.addSubview(column)
        let window = HostedPage.show(controller, size: size, inScene: false)
        window.traitOverrides.preferredContentSizeCategory = category
        for _ in 0..<4 { HostedPage.wait(0.05); window.layoutIfNeeded() }
        return Page(window: window, sections: sections, links: links, atoms: atoms)
    }

    // MARK: Reading the page

    private func frame(_ view: UIView, in list: UIView) -> CGRect { view.convert(view.bounds, to: list) }

    private func hairlines(_ list: UKModuleListView) -> [UKHairline] {
        HostedPage.descendants(of: list).compactMap { $0 as? UKHairline }
    }

    /// The drawn line of a hairline: its leading inset and how far it stops short of the list's trailing edge.
    private func insets(of hairline: UKHairline, in list: UKModuleListView) throws -> (leading: CGFloat, trailing: CGFloat) {
        let line = try XCTUnwrap(hairline.subviews.first)
        let box = frame(line, in: list)
        return (box.minX, list.bounds.width - box.maxX)
    }

    private func title(_ text: String, in row: UIView, list: UKModuleListView) throws -> CGRect {
        let label = try XCTUnwrap(HostedPage.descendants(of: row).compactMap { $0 as? UILabel }.first { $0.text == text },
                                  "no label \(text)")
        return frame(label, in: list)
    }

    /// Views that draw a rounded fill of their own: a corner radius and a background that is not clear. The system's switch and slider
    /// draw their own tracks and are left out.
    private func roundedFills(in root: UIView) -> [UIView] {
        func visit(_ view: UIView) -> [UIView] {
            if view is UISwitch || view is UISlider { return [] }
            let own = view.alpha > 0 && view.layer.cornerRadius > 0 && (view.backgroundColor.map { $0.cgColor.alpha > 0 } ?? false)
            return (own ? [view] : []) + view.subviews.flatMap(visit)
        }
        return root.subviews.flatMap(visit)
    }

    private func isInsideSystemControl(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let next = current {
            if next is UISwitch || next is UISlider { return true }
            current = next.superview
        }
        return false
    }

    private func row(_ id: String, _ page: Page) throws -> UIView {
        try XCTUnwrap(page.atoms[id] ?? page.links[id], "no row \(id)")
    }

    // MARK: Geometry: one group per section

    /// UX: each module-list section is exactly one filled 26 pt container, drawn by the list; no row inside has a fill or corners of its
    /// own, and the hairlines are rows minus one (1, 3, 3, 1, 1, 0).
    func testEachSectionIsOneFilledContainerWithNoRowCardAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let page = try settingsPage(size: size)
            defer { page.window.isHidden = true }
            XCTAssertEqual(page.lists.count, 6, "\(size): six module lists")
            for (list, expected) in zip(page.lists, [1, 3, 3, 1, 1, 0]) {
                let modules = HostedPage.descendants(of: list).compactMap { $0 as? UKModuleView }
                XCTAssertEqual(modules.count, 1, "\(size): one container per list")
                let module = try XCTUnwrap(modules.first)
                XCTAssertEqual(module.layer.cornerRadius, 26, "\(size): 26 pt corners")
                XCTAssertEqual(module.layer.cornerCurve, .continuous)
                XCTAssertTrue(module.clipsToBounds, "\(size): the group clips its rows and their wash")
                XCTAssertGreaterThan(module.backgroundColor?.cgColor.alpha ?? 0, 0, "\(size): the container carries the fill")
                XCTAssertEqual(roundedFills(in: list).filter { $0 !== module }.count, 0,
                               "\(size): no row draws a rounded fill: \(roundedFills(in: list).filter { $0 !== module })")
                XCTAssertEqual(hairlines(list).count, expected, "\(size): hairlines are rows minus one")
                XCTAssertEqual(list.rows.count - 1, max(expected, 0))
            }
        }
    }

    /// UX: the groups' edges sit at the page padding in every window, and the list fills the width (no cap, no centring).
    func testGroupEdgesSitAtThePagePaddingAndFillTheWidth() throws {
        for size in Self.sizes {
            let page = try settingsPage(size: size)
            defer { page.window.isHidden = true }
            for list in page.lists {
                let box = list.convert(list.bounds, to: page.window)
                XCTAssertEqual(box.minX, HassTokens.Spacing.l, accuracy: 0.5, "\(size): leading edge at the page padding")
                XCTAssertEqual(size.width - box.maxX, HassTokens.Spacing.l, accuracy: 0.5, "\(size): trailing edge at the page padding")
            }
        }
    }

    /// UX: the hairlines start at 61 pt under a glyph row and at 15 pt under a text or control row, and stop 16 pt short of the edge.
    func testHairlineInsetsComeFromTheRowAboveAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let page = try settingsPage(size: size)
            defer { page.window.isHidden = true }
            let lists = page.lists
            // Top: one hairline under a link (a glyph row).
            // Appearance: blur, reset, badge, App Icon: three hairlines, each under a control or text row, so each starts at 15 pt.
            let expected: [[CGFloat]] = [[61], [15, 15, 15], [61, 61, 61], [61], [61], []]
            for (index, list) in lists.enumerated() {
                let lines = hairlines(list)
                for (hairline, leading) in zip(lines, expected[index]) {
                    let measured = try insets(of: hairline, in: list)
                    XCTAssertEqual(measured.leading, leading, accuracy: 0.5, "\(size): section \(index) hairline starts at \(leading)")
                    XCTAssertEqual(measured.trailing, 16, accuracy: 0.5, "\(size): section \(index) hairline stops 16 pt short")
                }
            }
        }
    }

    /// UX: a hairline sits between its two rows and does not overlap either.
    func testHairlinesSitBetweenTheirRows() throws {
        let page = try settingsPage(size: Self.sizes[1])
        defer { page.window.isHidden = true }
        for list in page.lists {
            for (index, hairline) in hairlines(list).enumerated() {
                let above = frame(list.rows[index], in: list), line = frame(hairline, in: list), below = frame(list.rows[index + 1], in: list)
                XCTAssertLessThanOrEqual(above.maxY, line.minY + 0.5)
                XCTAssertLessThanOrEqual(line.maxY, below.minY + 0.5)
                XCTAssertEqual(line.height, 0.5, accuracy: 0.2)
            }
        }
    }

    // MARK: Row heights and content insets

    /// UX: row heights at the Large size: Reset to Default 74, Show count on app icon 65, Background Blur 83 to 86, App Icon 74 (a
    /// title-only link), Version 74, a link with a subtitle at least as tall as the title-only link.
    func testRowHeightsAtTheLargeSizeAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let page = try settingsPage(size: size)
            defer { page.window.isHidden = true }
            func height(_ id: String) throws -> CGFloat { try row(id, page).frame.height }
            XCTAssertEqual(try height("settings-reset"), 74, accuracy: 0.5, "\(size): Reset to Default")
            XCTAssertEqual(try height("settings-badge"), 65, accuracy: 0.5, "\(size): Show count on app icon")
            let blurHeight = try height("settings-blur")
            XCTAssertTrue((83...86.5).contains(blurHeight), "\(size): Background Blur \(blurHeight)")
            XCTAssertEqual(try height("App Icon"), 74, accuracy: 0.5, "\(size): App Icon")
            XCTAssertEqual(try height("settings-version"), 74, accuracy: 0.5, "\(size): Version")
            XCTAssertGreaterThanOrEqual(try height("Vacation"), 74, "\(size): a link with a subtitle")
            XCTAssertGreaterThanOrEqual(try height("To-Do"), try height("App Icon"), "\(size): To-Do is not shorter than App Icon")
        }
    }

    /// UX: a row's text starts 15 pt (text and control rows) or 61 pt (glyph rows) from the group's leading edge, "Background Blur" is
    /// not clipped, and trailing content ends 17.5 pt from the trailing edge.
    func testContentInsetsAtEveryFamilyWidth() throws {
        for size in Self.sizes {
            let page = try settingsPage(size: size)
            defer { page.window.isHidden = true }
            let appearance = page.lists[1], about = page.lists[5], top = page.lists[0]
            let blur = try title("Background Blur", in: try row("settings-blur", page), list: appearance)
            XCTAssertEqual(blur.minX, 15, accuracy: 0.5, "\(size): the blur title is 15 pt in, not clipped")
            XCTAssertEqual(try title("50%", in: try row("settings-blur", page), list: appearance).maxX, appearance.bounds.width - 17.5, accuracy: 0.5,
                           "\(size): the value ends 17.5 pt from the edge")
            XCTAssertEqual(try title("Reset to Default", in: try row("settings-reset", page), list: appearance).minX, 15, accuracy: 0.5)
            XCTAssertEqual(try title("Show count on app icon", in: try row("settings-badge", page), list: appearance).minX, 15, accuracy: 0.5)
            let toggle = try XCTUnwrap(HostedPage.descendants(of: try row("settings-badge", page)).compactMap { $0 as? UISwitch }.first)
            XCTAssertEqual(appearance.bounds.width - frame(toggle, in: appearance).maxX, 17.5, accuracy: 2.5, "\(size): the switch ends about 17.5 pt in (the system control aligns itself)")
            XCTAssertEqual(try title("Vacation", in: try row("Vacation", page), list: top).minX, 61, accuracy: 0.5, "\(size): a link's text starts after its glyph")
            XCTAssertEqual(try title("Version", in: try row("settings-version", page), list: about).minX, 61, accuracy: 0.5)
            XCTAssertEqual(try title("0.1.0 (1)", in: try row("settings-version", page), list: about).maxX, about.bounds.width - 17.5, accuracy: 0.5)
        }
    }

    /// UX: a link's row mode keeps its padding, so the lone links of Household Admin keep the height and the text position they had as a
    /// card; in a plain section the same link keeps its own card.
    func testALoneLinkKeepsItsHeightAndTextPositionInAGroupAndItsCardInAPlainSection() throws {
        for (size, category) in Self.sizes.flatMap({ size in [Self.large, Self.ax3, Self.ax5].map { (size, $0) } }) {
            let inList = link("Presence Overrides", "Who is home")
            let inPlain = link("Presence Overrides", "Who is home")
            let grouped = section("lone", children: [inList])
            let plain = section("lone-plain", style: .plain, children: [inPlain])
            let controller = UIViewController()
            let column = UKColumnView(spacing: 24, insets: UIEdgeInsets(top: 60, left: 16, bottom: 0, right: 16))
            column.setViews([grouped, plain])
            column.frame = CGRect(origin: .zero, size: size)
            controller.view.addSubview(column)
            let window = HostedPage.show(controller, size: size, inScene: false)
            defer { window.isHidden = true }
            window.traitOverrides.preferredContentSizeCategory = category
            for _ in 0..<4 { HostedPage.wait(0.05); window.layoutIfNeeded() }
            XCTAssertEqual(inList.frame.height, inPlain.frame.height, accuracy: 0.5, "\(size): same height as the card")
            let listText = try XCTUnwrap(HostedPage.descendants(of: inList).compactMap { $0 as? UILabel }.first { $0.text == "Presence Overrides" })
            let plainText = try XCTUnwrap(HostedPage.descendants(of: inPlain).compactMap { $0 as? UILabel }.first { $0.text == "Presence Overrides" })
            XCTAssertEqual(listText.convert(listText.bounds, to: inList).origin.x, plainText.convert(plainText.bounds, to: inPlain).origin.x,
                           accuracy: 0.5, "\(size): same text position")
            let list = try XCTUnwrap(HostedPage.descendants(of: grouped).compactMap { $0 as? UKModuleListView }.first)
            XCTAssertEqual(roundedFills(in: list).count, 1, "\(size): one fill, not a fill on a fill")
            XCTAssertEqual(hairlines(list).count, 0)
            XCTAssertFalse(inList.cell.isHighlighted)
            XCTAssertTrue(inList.cell.isListRow)
            XCTAssertFalse(inPlain.cell.isListRow, "a link in a plain section keeps its card")
            let card = roundedFills(in: inPlain)
            XCTAssertEqual(card.count, 1, "\(size): the plain link keeps one card")
            XCTAssertEqual(card.first?.layer.cornerRadius, 26)
        }
    }

    // MARK: Dynamic Type

    /// UX and accessibility: at AX3 and AX5 the glyph sits above the text and every hairline starts at 15 pt, rows grow, no title is cut
    /// and no row is clipped by the group.
    func testAccessibilitySizesStackTheGlyphAndKeepHairlinesAtFifteenPoints() throws {
        for size in Self.sizes {
            let large = try settingsPage(size: size)
            let largeHeights = ["Vacation", "settings-reset", "settings-badge", "settings-blur", "settings-version"].map { try? row($0, large).frame.height }
            large.window.isHidden = true
            for category in [Self.ax3, Self.ax5] {
                let page = try settingsPage(size: size, category: category)
                defer { page.window.isHidden = true }
                for (index, list) in page.lists.enumerated() {
                    for hairline in hairlines(list) {
                        let measured = try insets(of: hairline, in: list)
                        XCTAssertEqual(measured.leading, 15, accuracy: 0.5, "\(size) \(category.rawValue): section \(index) starts at 15 pt")
                        XCTAssertEqual(measured.trailing, 16, accuracy: 0.5)
                    }
                    for row in list.rows {
                        let box = frame(row, in: list)
                        XCTAssertTrue(list.bounds.insetBy(dx: -0.5, dy: -0.5).contains(box), "\(size): a row stays inside its group: \(box)")
                        for label in HostedPage.descendants(of: row).compactMap({ $0 as? UILabel }) where !(label.text ?? "").isEmpty {
                            let need = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
                            XCTAssertGreaterThanOrEqual(label.bounds.height + 1, need,
                                "\(size) \(category.rawValue): \(label.text ?? "") is not truncated (label \(label.bounds), needs \(need), pref \(label.preferredMaxLayoutWidth))")
                            XCTAssertTrue(row.bounds.insetBy(dx: -0.5, dy: -0.5).contains(label.convert(label.bounds, to: row)),
                                          "\(size): \(label.text ?? "") stays inside its row")
                        }
                    }
                }
                let vacation = try row("Vacation", page), glyph = try XCTUnwrap(HostedPage.descendants(of: vacation).compactMap { $0 as? UIImageView }.first { $0.image != nil })
                let text = try title("Vacation", in: vacation, list: page.lists[0])
                XCTAssertLessThanOrEqual(frame(glyph, in: page.lists[0]).maxY, text.minY + 0.5, "\(size) \(category.rawValue): the glyph sits above the title")
                XCTAssertEqual(text.minX, 15, accuracy: 0.5, "\(size): the title is 15 pt in")
                let blur = try row("settings-blur", page), value = try title("50%", in: blur, list: page.lists[1])
                let blurTitle = try title("Background Blur", in: blur, list: page.lists[1])
                XCTAssertGreaterThanOrEqual(value.minY, blurTitle.maxY - 0.5, "\(size) \(category.rawValue): the value sits under its title")
                XCTAssertEqual(blurTitle.minX, 15, accuracy: 0.5, "\(size): not clipped")
                let heights = ["Vacation", "settings-reset", "settings-badge", "settings-blur", "settings-version"].map { try? row($0, page).frame.height }
                for (grown, before) in zip(heights, largeHeights) { XCTAssertGreaterThan(grown ?? 0, before ?? .infinity, "\(size) \(category.rawValue): rows grow with the text") }
            }
        }
    }

    /// UX and accessibility: at AX5 a chevron row's subtitle frame is as tall as its text needs (the chevron and its gap come off the wrap
    /// width the row measures at), on the folded Duo's 350 and 466 pt windows and the iPhone's 390.
    func testAChevronRowSubtitleIsNotClippedAtTheLargestTextSize() throws {
        for size in [Self.sizes[0], Self.sizes[1], Self.sizes[2]] {
            let page = try settingsPage(size: size, category: Self.ax5)
            defer { page.window.isHidden = true }
            for id in ["Vacation", "To-Do", "Admin Controls", "Guests", "Server", "Report a Bug", "Suggest a Feature"] {
                let link = try row(id, page)
                let subtitle = try XCTUnwrap(HostedPage.descendants(of: link).compactMap { $0 as? UILabel }
                    .first { $0.font.pointSize <= 48 && $0.text != id && !($0.text ?? "").isEmpty }, id)
                let need = subtitle.sizeThatFits(CGSize(width: subtitle.bounds.width, height: .greatestFiniteMagnitude)).height
                XCTAssertGreaterThanOrEqual(subtitle.bounds.height + 1, need, "\(size) \(id): the subtitle frame holds its text")
            }
        }
    }

    // MARK: UX: press

    /// UX: pressing a link, Reset to Default or Version washes the whole row; the group clips the wash to its corners; the slider and the
    /// switch rows draw no wash.
    func testAPressWashesTheWholeRowAndTheGroupClipsIt() throws {
        for size in [Self.sizes[0], Self.sizes[3]] {
            let page = try settingsPage(size: size)
            defer { page.window.isHidden = true }
            let vacation = try XCTUnwrap(page.links["Vacation"]).cell
            vacation.isHighlighted = true
            let wash = try XCTUnwrap(vacation.subviews.first { $0.alpha == 1 && $0.bounds == vacation.bounds && ($0.backgroundColor?.cgColor.alpha ?? 0) > 0 })
            XCTAssertEqual(wash.layer.cornerRadius, 0, "\(size): the row's wash has no corners of its own")
            let module = try XCTUnwrap(HostedPage.descendants(of: page.lists[0]).compactMap { $0 as? UKModuleView }.first)
            XCTAssertTrue(module.clipsToBounds, "\(size): the group clips the wash on its first and last rows")
            vacation.isHighlighted = false
            for id in ["settings-reset", "settings-version"] {
                let button = try XCTUnwrap(page.atoms[id]?.content as? UKServerUIPreferenceRow)
                button.isHighlighted = true
                let wash = try XCTUnwrap(button.subviews.first { $0 !== button.row && $0.bounds == button.bounds && $0.backgroundColor != nil },
                                         "\(size): \(id) washes its whole bounds, padding included")
                XCTAssertEqual(wash.layer.cornerRadius, 0)
                if id == "settings-version" { XCTAssertEqual(wash.alpha, 0.10, accuracy: 0.01) }
                button.isHighlighted = false
            }
            XCTAssertNil(page.atoms["settings-blur"]?.content as? UIControl, "the slider row is no button")
            XCTAssertNil(page.atoms["settings-badge"]?.content as? UIControl, "the switch row is no button")
        }
    }

    // MARK: Accessibility

    /// Accessibility: one element per row (a link is a button named by title and subtitle), the switch and slider keep their elements,
    /// hairlines are not elements, and the reading order follows the visual order.
    func testRowsAreOneElementEachAndHairlinesAreHidden() throws {
        for size in [Self.sizes[0], Self.sizes[1], Self.sizes[3]] {
            let page = try settingsPage(size: size)
            defer { page.window.isHidden = true }
            let vacation = try XCTUnwrap(page.links["Vacation"]).cell
            XCTAssertTrue(vacation.isAccessibilityElement)
            XCTAssertEqual(vacation.accessibilityLabel, "Vacation, Vacation Mode and Solo Trip")
            XCTAssertTrue(vacation.accessibilityTraits.contains(.button))
            let reset = try XCTUnwrap(page.atoms["settings-reset"]?.content as? UKServerUIPreferenceRow)
            XCTAssertEqual(reset.accessibilityLabel, "Reset to Default")
            XCTAssertTrue(reset.accessibilityTraits.contains(.button))
            let blur = try XCTUnwrap(page.atoms["settings-blur"]?.content as? UKPercentSliderRow)
            XCTAssertTrue(blur.isAccessibilityElement)
            XCTAssertTrue(blur.accessibilityTraits.contains(.adjustable))
            let badge = try XCTUnwrap(page.atoms["settings-badge"]?.content as? UKRowView)
            let toggle = try XCTUnwrap(HostedPage.descendants(of: badge).compactMap { $0 as? UISwitch }.first)
            XCTAssertEqual(toggle.accessibilityLabel, "Show count on app icon")
            XCTAssertTrue((badge.accessibilityElements as? [UIView])?.contains { $0 === toggle } ?? false)
            for list in page.lists {
                XCTAssertTrue(hairlines(list).allSatisfy { !$0.isAccessibilityElement }, "hairlines are not elements")
                let ys = list.rows.map { frame($0, in: list).minY }
                XCTAssertEqual(ys, ys.sorted(), "\(size): the rows are in visual order")
            }
        }
    }

    /// Accessibility: the group draws one fill (the opaque one with Reduce Transparency) and no row paints a second, so there is no seam or
    /// darker band between rows; the hairlines keep their own visible ink.
    func testTheGroupDrawsOneFillAndKeepsVisibleHairlines() throws {
        let page = try settingsPage(size: Self.sizes[1])
        defer { page.window.isHidden = true }
        let expected = UKDesignSurface.moduleTint(.thin, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
        for list in page.lists {
            let module = try XCTUnwrap(HostedPage.descendants(of: list).compactMap { $0 as? UKModuleView }.first)
            XCTAssertEqual(module.backgroundColor, expected)
            for row in list.rows {
                for view in HostedPage.descendants(of: row) where !isInsideSystemControl(view) {
                    XCTAssertFalse(view.layer.cornerRadius > 0 && (view.backgroundColor?.cgColor.alpha ?? 0) > 0, "no second fill in a row: \(view)")
                }
            }
            for hairline in hairlines(list) {
                XCTAssertGreaterThan(hairline.subviews.first?.backgroundColor?.cgColor.alpha ?? 0, 0, "the hairline draws")
            }
        }
        // The sheet surface (the Home Assistant sheet) keeps the sheet's cell colour on the same list.
        let sheet = UKModuleListView(.thin, hasGlyphs: true, surface: .sheet, rows: [UKRowView(UKRowContent("Server"))])
        XCTAssertEqual(HostedPage.descendants(of: sheet).compactMap { $0 as? UKModuleView }.first?.backgroundColor, UKDesignSurface.sheetCell)
    }

    // MARK: Regression: lists that declare nothing do not move

    private func hosted(_ list: UKModuleListView, width: CGFloat = 358) -> UIWindow {
        let controller = UIViewController()
        let holder = UKServerUIFittingView.wrapping(list)
        controller.view.addSubview(holder)
        holder.frame = CGRect(x: 16, y: 60, width: width, height: holder.gridHeight(forWidth: width))
        let window = HostedPage.show(controller, size: CGSize(width: width + 32, height: 800), inScene: false)
        for _ in 0..<3 { HostedPage.wait(0.05); window.layoutIfNeeded() }
        return window
    }

    /// UX: the module lists of Vacation Mode (check rows), the Home Assistant sheet (value rows on the sheet) and the predictive climate
    /// detail (glyph rows) declare no insets, so their hairlines keep the scaled text inset or 16 pt, run flush to the trailing edge, and
    /// their rows keep the module heights (52 pt, 60 pt with a subtitle).
    func testListsThatDeclareNothingKeepTheirHairlinesAndHeights() throws {
        func rows(_ glyph: Bool) -> [UIView] {
            [UKRowView(UKRowContent("Lights", subtitle: "Turn off", symbol: glyph ? "lightbulb" : nil)), UKRowView(UKRowContent("Doors", symbol: glyph ? "door.left.hand.closed" : nil)),
             UKRowButton(UKRowView(UKRowContent("Server", value: "Home", symbol: glyph ? "server.rack" : nil, showsChevron: true)))]
        }
        let cases = [(true, TileSurface.page), (false, .page), (true, .sheet), (false, .sheet)]
        for ((glyphs, surface), category) in cases.flatMap({ item in [Self.large, Self.ax3, Self.ax5].map { (item, $0) } }) {
            let list = UKModuleListView(.thin, hasGlyphs: glyphs, surface: surface, rows: rows(glyphs))
            let window = hosted(list)
            defer { window.isHidden = true }
            window.traitOverrides.preferredContentSizeCategory = category
            // The holder is placed by hand here (a page's column would measure it again): give it the height it now measures.
            if let holder = window.rootViewController?.view.subviews.first(where: { $0 is UKServerUIFittingView }) {
                for _ in 0..<3 {
                    HostedPage.wait(0.05)
                    window.layoutIfNeeded()
                    holder.frame.size.height = (holder as? UKServerUIFittingView)?.gridHeight(forWidth: holder.bounds.width) ?? holder.frame.height
                }
            }
            let atLarge = category == Self.large
            let lines = hairlines(list)
            XCTAssertEqual(lines.count, 2)
            let expected = glyphs ? UIFontMetrics(forTextStyle: .body).scaledValue(for: ModuleRowMetrics.textInset, compatibleWith: list.traitCollection)
                : HassTokens.Spacing.l
            for hairline in lines {
                let measured = try insets(of: hairline, in: list)
                XCTAssertEqual(measured.leading, expected, accuracy: 0.5, "glyphs \(glyphs): the hairline keeps its inset")
                XCTAssertEqual(measured.trailing, 0, accuracy: 0.01, "glyphs \(glyphs): flush to the trailing edge")
            }
            if atLarge {
                XCTAssertEqual(list.rows[0].frame.height, ModuleRowMetrics.heightWithSubtitle, accuracy: 0.5)
                XCTAssertEqual(list.rows[1].frame.height, ModuleRowMetrics.height, accuracy: 0.5)
            }
            for row in list.rows {
                for label in HostedPage.descendants(of: row).compactMap({ $0 as? UILabel }) where !(label.text ?? "").isEmpty {
                    let need = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
                    // A line is 40 pt or more at these sizes; 3 pt allows the fractional rounding of a label measured at its own width.
                    XCTAssertGreaterThanOrEqual(label.bounds.height + 3, need, "\(category.rawValue): \(label.text ?? "") is not clipped in an unchanged list")
                }
            }
            XCTAssertEqual(roundedFills(in: list).count, 1, "one fill")
            for row in list.rows { XCTAssertNil((row as? UKSeparatorInsetDeclaring)?.separatorInsets, "\(type(of: row)) declares nothing") }
        }
    }

    /// UX: only a settings control that declares a kind changes a list; another provider's control (here a label) and a settings link in a
    /// plain section keep the module metrics.
    func testOnlyDeclaredSettingsKindsTakeTheGroupedMetrics() throws {
        let atom = UKServerUISettingsAtom()
        let label = UILabel()
        label.text = "Provider control"
        atom.install(label, identifier: "other")
        XCTAssertNil(atom.separatorInsets, "an undeclared atom keeps the list's inset")
        atom.settingsKind = .control
        XCTAssertEqual(atom.separatorInsets, .grouped(afterGlyph: false))
        atom.settingsKind = .link
        XCTAssertEqual(atom.separatorInsets, .grouped(afterGlyph: true))
        XCTAssertEqual(UKSeparatorInsets.grouped(afterGlyph: true).leadingInset(for: UITraitCollection(preferredContentSizeCategory: .large)), 61)
        XCTAssertEqual(UKSeparatorInsets.grouped(afterGlyph: true).leadingInset(for: UITraitCollection(preferredContentSizeCategory: Self.ax3)), 15)
        XCTAssertEqual(UKSeparatorInsets.grouped(afterGlyph: false).leadingInset(for: UITraitCollection(preferredContentSizeCategory: .large)), 15)
        XCTAssertEqual(UKSettingsRowKind.control.verticalPadding, 10.5)
        XCTAssertEqual(UKSettingsRowKind.link.verticalPadding, 15)
        XCTAssertEqual(UKSettingsRowKind.textButton.verticalPadding, 15)
        XCTAssertTrue(UKSettingsRowKind.link.hasGlyph)
        XCTAssertFalse(UKSettingsRowKind.textButton.hasGlyph)
    }

    /// UX: a link whose section is one the document turns from plain to module-list (a new publication) joins the group, and one turned
    /// back keeps its card.
    func testALinkFollowsItsSectionStyleWhenThePublicationChanges() throws {
        let item = link("Server", "Account")
        let grouped = section("s", children: [item])
        XCTAssertTrue(item.cell.isListRow)
        let value = ServerUICompositionDocument.Section(node: .init(id: "s", title: "", span: 1), header: "", footer: "", style: .plain,
                                                        density: .thin, hasGlyphs: false, spacing: .points(8), children: [])
        grouped.apply(value, children: [item], surface: .page)
        XCTAssertFalse(item.cell.isListRow)
    }
}
