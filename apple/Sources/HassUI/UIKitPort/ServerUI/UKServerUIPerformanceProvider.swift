#if os(iOS)
import HassCore
import HassDesign
import HassTelemetry
import Observation
import UIKit

// MARK: - Local diagnostics

/// Projects the existing telemetry report into shell-owned keyed collections.
@MainActor @Observable
final class UKServerUIPerformanceProvider: UKServerUISettingsProvider {
    let definition: ServerUISettingsSource
    let collections: [String: ServerUIRowCollection]
    private let current: () -> Bool
    private var busy = false
    private var recording: Bool
    private var confirming = false
    private var sharing = false
    var isCurrentSession: Bool { current() }
    var protectsPublication: Bool { busy || confirming || sharing }

    init(id: String, isCurrentSession: @escaping () -> Bool) throws {
        definition = .init(providerId: id, domain: .performance)
        current = isCurrentSession
        recording = Telemetry.isEnabled
        collections = Dictionary(uniqueKeysWithValues: ["scrolling", "loading", "navigation", "live", "actions", "images"]
            .map { ($0, ServerUIRowCollection()) })
        try refresh()
    }

    func accepts(_ control: ServerUISettingsControl) -> Bool {
        control.kind.domain == .performance && (control.kind == .performanceRecording
            || ["refresh", "clear-images", "reset", "export"].contains(control.item))
    }

    func refresh() throws {
        let report = PerformanceReport.current()
        func row(_ id: String, _ title: String, _ value: String, _ subtitle: String? = nil) -> ServerUIRowItem {
            .init(id: id, title: title, subtitle: subtitle, value: value)
        }
        func stats(_ id: String, _ title: String, _ stat: TelemetryStats) -> ServerUIRowItem {
            row(id, title, "\(PerformanceScreen.number(stat.p50)) ms",
                "median, p95 \(PerformanceScreen.number(stat.p95)) ms, max \(PerformanceScreen.number(stat.max)) ms, \(stat.count) samples")
        }
        var scrolling = report.scroll.map { row("page." + $0.page, $0.page, "\(PerformanceScreen.number($0.stats.hitchRatio, fraction: 1)) ms/s",
                                                  "\($0.stats.hitches) hitches in \($0.stats.frames) frames") }
        if let ratio = report.metricKitHitchRatio { scrolling.append(row("metrickit", "MetricKit (last day)", "\(PerformanceScreen.number(ratio, fraction: 1)) ms/s")) }
        try collections["scrolling"]?.apply(scrolling, phase: .ready)
        try collections["loading"]?.apply(report.pages.map { stats("page." + $0.name, $0.name, $0.stats) }
            + [row("instant", "Shown instantly", "\(report.counter("gate.instant"))")], phase: .ready)
        try collections["navigation"]?.apply(report.navigation.map {
            row($0.surface.rawValue, $0.surface.title, PerformanceScreen.navigationValue($0), PerformanceScreen.navigationDetail($0))
        }, phase: .ready)
        var live = [row("deliveries", "Deliveries", "\(report.counter("entity.deliveries"))", "\(report.counter("entity.changed")) entity changes")]
        if let stat = report.stats["EntityUpdate"] { live.append(stats("apply", "Apply time", stat)) }
        try collections["live"]?.apply(live, phase: .ready)
        var actions = [row("rollbacks", "Rolled back", "\(report.counter("optimistic.rollbacks"))")]
        if let stat = report.stats["ServiceCall"] { actions.append(stats("call", "Service call", stat)) }
        if let stat = report.stats["OptimisticConfirm"] { actions.append(stats("confirm", "Confirmed by Home Assistant", stat)) }
        try collections["actions"]?.apply(actions, phase: .ready)
        var images = [
            row("hits", "Cache hits", "\(report.counter("image.memoryHits") + report.counter("image.diskHits"))",
                "\(report.counter("image.memoryHits")) memory, \(report.counter("image.diskHits")) disk"),
            row("downloads", "Downloads", "\(report.counter("image.fetches") + report.counter("image.changed"))",
                "\(report.counter("image.notModified")) unchanged (304), \(report.counter("image.failures")) failed"),
            row("disk", "On disk", ByteCountFormatter.string(fromByteCount: Int64(report.diskBytes), countStyle: .file), "\(report.diskFiles) images"),
        ]
        if let stat = report.stats["ImageDecode"] { images.append(stats("decode", "Decode", stat)) }
        try collections["images"]?.apply(images, phase: .ready)
    }

    func make(_ control: ServerUISettingsControl, host: UKServerUISettingsAtom, page: UKServerUIPage) throws -> UIView {
        guard accepts(control) else { throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources") }
        if control.kind == .performanceRecording {
            let toggle = UISwitch()
            toggle.isOn = recording
            toggle.accessibilityLabel = control.node.title
            toggle.addAction(UIAction { [weak self, weak host, weak page, weak toggle] _ in
                guard let self, let host, let page, let toggle else { return }
                host.perform(from: page) {
                    try self.requireCurrent()
                    self.recording = toggle.isOn
                    Telemetry.isEnabled = toggle.isOn
                }
            }, for: .valueChanged)
            return UKRowView(.init(control.node.title, subtitle: control.subtitle), accessory: toggle)
        }
        let button = UKPrimaryButton(control.node.title) { [weak self, weak host, weak page] in
            guard let self, let host, let page else { return }
            host.perform(from: page) {
                try self.requireCurrent()
                switch control.item {
                case "refresh": try self.refresh()
                case "clear-images": ImagePipeline.shared.removeAll(); try self.refresh()
                case "reset":
                    self.confirming = true
                    let spec = AlertCopy.resetMeasurements
                    let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: spec.confirm.title, style: .destructive) { [weak self] _ in
                        guard let self else { return }
                        defer { self.confirming = false }
                        host.perform(from: page) { try self.requireCurrent(); Telemetry.log.reset(); try self.refresh() }
                    })
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.confirming = false })
                    page.present(alert, animated: true)
                case "export": self.export(from: page)
                default: throw HouseholdSettingsTarget.Failure.invalidTarget
                }
            }
        }
        host.bag.observe { [weak self, weak button] in button?.isEnabled = self?.busy == false && self?.isCurrentSession == true }
        return button
    }

    private func export(from page: UKServerUIPage) {
        guard !busy else { return }
        busy = true
        Task { [self] in
            defer { busy = false }
            do {
                let url = try await PerformanceReport.writeExportAsync()
                try requireCurrent()
                let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                sharing = true
                sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in
                    Task { @MainActor in self?.sharing = false }
                }
                sheet.popoverPresentationController?.sourceView = page.view
                sheet.popoverPresentationController?.sourceRect = CGRect(x: page.view.bounds.midX, y: page.view.bounds.midY, width: 0, height: 0)
                sheet.popoverPresentationController?.permittedArrowDirections = []
                page.present(sheet, animated: true)
            } catch {
                let alert = UIAlertController(title: "Couldn't Export Telemetry", message: "Try again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                page.present(alert, animated: true)
            }
        }
    }
}
#endif
