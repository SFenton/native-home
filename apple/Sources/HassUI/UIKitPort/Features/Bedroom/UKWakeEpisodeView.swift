#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Active wake episode

/// The canonical active-episode card, shared by compiled and authored wake sheets.
@MainActor
final class UKWakeEpisodeView: UIStackView {
    private let controller: WakeLightController
    private let stopLabel: String
    private let pendingLabel: String
    private let heading: UKBedroomSectionHeader
    private let content = UIStackView()
    private let stop: UKFilledButton
    private let bag = UKObservationBag()
    private var occurrenceLabels: [String]?

    init(controller: WakeLightController, stopLabel: String = "Stop Wake-Light Episode",
         episode: ServerUIBedroomControl.Episode? = nil, identifier: String = "wake.stop") {
        self.controller = controller
        self.stopLabel = stopLabel
        pendingLabel = episode?.pendingLabel ?? "Stopping Wake Lights…"
        heading = UKBedroomSectionHeader(title: episode?.heading ?? "Active Wake-Light Controls",
            detail: episode?.detail ?? "Stopping ends this wake for the room and leaves the lights as they are.")
        stop = UKFilledButton(title: stopLabel, fill: UKDeviceStyle.danger) {
            Task { await controller.endEpisode() }
        }
        super.init(frame: .zero)
        axis = .vertical
        content.axis = .vertical
        content.spacing = HassTokens.Spacing.m
        stop.accessibilityIdentifier = identifier
        addArrangedSubview(UKSheetCardView(content: content))
        bag.observe { [weak self] in self?.refresh() }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reads the controller within its owner's observation scope as well as the card's own scope.
    func refresh() {
        let snapshot = controller.snapshot
        let labels = snapshot.activeOccurrences.map { occurrence in
            let alarm = snapshot.alarms.first { $0.id == occurrence.alarmId }
            return "\(alarm?.label ?? "Wake Alarm") · \(WakeLight.displayTime(occurrence.wakeAt))"
        }
        if labels != occurrenceLabels {
            occurrenceLabels = labels
            content.ukSetArranged([heading] + labels.map { UKDeviceText.subheadline($0, ink: UKDesignInk.primary) } + [stop])
        }
        let title = controller.stopping ? pendingLabel : stopLabel
        if stop.accessibilityLabel != title { stop.setTitle(title) }
        stop.isEnabled = controller.live.available && !controller.stopping
        isHidden = labels.isEmpty
        ukRemeasureContainers(includingSelf: true)
    }
}
#endif
