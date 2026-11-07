#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A list page with its one primary action pinned at the bottom (`pinnedBar(barMaterial: true)`): the list inside a
/// ``UKPinnedBarViewController`` whose bar holds the button with the page padding.
@MainActor
enum UKSprinklerPinnedPage {
    static func wrap(_ content: UKSprinklerListController, button: UKPrimaryButton) -> UKSheetPinnedBarPage {
        // The list's view loads here so its collection view can be handed to the bar (scroll edge effect, large-title tracking).
        content.loadViewIfNeeded()
        let bar = UIView()
        button.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(button)
        button.ukPin(to: bar, insets: UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l,
                                                   bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l))
        return UKSheetPinnedBarPage(content: content, bar: bar, scrollView: content.collectionView, barMaterial: true)
    }
}

/// Water a zone for a chosen time (`SprinklerWaterPage`; web `waterDetail`): a Run Time stepper with presets, and the pinned
/// Start Watering button in the water colour with dark text (direction G, Primary buttons).
@MainActor
final class UKSprinklerWaterPage: UKSprinklerListController {
    private let controller: SprinklerController
    private let zone: Int
    private let done: () -> Void
    private let bag = UKObservationBag()
    private let button: UKPrimaryButton
    private var minutes = SprinklersConfig.manualRunTime.default
    private var sending = false
    /// The pushed controller that holds this list and its bar (its navigation item is the page's).
    private weak var host: UIViewController?

    /// Builds the page and the controller to push.
    /// - Parameters:
    ///   - done: Pops the page.
    ///   - close: Closes the whole sheet.
    static func make(controller: SprinklerController, zone: Int, context: UKContext, done: @escaping () -> Void,
                     close: @escaping () -> Void) -> UIViewController {
        let page = UKSprinklerWaterPage(controller: controller, zone: zone, done: done)
        let wrapper = UKSprinklerPinnedPage.wrap(page, button: page.button)
        page.host = wrapper
        wrapper.navigationItem.rightBarButtonItem = UKSheetItems.close(action: close)
        page.refresh()
        return wrapper
    }

    private init(controller: SprinklerController, zone: Int, done: @escaping () -> Void) {
        self.controller = controller
        self.zone = zone
        self.done = done
        // The one primary action, in the owner's water colour with dark text (direction G, Primary buttons).
        button = UKPrimaryButton("Start Watering", systemImage: SprinklerStyle.symbol, family: .water, isBusy: false,
                                 busyTitle: "Starting") {}
        super.init(nibName: nil, bundle: nil)
        button.action = { [weak self] in self?.startWatering() }
        button.accessibilityIdentifier = "sprinkler.startWatering"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.tintColor = UKInk.action
        bag.observe { [weak self] in self?.refresh() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        controller.clearError()
    }

    // MARK: State

    private func refresh() {
        let controller = controller
        let snapshot = controller.snapshot
        let zoneState = snapshot.zones.indices.contains(zone) ? snapshot.zones[zone] : nil
        let canRun = controller.canStartWatering && (zoneState?.available ?? false)
        let range = SprinklersConfig.manualRunTime.min...SprinklersConfig.manualRunTime.max
        let minutes = self.minutes
        var sections: [UKSprinklerSection] = []

        if let error = controller.errorMessage {
            sections.append(UKSprinklerSection(id: "error", rows: [
                UKSprinklerRow(id: "error", make: { UKSprinklerAlertContent() },
                               update: { ($0 as? UKSprinklerAlertContent)?.show(message: error) }, edgeToEdge: true),
            ]))
        }

        let footer = controller.isWatering
            ? "Another zone is watering. Stop it to water this one."
            : "Waters \(zoneState?.name ?? controller.config.title) once, for \(range.lowerBound) to \(range.upperBound) minutes. The schedule is not changed."
        sections.append(UKSprinklerSection(
            id: "water", header: "Water Now", footer: footer, footerIdentifier: controller.isWatering ? "sprinkler.waterBlocked" : nil,
            rows: [
                UKSprinklerRow(id: "runTime", make: { UKSprinklerStepperContent(symbol: "timer") }, update: { [weak self] in
                    ($0 as? UKSprinklerStepperContent)?.show(
                        title: "Run Time", value: minutes, range: range, step: 1, valueText: "\(minutes) min", spokenValue: "\(minutes) minutes",
                        isEnabled: canRun, identifier: "sprinkler.runTime") { value in
                        self?.minutes = value
                        self?.refresh()
                    }
                }),
                // Presets for the usual values; the stepper fine-tunes (HIG Steppers: a long range needs a faster way).
                UKSprinklerRow(id: "presets", make: { [weak self] in
                    UKSprinklerPresetsContent { value in
                        self?.minutes = value
                        self?.refresh()
                    }
                }, update: {
                    ($0 as? UKSprinklerPresetsContent)?.show(selection: UKSprinklerWaterPage.presetSelection(minutes), isEnabled: canRun)
                }, insets: NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)),
            ]))
        setSections(sections, animated: isViewLoaded && view.window != nil)

        host?.navigationItem.title = zoneState?.name ?? controller.config.title
        button.isEnabled = canRun
        button.isBusy = sending
    }

    /// The preset that matches `minutes`, or `nil` when the stepper has moved off every preset.
    private static func presetSelection(_ minutes: Int) -> Int? { SprinklerWaterPage.presetSelection(minutes) }

    /// Starts the zone, then closes the page when Home Assistant accepted it.
    private func startWatering() {
        sending = true
        refresh()
        Task { @MainActor [self] in
            let ok = await controller.startWatering(zone: zone, minutes: minutes)
            sending = false
            refresh()
            if ok { done() }
        }
    }
}
#endif
