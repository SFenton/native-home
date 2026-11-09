import AppKit
import SwiftUI

/// Puts a view in an off-screen window on the macOS test host so SwiftUI installs its state and presents
/// its sheets, as it does on a device. Controls are still driven through ``ControlProbe``; the window is for
/// what only a live hierarchy does (state, bindings, `.sheet`).
@MainActor
final class SheetHostWindow {
    let window: NSWindow
    let host: NSHostingView<AnyView>

    init<V: View>(_ view: V, size: CGSize = CGSize(width: 700, height: 900)) {
        _ = NSApplication.shared
        host = NSHostingView(rootView: AnyView(view))
        // A fixed frame and no intrinsic sizing: the grid layout needs a finite width.
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        settle()
    }

    deinit { MainActor.assumeIsolated { window.close() } }

    /// Runs the main loop briefly so state changes, layout and presentations land.
    func settle(_ seconds: TimeInterval = 0.3) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        host.layoutSubtreeIfNeeded()
    }

    /// Whether a sheet is attached to the window.
    var hasSheet: Bool { window.attachedSheet != nil || !(window.sheets.isEmpty) }
}

extension SheetHostWindow {
    /// Whether any view in the window's hierarchy has a class whose name contains `fragment`.
    func contains(_ fragment: String) -> Bool {
        func walk(_ view: NSView) -> Bool {
            if String(describing: type(of: view)).contains(fragment) { return true }
            return view.subviews.contains(where: walk)
        }
        return walk(host)
    }
}

extension SheetHostWindow {
    /// Every view of `type` in the window's hierarchy.
    func views<V: NSView>(ofType type: V.Type) -> [V] {
        var found: [V] = []
        func walk(_ view: NSView) {
            if let match = view as? V { found.append(match) }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found
    }
}
