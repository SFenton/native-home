#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

// Owned by the design DesignLists lane. Pages: modal-sizing, system-accessibility.
extension UKGallery {
    static func designLists(_ page: ComponentGallery.Page) -> UIViewController? {
        switch page {
        case .modalSizing: UKGalleryHost.navigation(UKModalSizingGalleryPage())
        case .systemAccessibility: UKGalleryHost.navigation(UKSystemAccessibilityGalleryPage())
        default: nil
        }
    }
}

/// The nav controller a design-lists gallery page sits in until the shell lane's wallpaper and header chrome land: a dark ground
/// and a large title, like the SwiftUI gallery's `NavigationStack` over the page backdrop.
@MainActor
private enum UKGalleryHost {
    static func navigation(_ root: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.overrideUserInterfaceStyle = .dark
        navigation.navigationBar.prefersLargeTitles = true
        navigation.view.backgroundColor = UIColor(rgb: 0x111723)
        return navigation
    }
}

// MARK: - system-accessibility

/// `FENTON_GALLERY=system-accessibility`: reports the accessibility settings the app actually sees (Reduce Motion, Reduce
/// Transparency, Increase Contrast, Bold Text), so a journey can prove its launch options took effect before it audits.
private final class UKSystemAccessibilityGalleryPage: UIViewController {
    private var labels: [String: UILabel] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "System Accessibility"
        view.backgroundColor = UIColor(rgb: 0x111723)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = HassTokens.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        for name in ["reduceMotion", "reduceTransparency", "increaseContrast", "boldText"] {
            let label = UILabel.uk(.body, ink: UKDesignInk.primary)
            label.isAccessibilityElement = false
            labels[name] = label
            let card = UKModuleView.wrapping(label, insets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
            card.isAccessibilityElement = true
            card.accessibilityIdentifier = "env.\(name)"
            stack.addArrangedSubview(card)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: HassTokens.Spacing.l),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: HassTokens.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -HassTokens.Spacing.l),
        ])
        for name in [UIAccessibility.reduceMotionStatusDidChangeNotification, UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                     UIAccessibility.boldTextStatusDidChangeNotification, UIAccessibility.darkerSystemColorsStatusDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: Self, _) in self.refresh() }
        refresh()
    }

    @objc private func refresh() {
        func text(_ name: String, _ isOn: Bool) {
            labels[name]?.text = "\(name): \(isOn ? "on" : "off")"
            labels[name]?.superview?.accessibilityLabel = "\(name): \(isOn ? "on" : "off")"
        }
        text("reduceMotion", UIAccessibility.isReduceMotionEnabled)
        text("reduceTransparency", UIAccessibility.isReduceTransparencyEnabled)
        text("increaseContrast", traitCollection.accessibilityContrast == .high)
        text("boldText", UIAccessibility.isBoldTextEnabled)
    }
}

// MARK: - modal-sizing

/// `FENTON_GALLERY=modal-sizing`: a short sheet that opens at its content's height, a tall one that scrolls at large, a sheet with
/// the section tab bar (full height), an edit sheet whose confirm check is disabled until a change, and the Sort and Filter sheets.
/// The launch default `modalSizingOpen` (short, tall, tabs, edit, sort, filter) opens one at once, as the SwiftUI gallery does. It also comes
/// as `FENTON_GALLERY_MODAL_OPEN`, which a reused journey app can change between tests (a launch argument always launches fresh); the variable wins.
private final class UKModalSizingGalleryPage: UIViewController {
    private enum Kind: String, CaseIterable {
        case short, tall, tabs, edit, sort, filter
        var title: String {
            switch self {
            case .short: "Short Sheet"
            case .tall: "Tall Sheet"
            case .tabs: "Tab Sheet"
            case .edit: "Edit Sheet"
            case .sort: "Sort Sheet"
            case .filter: "Filter Sheet"
            }
        }
    }

