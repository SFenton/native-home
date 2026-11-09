import SwiftUI

public extension HassTokens.Ink {
    /// A running timer's orange: the web's `--color-timer` (`rgb(255, 159, 10)`,
    /// `ha-sfenton-react-dash@f5a7bf9:src/styles/tokens.css:27`) on a dark sheet; on a light sheet a deeper orange that
    /// keeps 3:1 or better against the white cell for the 40 pt countdown and the progress bar.
    static let timer: Color = .adaptive(light: HassTokens.Palette.timerLight, dark: HassTokens.Palette.timer)
}

public extension HassTokens.Palette {
    /// The web's timer orange, `#FF9F0A`.
    static let timer: UInt32 = 0xFF9F0A
    /// The timer orange on a light sheet (`#B35C00`, 4.6:1 on white).
    static let timerLight: UInt32 = 0xB35C00
}
