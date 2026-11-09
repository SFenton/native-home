import SwiftUI

// MARK: - Height policy

/// How tall a ``SwiftUI/View/hassSheet(_:height:appearance:fitKey:predictedContentHeight:)`` modal opens on iPhone.
///
/// Owner decision, 2026-10-16 (replacing 2026-10-13's "all modals full height"): a sheet opens only as tall as its
/// content needs, so a short prompt does not leave a screen of empty ground. HIG Sheets: "Use the smallest detent
/// that shows the content; let people expand when the content is long" and "Prefer medium or custom detents for
/// short content".
public enum HassSheetHeight: Sendable, Equatable {
    /// As tall as the content (``SheetFit``), capped at the large detent; longer content scrolls. The default.
    case fitted
    /// As ``fitted``, but the page on top owns the height: a page pushed inside the sheet fits it to its own content, and
    /// Back returns it to the height of the page below. For a sheet whose pages are short and differ in length, where
    /// one fixed height would leave empty ground under one page or a scroller in the next (Quick Links: its tiles, Rooms
    /// and Security System; owner, 2026-10-26: "it should only show what it has to on any device"). An iPad page or form
    /// sheet does not resize after it opens, so there the root page's height stays and a longer page scrolls.
    case fittedToTopPage
    /// Always the large detent. Remotes, any modal with a section tab bar, sheets that navigate between pages and
    /// sheets over live video: their height must not change with a tab or a pushed page.
    case full
}

/// The pure sizing decisions behind ``HassSheetHeight/fitted``: measured content to a presentation detent.
public enum SheetFit {
    /// A detent the system understands, kept as plain data so the choice can be tested without a presentation.
    public enum Detent: Equatable, Sendable {
        /// A custom height in points (`PresentationDetent.height`).
        case height(CGFloat)
        /// The large detent: the content is as tall as the sheet can be, or taller.
        case large
        /// Shown until the first measurement arrives, so the sheet never opens full and then shrinks.
        case provisional
    }

    /// The shortest fitted sheet: grabber, header and one row. A shorter reading is a measurement taken before the
    /// content laid out.
    public static let minimumHeight: CGFloat = 220

    /// A content height within this many points of the available height opens at `.large` instead, so a custom
    /// detent a hair under large does not leave a sliver of the page above it.
    public static let largeSnap: CGFloat = 24

    /// How long a reading must stand before it moves a sheet that opened at a predicted height: longer than the page's
    /// transient layouts while the sheet presents (they change every frame), shorter than a person notices.
    public static let settleDelay = Duration.milliseconds(300)

    /// A reading smaller than this change is noise: the sheet does not move for it.
    public static let hysteresis: CGFloat = 2

    /// The detent for measured content.
    ///
    /// - Parameters:
    ///   - contentHeight: The sheet's wanted height (content plus the header and bottom insets), or nil before the
    ///     first measurement.
    ///   - availableHeight: The height of the large detent.
    /// - Returns: ``Detent/provisional`` before a measurement; ``Detent/large`` when the content reaches the large
    ///   detent; otherwise a ``Detent/height(_:)`` of at least ``minimumHeight``.
    public static func detent(contentHeight: CGFloat?, availableHeight: CGFloat) -> Detent {
        guard let contentHeight, contentHeight.isFinite else { return .provisional }
        guard availableHeight.isFinite, availableHeight > 0 else { return .large }
        if contentHeight >= availableHeight - largeSnap { return .large }
        return .height(max(contentHeight.rounded(.up), minimumHeight))
    }

    /// Whether a fitted sheet also offers the large detent so people can expand it (HIG Sheets: "let people expand when the
    /// content is long"): when it is taller than about half the window, or has not been measured yet. A short sheet stays one
    /// detent: there is little to gain from expanding it.
    public static func offersLarge(_ detent: Detent, availableHeight: CGFloat) -> Bool {
        switch detent {
        case .large: false
        case .provisional: true
        case let .height(value): availableHeight.isFinite && value > availableHeight / 2
        }
    }

