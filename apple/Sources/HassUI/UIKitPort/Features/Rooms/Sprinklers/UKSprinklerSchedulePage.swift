#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Edit a zone's program (`SprinklerSchedulePage`; web `scheduleDetail`): enabled, run now, days, start times and budget; Apply saves.
///
/// Two commit models, said aloud (HIG Entering data; owner, 2026-10-24): "Right now" (Program Enabled, Start Program Now) applies
/// immediately, since turning a program off is expected to take effect; "Schedule" (days, start times, budget) waits for Apply, and
/// leaving with edits asks first (``UKDiscardGuard``).
@MainActor
final class UKSprinklerSchedulePage: UKSprinklerListController {
    /// One editable start time. Its id is allocated once, so a row keeps its identity (and its picker) when another is removed.
    struct StartTime: Identifiable, Equatable {
        let id = UUID()
        var date: Date

        init(_ date: Date) { self.date = date }
    }

    private let controller: SprinklerController
    private let zone: Int
    private let done: () -> Void
    private let close: () -> Void
    private let format = SprinklerFormat()
    private let bag = UKObservationBag()
    private let button: UKPrimaryButton
    private let initial: SprinklerSchedulePage.Draft
    private var days: Set<Int>
    private var times: [StartTime]
    private var budget: Int
    private var sending = false
    private var chromeSignature = ""
    /// The pushed controller that holds this list and its bar (its navigation item is the page's).
    private weak var host: UIViewController?

    /// Builds the page and the controller to push.
    /// - Parameters:
    ///   - done: Pops the page.
    ///   - close: Closes the whole sheet.
    static func make(controller: SprinklerController, zone: Int, context: UKContext, done: @escaping () -> Void,
                     close: @escaping () -> Void) -> UIViewController {
        let page = UKSprinklerSchedulePage(controller: controller, zone: zone, done: done, close: close)
        let wrapper = UKSprinklerPinnedPage.wrap(page, button: page.button)
        page.host = wrapper
        UKHassModal.hidesSystemBack(wrapper)
        page.refresh()
        return wrapper
    }

