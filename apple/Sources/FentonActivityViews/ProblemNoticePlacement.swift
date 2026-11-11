import SwiftUI

/// Where a problem card draws its one-update failure notice (`card.notice`: "Couldn't resume. Try again.").
///
/// Two placements are built so both can be captured and judged (R-43, `build/design/R-43-notice-brief.md` §5). The widget
/// extension never sets it; the default is `replace`. After the pick the losing case, this enum and its environment value go.
public enum ProblemNoticePlacement: String, CaseIterable, Sendable {
    /// Option B: the notice takes the instruction's place for that update, as the job card's notice takes the value's.
    case replace
    /// Option C: the notice has its own line under the instruction, which keeps one line at ordinary text sizes.
    case line
}

private struct ProblemNoticePlacementKey: EnvironmentKey {
    static let defaultValue = ProblemNoticePlacement.replace
}

public extension EnvironmentValues {
    /// Where the problem card draws its failure notice. Temporary default `replace`; the debug gallery sets it.
    var problemNoticePlacement: ProblemNoticePlacement {
        get { self[ProblemNoticePlacementKey.self] }
        set { self[ProblemNoticePlacementKey.self] = newValue }
    }
}
