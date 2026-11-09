import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Color {
    /// The SwiftUI colour for a ``HassRGB`` token: dynamic on iOS (the same `UIColor` UIKit draws), the dark value on watchOS.
    init(_ rgb: HassRGB) {
        #if os(iOS)
        if rgb.isFixed { let c = rgb.light; self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha) }
        else { self.init(uiColor: UIColor(rgb)) }
        #elseif os(macOS)
        func plain(_ c: HassRGB.Components) -> NSColor { NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha) }
        if rgb.isFixed { let c = rgb.light; self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha) }
        else {
            self.init(nsColor: NSColor(name: nil) { appearance in
                plain(rgb.components(isDark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua, increasedContrast: false))
            })
        }
        #else
        let c = rgb.dark
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        #endif
    }
}
