"""The calibration scenarios: one push, one sheet and one control animation on the iPhone.

``chores-calib`` is the spike's sequence on the Chores page (reference gallery page ``chores``; native ``--server-ui-preview``
with the ``fullpair`` publication): tap "Your Chores" (a push to the resident's chores page), the back button, "Add Task" (the
task sheet) and "Cancel". ``control-calib`` is the components' own motion page (``FENTON_GALLERY=motion``, in both apps from the
same UIKit components): "Toggle Primary" (the card is the band 27 to 38 % down the screen on iPhone) flips the primary button between enabled and disabled, a state cross-fade.
"""

from __future__ import annotations

from .scenarios import Scenario, Step, register

CHORES = register(Scenario(
    "chores-calib", "Chores page: push, pop, sheet, dismiss", "chores",
    [Step('label="Your Chores"', 1600, "push"), Step('id="BackButton"', 1400, "pop"),
     Step('label="Add Task"', 1800, "sheet"), Step('label="Cancel"', 1400, "dismiss")],
    native_prepare=["Chores"]))

CONTROL = register(Scenario(
    "control-calib", "Motion gallery: the primary button's enabled state", "motion",
    [Step('label="Toggle Primary"', 1500, "disable", onset_threshold=0.02, min_frames=6, roi=(0.0, 0.27, 1.0, 0.38), expect_cut=True),
     Step('label="Toggle Primary"', 1500, "enable", onset_threshold=0.02, min_frames=6, roi=(0.0, 0.27, 1.0, 0.38))],
    native_mode="gallery"))
