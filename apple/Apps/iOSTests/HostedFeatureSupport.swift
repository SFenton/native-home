import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Helpers shared by the feature hosted tests (Settings, Household, Chores, Food, Inventory): a signed-in session on a server that
/// never answers, finding a control by accessibility identifier, tapping a list row the way a finger does, and answering alerts.
@MainActor
enum FeatureHost {
    /// A signed-in session whose connection never reaches a server (127.0.0.1:1), and a context wired to it.
    static func signedIn() throws -> (session: AppSession, connection: HassConnection, context: UKContext) {
        let session = AppSession(
            tokenStore: InMemoryTokenStore(),
            snapshotCache: EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "feature-host-\(UUID()).json")))
        let server = HassServer(baseURL: URL(string: "http://127.0.0.1:1")!)
        try session.didSignIn(server: server, tokens: AuthTokens(accessToken: "access", expiresAt: .distantFuture, refreshToken: "refresh"))
        guard case let .signedIn(connection, _) = session.phase else { throw XCTSkip("session did not sign in") }
        var context = UKGalleryChrome.context(store: connection.store, caller: connection)
        context.session = session
        context.connection = connection
        return (session, connection, context)
    }

    /// Runs the main loop for `seconds` so async rebuilds and observers settle.
    static func settle(_ seconds: TimeInterval = 0.2) {
        HostedPage.wait(seconds)
    }

    /// Runs the loop for `seconds` from an async test. A main-actor test body blocks queued `Task`s while it runs, so a nested run
    /// loop never lets them go; suspending does.
    static func settleAsync(_ seconds: TimeInterval = 0.2) async {
        try? await Task.sleep(for: .seconds(seconds))
        // One synchronous run-loop turn: lists reloaded by the awaited work lay out (diffable snapshots apply on it).
        spin()
    }

    /// Settles like ``settleAsync(_:)``, then keeps suspending until `condition` holds or `timeout` passes (a busy machine, or work left
    /// running by an earlier test, makes awaited work take longer than any fixed wait).
    @discardableResult
    static func settleAsync(until condition: () -> Bool, timeout: TimeInterval = 8) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { await settleAsync(0.1); HostedPage.layoutTracked() }
        return condition()
    }

    /// A synchronous run-loop turn (not callable lexically from async code, so it lives here).
    private static func spin() {
        HostedPage.wait(0.06)
    }

    /// Whether a view is on screen now: not hidden, and a collection cell not parked in the reuse queue (UIKit leaves those in the hierarchy).
    private static func isLive(_ view: UIView) -> Bool {
        if view.isHidden { return false }
        if let cell = view as? UICollectionViewCell, let collection = cell.superview as? UICollectionView {
            return collection.indexPath(for: cell) != nil
        }
        return true
    }

    /// The first live view under `root` with this accessibility identifier.
    static func view(_ identifier: String, in root: UIView) -> UIView? {
        guard isLive(root) else { return nil }
        // A glass tile that holds its own controls carries `<id>.tile` and leaves `<id>` to its accessibility element.
        if root.accessibilityIdentifier == identifier || root.accessibilityIdentifier == identifier + ".tile" { return root }
        for sub in root.subviews { if let hit = view(identifier, in: sub) { return hit } }
        return nil
    }

    /// A one-line account of the collection views under `root` (frame, rows, window), for assertion messages.
    static func describeLists(in root: UIView) -> String {
        var found: [String] = []
        func walk(_ view: UIView) {
            if let collection = view as? UICollectionView {
                let rows = (0..<collection.numberOfSections).reduce(0) { $0 + collection.numberOfItems(inSection: $1) }
                found.append("collection frame=\(collection.frame) content=\(collection.contentSize) offset=\(collection.contentOffset) cells=\(collection.visibleCells.map { "\($0.frame.minY)/\($0.frame.height)" }) rows=\(rows) window=\(collection.window != nil) hidden=\(collection.isHidden)")
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found.joined(separator: "; ")
    }

    /// Like ``view(_:in:)``, but scrolls the lists under `root` until a row below the fold is realised (a sheet is only as tall as its
    /// detent, and a collection view builds the cells in view). A list where it is not found goes back to where it was.
    static func reveal(_ identifier: String, in root: UIView) -> UIView? {
        if let found = view(identifier, in: root) { return found }
        // A list that is animating a new row in builds it a moment late: let it finish before scrolling.
        HostedPage.wait(0.6)
        var lists: [UICollectionView] = []
        func collect(_ view: UIView) {
            if let list = view as? UICollectionView, !list.isHidden { lists.append(list) }
            view.subviews.forEach(collect)
        }
        collect(root)
        // A snapshot applied with animation realises its new cell on the next layout pass.
        lists.forEach { $0.layoutIfNeeded() }
        if let found = view(identifier, in: root) { return found }
        for list in lists {
            list.layoutIfNeeded()
            let start = list.contentOffset
            let step = max(list.bounds.height * 0.6, 100)
            let bottom = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
            var offset = start.y
            while offset < bottom {
                offset = min(offset + step, bottom)
                list.setContentOffset(CGPoint(x: start.x, y: offset), animated: false)
                list.layoutIfNeeded()
                if let found = view(identifier, in: root) { return found }
            }
            list.setContentOffset(start, animated: false)
            list.layoutIfNeeded()
        }
        return nil
    }

    /// Lays out every view under `root` now.
    static func relayout(_ root: UIView) {
        root.subviews.forEach(relayout)
        root.setNeedsLayout()
        root.layoutIfNeeded()
    }

    /// Every accessibility identifier on screen under `root`.
    static func identifiers(in root: UIView) -> Set<String> {
        guard isLive(root) else { return [] }
        var found = Set<String>()
        if let id = root.accessibilityIdentifier {
            found.insert(id)
            if id.hasSuffix(".tile") { found.insert(String(id.dropLast(5))) }
        }
        for sub in root.subviews { found.formUnion(identifiers(in: sub)) }
        return found
    }

    /// Taps a collection-view row by the identifier its cell (or the view it hosts) carries; false when it is not on screen.
    @discardableResult
    static func tapRow(_ identifier: String, in root: UIView) -> Bool {
        guard let target = reveal(identifier, in: root) else { return false }
        var current: UIView? = target
        while let view = current {
            if let cell = view as? UICollectionViewCell, let collection = cell.superview as? UICollectionView,
               let path = collection.indexPath(for: cell) {
                collection.delegate?.collectionView?(collection, didSelectItemAt: path)
                return true
            }
            current = view.superview
        }
        return false
    }

    /// The switch with this identifier, or the one inside the labelled row that carries it (a glyph-and-title switch row).
    static func switchView(_ identifier: String, in root: UIView) -> UISwitch? {
        guard let found = reveal(identifier, in: root) else { return nil }
        if let toggle = found as? UISwitch { return toggle }
        func first(in view: UIView) -> UISwitch? {
            if let toggle = view as? UISwitch { return toggle }
            for sub in view.subviews { if let hit = first(in: sub) { return hit } }
            return nil
        }
        return first(in: found)
    }

    /// Flips a switch by identifier and sends its change, as a tap does.
    @discardableResult
    static func flip(_ identifier: String, in root: UIView) -> Bool {
        guard let toggle = switchView(identifier, in: root) else { return false }
        toggle.setOn(!toggle.isOn, animated: false)
        toggle.sendActions(for: .valueChanged)
        return true
    }

    /// Taps a button-like control by identifier.
    @discardableResult
    static func press(_ identifier: String, in root: UIView) -> Bool {
        guard let target = reveal(identifier, in: root) else {
            // A navigation bar's item is not a view with its identifier on iOS 26+: press the bar item the page set.
            if let item = barItem(identifier, from: root) { return press(item) }
            return false
        }
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside); return true }
        if tapRow(identifier, in: root) { return true }
        // A row that wraps its tap target (a check row's toggle).
        if let control = firstControl(in: target) { control.sendActions(for: .touchUpInside); return true }
        // The floating bar's glass controls are plain views that act on accessibility activation (as VoiceOver's double tap does).
        return target.accessibilityActivate()
    }

    /// The navigation bar item with this identifier on the top page of the navigation controller that holds `root` (or that is `root`'s
    /// controller): a bar item is not reliably a view in the hierarchy, so its identifier is read from the item itself.
    static func barItem(_ identifier: String, from root: UIView) -> UIBarButtonItem? {
        var responder: UIResponder? = root
        while let next = responder, !(next is UIViewController) { responder = next.next }
        guard let controller = responder as? UIViewController else { return nil }
        return barItem(identifier, on: controller)
    }

    static func barItem(_ identifier: String, on controller: UIViewController) -> UIBarButtonItem? {
        let page = (controller as? UINavigationController)?.topViewController ?? controller.navigationController?.topViewController ?? controller
        let item = page.navigationItem
        var items = (item.leftBarButtonItems ?? []) + (item.rightBarButtonItems ?? [])
        items += item.leadingItemGroups.flatMap(\.barButtonItems) + item.trailingItemGroups.flatMap(\.barButtonItems)
        if let back = item.backBarButtonItem { items.append(back) }
        return items.first { $0.accessibilityIdentifier == identifier }
    }

    /// Taps a bar item the way a person does: nothing happens when it is disabled.
    @discardableResult
    static func press(_ item: UIBarButtonItem) -> Bool {
        guard item.isEnabled else { return false }
        if let action = item.primaryAction { action.performWithSender(item, target: nil); return true }
        if let button = item.customView as? UIControl { button.sendActions(for: .touchUpInside); return true }
        if let action = item.action { return UIApplication.shared.sendAction(action, to: item.target, from: item, for: nil) }
        return false
    }

    /// Asserts that a system controller (share sheet, document picker, Quick Look) was presented. The hosted simulator's remote view
    /// services may refuse to show it, so a miss is a recorded non-strict expected failure, not a red test: the app's request (what it
    /// shares, which content types it asks for) is asserted separately.
    static func expectSystemPresentation(_ controller: UIViewController?, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("hosted simulator may not present remote view services", options: options) {
            XCTAssertNotNil(controller, reason, file: file, line: line)
        }
    }

    /// The first live control at or under `root`.
    static func firstControl(in root: UIView) -> UIControl? {
        guard isLive(root) else { return nil }
        if let control = root as? UIControl { return control }
        for sub in root.subviews { if let hit = firstControl(in: sub) { return hit } }
        return nil
    }

    /// The alert or sheet `controller` is showing, if any.
    static func alert(on controller: UIViewController) -> UIAlertController? {
        controller.shownSheet as? UIAlertController
    }

    /// Taps the alert action titled `title` (runs its handler).
    @discardableResult
    static func answer(_ alert: UIAlertController, _ title: String?, dismissing: Bool = true) -> Bool {
        guard let action = alert.actions.first(where: { $0.title == title }) else { return false }
        typealias Handler = @convention(block) (UIAlertAction) -> Void
        // A tap dismisses the alert, then runs the handler (which may present the next one).
        if dismissing, alert.presentingViewController != nil { alert.dismiss(animated: false) }
        guard let block = action.value(forKey: "handler") else { return true }
        unsafeBitCast(block as AnyObject, to: Handler.self)(action)
        return true
    }
}

extension UKSettingsListRow {
    /// The row with this id among `sections`.
    static func find(_ id: String, in sections: [UKSettingsListSection]) -> UKSettingsListRow? {
        sections.flatMap(\.rows).first { $0.id == id }
    }
}

extension UIViewController {
    /// The top-most controller presented over this one's window (a sheet, an alert, a picker), if any. UIKit forwards `present` from a
    /// child page to the window's root, so the page's own `presentedViewController` stays nil.
    var shownSheet: UIViewController? {
        var root: UIViewController = view.window?.rootViewController ?? self
        while let parent = root.parent { root = parent }
        var top = root
        while let next = top.presentedViewController { top = next }
        return top === root ? nil : top
    }
}
