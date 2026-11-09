#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// The shared pieces of the UIKit media remote (`Features/MediaRemote/*`, pattern: `.agents/patterns/media-remote.md`).

// MARK: - Keyboard state

/// The inline keyboard's state, shared by the pad's keyboard key (which opens it) and the Remote section (which shows the field):
/// the `@State var keyboard = KeyboardPrompt()` of `MediaRemoteSheet`, as an observable box so views bind to it.
@MainActor
@Observable
final class UKRemoteKeyboardState {
    var prompt = KeyboardPrompt()
}

// MARK: - Styling

/// Colors and sizes local to the remote (`RemoteStyle`).
@MainActor
enum UKRemoteStyle {
    /// The power disc while the device is on (``HassTokens/Ink/success``, filled).
    static let powerOn = UKDesignInk.success
    /// The power ring and glyph while the device is off.
    static let powerOff = UKDesignInk.secondary
    /// The glyph on the filled power disc.
    static let powerOnGlyph = UIColor(HassTokens.RGB.Ink.onSuccessFill)

    /// The media family's glyph on a sheet and its off glyph (`ColorFamily.media.glyph` / `.offGlyph`).
    static let mediaGlyph = UIColor(ColorFamily.media.glyphToken)
    static let mediaOffGlyph = UIColor(ColorFamily.media.offGlyphToken)
    /// The lights family's glyph and off glyph (the Hue Sync switches).
    static let lightsGlyph = UIColor(ColorFamily.lights.glyphToken)
    static let lightsOffGlyph = UIColor(ColorFamily.lights.offGlyphToken)

    /// The placeholder glyph of an app tile, deeper in a light sheet so the audit reads it as text (`AppTile.activeFallback`).
    static let activeFallback = UIColor.ukDynamic(light: UIColor(rgb: 0xC0436F), dark: UIColor(rgb: ColorFamily.media.spec.glyph))
    static let idleFallback = UIColor.ukDynamic(light: UIColor(rgb: 0x636366), dark: UIColor(rgb: ColorFamily.media.offGlyphRGB(.dark)))

    /// The SF Symbol for a button's MDI icon.
    static func symbol(_ mdi: String) -> String { SymbolMap.symbol(for: mdi) }
}

// MARK: - Controls with traits

/// A control whose VoiceOver traits are held apart from its enabled state, so `isEnabled = false` adds `.notEnabled` to whatever
/// traits ``semanticTraits`` names (a SwiftUI element's `.disabled` outside its combined accessibility element).
@MainActor
class UKRemoteControl: UIControl {
    /// The traits without `.notEnabled`.
    var semanticTraits: UIAccessibilityTraits = .button

    override var accessibilityTraits: UIAccessibilityTraits {
        get { isEnabled ? semanticTraits : semanticTraits.union(.notEnabled) }
        set { semanticTraits = newValue }
    }

    /// ``SemanticsTraits``: a toggle reads `.toggleButton` and On or Off, a chosen selection reads `.selected`.
    /// - Returns: The value to speak, if the semantics carry one.
    func applySemantics(_ semantics: ControlSemantics, base: UIAccessibilityTraits = .button) -> String? {
        switch semantics {
        case let .toggle(isOn):
            semanticTraits = base.union(.toggleButton)
            return isOn ? "On" : "Off"
        case let .selection(isSelected):
            semanticTraits = isSelected ? base.union(.selected) : base
            return nil
        case .command, .state:
            semanticTraits = base
            return nil
        }
    }
}

// MARK: - Measuring

/// A view laid out with Auto Layout inside, measured for the frame-based columns that hold it (``UKGridMeasuring``).
@MainActor
class UKRemoteMeasuredView: UIView, UKGridMeasuring {
    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard width > 0, width.isFinite else { return 0 }
        let size = systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                           withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return ceil(size.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
}

extension UIView {
    /// Asks every ancestor up to the nearest scroll view (inclusive) to lay out again: a child's height changed, so the column
    /// that holds it and the scroll view's content size follow.
    func ukInvalidateEnclosingLayout() {
        var view: UIView? = self
        while let current = view {
            current.setNeedsLayout()
            if current is UIScrollView { break }
            view = current.superview
        }
    }
}

/// One scrolling column of the remote, at most 640 pt wide and centred, 16 pt in from the edges (`RemoteScroll`).
@MainActor
final class UKRemoteCenteredColumn: UIView, UKGridMeasuring {
    static let maximumWidth: CGFloat = 640
    let content: UIView & UKGridMeasuring

    init(content: UIView & UKGridMeasuring) {
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func contentWidth(_ width: CGFloat) -> CGFloat { max(0, min(Self.maximumWidth, width - 2 * HassTokens.Spacing.l)) }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        content.gridHeight(forWidth: contentWidth(width)) + 2 * HassTokens.Spacing.l
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentWidth(bounds.width)
        content.frame = CGRect(x: ((bounds.width - width) / 2).rounded(), y: HassTokens.Spacing.l, width: width,
                               height: content.gridHeight(forWidth: width))
    }
}

/// A scroll view with one centred column in it (`RemoteScroll`).
@MainActor
enum UKRemoteScroll {
    static func make(_ content: UIView & UKGridMeasuring, identifier: String? = nil) -> UIScrollView {
        let scroll = UKColumnScrollView(content: UKRemoteCenteredColumn(content: content))
        scroll.backgroundColor = .clear
        scroll.keyboardDismissMode = .interactive
        scroll.accessibilityIdentifier = identifier
        return scroll
    }
}

// MARK: - Slider

/// A slider that moves by whole steps for VoiceOver adjust, as SwiftUI's `Slider(step:)` does.
@MainActor
final class UKRemoteSlider: UISlider {
    var step: Float = 1

    /// Snaps the thumb to the step grid.
    func snap() {
        guard step > 0 else { return }
        let snapped = minimumValue + ((value - minimumValue) / step).rounded() * step
        let clamped = min(maximumValue, max(minimumValue, snapped))
        if clamped != value { setValue(clamped, animated: false) }
    }

    override func accessibilityIncrement() { nudge(step) }
    override func accessibilityDecrement() { nudge(-step) }

    private func nudge(_ delta: Float) {
        setValue(min(maximumValue, max(minimumValue, value + delta)), animated: false)
        sendActions(for: .valueChanged)
    }
}
#endif