    private var filterSheet: UKFilterSheet?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Modal Sizing"
        view.backgroundColor = UIColor(rgb: 0x111723)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        for kind in Kind.allCases {
            let button = UKPrimaryButton(kind.title) { [weak self] in self?.open(kind) }
            button.accessibilityIdentifier = "sizing.open.\(kind.rawValue)"
            stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: HassTokens.Spacing.l),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: HassTokens.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -HassTokens.Spacing.l),
        ])
    }

    private let opener = UKGalleryAutoOpener(label: "modal-sizing")

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let raw = ukDirectionGOption("modalSizingOpen", environment: "FENTON_GALLERY_MODAL_OPEN"), let kind = Kind(rawValue: raw) else { return }
        opener.start(on: self) { [weak self] in self?.open(kind) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController == nil { opener.cancel() }
    }

    private func open(_ kind: Kind) {
        switch kind {
        case .short: present(listSheet(title: "Lighting Mode", scroll: "sizing.short.scroll", rows: [("Warm", "sun.max"), ("Cool", "snowflake"), ("Party", "party.popper")]))
        case .tall: present(listSheet(title: "All Lights", scroll: "sizing.tall.scroll", rows: (1...40).map { ("Light \($0)", "lightbulb") }))
        case .tabs: present(tabSheet())
        case .edit: present(editSheet())
        case .sort: present(sortSheet())
        case .filter: present(filterDemoSheet())
        }
    }

    private func present(_ modal: UKHassModalController) { modal.present(from: self) }

    // MARK: Sheets

    /// Rows in a scroll view with 16 pt of padding, on the sheet's cell.
    private func listSheet(title: String, scroll identifier: String, rows: [(String, String)]) -> UKHassModalController {
        let page = UKScrollPage()
        page.scrollView.accessibilityIdentifier = identifier
        let list = UKModuleListView(surface: .sheet, rows: rows.map { UKRowView(.init($0.0, symbol: $0.1), surface: .sheet) })
        page.setContent(list, insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        var options = UKHassModalOptions(title: title, fitKey: "ModalSizing.\(title)")
        options.closeIdentifier = "sizing.close"
        return UKHassModalController(root: page, options: options)
    }

    private func tabSheet() -> UKHassModalController {
        let page = UKTabSheetPage()
        var options = UKHassModalOptions(title: "Living Room TV", fitKey: "ModalSizing.tabs")
        options.closeIdentifier = "sizing.close"
        options.height = .full
        options.width = .page
        return UKHassModalController(root: page, options: options)
    }

    private func editSheet() -> UKHassModalController {
        let original = "Replace the furnace filter"
        let form = UKFormViewController()
        var options = UKHassModalOptions(title: "Edit Task", fitKey: "ModalSizing.edit")
        options.showsClose = false
        let modal = UKHassModalController(root: form, options: options)
        var name = original
        let confirm = UKSheetConfirmItem("Save", isEnabled: false, identifier: "sizing.edit.save") { [weak modal] in modal?.close() }
        func refresh() {
            confirm.update(isEnabled: SheetEditState.canConfirm(isValid: !name.isEmpty, hasChanges: name != original))
        }
        form.setSections([UKFormSection(id: "main", rows: [
            UKFormRow(id: "name", identifier: "sizing.edit.name", .text(placeholder: "Task Name", text: name) { name = $0; refresh() }),
        ])], animated: false)
        form.navigationItem.leftBarButtonItem = UKSheetItems.cancel(identifier: "sizing.edit.cancel") { [weak modal] in modal?.close() }
        form.navigationItem.rightBarButtonItem = confirm.barButtonItem
        refresh()
        return modal
    }

    private func sortSheet() -> UKHassModalController {
        let state = SortState()
        // The sheet's reset handler needs the sheet: build through a holder.
        let holder = FilterHolder()
        let built = UKFilterSheet(title: "Sort Rows", canApply: false, canReset: false, onApply: {}, onReset: { [weak holder] in
            state.draft = 0
            holder?.refresh?()
        }, sections: [])
        holder.sheet = built
        holder.refresh = { [weak built] in
            built?.update(subtitle: nil, canApply: state.draft != 0, canReset: state.draft != 0, sections: [
                UKFormSection(id: "sort", header: "Sort By", rows: (0..<3).map { index in
                    UKFormRow(id: "option\(index)", identifier: "sizing.sort.\(index)",
                              .option(title: "Option \(index + 1)", subtitle: nil, swatch: [], isSelected: state.draft == index) {
                                  state.draft = index
                                  holder.refresh?()
                              })
                }),
            ])
        }
        holder.refresh?()
        filterSheet = built
        return built.modal
    }

    private func filterDemoSheet() -> UKHassModalController {
        let state = FilterState()
        let holder = FilterHolder()
        let built = UKFilterSheet(title: "Filter Recipes", subtitle: "1 Filter On", canApply: true, canReset: true, onApply: {}, onReset: { [weak holder] in
            state.expiringOnly = false
            state.minimum = 0
            holder?.refresh?()
        }, sections: [])
        holder.sheet = built
        holder.refresh = { [weak built] in
            built?.update(subtitle: state.expiringOnly ? "1 Filter On" : nil, canApply: state.expiringOnly,
                          canReset: state.expiringOnly || state.minimum != 0, sections: [
                UKFormSection(id: "coverage", header: "Ingredient Coverage", headerStyle: .system, rows: [
                    UKFormRow(id: "expiring", identifier: "sizing.filter.expiring", .toggle(title: "Expiring Ingredients Only", isOn: state.expiringOnly) { on in
                        state.expiringOnly = on
                        holder.refresh?()
                    }),
                    UKFormRow(id: "minimum", .slider(label: "Minimum Ingredients Available", value: state.minimum, range: 0...100) { value in
                        state.minimum = value
                        holder.refresh?()
                    }),
                ]),
                // Enough rows that the form scrolls: the header must stay clear of a material while rows pass under it.
                UKFormSection(id: "categories", header: "Categories", headerStyle: .system, rows: (1...14).map { index in
                    UKFormRow(id: "category\(index)", .toggle(title: "Category \(index)", isOn: false) { _ in })
                }),
            ])
        }
        holder.refresh?()
        filterSheet = built
        return built.modal
    }

    private final class SortState { var draft = 0 }
    private final class FilterState {
        var expiringOnly = true
        var minimum: Float = 40
    }
    private final class FilterHolder {
        var sheet: UKFilterSheet?
        var refresh: (() -> Void)?
    }
}

