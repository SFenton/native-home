#if os(iOS)
import HassCore
import UIKit

// MARK: - Linear gauge

/// A rail with a track, a span coloured by a gradient and a marker (`sh.linear-gauge@1`): the weather panel's temperature rail made generic.
///
/// It takes the document's gauge (a value: colours, sizes, stops) and the numbers read from it (``UKGaugeReading``), and places the parts with
/// ``ServerUIGaugeMath``, the arithmetic the shared corpus pins. A new reading moves the span and the marker in place: with the gauge's
/// `animates` on, and Reduce Motion off (read through ``UKMotion``), they glide with the standard token; otherwise they jump. A gauge scrolling
/// on a page writes nothing per frame: frames change only when a reading or the width does.
///
/// For VoiceOver the rail is hidden, or one element named by the document whose value is its text or the marker's percent (HIG, Accessibility).
/// The marker is kept wholly inside the track, and every position mirrors in a right-to-left language.
@MainActor
final class UKLinearGaugeView: UIView, UKGridMeasuring, UKStackMeasuring {
    private(set) var gauge: ServerUILinearGauge?
    private(set) var reading = UKGaugeReading()
    /// How many times a frame was placed with an animation, for tests of Reduce Motion.
    private(set) var animatedMoves = 0
    /// How many times a reading or a gauge changed what was drawn.
    private(set) var drawCount = 0

    private let track = UIView()
    private let spanView = UIView()
    private let gradient = CAGradientLayer()
    private let marker = UIView()
    private var placedWidth: CGFloat = -1
    private var placedRightToLeft = false

