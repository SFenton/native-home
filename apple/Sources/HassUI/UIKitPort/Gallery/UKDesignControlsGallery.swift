#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the design DesignControls lane. Pages: thermostat-dial, floating-actions, motion.
//
// Stand-ins (drawn here until the other design lanes land their components, never as parallel components):
//  - the pages sit in a plain `UINavigationController` on the page base ground; the shell lane's wallpaper and header fade replace it;
//  - the Sort and Filter sheets of `floating-actions` use the real `UKFilterSheet`;
//  - the `motion` page carries the cases built from components this lane ports; each other lane appends its own cases to
//    `UKMotionGallery.extraCases` when its component lands (GlassTile, StatusPill, ChipRail, rows, pickers …).
extension UKGallery {
    static func designControls(_ page: ComponentGallery.Page) -> UIViewController? {
        let root: UIViewController
        switch page {
        case .thermostatDial: root = UKThermostatDialGalleryController()
        case .floatingActions: root = UKFloatingActionsGalleryController().makeHosted()
        case .motion: root = UKMotionGalleryController()
        default: return nil
        }
        let navigation = UINavigationController(rootViewController: root)
        navigation.overrideUserInterfaceStyle = .dark
        navigation.navigationBar.prefersLargeTitles = true
        return navigation
    }
}

// MARK: - Shared chrome

/// The dark ground of a gallery page: the house backdrop's base (`#111723`).
private var galleryGround: UIColor { UIColor(red: 17 / 255, green: 23 / 255, blue: 35 / 255, alpha: 1) }

/// Lays its views out in as many columns as `LazyVGrid(columns: [GridItem(.adaptive(minimum:))])` would, top aligned.
private final class UKGalleryGrid: UIView {
    private let items: [UIView]
    private let minimum: CGFloat
    private let spacing: CGFloat
    private let rows = UIStackView()
    private var columns = 0

    init(items: [UIView], minimum: CGFloat, spacing: CGFloat) {
        self.items = items
        self.minimum = minimum
        self.spacing = spacing
        super.init(frame: .zero)
        rows.axis = .vertical
        rows.spacing = spacing
        addSubview(rows)
        rows.ukPin(to: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let wanted = max(1, Int(((bounds.width + spacing) / (minimum + spacing)).rounded(.down)))
        guard wanted != columns else { return }
        columns = wanted
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for start in stride(from: 0, to: items.count, by: wanted) {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = spacing
            row.distribution = .fillEqually
            row.alignment = .top
            for offset in 0..<wanted { row.addArrangedSubview(start + offset < items.count ? items[start + offset] : UIView()) }
            rows.addArrangedSubview(row)
        }
    }
}

/// A scroll view with a vertical stack inside, padded by `HassTokens.Spacing.l`.
private func makeScroll(in controller: UIViewController, stack: UIStackView) -> UIScrollView {
    let scroll = UIScrollView()
    controller.view.addSubview(scroll)
    scroll.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        scroll.topAnchor.constraint(equalTo: controller.view.topAnchor), scroll.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        scroll.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
    ])
    scroll.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    let pad = HassTokens.Spacing.l
    NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: pad),
        stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -pad),
        stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: pad),
        stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -pad),
        stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -pad * 2),
    ])
    return scroll
}

// MARK: - thermostat-dial

