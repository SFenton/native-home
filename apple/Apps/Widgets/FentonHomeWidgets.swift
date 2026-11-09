import SwiftUI
import WidgetKit

/// The widget extension's entry point. Phase 1 hosts the Home Live Activity only; Home Screen widgets and Controls
/// can join this bundle later without a new extension (`.agents/platforms/apple/live-activities.md` §9).
@main
struct FentonHomeWidgets: WidgetBundle {
    var body: some Widget {
        HomeLiveActivity()
    }
}
