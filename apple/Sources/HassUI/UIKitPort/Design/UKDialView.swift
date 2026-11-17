#if os(iOS)
import HassCore
import HassTelemetry
import UIKit

// MARK: - Dial

/// A circular gauge (`sh.dial@1`): ticks along a sweep, letters round the rim, a flag, a pointer at a value and up to three lines of text in the
/// middle. It is the app's one dial: the weather panel's compass and barometer draw through it, and so does an authored `dial`.
///
/// It takes the document's dial (a value: sweep, inks, sizes) and the numbers read from it (``UKDialReading``), and places every part with
/// ``ServerUIDialLayout``, the arithmetic the shared corpus pins. A new reading moves the needle in place: with the needle's `animates` on, and
/// Reduce Motion off (read through ``UKMotion``), it turns the short way round with the standard token; otherwise it jumps. A tick pointer, the
/// letters and the text change at once. A dial scrolling on a page writes nothing per frame: parts move only when a reading, the look or the width
/// changes.
///
/// For VoiceOver the dial is hidden, or one element named by the document whose value is its text or the pointer's percent of the sweep (HIG,
/// Accessibility). The letters and the text in the middle are never read on their own. A dial keeps its places in a right-to-left language unless
/// the document says it mirrors.
@MainActor
final class UKDialView: UIView, UKGridMeasuring, UKStackMeasuring {
    private(set) var dial: ServerUIDial?
    private(set) var reading = UKDialReading()
    /// How many times the needle turned with an animation, for tests of Reduce Motion.
    private(set) var animatedTurns = 0
    /// How many times a reading or a dial changed what was drawn.
    private(set) var drawCount = 0
    /// The needle's turn in degrees as placed, unwrapped so a 350 to 10 change goes 20 degrees on; `nil` while it has none.
    private(set) var turned: Double?

    private let face = UKDialFaceView()
    private let needle = UKDialNeedleView()
    private var letters: [UILabel] = []
    private var lines: [UKServerUIText] = []
    private var placedSize = CGSize(width: -1, height: -1)
    private var placedRightToLeft = false

