#if DEBUG
import Foundation
import HassDesign
import SwiftUI

/// Switches the gallery pages read from the process environment.
enum GalleryEnvironment {
    /// `FENTON_GALLERY_CLEAN=1`: screenshots leave the debug line out.
    static var isClean: Bool { ProcessInfo.processInfo.environment["FENTON_GALLERY_CLEAN"] == "1" }
}
#endif
