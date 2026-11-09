#if os(iOS)
import HassDesign
import HassTelemetry
import UIKit

/// Settings → Performance (``PerformanceScreen``): what the telemetry has measured on this device, and an export for sharing
/// through the system share sheet (pattern `telemetry.md`; HIG Lists and tables, Activity views). A list of labelled values on the
/// wallpaper, like the Settings list that pushes it.
final class UKPerformanceViewController: UKPageViewController {
    private let driver = UKSettingsListDriver(style: .wallpaper)
    private var report = PerformanceReport.current()
    private var recording = Telemetry.isEnabled
    private var exportURL: URL?
    private var refreshTask: Task<Void, Never>?
    private var hasRefreshed = false
    private let refreshControl = UIRefreshControl()

    init(context: UKContext) { super.init(context: context, title: "Performance") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { refreshTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let collection = driver.collectionView!
        collection.accessibilityIdentifier = "performance.screen"
        collection.refreshControl = refreshControl
        install(scrollView: collection)
        UKScrollFit.allowsPullToRefresh(collection)
        refreshControl.addAction(UIAction { [weak self] _ in self?.refresh(endRefreshing: true) }, for: .valueChanged)
        let refreshItem = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), primaryAction: UIAction { [weak self] _ in self?.refresh() })
        refreshItem.title = "Refresh"
        refreshItem.accessibilityLabel = "Refresh"
        refreshItem.accessibilityIdentifier = "performance.refresh"
        // The shell owns the trailing header buttons, so Refresh leads, beside Back.
        navigationItem.leftBarButtonItem = refreshItem
        navigationItem.leftItemsSupplementBackButton = true
        rebuild()
    }

    /// The report is read and the export written once the page is on screen, not while it slides in: the rebuild is a turn the
    /// animation would otherwise share (`.agents/design/motion.md` §4.2, heavy destination work waits for didShow).
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasRefreshed { hasRefreshed = true; refresh() }
    }

    /// Rereads the report and the export file (`.task(id: refreshTick)`, which cancels a refresh in flight).
    private func refresh(endRefreshing: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            report = PerformanceReport.current()
            rebuild()
            let url = try? await PerformanceReport.writeExportAsync()
            guard !Task.isCancelled else { return }
            exportURL = url
            rebuild()
            if endRefreshing { refreshControl.endRefreshing() }
        }
    }

    // MARK: Sections

    private func rebuild() {
        driver.setSections(sections())
    }

    func sections() -> [UKSettingsListSection] {
        let report = report
        var result: [UKSettingsListSection] = []

        result.append(UKSettingsListSection(
            id: "recording",
            footer: "Measures scrolling, navigation, loading, live updates and images on this device. Nothing leaves the device unless you export it.",
            rows: [UKSettingsRows.toggle(id: "recording", identifier: "performance.recording", title: "Record Telemetry", isOn: recording) { [weak self] on in
                self?.recording = on
                Telemetry.isEnabled = on
            }]))

        var scroll: [UKSettingsListRow] = []
        if report.scroll.isEmpty { scroll.append(empty("scroll.empty", "Scroll a page to measure it.")) }
        for (index, row) in report.scroll.enumerated() {
            scroll.append(measured("scroll.\(index)", title: row.page, value: "\(PerformanceScreen.number(row.stats.hitchRatio, fraction: 1)) ms/s",
                                   detail: "\(row.stats.hitches) hitches in \(row.stats.frames) frames · worst \(Int(row.stats.worstFrameMs)) ms",
                                   tone: row.stats.hitchRatio < 5 ? .good : row.stats.hitchRatio < 10 ? .warning : .bad))
        }
        if let ratio = report.metricKitHitchRatio {
            scroll.append(measured("scroll.metrickit", title: "MetricKit (last day)", value: "\(PerformanceScreen.number(ratio, fraction: 1)) ms/s",
                                   detail: "System scroll hitch ratio", tone: ratio < 5 ? .good : ratio < 10 ? .warning : .bad))
        }
        result.append(UKSettingsListSection(id: "scrolling", header: .system("Scrolling"), rows: scroll))

        var loading: [UKSettingsListRow] = []
        if report.pages.isEmpty { loading.append(empty("pages.empty", "No page has waited for content yet.")) }
        for (index, page) in report.pages.enumerated() { loading.append(stats("pages.\(index)", page.name, page.stats)) }
        loading.append(measured("pages.instant", title: "Shown instantly", value: "\(report.counter("gate.instant"))", detail: "Pages whose data was already there"))
        result.append(UKSettingsListSection(id: "loading", header: .system("Page Loading"), rows: loading))

        var navigation: [UKSettingsListRow] = []
        if report.navigation.isEmpty {
            navigation.append(empty("navigation.empty", "Switch tabs and open pages to measure them.", identifier: "performance.navigation.empty"))
        }
        for row in report.navigation {
            navigation.append(measured("navigation.\(row.surface.rawValue)", title: row.surface.title, value: PerformanceScreen.navigationValue(row),
                                       detail: PerformanceScreen.navigationDetail(row), tone: PerformanceScreen.navigationTone(row),
                                       identifier: "performance.navigation.\(row.surface.rawValue)"))
        }
        result.append(UKSettingsListSection(id: "navigation", header: .system("Navigation"), rows: navigation))

        var live: [UKSettingsListRow] = []
        if let stat = report.stats["EntityUpdate"] { live.append(stats("live.apply", "Apply time", stat)) }
        live.append(measured("live.deliveries", title: "Deliveries", value: "\(report.counter("entity.deliveries"))", detail: "\(report.counter("entity.changed")) entity changes"))
        result.append(UKSettingsListSection(id: "live", header: .system("Live Updates"), rows: live))

        var actions: [UKSettingsListRow] = []
        if let stat = report.stats["ServiceCall"] { actions.append(stats("actions.call", "Service call", stat)) }
        if let stat = report.stats["OptimisticConfirm"] { actions.append(stats("actions.confirm", "Confirmed by Home Assistant", stat)) }
        actions.append(measured("actions.rollbacks", title: "Rolled back", value: "\(report.counter("optimistic.rollbacks"))", detail: "Optimistic values undone by failed calls"))
        result.append(UKSettingsListSection(id: "actions", header: .system("Actions"), rows: actions))

        var images = [
            measured("images.hits", title: "Cache hits", value: "\(report.counter("image.memoryHits") + report.counter("image.diskHits"))",
                     detail: "\(report.counter("image.memoryHits")) memory · \(report.counter("image.diskHits")) disk"),
            measured("images.downloads", title: "Downloads", value: "\(report.counter("image.fetches") + report.counter("image.changed"))",
                     detail: "\(report.counter("image.notModified")) unchanged (304) · \(report.counter("image.failures")) failed"),
        ]
        if let stat = report.stats["ImageDecode"] { images.append(stats("images.decode", "Decode", stat)) }
        images.append(measured("images.disk", title: "On disk", value: ByteCountFormatter.string(fromByteCount: Int64(report.diskBytes), countStyle: .file),
                               detail: "\(report.diskFiles) images"))
        images.append(UKSettingsRows.button(id: "images.clear", identifier: "performance.clearImages", title: "Clear Image Cache", ink: .systemRed) { [weak self] in
            ImagePipeline.shared.removeAll()
            self?.refresh()
        })
        result.append(UKSettingsListSection(id: "images", header: .system("Images"), rows: images))

        var export: [UKSettingsListRow] = []
        if let exportURL {
            export.append(UKSettingsListRow(id: "export", signature: "export|\(exportURL.path)", action: { [weak self] in self?.share(exportURL) }, configure: { cell in
                var content = UKRowContent("Export Telemetry", symbol: "square.and.arrow.up", glyph: UKDesignInk.action, style: .form)
                content.titleInk = UKDesignInk.action
                content.verticalPadding = 14
                cell.show(UKRowView(content), insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: HassTokens.minTarget)
                cell.makeElement(label: "Export Telemetry", traits: .button, identifier: "performance.export")
            }))
        }
        export.append(UKSettingsRows.button(id: "reset", identifier: "performance.reset", title: "Reset Measurements", ink: .systemRed) { [weak self] in
            guard let self else { return }
            UKAlerts.alert(AlertCopy.resetMeasurements, from: self) { [weak self] in
                Telemetry.log.reset()
                self?.refresh()
            }
        })
        result.append(UKSettingsListSection(id: "export", footer: "\(report.recordCount) samples · \(report.metricKitPayloads) MetricKit reports",
                                            rows: export))
        return result
    }

    private func empty(_ id: String, _ text: String, identifier: String? = nil) -> UKSettingsListRow {
        UKSettingsListRow(id: id, signature: "empty|\(text)") { cell in
            var content = UKRowContent(text, style: .form)
            content.titleInk = UKDesignInk.secondary
            content.verticalPadding = 11
            cell.show(UKRowView(content), insets: NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), minHeight: HassTokens.minTarget)
            cell.makeElement(label: text, traits: .staticText, identifier: identifier)
        }
    }

    private func stats(_ id: String, _ title: String, _ stats: TelemetryStats) -> UKSettingsListRow {
        measured(id, title: title, value: "\(PerformanceScreen.number(stats.p50)) ms",
                 detail: "median · p95 \(PerformanceScreen.number(stats.p95)) ms · max \(PerformanceScreen.number(stats.max)) ms · \(stats.count) samples")
    }

    private func measured(_ id: String, title: String, value: String, detail: String, tone: PerformanceRow.Tone = .neutral,
                          identifier: String? = nil) -> UKSettingsListRow {
        UKSettingsListRow(id: id, signature: "row|\(title)|\(value)|\(detail)|\(tone)") { cell in
            cell.show(UKRowView.performance(title: title, value: value, detail: detail, tone: tone))
            cell.makeElement(label: title, value: PerformanceRow.spokenValue(value: value, detail: detail, tone: tone), identifier: identifier)
        }
    }

    private func share(_ url: URL) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        sheet.popoverPresentationController?.permittedArrowDirections = []
        present(sheet, animated: true)
    }
}

extension UKRowView {
    /// A timing row (``PerformanceRow``): the title and the value (semibold) on one line, or one under the other once they no longer fit,
    /// with the detail beneath the title. Only a bad value takes colour; its glyph follows the value.
    static func performance(title: String, value: String, detail: String, tone: PerformanceRow.Tone) -> UKRowView {
        var content = UKRowContent(title, subtitle: detail, value: value, style: .form)
        content.valueInk = tone == .bad ? UKDesignInk.danger : UKDesignInk.primary
        content.valueWeight = .semibold
        content.verticalPadding = HassTokens.Spacing.xs + 7
        var accessory: UIView?
        if let symbol = PerformanceRow.toneSymbol(tone) {
            let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.body, weight: .semibold))))
            icon.tintColor = content.valueInk
            icon.isAccessibilityElement = false
            icon.setContentHuggingPriority(.required, for: .horizontal)
            accessory = icon
        }
        return UKRowView(content, accessory: accessory)
    }
}
#endif