    /// Whether a new reading moves the sheet.
    public static func shouldUpdate(from old: CGFloat?, to new: CGFloat) -> Bool {
        guard new.isFinite, new > 0 else { return false }
        guard let old else { return true }
        return abs(new - old) >= hysteresis
    }

    /// Whether a scroll view's reading is the page's own vertical scroller rather than a chip rail or carousel
    /// inside it: a horizontal scroller's content is wider than its container, and a tiny container is a rail.
    public static func isPageScroller(contentWidth: CGFloat, containerWidth: CGFloat, containerHeight: CGFloat) -> Bool {
        contentWidth <= containerWidth + 1 && containerHeight >= 120
    }

    /// The part of a bottom inset a custom detent has to ask for: what lies beyond the system's own bottom safe area.
    ///
    /// UIKit measures a custom detent up from the bottom safe area and adds that area itself, so a sheet given detent `D` is
    /// `D` plus the safe area tall (iPhone and the folded iPhone Duo: 34 pt; iPad: 20 pt). A detent that also counted the safe
    /// area (it did until 2026-10-28) left that much empty ground under the content. The page's scroller still reports the
    /// safe area as its bottom inset, and it is there: inside the sheet, under the detent. A pinned bar's height, or any other
    /// inset beyond the safe area, is not, so it stays in the detent.
    public static func bottomBeyondSafeArea(inset: CGFloat, safeArea: CGFloat) -> CGFloat {
        max(0, max(0, inset) - max(0, safeArea))
    }

    /// The wanted detent from a scroll view's geometry: its content plus the header above it and whatever lies below it beyond
    /// the system's bottom safe area (``bottomBeyondSafeArea(inset:safeArea:)``; a pinned tab bar, not the home indicator).
    ///
    /// - Parameter systemBottomInset: The bottom safe area the system adds to a custom detent by itself; 0 counts the whole
    ///   bottom inset (a measure that is not a detent).
    public static func wantedHeight(contentHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat, systemBottomInset: CGFloat = 0) -> CGFloat {
        max(0, contentHeight) + max(0, topInset) + bottomBeyondSafeArea(inset: bottomInset, safeArea: systemBottomInset)
    }

    /// The wanted sheet height from the sheet's own height and the scroller's viewport: whatever the sheet holds
    /// besides the scroller (header, grabber, a pinned tab bar, safe areas) plus the scroller's content. Unlike the
    /// insets, this counts a scroller laid out *below* the header (iPad's form sheet) as well as one under it.
    public static func wantedHeight(sheetHeight: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        max(0, sheetHeight - viewportHeight) + max(0, contentHeight)
    }

    /// One reading of the page's vertical scroller.
    public struct Reading: Equatable, Sendable {
        /// The scroller's content height.
        public var content: CGFloat
        /// The scroller's viewport height.
        public var viewport: CGFloat
        /// The insets the scroller reports above and below its content.
        public var topInset: CGFloat
        public var bottomInset: CGFloat
        /// The scroller's width: the width the page lays out at.
        public var width: CGFloat

        public init(content: CGFloat, viewport: CGFloat = 0, topInset: CGFloat = 0, bottomInset: CGFloat = 0, width: CGFloat = 0) {
            self.width = width
            self.content = content
            self.viewport = viewport
            self.topInset = topInset
            self.bottomInset = bottomInset
        }
    }
}

// MARK: - Measurement channel

/// Receives the measured height of a fitted sheet's content, from the page ``SwiftUI/View/modalChrome()`` is
/// applied to. Created by `hassSheet` and handed down through the environment.
@MainActor
@Observable
public final class SheetFitModel {
    /// The wanted height of the sheet, nil until the page has reported.
    public private(set) var contentHeight: CGFloat?
    /// The height the sheet opened at (a prediction or a remembered height), nil when it had none.
    public let initialHeight: CGFloat?

