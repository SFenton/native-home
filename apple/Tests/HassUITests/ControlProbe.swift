import SwiftUI

/// Walks a SwiftUI view value with reflection so a test can reach the closures a screen hands to its
/// controls (a tile's action, a date field's `onChange`) and call them, as a tap or a wheel turn would.
///
/// The macOS test host has no accessibility tree to press, so the value tree is the stable seam. Custom
/// views are expanded through their `body`; SwiftUI containers through their stored children.
@MainActor
enum ControlProbe {
    /// Every `T` reachable from `value`, outermost first. A match is not searched further.
    static func all<T>(_ type: T.Type, in value: Any, depth: Int = 0) -> [T] {
        guard depth < 60 else { return [] }
        if let match = value as? T { return [match] }
        var found: [T] = []
        for child in Mirror(reflecting: value).children {
            found += all(type, in: child.value, depth: depth + 1)
        }
        if found.isEmpty, let view = value as? any View, isApp(view) {
            found += all(type, in: body(of: view), depth: depth + 1)
        }
        return found
    }

    /// The first `T` in `value`; fails the caller's expectation when absent.
    static func first<T>(_ type: T.Type, in value: Any) -> T? { all(type, in: value).first }

    private static func body<V: View>(of view: V) -> Any { view.body }

    /// Only the app's own views are expanded; framework views have no useful `body`.
    private static func isApp(_ view: any View) -> Bool {
        let name = String(reflecting: type(of: view))
        return name.hasPrefix("HassUI.") || name.hasPrefix("HassDesign.") || name.hasPrefix("HassUITests.")
    }
}