/// `ThermostatDialGallery`: every dial state the Climate page needs, from fixture values, each echoing its commit back like Home
/// Assistant would.
private final class UKThermostatDialGalleryController: UIViewController {
    private var fixtures = ThermostatDialGallery.fixtures
    private var dials: [String: UKThermostatDial] = [:]
    private let lastCommit = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Thermostat Dial"
        view.backgroundColor = galleryGround.blended(with: UIColor.systemBlue.withAlphaComponent(0.08))
        lastCommit.text = "Last commit: None"
        lastCommit.font = UKFont.preferred(.footnote)
        lastCommit.adjustsFontForContentSizeCategory = true
        lastCommit.textColor = UIColor(HassTokens.RGB.Ink.secondary)
        lastCommit.accessibilityIdentifier = "gallery.lastCommit"
        lastCommit.numberOfLines = 0
        let cards = fixtures.map(card)
        let grid = UKGalleryGrid(items: cards, minimum: 320, spacing: HassTokens.Spacing.l)
        let stack = UIStackView(arrangedSubviews: [lastCommit, grid])
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.l
        _ = makeScroll(in: self, stack: stack)
    }

    private func card(_ fixture: ThermostatDialGallery.Fixture) -> UIView {
        let title = UILabel()
        title.text = fixture.name
        title.font = UKFont.preferred(.headline)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = UIColor(HassTokens.RGB.Ink.primary)
        title.accessibilityTraits = .header
        let dial = UKThermostatDial(fixture.configuration, size: .modal, surface: .page) { [weak self] targets in
            // Echo the commit back like Home Assistant would.
            guard let self, let index = fixtures.firstIndex(where: { $0.id == fixture.id }) else { return }
            fixtures[index].configuration.targets = targets
            dials[fixture.id]?.configuration = fixtures[index].configuration
            lastCommit.text = "Last commit: \(fixture.id) \(ThermostatDialGallery.describe(targets))"
        }
        dials[fixture.id] = dial
        let column = UIStackView(arrangedSubviews: [title, dial])
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        column.alignment = .fill
        let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        material.layer.cornerRadius = HassTokens.Radius.tile
        material.layer.cornerCurve = .continuous
        material.clipsToBounds = true
        material.contentView.addSubview(column)
        column.ukPin(to: material.contentView, insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        material.accessibilityContainerType = .semanticGroup
        material.accessibilityIdentifier = "gallery.thermostat.\(fixture.id)"
        return material
    }
}

private extension UIColor {
    /// This colour with `overlay` laid over it.
    func blended(with overlay: UIColor) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        resolvedColor(with: dark).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        overlay.resolvedColor(with: dark).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 * (1 - a2) + r2 * a2, green: g1 * (1 - a2) + g2 * a2, blue: b1 * (1 - a2) + b2 * a2, alpha: 1)
    }
}

// MARK: - floating-actions

/// `FloatingActionsGallery`: a scrolling list under a bar with a labeled action, an expandable search and icon-only Sort and
/// Filter actions that open filter sheets.
private final class UKFloatingActionsGalleryController: UITableViewController {
    private enum Sort: String, CaseIterable {
        case available = "Ingredients Available", expiring = "Expiring Soon", alphabetical = "Alphabetical"
        var key: String { "\(self)" }
    }

    private let search = UKFloatingSearch(prompt: "Search rows")
    private let bag = UKObservationBag()
    private var sort: Sort = .available
    private var minimum = 0.0
    private var lastAction = "none"
    private let lastCallLabel = UKGalleryLastCallView(title: "Last action")
    private let items = (1...30).map { "Row \($0)" }
    private var bar: UKFloatingActionBar?

    init() {
        super.init(style: .insetGrouped)
        title = "Floating Actions"
    }
    required init?(coder: NSCoder) { fatalError() }

