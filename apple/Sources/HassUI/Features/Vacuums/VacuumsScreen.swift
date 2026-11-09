import HassCore
import HassDesign
import SwiftUI

// MARK: - Format

/// What the Vacuums page says about its robots, kept apart from the generic page so tests can call it.
enum VacuumPageFormat {
    /// The page summary from the robots' states: counts of cleaning, returning and errored robots ("Needs
    /// Attention"), "All Docked" when every robot is docked, or nil when there is nothing to say.
    static func summary(states: [String?]) -> String? {
        let normalized = states.map { $0?.trimmingCharacters(in: .whitespaces).lowercased() ?? "" }
        let parts = [("cleaning", "Cleaning"), ("returning", "Returning"), ("error", "Needs Attention")].compactMap { state, label in
            let count = normalized.count(where: { $0 == state })
            return count > 0 ? "\(count) \(label)" : nil
        }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        if !normalized.isEmpty, normalized.allSatisfy({ $0 == "docked" }) { return "All Docked" }
        return nil
    }

    /// What a robot's tile draws.
    struct TileFace: Equatable {
        var subtitle: String
        var icon: String
        var isActive: Bool
        var isError: Bool
        /// The battery band while cleaning; nil otherwise.
        var progress: Double?
    }

    /// A robot's tile: filled while it works (cleaning, returning, paused), off when docked or idle, and the error
    /// face with the reported issue appended ("Error • 23% • Wheel Stuck").
    static func tile(state: String?, battery: String?, error: String?) -> TileFace {
        let visual = VacuumVisual.state(state)
        let isError = visual.tone == .danger
        var subtitle = VacuumFormat.tileSubtitle(state: state, battery: battery)
        let issue = VacuumStatusResolver.nativeIssue(error)
        if isError, issue.status == .present, let code = issue.code, !code.isEmpty {
            subtitle += " • \(StateText.titleCase(code))"
        }
        let isCleaning = state?.trimmingCharacters(in: .whitespaces).lowercased() == "cleaning"
        let level = battery.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { min(max($0 / 100, 0), 1) }
        return TileFace(
            subtitle: subtitle,
            icon: visual.icon,
            isActive: [.active, .returning, .warning].contains(visual.tone),
            isError: isError,
            progress: isCleaning ? level : nil
        )
    }
}