    /// The page whose readings set the height. Whoever reported first, the sheet's root page, unless
    /// ``followsTopPage``: then the page that appeared last. In the default mode pages pushed inside the sheet report
    /// too and are ignored, so the sheet keeps its height across a push and a pop instead of resizing under the reader.
    private var owner: UUID?
    /// The first page to report or appear: the only one whose heights are remembered for the next presentation.
    private var root: UUID?
    /// The page on top owns the height (``HassSheetHeight/fittedToTopPage``).
    public let followsTopPage: Bool
    /// The latest reading of each page, so a page that becomes the owner again (after a pop) resizes at once.
    private var readings: [UUID: SheetFit.Reading] = [:]
    private var reading: SheetFit.Reading? { owner.flatMap { readings[$0] } }
    /// The top and bottom chrome of the root page, once it has reported and has the standard inline header: what
    /// ``SheetChromeMemory`` learns, so a sheet that cannot be measured before it opens can still be predicted. The bottom is
    /// only what lies beyond the system's bottom safe area (``SheetFit/bottomBeyondSafeArea(inset:safeArea:)``): 0 on a
    /// standard sheet.
    public private(set) var rootChrome: SheetChrome?
    /// The root page's scroller width, which with the window's width gives ``SheetChrome/widthInset``.
    public private(set) var rootWidth: CGFloat?
    /// Whether the system gave the sheet less height than it asked for when ``rootChrome`` was read (``isCutShort``): its
    /// header then reads taller than any other sheet's (82 pt on the folded iPhone Duo against 74), so only the bottom inset
    /// and the width are the chrome's, not the top.
    public private(set) var rootIsCutShort = false
    /// Whether each page has the standard inline header (no top bar of its own); only such a root page teaches the chrome.
    private var standardHeaders: [UUID: Bool] = [:]
    private var sheetHeight: CGFloat?
    /// The tallest a partial-height sheet's page area can be on this device, as learned (``SheetChromeMemory/maxSheetHeight``):
    /// the page area of a sheet at the large detent, in the measure ``setSheetHeight(_:)`` takes (above the bottom inset).
    /// Nil until a sheet at the large detent has reported it.
    public var maxSheetHeight: CGFloat?
    /// The sheet is at the large detent (set by the presenting sheet), where its header and height are the system's maximum.
    public var detentIsLarge = false
    /// The page area of the sheet at the large detent, once it is at it: what ``maxSheetHeight`` is learned from.
    public private(set) var largeSheetHeight: CGFloat?
    private var safeTop: CGFloat = 0
    private var safeBottom: CGFloat = 0
    /// The bottom safe area the system adds to a custom detent by itself (the window's: 34 pt on an iPhone and the folded iPhone
    /// Duo, 20 pt on an iPad), which the detent therefore must not ask for again (``SheetFit/bottomBeyondSafeArea(inset:safeArea:)``;
    /// owner, 2026-10-28, `proposals/sheet-bottom-gap`, option B). Set by the presenting sheet; 0 (the default) counts the whole bottom
    /// inset, as a measure that is not a detent does.
    public var systemBottomInset: CGFloat = 0 { didSet { if systemBottomInset != oldValue { recompute() } } }
    private let onChange: (CGFloat) -> Void
    private let settleDelay: Duration?
    /// The reading waiting to stand still (``init(initial:followsTopPage:settleDelay:onChange:)``).
    private var pendingUpdate: Task<Void, Never>?

    /// Creates the model.
    /// - Parameters:
    ///   - initial: A height remembered from the last time this sheet opened, so it opens at the right height.
    ///   - followsTopPage: The page on top owns the height (``HassSheetHeight/fittedToTopPage``).
    ///   - settleDelay: How long a reading must stand before it moves a sheet that opened at a predicted height. While the
    ///     sheet is presenting, the page lays out at transient sizes and reads heights that are not its final one (the camera
    ///     viewer read 569, 517, 551, 547, 530 ... 518 pt on the way to its predicted 517), so a sheet that already has its
    ///     final height waits for a reading to stand still. Nil (the default) moves at once, as an unpredicted sheet must.
    ///   - onChange: Called with each accepted height of the root page.
    public init(initial: CGFloat? = nil, followsTopPage: Bool = false, settleDelay: Duration? = nil,
                onChange: @escaping (CGFloat) -> Void = { _ in }) {
        contentHeight = initial
        initialHeight = initial
        self.settleDelay = settleDelay
        self.followsTopPage = followsTopPage
        self.onChange = onChange
    }

