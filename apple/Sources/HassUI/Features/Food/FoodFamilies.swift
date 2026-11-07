import HassDesign

/// The colour family of each Food tile (owner, 2026-10-16: "Food Spaces / All Food should have colours like the web").
///
/// The families themselves live in `HassDesign/ColorFamily`, with their contrast tests; this maps EverShelf's location
/// keys (`FoodConfig.Space.location`) to them.
enum FoodFamilies {
    /// The family of the storage space with this EverShelf location key (web `EVERSHELF_FOOD_SPACES[].color`).
    static func family(forLocation location: String) -> ColorFamily {
        switch location {
        case "dispensa": .pantry
        case "frigo": .fridge
        case "freezer": .freezer
        case "spice_rack": .spiceRack
        case "cabinet": .cabinet
        default: .food
        }
    }
}