    private var rows: [String] { items.filter { search.text.isEmpty || $0.localizedCaseInsensitiveContains(search.text) } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = galleryGround
        tableView.backgroundColor = .clear
        // The debug line is the table's header, a label of its own so XCUITest reads it as a static text.
        lastCallLabel.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        lastCallLabel.textAlignment = .center
        tableView.tableHeaderView = lastCallLabel
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        bag.observe { [weak self] in
            guard let self else { return }
            _ = search.text
            tableView.reloadSections(IndexSet(integer: 0), with: .none)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = rows[indexPath.row]
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }

    /// The bar, built once: the page is hosted with it by `makeHosted()`.
    func makeHosted() -> UIViewController {
        let bar = UKFloatingActionBar(actions: [
            UKFloatingAction(id: "sort", title: "Sort", symbol: "arrow.up.arrow.down", showsTitle: false, isActive: sort != .available) { [weak self] in self?.presentSort() },
            UKFloatingAction(id: "filter", title: "Filter", symbol: "slider.horizontal.3", showsTitle: false, isActive: minimum > 0) { [weak self] in self?.presentFilter() },
            UKFloatingAction(id: "add", title: "Add Task", symbol: "plus") { [weak self] in self?.record("add") },
        ], search: search)
        self.bar = bar
        return UKPinnedBarViewController(content: self, bar: bar, scrollView: tableView)
    }

    private func record(_ action: String) {
        lastAction = action
        lastCallLabel.record(action)
    }

    private var sortSheet: UKFilterSheet?
    private var sortDraft: Sort = .available
    private var filterSheet: UKFilterSheet?
    private var filterDraft = 0.0

    private func presentSort() {
        sortDraft = sort
        let sheet = UKFilterSheet(title: "Sort Rows", canApply: false, canReset: sort != .available,
                                  onApply: { [weak self] in
                                      guard let self else { return }
                                      sort = sortDraft
                                      bar?.setActive(sort != .available, forActionID: "sort")
                                      record("sort \(sort.rawValue)")
                                  },
                                  onReset: { [weak self] in
                                      self?.sortDraft = .available
                                      self?.refreshSort()
                                  },
                                  sections: sortSections())
        sortSheet = sheet
        sheet.present(from: self)
    }

    private func sortSections() -> [UKFormSection] {
        [UKFormSection(id: "sort", header: "Sort By", rows: Sort.allCases.map { option in
            UKFormRow(id: option.key, identifier: "gallery.sort.\(option.key)",
                      .option(title: option.rawValue, subtitle: "Sort by \(option.rawValue.lowercased()).", swatch: [], isSelected: sortDraft == option) { [weak self] in
                          self?.sortDraft = option
                          self?.refreshSort()
                      })
        })]
    }

    private func refreshSort() {
        sortSheet?.update(subtitle: nil, canApply: sortDraft != sort, canReset: sortDraft != .available, sections: sortSections())
    }

    private func presentFilter() {
        filterDraft = minimum
        let slider = UKPercentSliderRow("Minimum Ingredients Available", value: minimum, identifier: "gallery.filter.minimum") { [weak self] value in
            self?.filterDraft = (value / 5).rounded() * 5
            self?.refreshFilter()
        }
        filterSlider = slider
        let sheet = UKFilterSheet(title: "Filter Rows", canApply: false, canReset: minimum > 0,
                                  onApply: { [weak self] in
                                      guard let self else { return }
                                      minimum = filterDraft
                                      bar?.setActive(minimum > 0, forActionID: "filter")
                                      record("filter \(Int(minimum))")
                                  },
                                  onReset: { [weak self] in
                                      self?.filterDraft = 0
                                      self?.filterSlider?.value = 0
                                      self?.refreshFilter()
                                  },
                                  sections: filterSections(slider))
        filterSheet = sheet
        sheet.present(from: self)
    }

    private var filterSlider: UKPercentSliderRow?

    private func filterSections(_ slider: UKPercentSliderRow) -> [UKFormSection] {
        [UKFormSection(id: "coverage", header: "Minimum Ingredients Available", rows: [UKFormRow(id: "minimum", .custom { slider })])]
    }

    private func refreshFilter() {
        guard let slider = filterSlider else { return }
        filterSheet?.update(subtitle: nil, canApply: filterDraft != minimum, canReset: filterDraft > 0, sections: filterSections(slider))
    }
}


// MARK: - motion

/// A component with a two-state look in the motion gallery.
@MainActor
struct UKMotionCase {
    var id: String
    var title: String
    var make: () -> UIView
    /// Puts the component in the state (called with the view `make` returned).
    var apply: (UIView, Bool) -> Void
}

/// Cases other lanes add when their components land (`UKMotionGallery.extraCases.append(…)` from the lane's gallery file).
@MainActor
enum UKMotionGallery {
    static var extraCases: [UKMotionCase] = []

    /// The cases built from this lane's components. With `FENTON_UK_EXTRAS=1` the controls that have no SwiftUI counterpart in the
    /// SwiftUI motion page (segmented choice, modal tab bar, page indicator, slider, schedule fields …) are added so they can be
    /// seen and driven.
    static var cases: [UKMotionCase] {
        var cases: [UKMotionCase] = [
            UKMotionCase(id: "primaryButton", title: "PrimaryButton", make: { UKPrimaryButton("Save") {} }, apply: { view, on in (view as? UKPrimaryButton)?.isEnabled = on }),
            UKMotionCase(id: "floatingActionBar", title: "FloatingActionBar", make: {
                UKFloatingActionBar(actions: [
                    UKFloatingAction(id: "filter", title: "Filter", symbol: "slider.horizontal.3", showsTitle: false) {},
                    UKFloatingAction(id: "add", title: "Add Task", symbol: "plus") {},
                ])
            }, apply: { view, on in (view as? UKFloatingActionBar)?.setActive(on, forActionID: "filter") }),
        ]
        if ProcessInfo.processInfo.environment["FENTON_UK_EXTRAS"] == "1" { cases += extras }
        return cases + extraCases
    }