    /// A page came on screen. With ``followsTopPage`` it takes the height, at once when it has reported before (Back to
    /// a page measured earlier); otherwise only the first page counts.
    public func pageAppeared(_ page: UUID) {
        if root == nil { root = page }
        guard followsTopPage else {
            if owner == nil { owner = page }
            return
        }
        owner = page
        recompute()
    }

    /// Records whether a page has the standard inline header. A page that adds a top bar (``modalTabBar`` at the top) has
    /// a taller header than every other sheet, so its insets must not teach the shared chrome.
    public func setStandardHeader(_ standard: Bool, for page: UUID) {
        standardHeaders[page] = standard
        recompute()
    }

    /// Records a reading from a page.
    /// - Parameters:
    ///   - height: The content height, with no insets.
    ///   - page: The reporting page's identity.
    public func report(_ height: CGFloat, from page: UUID) {
        report(SheetFit.Reading(content: height), from: page)
    }

    /// Records a reading from a page.
    public func report(_ reading: SheetFit.Reading, from page: UUID) {
        if root == nil { root = page }
        if owner == nil { owner = page }
        readings[page] = reading
        guard owner == page else { return }
        recompute()
    }

    /// Records the height of the presented sheet's page area: the sheet less the bottom safe area, which the detent is measured
    /// up from. A custom detent `D` gives a page area of `D` (the sheet is `D` plus the safe area tall) and ``SheetFit/wantedHeight``
    /// asks for exactly that, so a sheet that got what it asked for reads exactly its detent. Measured on the folded iPhone Duo
    /// (iOS 27.1), 2026-10-26: Upper Deck asked 479 and read 479 (a 513 pt sheet); the large detent reads 554 (588 pt).
    public func setSheetHeight(_ height: CGFloat) {
        sheetHeight = height
        if detentIsLarge, height > 0 { largeSheetHeight = height }
        recompute()
    }

    /// Whether the sheet has been given as much height as the system allows, so a taller reading cannot make it any taller.
    ///
    /// A custom detent `D` gives a page area of `D` (``setSheetHeight(_:)``), and the system stops it at ``maxSheetHeight``. A
    /// sheet at or past that (the folded iPhone Duo's Front Door: 565 pt asked, 554 pt of page area) already shows all it can;
    /// asking for 8 pt more changes nothing on screen but moves the detent. While the sheet is that tall its header also reads
    /// taller (82 pt against 74), which is why such a reading must not set the height.
    private func atMaximum(_ current: CGFloat) -> Bool {
        guard !usesSheetEstimate, let maxSheetHeight else { return false }
        return current >= maxSheetHeight - 1
    }

    /// Whether the sheet is a custom height that the system cut short, from the page area it was actually given against the
    /// detent it asked for (both in the measure above the bottom safe area). Its header reads taller than any other sheet's, so such a sheet teaches no top chrome.
    ///
    /// (Until 2026-10-26 this compared the page area with the detent *plus* the bottom inset, as if the page area included
    /// it. It does not: every sheet read as cut short, nothing but a large sheet ever taught the chrome, and the first
    /// camera sheet on the folded iPhone Duo taught nothing, so the second opened from the fallback and moved.)
    private var isCutShort: Bool {
        guard !usesSheetEstimate, !detentIsLarge, let sheetHeight, let contentHeight else { return false }
        return sheetHeight + 2 < contentHeight
    }

    /// Records the page's safe-area insets: the navigation bar above it and the home indicator and a pinned tab bar
    /// below it. A scroller laid out below the header (iPad's form sheet) reports no inset for the bar.
    public func setSafeInsets(top: CGFloat, bottom: CGFloat) {
        safeTop = top
        safeBottom = bottom
        recompute()
    }

    /// Whether the sheet-minus-scroller estimate counts (regular width, where the scroller sits below the header).
    /// Set by the presenting sheet from its size class.
    public var usesSheetEstimate = false

