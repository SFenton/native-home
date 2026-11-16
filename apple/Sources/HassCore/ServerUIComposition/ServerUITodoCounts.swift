import Foundation

/// Configured quick-link counts, without reading house configuration.
public enum ServerUITodoCounts {
    /// Returns nil for missing, unavailable or unsafe counts instead of inventing an empty list.
    public static func text(configuration: ServerUICompositionDocument.TodoCounts,
                            state: (String) -> String?) -> String? {
        var total: Int64 = 0
        var overdue: Int64 = 0
        for list in configuration.lists {
            guard let count = ServerUIInventorySummary.count(state(list.entityId)),
                  count <= ServerUIInventorySummary.maximumCount - total else { return nil }
            total += count
            if list.overdue { overdue += count }
        }
        guard total > 0 else { return configuration.zeroText }
        var text = "\(total) \(configuration.openSuffix)"
        if overdue > 0 { text += configuration.separator + "\(overdue) \(configuration.overdueSuffix)" }
        return text
    }
}
