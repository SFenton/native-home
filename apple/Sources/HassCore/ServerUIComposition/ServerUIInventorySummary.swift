import Foundation

// MARK: - Configured inventory summary

/// Pure count parsing and total-first selection, matching Quick Links without HouseConfig reads.
public enum ServerUIInventorySummary {
    /// Bounds match the wire's safe integer range; malformed/missing values never become zero.
    public static let maximumCount = 9_007_199_254_740_991

    /// Production counters accept decimal sensor strings and truncate toward zero.
    public static func count(_ state: String?) -> Int? {
        guard let text = state?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let number = Double(text), number.isFinite, number >= 0,
              number <= Double(maximumCount) else { return nil }
        return Int(number.rounded(.towardZero))
    }

    /// A valid nonzero total wins. Only a zero total reads/sums spaces; an authored expiry counter is required when present.
    public static func text(configuration: ServerUICompositionDocument.InventorySummary,
                            state: (String) -> String?, locationCount: Int? = nil) -> String? {
        guard let total = count(state(configuration.totalEntityId)) else { return nil }
        let expiry: String
        if let id = configuration.expiringEntityId {
            guard let expiring = configuration.expiringLocation == nil ? count(state(id)) : locationCount else { return nil }
            expiry = configuration.separator + "\(expiring) \(configuration.expiringSuffix)"
        } else { expiry = "" }
        var items = total
        if total == 0 {
            for id in configuration.spaceEntityIds {
                guard let value = count(state(id)), value <= maximumCount - items else { return nil }
                items += value
            }
        }
        return "\(items) \(items == 1 ? configuration.singular : configuration.plural)"
            + expiry
    }

    /// Space subtitles use the canonical expiry-list projection, not the whole-house sensor count.
    public static func text(configuration: ServerUICompositionDocument.InventorySummary,
                            entity: (String) -> EntityState?) -> String? {
        var locationCount: Int?
        if let location = configuration.expiringLocation {
            guard let id = configuration.expiringEntityId, let value = entity(id),
                  !value.isUnavailable, value.attributes["expiring_list"]?.array != nil else { return nil }
            locationCount = FoodConfig.expiringCount(location: location, entity: value)
        }
        return text(configuration: configuration, state: { entity($0)?.state }, locationCount: locationCount)
    }
}