    private struct Tab: Hashable, Identifiable {
        var id: String
        var title: String
        var symbol: String
    }

    private static let tabs = [Tab(id: "a", title: "Controls", symbol: "slider.horizontal.3"), Tab(id: "b", title: "Schedules", symbol: "calendar"), Tab(id: "c", title: "Info", symbol: "info.circle")]

    private static var extras: [UKMotionCase] {
        [
            UKMotionCase(id: "segmentedChoice", title: "SegmentedChoice", make: {
                UKSegmentedChoice(label: "Mist level", options: ["Low", "Medium", "High"], title: { $0 }, selection: "Low", identifier: "motion.segmented") { _ in }
            }, apply: { view, on in (view as? UKSegmentedChoice<String>)?.selection = on ? "High" : "Low" }),
            UKMotionCase(id: "modalTabBar", title: "ModalTabBar (badged)", make: {
                UKModalTabBar(tabs: tabs, label: "Sections", title: { $0.title }, symbol: { $0.symbol }, badge: { $0.id == "b" ? 3 : 0 }, selection: tabs[0], identifier: "motion.tabs") { _ in }
            }, apply: { view, on in (view as? UKModalTabBar<Tab>)?.selection = on ? tabs[1] : tabs[0] }),
            UKMotionCase(id: "modalTabBarIcons", title: "ModalTabBar (icons)", make: {
                UKModalTabBar(tabs: tabs, label: "Sections", title: { $0.title }, symbol: { $0.symbol }, selection: tabs[0], identifier: "motion.tabs.icons") { _ in }
            }, apply: { view, on in (view as? UKModalTabBar<Tab>)?.selection = on ? tabs[2] : tabs[0] }),
            UKMotionCase(id: "pageIndicator", title: "PageIndicator", make: {
                UKPageIndicator(page: 0, pageCount: 4, label: "Suggestion page", identifier: "motion.pages", ink: .white) { _ in }
            }, apply: { view, on in (view as? UKPageIndicator)?.page = on ? 2 : 0 }),
            UKMotionCase(id: "percentSlider", title: "PercentSliderRow", make: {
                UKPercentSliderRow("Brightness", value: 40, identifier: "motion.slider") { _ in }
            }, apply: { view, on in (view as? UKPercentSliderRow)?.value = on ? 80 : 40 }),
            UKMotionCase(id: "controllerToggle", title: "ControllerToggle", make: {
                let host = UIView()
                let toggle = UKControllerToggle(isOn: false) { _ in }
                host.addSubview(toggle)
                toggle.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([toggle.topAnchor.constraint(equalTo: host.topAnchor), toggle.bottomAnchor.constraint(equalTo: host.bottomAnchor), toggle.leadingAnchor.constraint(equalTo: host.leadingAnchor)])
                return host
            }, apply: { view, on in (view.subviews.first as? UKControllerToggle)?.show(on) }),
            UKMotionCase(id: "pagedRow", title: "PagedRow", make: {
                UKPagedRowView(itemCount: 12, perPage: 4) { index in
                    let label = UILabel()
                    label.text = "\(index + 1)"
                    label.textAlignment = .center
                    label.font = UKFont.preferred(.title3)
                    label.textColor = UIColor(HassTokens.RGB.Ink.primary)
                    return label
                }
            }, apply: { view, on in (view as? UKPagedRowView)?.firstVisible = on ? 8 : 0 }),
            UKMotionCase(id: "scheduleFields", title: "ScheduleDateFields", make: {
                UKScheduleDateFields(fields: [
                    ScheduleDateField(label: "Starts", part: .dateAndTime, value: Date(timeIntervalSince1970: 1_800_000_000), identifier: "motion.start") { _ in },
                    ScheduleDateField(label: "Ends", part: .time, value: Date(timeIntervalSince1970: 1_800_003_600), identifier: "motion.end") { _ in },
                ])
            }, apply: { _, _ in }),
        ]
    }
}

/// `MotionGallery`: every component with a state appears in a card with a **Toggle state** button, and **Toggle All** flips every
/// card at once, so a person can watch each cross-fade (and UI tests can drive them). The toggles change plain state: nothing here
/// wraps them in an animation, so a component that does not animate its own colours visibly jumps.
///
/// Each card's component sits in an element `motion.component.<id>` whose accessibility value is `On` or `Off`; `motion.state.<id>`
/// reads the same state as text.
private final class UKMotionGalleryController: UIViewController {
    private let cases = UKMotionGallery.cases
    private var on: Set<String> = []
    private var views: [String: UIView] = [:]
    private var stateLabels: [String: UILabel] = [:]
    private var components: [String: UIView] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Motion"
        view.backgroundColor = galleryGround
        let stack = UIStackView(arrangedSubviews: cases.map(card))
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.l
        let scroll = makeScroll(in: self, stack: stack)
        scroll.accessibilityIdentifier = "motion.scroll"
        let toggleAll = UIBarButtonItem(title: "Toggle All", primaryAction: UIAction { [weak self] _ in self?.toggleAll() })
        toggleAll.accessibilityIdentifier = "motion.toggleAll"
        navigationItem.rightBarButtonItem = toggleAll
    }

