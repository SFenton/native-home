import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Chrome

/// What a fitted sheet's detent adds around its page's scroll content: the inline header above it and whatever lies below it
/// beyond the system's bottom safe area. A detent is the content plus these
/// (``SheetFit/wantedHeight(contentHeight:topInset:bottomInset:systemBottomInset:)``).
///
/// Every sheet with the standard inline header has the same chrome on a given system, so one sheet that has opened
/// teaches all the others (``SheetChromeMemory``). That is what lets a sheet whose content can be computed before it opens
/// (the camera viewer: video width over aspect ratio, plus a measured controls row) open at its final height on its first
/// presentation too, with no measure-then-move (owner, 2026-10-26: "Why does first open have to measure and move at all?
/// Can't we precompute this?").
public struct SheetChrome: Equatable, Sendable {
    /// The header above the content: the grabber, the inline navigation bar and the safe area (74 pt on an iPhone 17 Pro).
    public var top: CGFloat
    /// The inset below the content beyond the system's bottom safe area: 0 on a standard sheet. The home indicator (34 pt on an
    /// iPhone 17 Pro, 20 pt on an iPad) is not part of it: the system measures a custom detent up from that safe area and adds it
    /// itself (``SheetFit/bottomBeyondSafeArea(inset:safeArea:)``; owner, 2026-10-28, `proposals/sheet-bottom-gap`, option B).
    public var bottom: CGFloat

    /// How much narrower the page lays out than the window. 0 on an iPhone, where iOS draws an inset sheet scaled and lays the
    /// page out at the window's width (iOS 26.5 and 27.0); 16 on the folded iPhone Duo (iOS 27.1), where the sheet is inset 8 pt
    /// a side and the page is laid out at the sheet's width.
    public var widthInset: CGFloat

    /// Creates the chrome.
    public init(top: CGFloat, bottom: CGFloat, widthInset: CGFloat = 0) {
        self.top = top
        self.bottom = bottom
        self.widthInset = widthInset
    }

    /// The detent for content of this height, whole points as the measured path rounds.
    public func sheetHeight(forContent content: CGFloat) -> CGFloat {
        SheetFit.wantedHeight(contentHeight: content, topInset: top, bottomInset: bottom).rounded()
    }

    /// Whether a reading is the chrome of a standard inline-header sheet and not a transient one (a reading taken before
    /// the page laid out is 0; a page with a header of its own is taller than any plausible standard header).
    static func isPlausible(top: CGFloat, bottom: CGFloat, widthInset: CGFloat = 0) -> Bool {
        (40...110).contains(top) && (0...60).contains(bottom) && (0...40).contains(widthInset)
    }
}

// MARK: - Memory

/// The chrome of fitted sheets, learned from any fitted sheet with the standard inline header and kept on disk, so a
/// prediction (``SwiftUI/View/hassSheet(_:height:appearance:fitKey:predictedContentHeight:)``) knows the header and any bottom
/// inset beyond the safe area before its sheet opens.
///
/// Stored under a context without the app build (the system version, the large detent's height, the text size and the
/// width class), because a new build changes none of these and should not forget; a heights table
/// (``SheetFitMemory``) is keyed by the build because content can change with one. Before anything is learned in a context
/// the chrome is ``fallback()``: no bottom inset and a per-system header constant.
@MainActor
public enum SheetChromeMemory {
    private static var chromes: [String: SheetChrome] = [:]
    /// Where chromes persist; tests replace it.
    static var store: UserDefaults? = SheetFitStorage.launchDefaults
    /// The defaults key of the persisted table. `v2` (2026-10-28): the bottom of a chrome is what lies beyond the bottom safe area
    /// (0, not 34), so a `v1` chrome would predict every camera sheet 34 pt too tall; the old table is ignored and removed
    /// (``SheetFitStorage``).
    static let storeKey = "sheetChrome.v2"
    /// The defaults key of the table before the safe area was left out of the detent.
    static let legacyStoreKey = "sheetChrome.v1"

    /// What a learned chrome is valid for: system version, large-detent height (window size and orientation), text size and
    /// width class. No build number.
    static var context: () -> String = {
        #if os(iOS)
        let system = UIDevice.current.systemVersion.split(separator: ".").prefix(2).joined(separator: ".")
        let size = LargeDetent.textSize()
        let widthClass = LargeDetent.window()?.traitCollection.horizontalSizeClass == .regular ? "regular" : "compact"
        #else
        let system = "host", size = "host", widthClass = "compact"
        #endif
        return "\(system)|\(Int(LargeDetent.height().rounded()))|\(size)|\(widthClass)"
    }

