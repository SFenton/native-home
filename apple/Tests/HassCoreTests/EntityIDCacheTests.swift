@testable import HassCore
import Testing

// MARK: - The entity id grammar is matched once per string

struct EntityIDCacheTests {
    /// Ids and near-misses: every one must get the verdict the uncached pattern gives.
    private static let corpus: [String] = [
        "light.demo.demo_lamp", "switch.demo_a", "sensor.demo_power_2", "input_boolean.demo_x", "a.b", "a1.b1", "x_y.z_9",
        "", ".", "light.", ".lamp", "light", "Light.demo_lamp", "light.Demo_lamp", "light.demo_la-mp", "light.demo_la mp", "light .lamp",
        "1light.demo_lamp", "_light.demo_lamp", "light.demo_lamp\n", "light.demo_lamp ", " light.demo_lamp", "light.demo.demo_lamp",
        "light..demo_lamp", "light.demo_lamp.", "lïght.demo_lamp", "light.demo_lampé", "light.\u{0663}", "person.demo_a\u{0}",
        "light." + String(repeating: "a", count: 154), "light." + String(repeating: "a", count: 155),
        "light." + String(repeating: "a", count: 160),
    ]

    @Test func everyStringGetsTheVerdictOfThePattern() {
        var cache = EntityIDCache()
        for id in Self.corpus {
            let expected = EntityIDCache.matchesPattern(id)
            let first = cache.isValid(id), again = cache.isValid(id)
            #expect(first == expected, "first read of \(id.debugDescription)")
            #expect(again == expected, "cached read of \(id.debugDescription)")
        }
    }

    @Test func thePatternAcceptsAndRejectsWhatItDid() {
        #expect(EntityIDCache.matchesPattern("light.demo.demo_lamp"))
        #expect(EntityIDCache.matchesPattern("light." + String(repeating: "a", count: 154)), "160 units is the limit")
        #expect(!EntityIDCache.matchesPattern("light." + String(repeating: "a", count: 155)))
        #expect(!EntityIDCache.matchesPattern("Light.demo_lamp"))
        #expect(!EntityIDCache.matchesPattern("light.demo_lamp\n"), "a trailing newline is not part of an id")
        #expect(!EntityIDCache.matchesPattern("light"))
    }

    @Test func aRepeatedIDIsMatchedOnce() {
        var cache = EntityIDCache()
        var verdicts: [Bool] = []
        for _ in 0..<100 { verdicts.append(cache.isValid("light.demo.demo_lamp")) }
        for _ in 0..<100 { verdicts.append(cache.isValid("light.Demo_lamp")) }
        #expect(verdicts == Array(repeating: true, count: 100) + Array(repeating: false, count: 100))
        #expect(cache.matches == 2, "a rejected id is remembered too")
    }

    @Test func theCacheStaysBounded() {
        var cache = EntityIDCache()
        var allValid = true
        for index in 0..<(EntityIDCache.capacity * 3) { allValid = cache.isValid("sensor.demo_\(index)") && allValid }
        #expect(allValid)
        #expect(cache.matches == EntityIDCache.capacity * 3)
        let forgotten = cache.isValid("sensor.demo_0")
        #expect(forgotten, "an id forgotten when the cache started over is matched again, with the same answer")
    }
}
