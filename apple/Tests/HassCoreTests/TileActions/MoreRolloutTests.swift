import Foundation
@testable import HassCore
import HassTestSupport
import Testing

private func entity(_ id: String, _ state: String) -> EntityState { EntityState(entityId: id, state: state) }

// MARK: - Chores quick links (item 26)

@Suite(.demoHouse)
struct ChoresOpenSubtitleTests {
    @Test func theOpenCountMovesIntoTheSubtitleWithTheOverdueBeside() {
        #expect(ChoresConfig.openSubtitle(.init(overdue: 2, upcoming: 1, noDueDate: 0, total: 3)) == "3 open · 2 overdue")
        #expect(ChoresConfig.openSubtitle(.init(overdue: 0, upcoming: 2, noDueDate: 1, total: 3)) == "3 open")
        #expect(ChoresConfig.openSubtitle(.init(overdue: 1, total: 1)) == "1 open · 1 overdue")
    }

    @Test func nothingOpenSaysSoAtZero() {
        #expect(ChoresConfig.openSubtitle(.init()) == "Nothing open")
    }

    @Test func aLinkReadsItsOwnPagesCounts() {
        let states = ["todo.demo_todo_3": "2", "todo.demo_todo_16": "1",
                      "todo.demo_todo_2": "4"]
        let lookup: (String) -> EntityState? = { id in states[id].map { entity(id, $0) } }
        let alex = ChoresConfig.quickLinks[1]
        let counts = ChoresConfig.counts(for: alex.page, lookup)
        #expect(alex.openSubtitle(lookup) == ChoresConfig.openSubtitle(counts))
        #expect(alex.openSubtitle(lookup).hasPrefix("\(counts.total) open"))
        #expect(ChoresConfig.quickLinks[0].openSubtitle(lookup) == "4 open", "Groceries has nothing overdue")
        #expect(ChoresConfig.quickLinks[2].openSubtitle { _ in nil } == "Nothing open", "no data is nothing open")
    }
}

// MARK: - Vacation Mode and Solo Trip (items 27, 28)

@Suite(.demoHouse)
struct AwayTileActionsTests {
    @Test func theTilesActAndOpenNothing() {
        #expect(AwayTileActions.classification == .action(1))
        #expect(AwayTileActions.actionId == "power")
    }

    @Test func vacationModeReadsOffOnAndPending() throws {
        let off = try #require(AwayTileActions.vacationMode(isOn: false, isPending: false, isDisabled: false).first)
        #expect(off.verb == "Turn On" && off.isOn == false && off.symbol == "power" && off.phase == .ready && off.feedback == .optimistic)
        let on = try #require(AwayTileActions.vacationMode(isOn: true, isPending: false, isDisabled: false).first)
        #expect(on.verb == "Turn Off" && on.isOn == true)
        let pending = try #require(AwayTileActions.vacationMode(isOn: false, isPending: true, isDisabled: false).first)
        #expect(pending.verb == "Cancel" && pending.isOn == true, "the sheet is open: the disc shows on and a tap withdraws it")
    }

    @Test func aDisabledCardDimsItsDiscInPlace() throws {
        let spec = try #require(AwayTileActions.vacationMode(isOn: true, isPending: false, isDisabled: true).first)
        #expect(spec.phase == .unavailable && spec.id == "power", "the set never changes shape")
        #expect(AwayTileActions.soloTrip(isOn: false, isDisabled: true).first?.phase == .unavailable)
    }

    @Test func soloTripTurnsOnAndOff() throws {
        let off = try #require(AwayTileActions.soloTrip(isOn: false, isDisabled: false).first)
        #expect(off.verb == "Turn On" && off.isOn == false && off.phase == .ready)
        let on = try #require(AwayTileActions.soloTrip(isOn: true, isDisabled: false).first)
        #expect(on.verb == "Turn Off" && on.isOn == true)
    }

    @Test func theControllersOwnTheEffectSoTheSpecsCarryNoCall() {
        for spec in AwayTileActions.vacationMode(isOn: true, isPending: false, isDisabled: false) + AwayTileActions.soloTrip(isOn: true, isDisabled: false) {
            #expect(spec.call == nil && spec.optimistic.isEmpty && spec.tracking.isEmpty && spec.confirmation == nil,
                    "the view adds the question; the controller sends the calls")
        }
    }
}

// MARK: - Sprinklers (item 30)

@Suite(.demoHouse)
struct SprinklerShownValveTests {
    let provider = SprinklerActions(SprinklersConfig.controllers[1])

    private func snapshot(open: String?) -> SprinklerSnapshot {
        SprinklerSnapshot(config: SprinklersConfig.controllers[1]) { id in entity(id, id == open ? "open" : "closed") }
    }

    @Test func theShownValveDecidesTheDiscNotTheRawSnapshot() throws {
        let valve = SprinklersConfig.controllers[1].zones[0].valveEntityId
        // Watering in Home Assistant, but a tapped Stop already shows none: the disc dims at once.
        let stopped = try #require(provider.actions(for: snapshot(open: valve), shownValve: nil).first)
        #expect(stopped.phase == .unavailable && stopped.call == SprinklersConfig.stopWatering(valve: valve))
        // A tapped zone shows its valve before the controller reports it: the disc is ready and stops that valve.
        let started = try #require(provider.actions(for: snapshot(open: nil), shownValve: valve).first)
        #expect(started.phase == .ready && started.call == SprinklersConfig.stopWatering(valve: valve))
    }

    @Test func anUnavailableControllerNeverOffersStop() throws {
        let gone = SprinklerSnapshot(config: SprinklersConfig.controllers[1]) { _ in nil }
        let valve = SprinklersConfig.controllers[1].zones[0].valveEntityId
        #expect(provider.actions(for: gone, shownValve: valve).first?.phase == .unavailable)
    }

    @Test func theSnapshotOverloadStillReadsTheLiveValve() throws {
        let valve = SprinklersConfig.controllers[1].zones[1].valveEntityId
        #expect(provider.actions(for: snapshot(open: valve)).first?.phase == .ready)
        #expect(provider.actions(for: snapshot(open: nil)).first?.phase == .unavailable)
    }
}
