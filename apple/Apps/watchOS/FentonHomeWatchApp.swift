import HassCore
import HassDesign
import SwiftUI

/// Watch app stub. Scope: `.agents/design/apple/watchos.md`.
@main
struct FentonHomeWatchApp: App {
    var body: some Scene {
        WindowGroup {
            // Scrolls, so the three lines never clip on a small Watch at accessibility text sizes.
            ScrollView {
                // The symbol is decorative, so VoiceOver speaks the name first.
                VStack(spacing: HassTokens.Spacing.s) {
                    Image(systemName: "house.fill").font(.title)
                        .accessibilityHidden(true)
                    Text(AppBranding.displayName).font(.headline)
                        // VoiceOver would read "S+H" as "S plus H".
                        .accessibilityLabel(AppBranding.spokenName)
                    Text("Coming soon").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