    private func toggleAll() {
        if on.count == cases.count { on = [] } else { on = Set(cases.map(\.id)) }
        cases.forEach(sync)
    }

    private func toggle(_ item: UKMotionCase) {
        if on.contains(item.id) { on.remove(item.id) } else { on.insert(item.id) }
        sync(item)
    }

    /// Plain state, never wrapped in an animation block.
    private func sync(_ item: UKMotionCase) {
        let isOn = on.contains(item.id)
        if let view = views[item.id] { item.apply(view, isOn) }
        components[item.id]?.accessibilityValue = isOn ? "On" : "Off"
        stateLabels[item.id]?.text = "State: \(isOn ? "On" : "Off")"
    }

    private func card(_ item: UKMotionCase) -> UIView {
        let title = UILabel()
        title.text = item.title
        title.font = UKFont.preferred(.headline)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = UIColor(HassTokens.RGB.Ink.primary)
        title.numberOfLines = 0
        var configuration = UIButton.Configuration.bordered()
        configuration.title = "Toggle state"
        configuration.baseForegroundColor = UIColor(HassTokens.RGB.Ink.action)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.toggle(item) })
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        // Without the word "Button": the audit flags a label that repeats the trait.
        button.accessibilityLabel = "Toggle \(item.title.replacing("Button", with: "").trimmingCharacters(in: .whitespaces))"
        button.accessibilityIdentifier = "motion.toggle.\(item.id)"
        let header = UIStackView(arrangedSubviews: [title, button])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = HassTokens.Spacing.s

        let component = item.make()
        views[item.id] = component
        let holder = UIView()
        holder.addSubview(component)
        component.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            component.topAnchor.constraint(equalTo: holder.topAnchor), component.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            component.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            component.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
        ])
        holder.isAccessibilityElement = false
        holder.accessibilityContainerType = .semanticGroup
        holder.accessibilityLabel = item.title
        holder.accessibilityValue = "Off"
        holder.accessibilityIdentifier = "motion.component.\(item.id)"
        components[item.id] = holder

        let state = UILabel()
        state.text = "State: Off"
        state.font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .regular)
        state.textColor = UIColor(HassTokens.RGB.Ink.secondary)
        state.accessibilityIdentifier = "motion.state.\(item.id)"
        stateLabels[item.id] = state

        let column = UIStackView(arrangedSubviews: [header, holder, state])
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        let module = UIView()
        module.backgroundColor = UIColor(HassTokens.RGB.Surface.moduleThin)
        module.layer.cornerRadius = HassTokens.Radius.module
        module.layer.cornerCurve = .continuous
        module.addSubview(column)
        column.ukPin(to: module, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: HassTokens.Spacing.m, bottom: HassTokens.Spacing.m, right: HassTokens.Spacing.m))
        return module
    }
}
#endif
