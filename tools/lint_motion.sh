#!/usr/bin/env bash
# Lints the motion rules (.agents/patterns/motion.md, "Lint"; .agents/design/motion.md §7, §9; .agents/design/motion-components.md).
# Run by tools/apple_coverage.sh and by the pr-checks workflow. Exit 1 with one line per violation; every allowlisted exception carries its reason.
#
# Rules (apple/Sources/HassUI and HassDesign):
#   animation-no-value  `.animation(` without `value:` (the `.animation(_:body:)` closure form and `TimelineView(.animation` are fine)
#   literal-duration    a literal `duration: 0.3` outside MotionTokens.swift (call sites take a token)
#   transition          `.transition(` in HassUI/App and HassUI/Features (in-place swaps only, listed below)
#   repeat-forever      `repeatForever` outside ArcSpinner and the pending pulse
#   state-colour        a state-driven `.background` / `.fill` / `.foregroundStyle` ternary in a component of motion-components.md
#                       whose file never uses stateColorTransition / stateForeground / stateColor / quickTransition
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 - "$ROOT" <<'PY'
import os, re, sys

root = sys.argv[1]
sources = os.path.join(root, "apple", "Sources")

# (rule, path substring, reason). A violation of `rule` in a file whose path contains the substring is allowed.
ALLOW = [
    ("literal-duration", "HassDesign/Loading/", "ContentGate's profile constants are the owner's loading timings (.agents/patterns/content-gate.md)"),
    ("literal-duration", "HassDesign/Motion/MotionTokens.swift", "the one place durations are written"),
    ("transition", "HassUI/App/Shell/NavigationFlyout.swift", "the flyout and its scrim are an overlay swap in place, not navigation content"),
    ("transition", "HassUI/App/Layout/HingedPanes.swift", "the trailing pane opening beside the leading one is an in-place swap on a wide or unfolded window, not a push"),
    ("transition", "HassUI/App/Layout/OnDemandSplit.swift", "the split pane opening beside the root is an in-place swap on regular width, not a push"),
    ("transition", "HassUI/Features/Home/StatusRail.swift", "the chip's neutral and tinted grounds swap in place (the approved status chip fade)"),
    ("transition", "HassUI/Features/MediaRemote/MediaRemoteControls.swift", "the keyboard form swaps in place inside the remote sheet"),
    ("transition", "HassUI/Features/Cameras/CameraLiveView.swift", "the live video fades over its snapshot in place"),
    ("transition", "HassUI/Features/Home/CameraGrid.swift", "the tile's live dot, arc and offline icon cross-fade in place"),
    ("transition", "HassUI/Features/Inventory/InventoryScreen.swift", "the split detail pane swaps in place on regular width"),
    ("transition", "HassUI/Features/Food/RecipesScreen.swift", "the split detail pane swaps in place on regular width"),
    ("repeat-forever", "HassDesign/ArcSpinner.swift", "the one spinner"),
    ("state-colour", "HassUI/Features/Climate/ClimateTrackingTab.swift", "known finding (2026-10-30): the room checkmark ink snaps; it passed only while it shared a file with a stateColorTransition. Adding the fade is a visible motion change, so it waits for the owner (propose-first)"),
    ("repeat-forever", "HassDesign/PendingValue.swift", "the pending pulse: one Core Animation loop per bar, run on the render server"),
    ("transition", "HassUI/App/RootView.swift", "the launch ground and the sign-in layer fade over the signed-in tree in place (the root's own layers, not a push)"),
    ("transition", "HassUI/App/Shell/OfflineOverlay.swift", "the offline chip appears over the page in place"),
    ("transition", "HassUI/App/Shell/ShellHeader.swift", "the profile badge fades in place on the header button (motion-timings 2)"),
    ("transition", "HassUI/Features/Settings/Profile/SummaryPanel.swift", "the panel's content cross-fades in place when its tab changes"),
]

