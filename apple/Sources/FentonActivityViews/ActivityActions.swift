import FentonActivityModel
import SwiftUI

/// Draws a card's buttons.
///
/// A Live Activity button must be a `Button(intent:)`, and the App Intent lives in the app and the widget extension
/// (`apple/Apps/Shared/LiveActivityIntents.swift`), not in this package. The extension injects intent buttons here;
/// the gallery, the hosted tests and previews keep the plain default, which draws the same labels and does nothing.
public struct ActivityActions: Sendable {
    /// A control on a card ("Stop"), drawn with `label`.
    public var control: @MainActor @Sendable (_ tag: String, _ control: ActivityControl, _ label: AnyView) -> AnyView

    /// Creates actions.
    public init(control: @escaping @MainActor @Sendable (_ tag: String, _ control: ActivityControl, _ label: AnyView) -> AnyView) {
        self.control = control
    }

    /// Plain buttons that do nothing.
    public static let inert = ActivityActions(
        control: { _, _, label in AnyView(Button(action: {}) { label }.buttonStyle(.plain)) }
    )
}

private struct ActivityActionsKey: EnvironmentKey {
    static let defaultValue = ActivityActions.inert
}

public extension EnvironmentValues {
    /// How the activity's buttons are drawn; the widget extension sets intent buttons.
    var activityActions: ActivityActions {
        get { self[ActivityActionsKey.self] }
        set { self[ActivityActionsKey.self] = newValue }
    }
}
