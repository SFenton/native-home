import HassCore
import HassDesign
import SwiftUI

/// A small copy of an app icon: the same art the asset catalog's PNGs are rendered from (``AppIconArtwork``), clipped to
/// the system's icon corner radius (about 22.4% of the side). Drawing it from the one source means a preview can never
/// differ from the icon it stands for. Decorative: the row or button around it carries the name.
struct AppIconPreview {
    let choice: AppIconChoice
    let side: CGFloat

    /// The Home Screen icon's corner radius as a fraction of its side.
    static let cornerFraction: CGFloat = 0.2237

}