    /// The content plus the larger of the scroller's insets and the page's safe areas, less the bottom safe area the system adds to
    /// a detent itself (``systemBottomInset``); at regular width also the larger of that and the sheet's height minus the
    /// scroller's viewport plus its content, so the sheet is never too short.
    private func recompute() {
        guard let reading else { return }
        var wanted = SheetFit.wantedHeight(contentHeight: reading.content, topInset: max(reading.topInset, safeTop),
                                           bottomInset: max(reading.bottomInset, safeBottom),
                                           systemBottomInset: systemBottomInset).rounded()
        // The sheet-minus-scroller estimate is for a scroller laid out below the header (iPad's form sheet). On a phone
        // the scroller runs under the header and the safe areas above are the chrome, and counting the sheet's own height
        // there made a ratchet: a scroller that does not grow with the sheet reads the same viewport at every height, so
        // each taller sheet asked for 14 pt more until it reached large (the bathroom fan sheet, 2026-10-17: 400 pt of
        // blank ground under a 330 pt page).
        if usesSheetEstimate, let sheetHeight, reading.viewport > 0 {
            wanted = max(wanted, SheetFit.wantedHeight(sheetHeight: sheetHeight, viewportHeight: reading.viewport,
                                                       contentHeight: reading.content).rounded())
        }
        if let root, standardHeaders[root] ?? true, let rootReading = readings[root] {
            // Written only when they change: @Observable does not compare, and every scroll reading lands here.
            let chrome = SheetChrome(top: max(rootReading.topInset, safeTop).rounded(),
                                     bottom: SheetFit.bottomBeyondSafeArea(inset: max(rootReading.bottomInset, safeBottom), safeArea: systemBottomInset).rounded())
            let width = rootReading.width > 0 ? rootReading.width : nil
            if rootChrome != chrome { rootChrome = chrome }
            if rootWidth != width { rootWidth = width }
            if rootIsCutShort != isCutShort { rootIsCutShort = isCutShort }
        }
        // A reading back within hysteresis of the height the sheet has cancels a transient one that was waiting.
        pendingUpdate?.cancel()
        pendingUpdate = nil
        guard SheetFit.shouldUpdate(from: contentHeight, to: wanted), !growsPastMaximum(to: wanted) else { return }
        guard let settleDelay else { return accept(wanted) }
        pendingUpdate = Task { [weak self] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled, let self, SheetFit.shouldUpdate(from: contentHeight, to: wanted), !growsPastMaximum(to: wanted) else { return }
            accept(wanted)
        }
    }

    /// A reading taller than the height the sheet has, while the sheet is already as tall as the system allows: by what was
    /// learned (``maxSheetHeight``), or because the system just gave this sheet less than it asked for (``isCutShort``), which
    /// is the same fact seen on the sheet itself and needs no earlier sheet at the large detent (the folded iPhone Duo's Front
    /// Door, 557 asked and 554 given, reads 565 once its header grows to 82).
    private func growsPastMaximum(to wanted: CGFloat) -> Bool {
        guard let contentHeight, wanted > contentHeight else { return false }
        return atMaximum(contentHeight) || isCutShort
    }

    private func accept(_ wanted: CGFloat) {
        contentHeight = wanted
        if owner == root { onChange(wanted) }
    }
}

/// Heights remembered per call site, so a sheet opens at its final height at once instead of at `.medium` and then jumping.
/// Keys are the `#fileID:#line` of the `hassSheet` call.
///
/// Kept for the life of the process and also on disk (owner, 2026-10-26, `hass-modal`: "a fitted sheet must not open at
/// .medium and then jump"), under a context that changes whenever the height could: the app build, the window size and the
/// text size. The first time a sheet ever opens on a device, in a context, there is nothing to remember and it still measures
/// after it appears.
@MainActor
public enum SheetFitMemory {
    private static var heights: [String: CGFloat] = [:]
    /// Where heights persist; tests replace it.
    static var store: UserDefaults? = SheetFitStorage.launchDefaults
    /// The defaults key of the persisted table. `v2` (2026-10-28): a height now excludes the bottom safe area the system adds to a
    /// custom detent (``SheetFit/bottomBeyondSafeArea(inset:safeArea:)``), so a `v1` height would reopen its sheet 34 pt too tall and
    /// move it; the old table is ignored and removed (``SheetFitStorage``).
    static let storeKey = "sheetFit.heights.v2"
    /// The defaults key of the table before the safe area was left out of the detent.
    static let legacyStoreKey = "sheetFit.heights.v1"

