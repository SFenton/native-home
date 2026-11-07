import Foundation

// MARK: - State text

/// Display text for raw Home Assistant states, shared by every feature (web `entityState.ts`).
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/entityState.ts:48`.
public enum StateText {
    /// `titleCaseState`: `armed_away` → `Armed Away`. Only `_` separates words, and only each word's first
    /// letter changes, as on the web. A missing or empty state reads `empty` (`Unknown` by default).
    public static func titleCase(_ state: String?, empty: String = "Unknown") -> String {
        guard let state, !state.isEmpty else { return empty }
        return state.split(separator: "_", omittingEmptySubsequences: false)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