    private init(controller: SprinklerController, zone: Int, done: @escaping () -> Void, close: @escaping () -> Void) {
        self.controller = controller
        self.zone = zone
        self.done = done
        self.close = close
        let program = controller.program(zone)
        days = Set(program?.days ?? [])
        let starts = (program?.startTimes.isEmpty ?? true) ? [SprinklersConfig.defaultStartTime] : program?.startTimes ?? []
        let startTimes = starts.compactMap { SprinklerFormat.date(clock: $0) }.map(StartTime.init)
        times = startTimes
        budget = program?.budget ?? 100
        initial = SprinklerSchedulePage.Draft(days: Set(program?.days ?? []), clocks: startTimes.map { SprinklerFormat.clock(from: $0.date) },
                                              budget: program?.budget ?? 100)
        button = UKPrimaryButton("Apply", systemImage: "checkmark", family: .water, isBusy: false, busyTitle: "Applying") {}
        super.init(nibName: nil, bundle: nil)
        button.action = { [weak self] in self?.apply() }
        button.accessibilityIdentifier = "sprinkler.schedule.apply"
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

    // MARK: Draft

    private var draft: SprinklerSchedulePage.Draft {
        SprinklerSchedulePage.Draft(days: days, clocks: times.map { SprinklerFormat.clock(from: $0.date) }, budget: budget)
    }

    /// Days, start times or budget differ from what the page opened with: Back, Close and a swipe down ask first.
    private var hasEdits: Bool { draft != initial }

    // MARK: State

    private func refresh() {
        let controller = controller
        let zone = zone
        let snapshot = controller.snapshot
        let program = controller.program(zone)
        let zoneName = snapshot.zones.indices.contains(zone) ? snapshot.zones[zone].name : controller.config.title
        let available = program?.available ?? false
        let enabled = program?.enabled ?? false
        let canStart = controller.canStartWatering && enabled
        let blocker = SprinklerSchedulePage.applyBlocker(days: days, startTimes: times.count)
        var sections: [UKSprinklerSection] = []

        if let error = controller.errorMessage {
            sections.append(UKSprinklerSection(id: "error", rows: [
                UKSprinklerRow(id: "error", make: { UKSprinklerAlertContent() },
                               update: { ($0 as? UKSprinklerAlertContent)?.show(message: error) }, edgeToEdge: true),
            ]))
        }

        sections.append(UKSprinklerSection(
            id: "now", header: "Right now", footer: "These apply immediately, without Apply.",
            rows: [
                UKSprinklerRow(id: "enabled", make: { UKSprinklerToggleContent(symbol: "calendar.badge.checkmark") }, update: {
                    ($0 as? UKSprinklerToggleContent)?.show(title: "Program Enabled", isOn: enabled, isEnabled: available,
                                                            identifier: "sprinkler.schedule.enabled") { controller.setProgramEnabled(zone: zone, $0) }
                }),
                UKSprinklerRow(id: "start", make: { UKSprinklerButtonContent() }, update: {
                    ($0 as? UKSprinklerButtonContent)?.show(title: "Start Program Now", symbol: "play.fill",
                                                            ink: canStart ? UKInk.action : UIColor.tertiaryLabel, isEnabled: canStart,
                                                            identifier: "sprinkler.schedule.start")
                }, action: canStart ? { controller.startProgram(zone: zone) } : nil, isEnabled: canStart),
            ]))

        // The reason Apply is off, in text VoiceOver reads with the section (HIG, Buttons: say why); otherwise what Apply saves.
        sections.append(UKSprinklerSection(
            id: "schedule", header: "Schedule",
            footer: blocker ?? "Days, start times and the watering budget are saved with Apply.",
            footerIdentifier: blocker == nil ? nil : "sprinkler.schedule.reason",
            rows: [
                UKSprinklerRow(id: "days", make: { UKSprinklerPlainTextContent("Days") }),
                UKSprinklerRow(id: "dayPicker", make: { UKSprinklerDayPickerRow() }, update: { [weak self] in
                    ($0 as? UKSprinklerDayPickerRow)?.show(days: self?.days ?? [], isEnabled: available) { day in self?.toggleDay(day) }
                }, insets: NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)),
            ]))

        // Rows are identified by their own id, not their position, so removing one keeps the others' pickers.
        var timeRows: [UKSprinklerRow] = times.enumerated().map { index, time in
            let id = time.id
            return UKSprinklerRow(id: "time.\(id.uuidString)", make: { [weak self] in
                UKSprinklerTimeContent { self?.removeTime(id) }
            }, update: { [weak self] in
                ($0 as? UKSprinklerTimeContent)?.show(index: index, date: time.date, canRemove: (self?.times.count ?? 0) > 1, isEnabled: available) { date in
                    self?.setTime(id, to: date)
                }
            })
        }
        timeRows.append(UKSprinklerRow(id: "addTime", make: { UKSprinklerButtonContent() }, update: {
            ($0 as? UKSprinklerButtonContent)?.show(title: "Add Another Start Time", symbol: "plus",
                                                    ink: available ? UKInk.action : UIColor.tertiaryLabel, isEnabled: available,
                                                    identifier: "sprinkler.schedule.addTime")
        }, action: available ? { [weak self] in self?.addTime() } : nil, isEnabled: available))
        sections.append(UKSprinklerSection(id: "times", header: "Start Times", rows: timeRows))

        let budget = budget
        sections.append(UKSprinklerSection(
            id: "budget", footer: "Run Time · \(program?.runTimeMinutes ?? 0) min",
            rows: [
                UKSprinklerRow(id: "budget", make: { UKSprinklerStepperContent(symbol: "percent") }, update: { [weak self] in
                    ($0 as? UKSprinklerStepperContent)?.show(
                        title: "Watering Budget", value: budget, range: SprinklersConfig.budgetRange.min...SprinklersConfig.budgetRange.max,
                        step: SprinklersConfig.budgetRange.step, valueText: "\(budget)%", spokenValue: "\(budget) percent", isEnabled: available,
                        identifier: "sprinkler.schedule.budget") { value in
                        self?.budget = value
                        self?.refresh()
                    }
                }),
            ]))

        setSections(sections, animated: isViewLoaded && view.window != nil)

        button.isEnabled = available && blocker == nil
        button.isBusy = sending
        refreshChrome(title: format.programName(zone: zoneName), subtitle: program.map(format.summary))
    }

    /// The title, subtitle, Back and Close, and the swipe-down guard. Back and Close are rebuilt only when what they depend on changes.
    private func refreshChrome(title: String, subtitle: String?) {
        guard let host else { return }
        host.navigationItem.title = title
        UKSheetSubtitle.apply(subtitle, to: host.navigationItem)
        let signature = "\(hasEdits)|\(sending)"
        guard signature != chromeSignature else { return }
        chromeSignature = signature
        let edits = hasEdits
        let pop = done
        let closeSheet = close
        host.navigationItem.leftBarButtonItem = UKSheetItems.back(identifier: "sprinkler.schedule.back", hasChanges: edits, isEnabled: !sending,
                                                                  presenter: host) { pop() }
        host.navigationItem.rightBarButtonItem = UKSheetItems.close(hasChanges: edits, presenter: host) { closeSheet() }
        UKDiscardGuard.apply(to: host, hasChanges: edits, isBusy: sending)
    }

    // MARK: Edits

    private func toggleDay(_ day: Int) {
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
        refresh()
    }

    private func addTime() {
        times.append(StartTime(SprinklerFormat.date(clock: SprinklersConfig.defaultStartTime) ?? .now))
        refresh()
    }

    private func removeTime(_ id: StartTime.ID) {
        times.removeAll { $0.id == id }
        refresh()
    }

    private func setTime(_ id: StartTime.ID, to date: Date) {
        guard let index = times.firstIndex(where: { $0.id == id }), times[index].date != date else { return }
        times[index].date = date
        refresh()
    }

    /// Saves the draft, then closes the page when Home Assistant accepted it.
    private func apply() {
        sending = true
        refresh()
        Task { @MainActor [self] in
            let ok = await controller.saveSchedule(
                zone: zone, days: Array(days), startTimes: times.map { SprinklerFormat.clock(from: $0.date) }, budget: budget)
            sending = false
            refresh()
            if ok { done() }
        }
    }
}
#endif
