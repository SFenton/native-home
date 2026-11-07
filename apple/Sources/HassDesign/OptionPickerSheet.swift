import SwiftUI

/// The option of a sheet (`UKOptionPickerSheet`) that picks one option from a short list (web `OptionPickerDialog` with `presentation="sheet"`;
/// pattern: `.agents/patterns/option-picker.md`).
///
/// Each row shows the option, an optional color swatch, and a checkmark on the current choice. Choosing an option
/// calls `choose` (not for the current one) and dismisses. Rows are at least 44 pt tall and read as selected to
/// VoiceOver (HIG: Pickers, Lists and tables).
public enum OptionPickerSheet {
    /// One choice.
    public struct Option: Identifiable, Hashable {
        /// What `choose` receives.
        public var value: String
        /// What the row shows.
        public var label: String
        /// Colors drawn as a gradient swatch; empty for none.
        public var swatch: [Color]

        public var id: String { value }

        /// Creates an option.
        public init(value: String, label: String? = nil, swatch: [Color] = []) {
            self.value = value
            self.label = label ?? value
            self.swatch = swatch
        }
    }
}