    /// The header height of a phone sheet on a system nothing has taught yet, measured on the simulators
    /// (`.agents/patterns/modal-sheet.md`, Height): an iPhone 17 Pro (the window has a top safe area, 62 pt) and the folded
    /// iPhone Duo (it has none).
    static func defaultTop() -> CGFloat {
        #if os(iOS)
        if let window = LargeDetent.window(), window.safeAreaInsets.top == 0 { return SheetChromeDefaults.topWithoutTopInset }
        if #available(iOS 27.0, *) { return SheetChromeDefaults.topIOS27 }
        #endif
        return SheetChromeDefaults.topIOS26
    }

    /// What nothing has taught yet: the system's default header and no bottom inset beyond the safe area (a standard sheet has none).
    static func fallback() -> SheetChrome {
        SheetChrome(top: defaultTop(), bottom: 0)
    }

    /// The chrome to predict with: what a sheet in this context taught, else ``fallback()``.
    public static func current() -> SheetChrome {
        let key = context()
        if let chrome = chromes[key] { return chrome }
        if let table = store?.dictionary(forKey: storeKey) as? [String: [Double]], let pair = table[key], pair.count == 3 {
            let chrome = SheetChrome(top: CGFloat(pair[0]), bottom: CGFloat(pair[1]), widthInset: CGFloat(pair[2]))
            chromes[key] = chrome
            return chrome
        }
        return fallback()
    }

    /// Teaches the chrome of this context. An implausible reading (taken before the page laid out, or from a page with a
    /// header of its own) is ignored.
    public static func learn(_ chrome: SheetChrome) {
        guard SheetChrome.isPlausible(top: chrome.top, bottom: chrome.bottom, widthInset: chrome.widthInset) else { return }
        let key = context()
        guard chromes[key] != chrome else { return }
        chromes[key] = chrome
        guard let store else { return }
        var table = store.dictionary(forKey: storeKey) as? [String: [Double]] ?? [:]
        table[key] = [Double(chrome.top), Double(chrome.bottom), Double(chrome.widthInset)]
        store.set(table, forKey: storeKey)
    }

    /// Teaches the chrome the root page of a fitted sheet measured: its insets, and how much narrower it is than the window.
    ///
    /// A sheet the system cut short (a tall first sheet on the folded iPhone Duo) has a taller header than every other sheet
    /// (``SheetFitModel/rootIsCutShort``), so it teaches the bottom inset and the width but keeps the top that was known: the
    /// second sheet then opens with the right width, and no warm-up sheet is needed.
    public static func learn(from model: SheetFitModel, windowWidth: CGFloat?) {
        guard var chrome = model.rootChrome else { return }
        if model.rootIsCutShort { chrome.top = current().top }
        if let rootWidth = model.rootWidth, let windowWidth { chrome.widthInset = max(0, windowWidth - rootWidth) }
        learn(chrome)
    }

    /// Whether a sheet in this context has taught the chrome (so ``current()`` is not the fallback).
    public static var isLearned: Bool {
        let key = context()
        if chromes[key] != nil { return true }
        return (store?.dictionary(forKey: storeKey) as? [String: [Double]])?[key] != nil
    }

    // MARK: Maximum height

    private static var maxHeights: [String: CGFloat] = [:]
    /// The defaults key of the persisted maximum heights.
    static let maxStoreKey = "sheetChrome.maxHeight.v1"

    /// The tallest a partial-height sheet's page area can be in this context: the page area (above the bottom inset) of a sheet
    /// at the large detent, learned from any sheet that reached it. Nil until one has. The system stops a custom-height sheet
    /// there (the folded iPhone Duo: 554 pt of page area in a 588 pt sheet in a 678 pt window, where ``LargeDetent`` computes
    /// 668), and a sheet that is that tall cannot grow, so a taller reading is not a reason to move it (``SheetFitModel``).
    public static var maxSheetHeight: CGFloat? {
        let key = context()
        if let value = maxHeights[key] { return value }
        guard let table = store?.dictionary(forKey: maxStoreKey) as? [String: Double], let value = table[key] else { return nil }
        maxHeights[key] = CGFloat(value)
        return CGFloat(value)
    }

    /// Teaches the maximum sheet height of this context. A height at or below the sheet's own chrome is no reading of a large sheet.
    public static func learnMaxSheetHeight(_ height: CGFloat) {
        guard height.isFinite, height > 200 else { return }
        let key = context()
        guard maxHeights[key] != height else { return }
        maxHeights[key] = height
        guard let store else { return }
        var table = store.dictionary(forKey: maxStoreKey) as? [String: Double] ?? [:]
        table[key] = Double(height)
        store.set(table, forKey: maxStoreKey)
    }

