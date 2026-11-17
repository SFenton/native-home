#if os(iOS)
import HassDesign
import Foundation

// MARK: - The words a light tile says

/// The words a light tile says for its states (`sh.state-words@1`), as plain text. An absent word is production's.
struct UKLightWords: Equatable {
    var on: String?
    var off: String?
    var unavailable: String?
    var level: String?

    init(on: String? = nil, off: String? = nil, unavailable: String? = nil, level: String? = nil) {
        self.on = on
        self.off = off
        self.unavailable = unavailable
        self.level = level
    }

    /// The state line and spoken value of a light that dims: "Off", "45%" or "Unavailable", or the authored words.
    func status(percent: Int, isUnavailable: Bool) -> String {
        if isUnavailable { return unavailable ?? "Unavailable" }
        guard percent > 0 else { return off ?? "Off" }
        return (level ?? "{value}%").replacingOccurrences(of: "{value}", with: String(percent))
    }

    /// The state line of a light that does not dim: "On", "Off" or "Unavailable", or the authored words.
    func power(isOn: Bool, isUnavailable: Bool) -> String {
        if isUnavailable { return unavailable ?? "Unavailable" }
        return isOn ? on ?? "On" : off ?? "Off"
    }

    /// Every line the tile can show, so the grid sizes it for the longest and a live change never re-spans it.
    var candidates: [String] {
        [off ?? "Off", (level ?? "{value}%").replacingOccurrences(of: "{value}", with: "100"), unavailable ?? "Unavailable", on ?? "On"]
    }
}
#endif
