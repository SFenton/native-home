#if os(iOS) && DEBUG
import HassCore
import ObjectiveC
import UIKit

nonisolated(unsafe) private var lastCallBagKey: UInt8 = 0

/// Gallery page `vacuums`: the page, every sheet, the area editor and the report on fixture state with a recording service caller and
/// mock maps (`VacuumGallery`).
///
/// `FENTON_GALLERY_VACUUM=<map id>` opens that vacuum's sheet, `FENTON_GALLERY_TAB=<tab>` picks its tab, `FENTON_GALLERY_SCENARIO` sets
/// the robots' state (`docked`, `cleaning`, `error`, `resumable` or `unavailable`) and `FENTON_GALLERY_CLEAN=1` leaves the debug line out.
extension UKGallery {
    static func vacuums(_ page: ComponentGallery.Page) -> UIViewController? {
        guard page == .vacuums else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let scenario = environment["FENTON_GALLERY_SCENARIO"].flatMap(VacuumFixtures.Scenario.init(rawValue:)) ?? .docked
        let store = VacuumFixtures.store(scenario)
        let recorder = GalleryServiceRecorder(store: store)
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let sheetContext = context.with { $0.surface = .sheet }
        let initialVacuum = environment["FENTON_GALLERY_VACUUM"].flatMap { id in Vacuums.all.first { $0.vacuumMapId == id } }
        let initialTab = environment["FENTON_GALLERY_TAB"].flatMap(VacuumTab.init(rawValue:)) ?? .controls
        // At accessibility text sizes the line is left out, as the SwiftUI gallery does: it grew over the sheet's section bar.
        let showsLastCall = !GalleryEnvironment.isClean && !UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
        func lastCall() -> UIView? {
            guard showsLastCall else { return nil }
            let label = UKGalleryLastCallView()
            let bag = UKObservationBag()
            bag.observe { label.record(recorder.lastCall) }
            objc_setAssociatedObject(label, &lastCallBagKey, bag, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return label
        }
        let pageLine = lastCall()
        let page = UKVacuumsViewController(context: context, caller: recorder, initialVacuum: initialVacuum) { vacuum in
            let controller = VacuumController(vacuum: vacuum, store: store, caller: recorder)
            // The area `areaDrawn` draws on the mock map (the SwiftUI gallery's scenario): the Controls tab shows Edit Area and Clear Area.
            if scenario == .areaDrawn, vacuum.areaCleaning != nil { controller.areaSelection = VacuumFixtures.drawnArea }
            let sheet = UKVacuumSheetViewController(
                controller: controller,
                loader: VacuumFixtures.loader(vacuum, scenario: scenario), server: nil, catalog: nil, services: VacuumFixtures.services,
                initialTab: initialTab, context: sheetContext, debugLine: lastCall())
            return sheet
        }
        page.bottomAccessory = pageLine
        return UKGalleryChrome.wrap(page, context: context)
    }
}
#endif
