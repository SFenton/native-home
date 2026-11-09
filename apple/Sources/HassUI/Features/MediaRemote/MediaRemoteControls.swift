import HassCore
import HassDesign
import SwiftUI

// MARK: - Shared pieces

/// Colors and sizes local to the remote.
enum RemoteStyle {
    /// Media device tint (web `media` tile tone), kept for room tiles; remote rows use ``ColorFamily/media``.
    static let media = Color(red: 0.36, green: 0.42, blue: 0.95)
    /// The power disc while the device is on: ``HassTokens/Ink/success``, filled. On means active, not a warning, so the
    /// web's red is dropped and there is no red and green pair for color-blind people to confuse (owner, 2026-10-24).
    static let powerOn = HassTokens.Ink.success
    /// The power ring and glyph while the device is off: neutral, outlined.
    static let powerOff = HassTokens.Ink.secondary
    /// The glyph on the filled power disc.
    static let powerOnGlyph = HassTokens.Ink.onSuccessFill

    /// The SF Symbol for a button's MDI icon.
    static func symbol(_ mdi: String) -> String { SymbolMap.symbol(for: mdi) }
}

/// A button's icon with its rotation and color rule applied. A button with a color rule (power) says its state by shape as
/// well as color: a filled success disc with a dark glyph while on, an outlined neutral ring and glyph while off (HIG:
/// Color, "don't rely on color alone"; WCAG 1.4.1).
struct RemoteButtonIcon {
    var button: MediaRemoteButton
    var tone: IconTone?
    var font: Font

    /// Diameter of the select key's centre dot.
    static let selectDot: CGFloat = 12




    private var color: Color {
        switch tone {
        case .active: RemoteStyle.powerOnGlyph
        case .inactive: RemoteStyle.powerOff
        case nil: HassTokens.Ink.primary
        }
    }
}

// MARK: - D-pad

/// The 3×3 remote grid (`.agents/design/direction-g.md`, Controls: Remote): Back, Up and Power; Left, Select and
/// Right; Home, Down and the keyboard, as large grey circles with a light haptic on each press (web `RemoteGrid`
/// plus its navigation row; HIG: Playing haptics). Select is blank on a SHIELD and a dot on Apple TV. A remote
/// without a keyboard (Apple TV) leaves that corner empty.
struct DirectionalPad {
    var controller: MediaRemoteController
    /// The width the pad must fit (the leading column in two columns); `nil` for no limit.
    var maxWidth: CGFloat?
    /// Whether the inline keyboard is open (the keyboard key reads Expanded or Collapsed).
    var keyboardOpen = false
    /// The keyboard key asks for the text prompt on this entity.
    var onTextPrompt: (String) -> Void = { _ in }


    static func diameter(scaled: CGFloat, maxWidth: CGFloat?) -> CGFloat {
        let size = min(max(scaled, 64), 104)
        guard let maxWidth else { return size }
        return max(HassTokens.minTarget, min(size, (maxWidth - 2 * HassTokens.Spacing.m) / 3))
    }



}

// MARK: - Slider and keyboard state

/// A slider that commits on release, or at once for steps that arrive without a drag (VoiceOver adjust,
/// keyboard), so a drag doesn't send a service call per point (the web sends one per `input` event).
struct SliderDraft: Equatable {
    /// The value under the finger while dragging.
    var draft: Double?

    /// The value to draw.
    func shown(live: Double) -> Double { draft ?? live }

    /// A new value from the slider.
    mutating func set(_ value: Double, commit: (Double) -> Void) {
        if draft == nil { commit(value) } else { draft = value }
    }

    /// Drag start keeps the live value as the draft; drag end commits the draft.
    mutating func editingChanged(_ editing: Bool, live: Double, commit: (Double) -> Void) {
        if editing {
            draft = live
        } else if let value = draft {
            draft = nil
            commit(value)
        }
    }
}

/// The inline keyboard under the pad (web `TextPromptForm`).
struct KeyboardPrompt: Equatable {
    /// The entity typed into while open.
    var target: String?
    var text = ""

    var isOpen: Bool { target != nil }
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The keyboard button: opens for `target`, or closes when already open for it.
    mutating func toggle(_ target: String) {
        if self.target == target { close() } else { self.target = target }
    }

    /// Cancel: closes and clears the text.
    mutating func close() { self = KeyboardPrompt() }

    /// Send: types the text and closes; blank text sends nothing and stays open.
    @MainActor mutating func submit(with controller: MediaRemoteController) {
        guard let target, !isBlank else { return }
        controller.sendText(text, to: target)
        close()
    }
}
