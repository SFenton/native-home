import CoreGraphics

/// The page-growth test the accessibility audit uses as Dynamic Type evidence, free of XCUITest so a unit test can pin it.
enum AuditGrowth {
    /// The smallest growth the page's sampled texts must show between the default size and AX5.
    static let minimumGrowth: CGFloat = 1.35

    /// Whether the page grew: `pairs` holds each sampled text's height at the smaller size and at the larger one. It grew when the
    /// sample is not empty, no text shrank (half a point allowed: the same fixed-size text measures 52.0 and 51.99 in two launches),
    /// and the heights together are at least 1.35 times taller.
    static func pageGrew(_ pairs: [(CGFloat, CGFloat)]) -> Bool {
        !pairs.isEmpty && pairs.allSatisfy { $0.1 >= $0.0 - 0.5 }
            && pairs.map(\.1).reduce(0, +) >= minimumGrowth * pairs.map(\.0).reduce(0, +)
    }

    /// The (smaller size, larger size) height pairs of the first `limit` texts both pages show, in reading order on the larger page.
    static func pairs(smaller: [String: CGRect], larger: [String: CGRect], limit: Int = 12) -> [(CGFloat, CGFloat)] {
        larger.filter { smaller[$0.key] != nil }
            .sorted { ($0.value.minY, $0.value.minX) < ($1.value.minY, $1.value.minX) }
            .prefix(limit)
            .compactMap { entry in smaller[entry.key].map { ($0.height, entry.value.height) } }
    }
}
