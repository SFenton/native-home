# Lighting Mode picker (modal)
> **What:** The option sheet the Lighting Mode row opens: modes with gradient swatches and a check on the current one. **Read when:** you change the picker call site or `OptionPickerSheet`.
- Mockup: [lighting-mode-picker.html](lighting-mode-picker.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/CustomLights/CustomLightsScreen.swift`, `HassDesign/OptionPickerSheet.swift` · Spec: `.agents/patterns/option-picker.md`, `.agents/pages/custom-lights/ios.md` · Patterns: option-picker, modal-sheet
- States covered: default, loading/error (fallback list), offline, Team Colors, long-text, medium, large, fitted, closed, ax5; dark and light
- Motion: check opacity (quick); transitions: present, dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (form sheet)
- Open notes: option-picker.md says medium and large detents; the call site is `.hassSheet(.form)` fitted; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
