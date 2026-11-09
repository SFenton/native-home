import HassDesign
import SwiftUI

/// Page math for the hourly carousels: how many hours each page holds and which hours open which page.
///
/// The web measures the DOM (`useHorizontalScrollControls`); native picks the count from the size class and text size
/// instead, so the layout needs no measuring pass and the math can be unit tested. Each page holds exactly
/// ``perPage`` hours (`containerRelativeFrame` splits the viewport evenly), so a swipe snaps to a page and no hour is
/// ever cut in half. Wide layouts (iPad, an unfolded Duo) hold more hours; larger text holds fewer.
struct WeatherCarouselPaging: Equatable {
    var count: Int
    var perPage: Int

    /// Pages for `count` items, `perPage` at a time.
    init(count: Int, perPage: Int) {
        self.count = max(0, count)
        self.perPage = max(1, perPage)
    }

    /// Hours per page for a layout: `compact` or `regular` is the count at the default text size, scaled down at
    /// the larger text sizes (never below two, so a page still reads as a row).
    static func hoursPerPage(compact: Int, regular: Int, sizeClass: UserInterfaceSizeClass?, typeSize: DynamicTypeSize) -> Int {
        let base = sizeClass == .regular ? regular : compact
        let factor: Double = switch typeSize {
        case .xSmall, .small, .medium, .large: 1
        case .xLarge, .xxLarge, .xxxLarge: 0.8
        case .accessibility1, .accessibility2: 0.5
        default: 0.34
        }
        return max(2, Int((Double(base) * factor).rounded()))
    }

    var pageCount: Int { PagedRowMetrics.pageCount(itemCount: count, perPage: perPage) }

    /// Whether more than one page exists, i.e. the carousel scrolls.
    var overflows: Bool { pageCount > 1 }

    /// The first item on a page.
    func firstIndex(ofPage page: Int) -> Int { PagedRowMetrics.firstIndex(ofPage: page, itemCount: count, perPage: perPage) }

    /// The page showing an item.
    func page(containing index: Int?) -> Int { PagedRowMetrics.page(containing: index, perPage: perPage, pageCount: pageCount) }

    /// The page index clamped to the available pages.
    func clamped(_ page: Int) -> Int { max(0, min(pageCount - 1, page)) }

    /// `Page 2 of 4`, for the pagination element's value.
    func pageDescription(_ page: Int) -> String { PagedRowMetrics.pageDescription(page, pageCount: pageCount) }
}

#if canImport(UIKit)
import UIKit

extension WeatherCarouselPaging {
    /// SwiftUI's `DynamicTypeSize` for a content size category.
    static func dynamicTypeSize(_ category: UIContentSizeCategory) -> DynamicTypeSize {
        switch category {
        case .extraSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .extraLarge: .xLarge
        case .extraExtraLarge: .xxLarge
        case .extraExtraExtraLarge: .xxxLarge
        case .accessibilityMedium: .accessibility1
        case .accessibilityLarge: .accessibility2
        case .accessibilityExtraLarge: .accessibility3
        case .accessibilityExtraExtraLarge: .accessibility4
        case .accessibilityExtraExtraExtraLarge: .accessibility5
        default: .large
        }
    }
}
#endif
