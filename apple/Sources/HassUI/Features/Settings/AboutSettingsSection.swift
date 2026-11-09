import HassCore
import HassDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Model

/// What the Settings → About → Version row shows and does: the build identity (``AppBuildInfo``) and a copy action
/// that confirms itself in text, by VoiceOver announcement and by haptic (owner, 2026-10-26, option B of the
/// `settings-version-row` proposal).
@MainActor
@Observable
final class AboutSettingsModel {
    /// The announcement and the footer text after a copy.
    static let copiedText = "Copied."
    /// The footer text before a copy.
    static let tapToCopyText = "Tap to copy."
    /// How long the footer says ``copiedText`` before it goes back to ``tapToCopyText``.
    static let copiedDuration: Duration = .seconds(2)

    /// The identity as shown: `2610.26.01 (57) · 42edc57`.
    let text: String
    /// The identity as VoiceOver reads it: `2610.26.01, build 57, commit 42edc57`.
    let spokenText: String
    /// Whether the last tap copied and the footer is still saying so.
    private(set) var didCopy = false
    /// Bumped once per copy; drives the confirmation haptic.
    private(set) var copies = TapCounter()

    private let pasteboard: (String) -> Void
    private let copiedDuration: Duration
    private let sleeper: (Duration) async -> Void
    private var resetTask: Task<Void, Never>?

    /// - Parameters:
    ///   - info: The bundle's Info.plist dictionary.
    ///   - copiedDuration: How long ``didCopy`` stays true.
    ///   - pasteboard: Writes the text to the system clipboard.
    ///   - sleeper: Waits ``copiedDuration``; tests inject one they release by hand instead of racing a wall clock.
    init(info: [String: Any]? = Bundle.main.infoDictionary,
         copiedDuration: Duration = AboutSettingsModel.copiedDuration,
         pasteboard: @escaping (String) -> Void = AboutSettingsModel.systemPasteboard,
         sleeper: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        text = AppBuildInfo.versionText(info)
        spokenText = AppBuildInfo.spokenVersionText(info)
        self.copiedDuration = copiedDuration
        self.pasteboard = pasteboard
        self.sleeper = sleeper
    }

    /// The footer under the row.
    var footer: String { didCopy ? Self.copiedText : Self.tapToCopyText }

    /// Copies ``text`` (not the spoken form), confirms it and, after ``copiedDuration``, goes back to the prompt.
    func copy() {
        pasteboard(text)
        copies.tap()
        didCopy = true
        Announcer.announce(Self.copiedText)
        resetTask?.cancel()
        resetTask = Task { [weak self, copiedDuration, sleeper] in
            await sleeper(copiedDuration)
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    /// The system clipboard.
    static let systemPasteboard: (String) -> Void = { text in
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
