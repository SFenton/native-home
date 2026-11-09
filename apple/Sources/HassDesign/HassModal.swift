import CoreGraphics

// The sheet vocabulary the UIKit port's `UKHassModal` presents with (pattern: `.agents/patterns/modal-sheet.md`).

/// How wide a `UKHassModal` modal is on iPad.
public enum HassSheetWidth: Sendable, Equatable {
    /// A form sheet (540 pt): lists, editors, prompts, short device controls.
    case form
    /// A page sheet, with room for tile grids, dials, maps and two columns.
    case page
}

/// How a `UKHassModal` modal chooses light or dark.
public enum HassSheetAppearance: Sendable {
    /// The user's system appearance (``SystemAppearance``): light or dark.
    case system
    /// Always dark: a sheet whose backdrop is a photo or gradient (Weather).
    case dark
}

/// The size of a form sheet on iPad: what SwiftUI's `FormPresentationSizing.form` gives (measured on iOS 26 and 27: 580 x 660 pt), for the
/// UIKit port's `.formSheet`, which has no sizing API of its own. One place, so every form-width sheet reads the same numbers.
public enum HassFormSheetSize {
    public static let width: CGFloat = 580
    public static let height: CGFloat = 660
}