    /// The dial's own rectangle in this view, and what was last placed in it, for tests.
    private(set) var dialFrame = CGRect.zero
    private(set) var placed: ServerUIDialLayout.Layout?
    var faceView: UIView { face }
    var needleView: UIView { needle }
    var isNeedleShown: Bool { !needle.isHidden }
    /// The letters that are drawn now, in order.
    var shownLetters: [String] { letters.filter { !$0.isHidden }.compactMap(\.text) }
    var letterLabels: [UILabel] { letters }
    /// The lines of text in the middle.
    var centerLines: [UKServerUIText] { lines }
    /// The needle's turn as drawn now, in degrees, read back from its transform.
    var needleDegrees: Double { atan2(needle.transform.b, needle.transform.a) * 180 / .pi }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(face)
        addSubview(needle)
        needle.isHidden = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKDialView, _) in
            guard view.dial?.size?.relativeTo != nil else { return }
            view.invalidateIntrinsicContentSize()
            view.ukRemeasureContainers(includingSelf: true)
            view.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Applying

    /// Draws `dial` with `reading`. Nothing changes when both are what is drawn.
    func apply(_ dial: ServerUIDial, reading: UKDialReading, speech: UKGaugeSpeech) {
        let lookChanged = self.dial != dial
        applySpeech(speech, reading: reading, dial: dial)
        guard lookChanged || reading != self.reading else { return }
        let first = self.dial == nil
        self.dial = dial
        self.reading = reading
        drawCount += 1
        if lookChanged {
            rebuildParts(for: dial)
            invalidateIntrinsicContentSize()
            ukRemeasureContainers(includingSelf: true)
        }
        applyLines(reading)
        place(animated: !first && !lookChanged && window != nil)
    }

    private func applySpeech(_ value: UKGaugeSpeech, reading: UKDialReading, dial: ServerUIDial) {
        switch value {
        case .hidden:
            isAccessibilityElement = false
            accessibilityLabel = nil
            accessibilityValue = nil
        case .value(let label, let text):
            isAccessibilityElement = true
            accessibilityTraits = .none
            accessibilityLabel = label
            let percent = dial.pointer == nil ? nil : ServerUIDialLayout.dialShare(reading.value, scale: dial.scale, sweep: dial.sweep).map { $0 * 100 }
            accessibilityValue = (text?.isEmpty == false ? text : nil) ?? percent.map { "\(Int($0.rounded()))%" }
        }
    }

    /// Builds the letters and the lines of text the dial holds, and gives the needle its inks.
    private func rebuildParts(for dial: ServerUIDial) {
        letters.forEach { $0.removeFromSuperview() }
        letters = (dial.labels?.items ?? []).map { item in
            let label = UILabel()
            label.text = item.text
            label.textColor = dial.labels.map { UKStyledText.color($0.ink) }
            label.textAlignment = .center
            label.isAccessibilityElement = false
            insertSubview(label, belowSubview: needle)
            return label
        }
        lines.forEach { $0.removeFromSuperview() }
        lines = dial.center.map { line in
            let text = UKServerUIText()
            text.isSectionTitle = line.style == .sectionTitle
            text.style = UKServerUIPreflight.textStyle(line.style)
            text.look = line.look
            // A line in the middle of a ring must stay inside it: a single line shrinks to a share of its size before it is cut.
            text.shrinksToFit = line.look.lines == 1
            text.isAccessibilityElement = false
            text.accessibilityElementsHidden = true
            insertSubview(text, belowSubview: needle)
            return text
        }
        if case .needle(_, let head, let tail, let dot, _)? = dial.pointer {
            needle.inks = (UKStyledText.color(head), UKStyledText.color(tail), UKStyledText.color(dot))
        }
    }

    private func applyLines(_ reading: UKDialReading) {
        guard let dial else { return }
        for (index, view) in lines.enumerated() {
            let unavailable = dial.center[index].unavailableText
            switch reading.lines.indices.contains(index) ? reading.lines[index] : .unavailable {
            case .text(let words): view.apply(.ready(words), unavailable: unavailable)
            case .unavailable: view.apply(.unavailable, unavailable: unavailable)
            case .loading: view.apply(.loading, unavailable: unavailable)
            }
        }
    }

    // MARK: Sizing

    /// The width the dial is drawn at when `available` points are on offer: its own size (scaled with the text size, up to its cap) or all of the room,
    /// and never more than `maxWidth`. With `height` the room is also short of height, the dial fits its shape in it: no wider than `aspect` times that
    /// height, as the weather barometer is in a tile taller than its shape.
    func dialWidth(forAvailable available: CGFloat, height: CGFloat = 0) -> CGFloat {
        guard let dial else { return 0 }
        var width = CGFloat(ServerUIDialLayout.fittedWidth(available: Double(available), height: Double(height), aspect: dial.aspect))
        if let size = dial.size {
            let own: CGFloat
            if let relativeTo = size.relativeTo {
                own = UKStyledText.scaledPoints(.init(points: size.points, relativeTo: relativeTo, maxPoints: size.maxPoints), traits: traitCollection)
            } else {
                own = CGFloat(size.points)
            }
            width = min(width, own)
        }
        if let cap = dial.maxWidth { width = min(width, CGFloat(cap)) }
        return width
    }

    override var intrinsicContentSize: CGSize {
        guard let dial else { return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
        if dial.size != nil {
            let width = dialWidth(forAvailable: .greatestFiniteMagnitude)
            return CGSize(width: width, height: width / CGFloat(dial.aspect))
        }
        return CGSize(width: UIView.noIntrinsicMetric, height: bounds.width > 0 ? gridHeight(forWidth: bounds.width) : UIView.noIntrinsicMetric)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let dial else { return .zero }
        let width = dialWidth(forAvailable: size.width)
        return CGSize(width: dial.size == nil ? size.width : width, height: width / CGFloat(dial.aspect))
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        guard let dial else { return 0 }
        return dialWidth(forAvailable: width) / CGFloat(dial.aspect)
    }

    var stackNaturalWidth: CGFloat { dial.map { dialWidth(forAvailable: $0.size == nil ? 96 : .greatestFiniteMagnitude) } ?? 0 }
    var stackFillsWidth: Bool { dial?.size == nil }
    var stackShrinks: Bool { true }

    // MARK: Placing

    /// Puts every part where ``ServerUIDialLayout`` says; the needle turns there when `animated` and Reduce Motion is off.
    private func place(animated: Bool) {
        guard let dial, bounds.width > 0 else { return }
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let width = dialWidth(forAvailable: bounds.width, height: bounds.height)
        let layout = ServerUIDialLayout.layoutDial(dial.layoutInput(width: Double(width), value: reading.value, rtl: rtl))
        let frame = CGRect(x: ((bounds.width - width) / 2).rounded(.down), y: max(0, (bounds.height - CGFloat(layout.height)) / 2),
                           width: width, height: CGFloat(layout.height))
        dialFrame = frame
        placed = layout
        face.frame = frame
        face.content = .init(layout: layout, ticks: dial.ticks, pointer: dial.pointer, flag: dial.flag)
        placeLetters(layout, in: frame)
        placeLines(layout, dial: dial, in: frame)
        placeNeedle(layout, dial: dial, in: frame, animated: animated)
        placedSize = bounds.size
        placedRightToLeft = rtl
    }

    private func placeLetters(_ layout: ServerUIDialLayout.Layout, in frame: CGRect) {
        guard let items = dial?.labels?.items else { return }
        let font = UIFont.systemFont(ofSize: CGFloat(ServerUIDialLayout.labelFontSize(radius: layout.radius)), weight: .semibold).rounded()
        var drawn = layout.labels.makeIterator()
        for (index, item) in items.enumerated() {
            let label = letters[index]
            guard !item.needsValue || layout.share != nil, let place = drawn.next() else {
                label.isHidden = true
                continue
            }
            label.isHidden = false
            label.font = font
            label.sizeToFit()
            label.center = CGPoint(x: frame.minX + CGFloat(place.x), y: frame.minY + CGFloat(place.y))
        }
    }

    /// The lines stand one under the other, centred on the ring's centre (`centerY` down the height) unless the dial states a place for the text.
    private func placeLines(_ layout: ServerUIDialLayout.Layout, dial: ServerUIDial, in frame: CGRect) {
        let heights = lines.map { ceil($0.gridHeight(forWidth: frame.width)) }
        var top = frame.minY + CGFloat(dial.textBlockTop(height: layout.height, blockHeight: Double(heights.reduce(0, +))))
        for (view, height) in zip(lines, heights) {
            view.frame = CGRect(x: frame.minX, y: top, width: frame.width, height: height)
            top += height
        }
    }

    private func placeNeedle(_ layout: ServerUIDialLayout.Layout, dial: ServerUIDial, in frame: CGRect, animated: Bool) {
        guard case .needle(_, _, _, _, let animates)? = dial.pointer, let turn = layout.needle else {
            needle.isHidden = true
            turned = nil
            return
        }
        let appearing = needle.isHidden
        needle.isHidden = false
        // The needle is a square as wide as the dial, turned about its own centre, which is the ring's.
        needle.transform = .identity
        needle.bounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.width)
        needle.center = CGPoint(x: frame.minX + CGFloat(layout.cx), y: frame.minY + CGFloat(layout.cy))
        let target = dial.sweep.isFullTurn ? ServerUIDialLayout.nextTurn(previous: turned, target: turn.rotation) : turn.rotation
        let previous = turned
        turned = target
        let turnTo = { self.needle.transform = CGAffineTransform(rotationAngle: CGFloat(target * .pi / 180)) }
        if animated, animates, !appearing, previous != nil, previous != target, !UKMotion.reduceMotion {
            // Start from where the needle stood, so a turn is a glide and not a jump to the old angle first.
            needle.transform = CGAffineTransform(rotationAngle: CGFloat((previous ?? target) * .pi / 180))
            animatedTurns += 1
            // One `LayoutChange` interval (page `Dial`) from the new reading to the glide settling.
            let interval = Telemetry.begin(Telemetry.Name.layoutChange, page: "Dial", "needle")
            UKMotion.animate(.standard, animations: turnTo, completion: { _ in Telemetry.end(interval) })
        } else {
            turnTo()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The size or the direction changed: place again at once; a reading changed through ``apply(_:reading:speech:)``.
        if bounds.size != placedSize || (effectiveUserInterfaceLayoutDirection == .rightToLeft) != placedRightToLeft { place(animated: false) }
    }
}

private extension UIFont {
    /// The rounded design of this font (`design: .rounded`).
    func rounded() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
