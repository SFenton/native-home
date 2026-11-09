/// How the two header buttons group (pure, so it is unit tested).
enum ShellHeaderGrouping: Equatable {
    /// Two separate glass circles with a 12 pt gap: the iPhone top bar and iPad.
    case twoCircles
    /// One shared glass blob: the iPhone Duo's vertical rail (owner, 2026-10-20).
    case oneGroup

    static func resolve(inVerticalBar: Bool) -> ShellHeaderGrouping { inVerticalBar ? .oneGroup : .twoCircles }
}