    /// What a remembered height is only valid for: build, large-detent height (window size and orientation) and text size.
    static var context: () -> String = {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let size = LargeDetent.textSize()
        return "\(build)|\(Int(LargeDetent.height().rounded()))|\(size)"
    }

    private static func fullKey(_ key: String) -> String { "\(key)|\(context())" }

    public static func height(for key: String) -> CGFloat? {
        if let value = heights[fullKey(key)] { return value }
        guard let table = store?.dictionary(forKey: storeKey) as? [String: Double], let value = table[fullKey(key)] else { return nil }
        heights[fullKey(key)] = CGFloat(value)
        return CGFloat(value)
    }

    public static func remember(_ height: CGFloat, for key: String) {
        let full = fullKey(key)
        guard heights[full] != height else { return }
        heights[full] = height
        guard let store else { return }
        var table = store.dictionary(forKey: storeKey) as? [String: Double] ?? [:]
        table[full] = Double(height)
        store.set(table, forKey: storeKey)
    }

    /// Forgets what this process remembers but keeps what is on disk: what a relaunch starts with (tests).
    static func dropProcessMemory() { heights.removeAll() }

    /// Forgets everything (tests).
    static func reset() {
        heights.removeAll()
        store?.removeObject(forKey: storeKey)
    }
}

// MARK: - Detent resolution

/// The height of the large detent on this device: the key window of the foreground scene below its top safe area. 0 where there is no window
/// (macOS, `swift test`), which resolves every fitted sheet to `.large`.
@MainActor
public enum LargeDetent {
    #if os(iOS)
    /// The key window of the foreground scene.
    public static func window() -> UIWindow? {
        // The foreground-active scene first, so a second scene (iPad multi-window, a Duo's two windows) cannot set the cap.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.filter { $0.activationState == .foregroundActive }
        let windows = (active.isEmpty ? scenes : active).flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
    #endif

    /// The text size the key window shows, by its raw `UIContentSizeCategory` name (``textSizeName(window:app:)``).
    static func textSize() -> String {
        #if os(iOS)
        let trait = window()?.traitCollection.preferredContentSizeCategory
        return textSizeName(window: trait == .unspecified ? nil : trait?.rawValue,
                            app: UIApplication.shared.preferredContentSizeCategory.rawValue)
        #else
        return "host"
        #endif
    }

    /// The app's text size, or the window's marked `|override` when a scene trait override makes them differ. In the shipping app the two
    /// are always the same, so the key is the app's. The Debug UI tests switch a running app to AX5 in place (`GalleryReset`); a sheet
    /// already open then keeps the height it opened with, so what it learns is filed apart and never read by an AX5 launch (filed
    /// under plain AX5, it opened the Food hub too short at the next AX5 launch on the same simulator, 2026-10-31).
    nonisolated static func textSizeName(window: String?, app: String) -> String {
        guard let window, !window.isEmpty, window != app else { return app }
        return window + "|override"
    }

    /// The window's bottom safe area (the home indicator): what the system adds to a custom detent by itself
    /// (``SheetFit/bottomBeyondSafeArea(inset:safeArea:)``). 0 where there is no window.
    static func bottomSafeArea() -> CGFloat {
        #if os(iOS)
        window()?.safeAreaInsets.bottom.rounded() ?? 0
        #else
        0
        #endif
    }

    /// The bottom safe area a detent must not ask for (``bottomSafeArea()``), except under `FENTON_SHEETFIT_LEGACY=1` (Debug builds): 0,
    /// so a journey can measure the same build as it drew sheets before 2026-10-28 (the detent counted the safe area).
    public static func systemBottomInset() -> CGFloat {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FENTON_SHEETFIT_LEGACY"] == "1" { return 0 }
        #endif
        return bottomSafeArea()
    }

    public static func height() -> CGFloat {
        #if os(iOS)
        guard let window = window() else { return 0 }
        return window.bounds.height - window.safeAreaInsets.top - 10
        #else
        return 0
        #endif
    }
}
