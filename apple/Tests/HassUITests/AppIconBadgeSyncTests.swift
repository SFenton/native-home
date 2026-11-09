import Foundation
@testable import HassUI
import Testing

private actor Recorder {
    var values: [Int] = []
    func add(_ v: Int) { values.append(v) }
}

@MainActor
struct AppIconBadgeSyncTests {
    private func make(enabled: Bool? = nil) -> (AppIconBadgeSync, Recorder, UserDefaults) {
        let defaults = UserDefaults(suiteName: "badge-\(UUID().uuidString)")!
        if let enabled { defaults.set(enabled, forKey: AppIconBadgeSync.enabledKey) }
        let rec = Recorder()
        return (AppIconBadgeSync(defaults: defaults, setter: { await rec.add($0) }), rec, defaults)
    }

    @Test func setsCountAndSkipsRepeats() async {
        let (sync, rec, _) = make()
        await sync.update(count: 3)
        await sync.update(count: 3)
        await sync.update(count: 5)
        #expect(await rec.values == [3, 5])
    }

    @Test func negativeClampsToZero() async {
        let (sync, rec, _) = make()
        await sync.update(count: -2)
        #expect(await rec.values == [0])
    }

    @Test func disabledShowsZero() async {
        let (sync, rec, _) = make(enabled: false)
        await sync.update(count: 4)
        #expect(await rec.values == [0])
    }

    @Test func clearAlwaysSets() async {
        let (sync, rec, _) = make()
        await sync.update(count: 0)
        await sync.clear()
        #expect(await rec.values == [0, 0])
    }
}