    /// The frame of the span and of the marker (the marker's is its place in the track), for tests.
    var spanFrame: CGRect { spanView.frame }
    var markerFrame: CGRect { marker.frame }
    var isSpanShown: Bool { !spanView.isHidden }
    var isMarkerShown: Bool { !marker.isHidden }
    /// The gradient's stops as drawn.
    var gradientLocations: [CGFloat] { (gradient.locations ?? []).map { CGFloat(truncating: $0) } }
    var gradientColors: [CGColor] { (gradient.colors as? [CGColor]) ?? [] }
    /// The identity of the drawn parts, for tests that an update keeps them.
    var partIdentity: [ObjectIdentifier] { [ObjectIdentifier(track), ObjectIdentifier(spanView), ObjectIdentifier(marker), ObjectIdentifier(gradient)] }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        track.layer.cornerCurve = .continuous
        spanView.layer.cornerCurve = .continuous
        spanView.clipsToBounds = true
        spanView.layer.addSublayer(gradient)
        marker.layer.cornerCurve = .circular
        for part in [track, spanView, marker] { addSubview(part) }
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UKLinearGaugeView, _) in view.paintColors() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Applying

    /// Draws `gauge` with `reading`. Nothing changes when both are what is drawn.
    func apply(_ gauge: ServerUILinearGauge, reading: UKGaugeReading, speech: UKGaugeSpeech) {
        applySpeech(speech, reading: reading, gauge: gauge)
        let lookChanged = self.gauge != gauge
        guard lookChanged || reading != self.reading else { return }
        let first = self.gauge == nil
        self.gauge = gauge
        self.reading = reading
        drawCount += 1
        if lookChanged {
            paintColors()
            invalidateIntrinsicContentSize()
            ukRemeasureContainers(includingSelf: true)
        }
        place(animated: !first && !lookChanged && gauge.animates && window != nil)
    }

    private func applySpeech(_ value: UKGaugeSpeech, reading: UKGaugeReading, gauge: ServerUILinearGauge) {
        switch value {
        case .hidden:
            isAccessibilityElement = false
            accessibilityLabel = nil
            accessibilityValue = nil
        case .value(let label, let text):
            isAccessibilityElement = true
            accessibilityTraits = .none
            accessibilityLabel = label
            let percent = reading.value.flatMap { gauge.marker == nil ? nil : ServerUIGaugeMath.percent($0, scale: gauge.scale) }
            accessibilityValue = (text?.isEmpty == false ? text : nil) ?? percent.map { "\(Int($0.rounded()))%" }
        }
    }

    private func paintColors() {
        guard let gauge else { return }
        let traits = traitCollection
        track.backgroundColor = UKStyledText.color(gauge.track)
        gradient.colors = gauge.stops.map { UKStyledText.color($0.ink).resolvedColor(with: traits).cgColor }
        gradient.locations = gauge.stops.map { NSNumber(value: $0.at) }
        if let look = gauge.marker {
            marker.backgroundColor = UKStyledText.color(look.ink)
            marker.layer.borderWidth = look.border.map { CGFloat($0.width) } ?? 0
            marker.layer.borderColor = look.border.map { UKStyledText.color($0.ink).resolvedColor(with: traits).cgColor }
        }
    }

    // MARK: Placing

    private func layout(for gauge: ServerUILinearGauge) -> ServerUIGaugeMath.Layout {
        ServerUIGaugeMath.layout(.init(
            scale: gauge.scale, value: gauge.marker == nil ? nil : reading.value, spanStart: reading.spanStart, spanSize: reading.spanSize,
            fill: gauge.fill, width: Double(bounds.width), markerSize: gauge.marker?.size ?? 0,
            rtl: effectiveUserInterfaceLayoutDirection == .rightToLeft))
    }

    /// Puts the track, the span and the marker where ``ServerUIGaugeMath`` says; gliding there when `animated` and Reduce Motion is off.
    private func place(animated: Bool) {
        guard let gauge, bounds.width > 0 else { return }
        let height = CGFloat(gauge.height)
        let frames = layout(for: gauge)
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let spanFrame = frames.span.map { CGRect(x: $0.left, y: 0, width: $0.width, height: height) }
        let markerSize = CGFloat(gauge.marker?.size ?? 0)
        let markerFrame = frames.marker.map { CGRect(x: $0.left, y: (height - markerSize) / 2, width: markerSize, height: markerSize) }
        track.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        track.layer.cornerRadius = height / 2
        spanView.layer.cornerRadius = height / 2
        marker.layer.cornerRadius = markerSize / 2
        gradient.startPoint = CGPoint(x: rtl ? 1 : 0, y: 0.5)
        gradient.endPoint = CGPoint(x: rtl ? 0 : 1, y: 0.5)
        // A part that was hidden appears where it belongs, never gliding in from the last place it was (its frame is not reset when it hides).
        let appearing = spanFrame != nil && (spanView.isHidden || spanView.frame == .zero) || markerFrame != nil && (marker.isHidden || marker.frame == .zero)
        spanView.isHidden = spanFrame == nil
        marker.isHidden = markerFrame == nil
        let move = { [self] in
            if let spanFrame {
                spanView.frame = spanFrame
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                gradient.frame = spanView.bounds
                CATransaction.commit()
            }
            if let markerFrame { marker.frame = markerFrame }
        }
        if animated, !appearing, !UKMotion.reduceMotion {
            animatedMoves += 1
            UKMotion.animate(.standard, animations: move)
        } else {
            move()
        }
        placedWidth = bounds.width
        placedRightToLeft = rtl
    }

    // MARK: Measuring

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: CGFloat(gauge?.height ?? ServerUILinearGauge.defaultHeight)) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: intrinsicContentSize.height) }
    func gridHeight(forWidth width: CGFloat) -> CGFloat { intrinsicContentSize.height }
    var stackNaturalWidth: CGFloat { 48 }
    var stackFillsWidth: Bool { true }
    var stackShrinks: Bool { true }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The width (or the direction) changed: place again at once; a reading changed through ``apply(_:reading:speech:)``.
        if bounds.width != placedWidth || (effectiveUserInterfaceLayoutDirection == .rightToLeft) != placedRightToLeft { place(animated: false) }
    }
}
#endif
