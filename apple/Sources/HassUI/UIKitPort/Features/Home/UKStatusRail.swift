#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A page's status chips (`StatusRail`, pattern: `.agents/patterns/status-rail.md`): Home shows all of them, Security its two. They
/// scroll in compact width and wrap in regular width, stopping short of a hinge (``UKChipRailView``). Each chip observes only the
/// entities its summary depends on.
@MainActor
enum UKStatusRail {
    /// A rail of chips bound to the store.
    /// - Parameters:
    ///   - chips: The chips, in order.
    ///   - idPrefix: Accessibility identifier prefix: `<prefix>.chip.<sheet>`.
    ///   - context: The page's context (the store the chips read).
    ///   - bag: Where the chips' observations live (the page's).
    ///   - onOpen: Called with the sheet a tapped chip opens.
    static func make(chips: [HomeConfig.StatusChip] = HomeConfig.statusChips, idPrefix: String = "home", context: UKContext,
                     bag: UKObservationBag, onOpen: @escaping (HomeConfig.ChipSheet) -> Void) -> UKChipRailView {
        let rail = UKChipRailView()
        let views = chips.map { chip -> UKStatusChipView in
            let view = UKStatusChipView()
            view.accessibilityIdentifier = "\(idPrefix).chip.\(chip.sheet.rawValue)"
            bag.observe { [weak view] in
                let store = context.store
                let summary = ScreenshotPrivacy.isRedacting && [.security, .occupancy].contains(chip.sheet)
                    ? "Hidden" : HomeConfig.summary(for: chip) { store.entity($0).state }
                let appearance = StatusChipAppearance.home(chip) { store.entity($0).state }
                view?.configure(title: chip.title, summary: summary, symbol: appearance.symbol, family: appearance.family,
                                isActive: appearance.isFilled, tint: appearance.tint) { onOpen(chip.sheet) }
            }
            return view
        }
        rail.setChips(views)
        return rail
    }
}
#endif