    /// Forgets what this process remembers but keeps what is on disk: what a relaunch starts with (tests).
    static func dropProcessMemory() {
        chromes.removeAll()
        maxHeights.removeAll()
    }

    /// Forgets everything (tests).
    static func reset() {
        chromes.removeAll()
        maxHeights.removeAll()
        store?.removeObject(forKey: storeKey)
        store?.removeObject(forKey: maxStoreKey)
    }
}

/// The header heights ``SheetChromeMemory`` falls back to before a sheet has taught the real ones, per system.
///
/// Measured on the simulators, 2026-10-26, as `max(topInset, safeTop)` of the camera viewer's page (the value a fitted sheet
/// adds above its content): see `.agents/patterns/modal-sheet.md`, Height. Used only until a sheet has taught the real value.
enum SheetChromeDefaults {
    /// iOS 17 through 26.
    static let topIOS26: CGFloat = 70
    /// iOS 27 and later.
    static let topIOS27: CGFloat = 70
    /// A window with no top safe area (the folded iPhone Duo, iOS 27.1: its sheet's header is 74).
    static let topWithoutTopInset: CGFloat = 74
}

// MARK: - Opening height

/// The height a fitted sheet opens at, before it has measured anything.
@MainActor
public enum SheetFitStart {
    /// A prediction (the content's height computed before presentation, plus the chrome) wins over a remembered height: it
    /// is for this exact content, and a remembered height may belong to other content under the same key. With neither, nil:
    /// the sheet measures after it appears.
    public static func height(predictedContent: CGFloat?, remembered: CGFloat?, chrome: @autoclosure () -> SheetChrome = SheetChromeMemory.current()) -> CGFloat? {
        if let predictedContent, predictedContent.isFinite, predictedContent > 0 {
            return chrome().sheetHeight(forContent: predictedContent)
        }
        return remembered
    }
}

/// Where the sheet-fit tables live: the standard defaults, cleared at launch under `FENTON_SHEETFIT_RESET=1` (Debug builds)
/// so a journey can see a sheet's very first presentation on a device that has never opened one.
@MainActor
enum SheetFitStorage {
    static let launchDefaults: UserDefaults = {
        let defaults = UserDefaults.standard
        removeLegacyTables(from: defaults)
        #if DEBUG
        if ProcessInfo.processInfo.environment["FENTON_SHEETFIT_RESET"] == "1" {
            defaults.removeObject(forKey: SheetFitMemory.storeKey)
            defaults.removeObject(forKey: SheetChromeMemory.storeKey)
            defaults.removeObject(forKey: SheetChromeMemory.maxStoreKey)
        }
        #endif
        return defaults
    }()
}

extension SheetFitStorage {
    /// Removes the tables an older build wrote, whose heights and chromes counted the bottom safe area in the detent
    /// (``SheetFitMemory/legacyStoreKey``, ``SheetChromeMemory/legacyStoreKey``). They are never read (the keys moved), so this only
    /// stops them lingering on disk.
    static func removeLegacyTables(from defaults: UserDefaults) {
        defaults.removeObject(forKey: SheetFitMemory.legacyStoreKey)
        defaults.removeObject(forKey: SheetChromeMemory.legacyStoreKey)
    }
}


// MARK: - Clearing

/// Everything the fitted sheets remember on this device: the heights they opened at (``SheetFitMemory``) and the chrome
/// predictions use (``SheetChromeMemory``), in the process and on disk.
///
/// Owner, 2026-10-26: "we clear everything on sign-out". Sign-out calls ``clearAll()``; the cost is one measured open per
/// sheet on a regular-width device after the next sign-in (compact width predicts its content anyway).
@MainActor
public enum SheetMemory {
    /// The `UserDefaults` keys the memories persist under.
    public static var persistedKeys: [String] { [SheetFitMemory.storeKey, SheetChromeMemory.storeKey, SheetChromeMemory.maxStoreKey] }

    /// The width a fitted page lays out at inside a window of this width, for a prediction that needs it (the camera viewer's
    /// video): the window's width less what a sheet taught (``SheetChrome/widthInset``), the window's width before any has.
    public static func pageWidth(inWindowOfWidth width: CGFloat) -> CGFloat {
        width - SheetChromeMemory.current().widthInset
    }

    /// Forgets every remembered sheet height and chrome, in memory and on disk.
    public static func clearAll() {
        SheetFitMemory.reset()
        SheetChromeMemory.reset()
        // Whatever store a memory is using, the standard defaults are where the app persists them.
        for key in persistedKeys { UserDefaults.standard.removeObject(forKey: key) }
        SheetFitStorage.removeLegacyTables(from: .standard)
    }
}
