import Foundation

/// The app's page indicator for every paging row and carousel (Food suggestions, the Weather sheet and the hourly
/// rows): a resizing capsule and dots in the card's ink, drawn by the app so it follows the card ink and the
/// capsule motion (`.agents/patterns/page-indicator.md`).
///
/// The full-width, 44 pt strip is two tap zones, as the HIG page control: a tap on the leading half goes back one page,
/// a tap on the trailing half goes forward. The strip is one accessibility element with an adjustable action (swipe up
/// and down), a "Page 2 of 5" value and a stable identifier; Switch Control and VoiceOver page with the adjustable
/// action. From ``dotLimit`` + 1 pages up the dots give way to a "4 of 12" label, because dots past about ten cannot
/// be counted (HIG, Page controls).
public enum PageIndicator {
    /// The most pages drawn as dots; one more shows ``countLabel(page:pageCount:)`` instead.
    public static let dotLimit = 10

    // MARK: - Rules

    /// Whether `pageCount` pages are shown as a count rather than dots.
    public static func showsCount(pageCount: Int) -> Bool { pageCount > dotLimit }

    /// `4 of 12`, the label that stands in for the dots.
    public static func countLabel(page: Int, pageCount: Int) -> String {
        "\(clamped(page, pageCount: pageCount) + 1) of \(max(1, pageCount))"
    }

    /// `Page 4 of 12`, the strip's accessibility value.
    public static func valueDescription(page: Int, pageCount: Int) -> String {
        "Page " + countLabel(page: page, pageCount: pageCount)
    }

    /// The page a tap on one side of the strip goes to, or nil at the end it cannot go past.
    public static func target(from page: Int, forward: Bool, pageCount: Int) -> Int? {
        PagedRowMetrics.page(from: clamped(page, pageCount: pageCount), step: forward ? 1 : -1, pageCount: pageCount)
    }

    private static func clamped(_ page: Int, pageCount: Int) -> Int { max(0, min(max(1, pageCount) - 1, page)) }
}
