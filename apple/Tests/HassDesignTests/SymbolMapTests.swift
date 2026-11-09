@testable import HassDesign
import Testing
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SymbolMapTests {
    @Test func mapsKnownIconsAndFallsBackToACircle() {
        #expect(SymbolMap.symbol(for: "mdi:robot-vacuum") != "circle")
        #expect(SymbolMap.symbol(for: "mdi:not-a-real-icon") == SymbolMap.fallback)
        #expect(SymbolMap.fallback == "circle")
    }

    /// `Image(systemName:)` with a name the system does not have draws nothing and warns nowhere, so every value in the table
    /// must build an image.
    @Test func everyMappedSymbolExists() {
        let missing = SymbolMap.allSymbols.sorted().filter { name in
            #if canImport(UIKit)
            UIImage(systemName: name) == nil
            #elseif canImport(AppKit)
            NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil
            #else
            false
            #endif
        }
        #expect(missing.isEmpty, "Not SF Symbols: \(missing)")
    }

    /// Off and alert variants keep a glyph that says what they are, not a question mark or a power button.
    @Test func offAndAlertIconsAreNotMisleading() {
        let misleading: Set<String> = ["questionmark.circle", "power"]
        for icon in ["mdi:robot-vacuum-off", "mdi:fan-off", "mdi:thermometer-alert", "mdi:shield-moon", "mdi:food-off-outline"] {
            #expect(!misleading.contains(SymbolMap.symbol(for: icon)), "\(icon)")
            #expect(SymbolMap.symbol(for: icon) != SymbolMap.fallback, "\(icon)")
        }
    }
}
