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
}

