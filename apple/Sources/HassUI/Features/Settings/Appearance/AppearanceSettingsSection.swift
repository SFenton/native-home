import HassCore
import HassDesign
import SwiftUI

/// Background Blur: a 0 to 100% slider (``PercentSliderRow``, the app's one slider-with-value row) for how soft the
/// house photo behind every page is, and Reset to Default. The default, 50%, is the web dashboard's blur on screen
/// (``BackdropBlur``). Dragging previews live: the backdrop store renders the latest value as fast as a render
/// finishes (``HouseBackdropStore``), keeping the previous picture up meanwhile.
struct BackdropBlurRows {


    /// The slider's name, which VoiceOver also reads.
    static let title = "Background Blur"

    /// The section's footer: what the slider does, or why it shows nothing.
    static func footer(reduceTransparency: Bool) -> String {
        reduceTransparency
            ? "Reduce Transparency is on, so pages use a plain background and the blur has nothing to soften."
            : "How soft the house photo behind every page is. The default matches the web dashboard; less blur can make text harder to read."
    }
}