# The files of motion-components.md rows that colour from state, for the state-colour rule.
COMPONENT_FILES = [
    "HassDesign/GlassTile.swift", "HassDesign/StatusPill.swift", "HassDesign/PrimaryButtonStyle.swift", "HassDesign/FloatingActionBar.swift",
    "HassDesign/SettingsSection.swift", "HassDesign/FilterSheet.swift", "HassDesign/OptionPickerSheet.swift",
    "HassUI/Features/Home/StatusRail.swift", "HassUI/Features/Bedroom/BedroomComponents.swift", "HassUI/Features/Cameras/CameraViewer.swift",
    "HassUI/Features/Chores/TodoItemRow.swift", "HassUI/Features/Climate/ClimateNotice.swift", "HassUI/Features/Climate/ClimateHubPill.swift",
    "HassUI/Features/Climate/ClimateAutomationTab.swift", "HassUI/Features/Climate/ClimateRoomsTab.swift",
    "HassUI/Features/CustomLights/CustomLightsScreen.swift", "HassUI/Features/CustomLights/CustomLightSheet.swift",
    "HassUI/Features/Home/Weather/WeatherBarChart.swift", "HassUI/Features/Inventory/InventoryRow.swift",
    "HassUI/Features/RoomDevices/AirPurifierSheet.swift", "HassUI/Features/RoomDevices/HumidifierSheet.swift",
    "HassUI/Features/Security/SecuritySystemSheet.swift", "HassUI/Features/Settings/AppIcon/AppIconChoiceButton.swift",
    "HassUI/Features/Sprinklers/SprinklerControllerSheet.swift", "HassUI/Features/Vacation/VacationModeScreen.swift",
    "HassUI/Features/Vacuums/VacuumControlsTab.swift", "HassUI/Features/Vacuums/VacuumRoomsTab.swift", "HassUI/Features/Vacuums/VacuumAutoCleanTab.swift",
    "HassUI/Features/Vacuums/VacuumActionsTab.swift", "HassUI/Features/Vacuums/VacuumInfoTab.swift", "HassUI/Features/Vacuums/VacuumAreaEditor.swift",
    "HassUI/Features/Vacuums/VacuumComponents.swift", "HassUI/Features/Vacuums/VacuumStatusChips.swift", "HassUI/Features/Vacuums/VacuumActionButton.swift",
    "HassUI/Features/Vacuums/VacuumSettingRow.swift", "HassUI/Features/Vacuums/VacuumActionTile.swift",
    "HassUI/Features/Vacuums/VacuumChoiceTile.swift", "HassUI/Features/Vacuums/VacuumShapeMotion.swift",
    "HassUI/Features/Climate/ClimateTrackingTab.swift",
]
HELPERS = ("stateColorTransition", "stateForeground", "stateColor(", "quickTransition")
STATE_TERNARY = re.compile(r"\.(background|fill|foregroundStyle)\(.*\?.*:")

def allowed(rule, rel):
    return any(r == rule and sub in rel for r, sub, _ in ALLOW)

violations = []
for base in ("HassUI", "HassDesign"):
    for dirpath, _, files in os.walk(os.path.join(sources, base)):
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, sources)
            lines = open(path, encoding="utf-8").read().split("\n")
            text = "\n".join(lines)
            for number, line in enumerate(lines, 1):
                code = line.split("//")[0] if not line.lstrip().startswith("///") else ""
                if not code.strip():
                    continue
                def flag(rule, message):
                    if not allowed(rule, rel):
                        violations.append(f"{rel}:{number}: [{rule}] {message}")
                if ".animation(" in code and "TimelineView(.animation" not in code and ".animation(forKey:" not in code:  # CALayer.animation(forKey:) is UIKit, not the modifier
                    joined = " ".join(lines[number - 1:number + 2])
                    after = joined[joined.index(".animation("):]
                    closure = re.match(r"\.animation\([^)]*\)\s*\{", after) or "body:" in after[:120]
                    if "value:" not in after[:160] and not closure:
                        flag("animation-no-value", "`.animation(` needs `value:` (or the closure form)")
                if re.search(r"duration:\s*[0-9]", code):
                    flag("literal-duration", "literal duration; use a MotionTokens value")
                if base == "HassUI" and (rel.startswith("HassUI/App") or rel.startswith("HassUI/Features")) and ".transition(" in code:
                    flag("transition", "`.transition(` on navigation content; allow only in-place swaps, with a reason")
                if "repeatForever" in code:
                    flag("repeat-forever", "`repeatForever` only in ArcSpinner and the pending pulse")
            if rel in COMPONENT_FILES and not any(h in text for h in HELPERS):
                for number, line in enumerate(lines, 1):
                    if not line.lstrip().startswith("//") and STATE_TERNARY.search(line):
                        if not allowed("state-colour", rel):
                            violations.append(f"{rel}:{number}: [state-colour] state-driven colour without stateColorTransition / stateForeground")

for v in sorted(set(violations)):
    print(v)
if violations:
    print(f"lint_motion: {len(set(violations))} violation(s). Fix them or add an allowlist entry with a reason in tools/lint_motion.sh.", file=sys.stderr)
    sys.exit(1)
print("lint_motion: ok")
PY
