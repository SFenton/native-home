#if os(iOS)
import Foundation
import ObjectiveC
import os
import UIKit

/// Counts the layout passes of a rotation or fold, and notes the shell values a pass wrote, so a layout loop shows up as numbers
/// (`.agents/platforms/apple/uikit-port.md`, "Rotation hang"). Off unless asked for: launch with `-UKLayoutCensus YES` (an Xcode scheme
/// argument, a Release build included) or `FENTON_LAYOUT_CENSUS=1`. Off, each call is one Bool read.
///
/// On, the summary is written to `os_log` (subsystem `com.sfenton.home`, category `layout-census`) once the main thread has been quiet
/// for 0.4 s: one line per rotation, `page.<Type>=<layouts> root=<n> shell=<n>` and the ordered notes (`hinge`, `bar`, `style`, `cap`,
/// `fixedTitle.write`). An endless loop never goes quiet, so the line is also written every 2 s while passes keep arriving (`busy`).
/// Read it afterwards with Console.app or `log collect` from the device, or launch with `OS_ACTIVITY_DT_MODE=YES` and
/// `devicectl device process launch --console` to read it on stderr.
///
/// On, ``install()`` also counts every view's `layoutSubviews` by class and size (`v.<Class>@<w>x<h>`), so a loop inside one layout
/// pass (a view that flips between two sizes, which no controller sees) names its view; the line keeps the 40 largest counts.
@MainActor
enum UKLayoutCensus {
    /// Settable so a hosted test can turn the census on and off in one process; nothing else writes it.
    nonisolated(unsafe) static var isEnabled = ProcessInfo.processInfo.environment["FENTON_LAYOUT_CENSUS"] == "1"
        || UserDefaults.standard.bool(forKey: "UKLayoutCensus")

    private static let log = Logger(subsystem: "com.sfenton.home", category: "layout-census")
    private static var counts: [String: Int] = [:]
    private static var events: [String] = []
    private static var quiet: DispatchWorkItem?
    private static var lastFlush = Date.distantPast

    private static var installed = false

    /// Starts counting every view's layout passes (census on only). Called once, from the root controller.
    static func install() {
        guard isEnabled, !installed else { return }
        installed = true
        guard let original = class_getInstanceMethod(UIView.self, #selector(UIView.layoutSubviews)),
              let counted = class_getInstanceMethod(UIView.self, #selector(UIView.census_layoutSubviews)) else { return }
        method_exchangeImplementations(original, counted)
        if let original = class_getInstanceMethod(UIView.self, #selector(UIView.setNeedsLayout)),
           let counted = class_getInstanceMethod(UIView.self, #selector(UIView.census_setNeedsLayout)) {
            method_exchangeImplementations(original, counted)
        }
        log.notice("installed view census")
    }

    /// Puts `layoutSubviews` and `setNeedsLayout` back (the census swaps them twice back to the originals); a hosted test ends with this.
    static func uninstall() {
        guard installed else { return }
        installed = false
        if let original = class_getInstanceMethod(UIView.self, #selector(UIView.layoutSubviews)),
           let counted = class_getInstanceMethod(UIView.self, #selector(UIView.census_layoutSubviews)) {
            method_exchangeImplementations(original, counted)
        }
        if let original = class_getInstanceMethod(UIView.self, #selector(UIView.setNeedsLayout)),
           let counted = class_getInstanceMethod(UIView.self, #selector(UIView.census_setNeedsLayout)) {
            method_exchangeImplementations(original, counted)
        }
    }

    private static var dirtyCalls = 0
    private static var stacks: [String: Int] = [:]

    /// Every 32nd `setNeedsLayout` while a burst runs: who asked, as the 14 frames above it (a loop names its caller).
    static func dirtied(_ view: UIView) {
        guard isEnabled else { return }
        dirtyCalls &+= 1
        guard dirtyCalls % 32 == 0 else { return }
        let frames = Thread.callStackSymbols.dropFirst(2).prefix(14).map { line -> String in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            return parts.count > 3 ? parts[3...].prefix(2).joined(separator: " ") : line
        }
        stacks["\(type(of: view))@\(Int(view.bounds.width))x\(Int(view.bounds.height)) <- " + frames.joined(separator: " < "), default: 0] += 1
    }

    static func bump(_ name: @autoclosure () -> String) {
        guard isEnabled else { return }
        counts[name(), default: 0] += 1
        scheduleFlush()
    }

    /// An ordered note: a value a layout pass changed.
    static func note(_ text: @autoclosure () -> String) {
        guard isEnabled else { return }
        events.append(text())
        scheduleFlush()
    }

    private static func scheduleFlush() {
        quiet?.cancel()
        if Date().timeIntervalSince(lastFlush) > 2 { flush(busy: true) }
        let item = DispatchWorkItem { flush(busy: false) }
        quiet = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    private static func flush(busy: Bool) {
        lastFlush = Date()
        let line = counts.sorted { $0.value > $1.value }.prefix(40).map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let notes = events.joined(separator: "; ")
        let dirty = stacks.sorted { $0.value > $1.value }.prefix(3).map { "\($0.value)x \($0.key)" }
        counts = [:]
        events = []
        stacks = [:]
        for stack in dirty { log.notice("dirty \(stack, privacy: .public)") }
        guard !line.isEmpty || !notes.isEmpty else { return }
        log.notice("\(busy ? "busy" : "settled", privacy: .public) \(line, privacy: .public) | \(notes, privacy: .public)")
    }
}
extension UIView {
    /// Swapped with `layoutSubviews` by ``UKLayoutCensus/install()``: the call below runs the original.
    @objc fileprivate func census_layoutSubviews() {
        UKLayoutCensus.bump("v.\(type(of: self))@\(Int(bounds.width))x\(Int(bounds.height))")
        census_layoutSubviews()
    }

    @objc fileprivate func census_setNeedsLayout() {
        UKLayoutCensus.dirtied(self)
        census_setNeedsLayout()
    }
}
#endif