/// A page that is a scroll view of one content view with insets (a sheet's `ScrollView { … }.padding(…)`).
private final class UKScrollPage: UIViewController, UKSheetFitting {
    let scrollView = UIScrollView()
    var sheetFitScrollView: UIScrollView? { scrollView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKDesignSurface.systemGround
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.alwaysBounceVertical = false
        view.addSubview(scrollView)
    }

    func setContent(_ content: UIView, insets: UIEdgeInsets) {
        loadViewIfNeeded()
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: insets.top),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -insets.bottom),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: insets.left),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -insets.right),
        ])
    }
}

/// A modal with a section tab bar: the real ``UKModalTabBar`` pinned along the bottom (icons on compact width, a menu at accessibility
/// sizes, `.agents/patterns/modal-sheet.md`).
private final class UKTabSheetPage: UIViewController {
    private enum Tab: String, CaseIterable, Identifiable {
        case controls = "Controls", apps = "Apps", info = "Info"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .controls: "appletvremote.gen4"
            case .apps: "play.rectangle"
            case .info: "info.circle"
            }
        }
    }
    private let label = UILabel.uk(.body, ink: UKDesignInk.primary, alignment: .center)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UKDesignSurface.systemGround
        let scroll = UIScrollView()
        scroll.accessibilityIdentifier = "sizing.tabs.scroll"
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        label.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(label)
        let bar = UKModalTabBar(tabs: Tab.allCases, label: "TV sections", title: { $0.rawValue }, symbol: { $0.symbol },
                                selection: Tab.controls, identifier: "sizing.tabs") { [weak self] tab in self?.label.text = tab.rawValue }
        label.text = Tab.controls.rawValue
        let control = bar.inset()
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: control.topAnchor),
            label.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: HassTokens.Spacing.l),
            label.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.l),
            label.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: HassTokens.Spacing.l),
            label.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -HassTokens.Spacing.l),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            control.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            control.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }
}

@MainActor
private extension UIImage {
    func withAccessibilityLabel(_ label: String) -> UIImage {
        accessibilityLabel = label
        return self
    }
}
#endif
