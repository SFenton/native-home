# Option picker

> **What:** picking one value from a short list in a sheet. **Read when:** a control opens a list of options (input_select modes, HVAC modes).

- `OptionPickerSheet(title:options:selected:identifierPrefix:choose:)` (`HassDesign/OptionPickerSheet.swift`, web `OptionPickerDialog` with `presentation="sheet"`). Present it with `.presentationDetents([.medium, .large])`.
- Rows are 44 pt or taller, show the label, an optional `GradientSwatch`, and a checkmark on the current value; the current row carries `.isSelected`. Choosing calls `choose` only for a new value, then dismisses.
- The sheet has an opaque grouped background at every detent. At the medium detent, the default glass let a page's colored tiles show through the rows and fail text contrast.
- Row identifiers are `<prefix>.<value>`.
- For two to four short choices inline, use `SegmentedChoice(label:options:title:selection:identifier:select:)` (`HassUI/Common/SegmentedChoice.swift`): a system segmented control that becomes a menu at accessibility sizes (direction G, Controls). UI tests reach an option as `segmentedControls[identifier].buttons[title]`. A sheet's section tabs use `modalTabBar` instead. Use this sheet when options need swatches or more room.
- First used by Custom Lights (Lighting Mode).
- Choose-one rows are `FilterOptionRow(title:subtitle:swatch:isSelected:action:)` (`HassDesign/FilterSheet.swift`): this sheet, the sort/filter sheets and the inventory sheets all draw it, so the checkmark, 44 pt height and `.isSelected` trait exist once. `SelectableOptionRow` (`SettingsSection.swift`) is the card variant with an icon and detail, used by the presence override. Moving either onto a system `Picker` changes the drawn row and needs a propose-first.
