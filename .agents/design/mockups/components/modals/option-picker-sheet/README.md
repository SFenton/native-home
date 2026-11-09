# OptionPickerSheet and GradientSwatch (component)
> **What:** a sheet that picks one value from a short list: label, optional gradient swatch, checkmark on the current value. **Read when:** a control chooses from options that need swatches or room (Lighting Mode); two to four short options use `SegmentedChoice` instead.
- Mockup: [option-picker-sheet.html](option-picker-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/OptionPickerSheet.swift`, `HassUI/Features/CustomLights/CustomLightsScreen.swift`, `HassCore/Config/CustomLightsConfig.swift` · Spec: `.agents/patterns/option-picker.md`, `modal-sheet.md` · Patterns: option-picker, modal-sheet, motion
- States covered: labels and swatches, each selection, labels only, long name, in context on iPhone and iPad (Custom Lights), ax5; dark and light
- Motion: check cross-fade (quick 0.2 s); sheet present and dismiss (Play)
- Devices: iPhone and iPad via the Device control
- Open notes: option-picker.md says to present with `[.medium, .large]`; the call site uses `.hassSheet(.form)`
