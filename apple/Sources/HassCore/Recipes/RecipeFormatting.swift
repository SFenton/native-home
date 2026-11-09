import Foundation

/// Text and grouping for the recipe detail, ported from the web
/// (`ha-sfenton-react-dash@9ac2a46:src/components/hass/recipes/recipeDetailFormatting.ts` and `RecipeDetailModal.tsx`).
public enum RecipeFormatting {
    // MARK: - Numbers and times

    /// Up to three fraction digits with grouping, in the user's locale.
    public static func number(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).locale(locale))
    }

    /// `Serves 4` for portions, `Makes 12 cookies` otherwise; nil without both parts (web `formatRecipeYield`).
    public static func yield(quantity: Double?, unit: String?, locale: Locale = .current) -> String? {
        guard let quantity, let unit, !unit.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let portions: Set = ["portion", "portions", "serving", "servings", "serve", "serves", "person", "persons", "people"]
        if portions.contains(unit.trimmingCharacters(in: .whitespaces).lowercased()) { return "Serves \(number(quantity, locale: locale))" }
        return "Makes \(number(quantity, locale: locale)) \(unit)"
    }

    /// `45 sec`, `20 min`, `1 hr`, `1 hr 15 min` (web `formatRecipeDuration`).
    public static func duration(seconds: Int?) -> String? {
        guard let seconds else { return nil }
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = Int((Double(seconds) / 60).rounded())
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) hr" }
        return "\(hours) hr \(rest) min"
    }

    /// The same duration spelled out for VoiceOver (`1 hour, 15 minutes`).
    public static func spokenDuration(seconds: Int?) -> String? {
        guard let seconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds < 60 ? [.second] : [.hour, .minute]
        return formatter.string(from: TimeInterval(seconds < 60 ? seconds : Int((Double(seconds) / 60).rounded()) * 60))
    }

    // MARK: - Ingredients

    /// `2–3 cups`, the server's text, or nil (web `recipeAmountText`).
    public static func amount(_ ingredient: RecipeDetail.Ingredient, locale: Locale = .current) -> String? {
        if let text = ingredient.amountText { return text }
        guard let quantity = ingredient.amountQuantity else { return nil }
        let value = ingredient.amountQuantityMax.map { "\(number(quantity, locale: locale))–\(number($0, locale: locale))" }
            ?? number(quantity, locale: locale)
        return ingredient.amountUnit.map { "\(value) \($0)" } ?? value
    }

    /// `Butter · 2 tbsp` (web `ingredientTitle`).
    public static func title(_ ingredient: RecipeDetail.Ingredient, locale: Locale = .current) -> String {
        amount(ingredient, locale: locale).map { "\(ingredient.displayName) · \($0)" } ?? ingredient.displayName
    }

    /// The inventory match as words (web `inventoryMatchLabel`).
    public static func inventoryLabel(_ ingredient: RecipeDetail.Ingredient) -> String {
        switch ingredient.inventoryState {
        case .staple: return "Staple"
        case .missing: return "Missing from Inventory"
        case .uncertain: return "Inventory Match Uncertain"
        case .inStock:
            let relation = ingredient.inventoryRelation?.lowercased() ?? ""
            return relation == "exact" || relation == "normalized_name" ? "Exact Inventory Match" : "In Inventory"
        }
    }

    /// Whether the row reads as on hand: overrides first, uncertain counts as missing (web `ingredientDisplayStatus`).
    public static func isOnHand(_ ingredient: RecipeDetail.Ingredient) -> Bool {
        switch ingredient.overrideAvailability {
        case .have: true
        case .missing: false
        case nil: ingredient.inventoryState == .inStock || ingredient.inventoryState == .staple
        }
    }

    /// A caveat about the quantity on hand, if any (web `ingredientQuantityExplanation`).
    public static func quantityNote(_ detail: RecipeDetail, _ ingredient: RecipeDetail.Ingredient) -> String? {
        if detail.capabilities.quantities == .displayOnly || ingredient.quantityState == .displayOnly { return "Source quantity is display-only" }
        if detail.capabilities.quantities == .unknown || ingredient.quantityState == .unknown { return "Quantity sufficiency is unknown" }
        switch ingredient.quantitySufficiency {
        case .insufficient: return "Inventory quantity may be insufficient"
        case .unknown: return "Quantity sufficiency is unknown"
        case .sufficient: return nil
        }
    }

    /// The source line with its leading amount removed, shown only when it says more than the name (web `ingredientSourceDetail`).
    public static func sourceDetail(_ ingredient: RecipeDetail.Ingredient, locale: Locale = .current) -> String? {
        guard var text = ingredient.sourceText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let amount = amount(ingredient, locale: locale) {
            for candidate in amountCandidates(amount) where text.lowercased().hasPrefix(candidate.lowercased()) {
                let remainder = text.dropFirst(candidate.count)
                if remainder.isEmpty || remainder.first.map({ " ,.;:·—–-".contains($0) }) == true {
                    text = remainder.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:·—–-"))
                    break
                }
            }
        }
        return comparable(text) == comparable(ingredient.displayName) || text.isEmpty ? nil : text
    }

    /// The chips under an ingredient, in display order (web `IngredientSubtitle`).
    public static func chips(_ detail: RecipeDetail, _ ingredient: RecipeDetail.Ingredient) -> [String] {
        var chips = [inventoryLabel(ingredient)]
        if ingredient.optional == true { chips.append("Optional") }
        if let product = ingredient.overrideProductName ?? ingredient.matchedProductName { chips.append("Product: \(product)") }
        if let override = ingredient.overrideAvailability {
            chips.append("Your override: \(override == .have ? "have it" : "missing")")
        }
        if let note = quantityNote(detail, ingredient) { chips.append(note) }
        return chips
    }

    /// Everything VoiceOver reads for an ingredient row after its title.
    public static func accessibilityDetails(_ detail: RecipeDetail, _ ingredient: RecipeDetail.Ingredient, statedByState: Bool = false) -> String {
        var parts = chips(detail, ingredient)
        if statedByState {
            // The checklist already says "On hand" or "Not on hand", so the plain inventory label repeats it, and a quantity
            // caveat means nothing for something that is not in the house.
            if ingredient.overrideAvailability == nil, [.inStock, .missing].contains(ingredient.inventoryState),
               parts.first == inventoryLabel(ingredient), inventoryLabel(ingredient) != "Exact Inventory Match" {
                parts.removeFirst()
            }
            if !isOnHand(ingredient), let note = quantityNote(detail, ingredient) { parts.removeAll { $0 == note } }
        }
        if let source = sourceDetail(ingredient) { parts.append("Source: \(source)") }
        if let match = ingredient.closestMatchLabel { parts.append("Matched as \(match)") }
        return parts.joined(separator: ". ")
    }

    /// What VoiceOver reads after an ingredient's title: its state (on hand, not on hand, or a match EverShelf is unsure
    /// of, which the row draws as a question mark), then the chips, source and match. Content, so it is the value, not a hint.
    public static func spokenValue(_ detail: RecipeDetail, _ ingredient: RecipeDetail.Ingredient, checklist: Bool) -> String {
        var parts: [String] = []
        if checklist {
            if isOnHand(ingredient) {
                parts.append("On hand")
            } else if ingredient.overrideAvailability == nil, ingredient.inventoryState == .uncertain {
                parts.append("Match unsure")
            } else {
                parts.append("Not on hand")
            }
        }
        let details = accessibilityDetails(detail, ingredient, statedByState: checklist)
        if !details.isEmpty { parts.append(details) }
        return parts.joined(separator: ". ")
    }

    static let unitAliases: [[String]] = [
        ["tablespoon", "tablespoons", "tbsp", "tbs"], ["teaspoon", "teaspoons", "tsp"], ["cup", "cups", "c"],
        ["ounce", "ounces", "oz"], ["pound", "pounds", "lb", "lbs"], ["gram", "grams", "g"], ["kilogram", "kilograms", "kg"],
        ["milliliter", "milliliters", "ml"], ["liter", "liters", "l"],
    ]

    /// The amount plus its unit aliases, longest first (web `recipeAmountCandidates`).
    static func amountCandidates(_ amount: String) -> [String] {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        var candidates: Set = [trimmed]
        if let space = trimmed.lastIndex(of: " ") {
            let quantity = trimmed[..<space].trimmingCharacters(in: .whitespaces)
            let unit = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            if !quantity.isEmpty, let group = unitAliases.first(where: { $0.contains(unit) }) {
                group.forEach { candidates.insert("\(quantity) \($0)") }
            }
        }
        return candidates.sorted { $0.count > $1.count }
    }

    static func comparable(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Sections

    /// A titled run of ingredients.
    public struct IngredientSection: Equatable, Identifiable, Sendable {
        public var id: String
        /// Heading, or nil for a single unlabeled list.
        public var heading: String?
        /// Generated headings ("Section 2", "Other Ingredients") draw quieter than the recipe's own.
        public var headingIsGenerated: Bool
        public var ingredients: [RecipeDetail.Ingredient]
    }

    /// Ingredients in their groups, with any ungrouped ones last (web `recipeIngredientSections`).
    public static func ingredientSections(_ detail: RecipeDetail) -> [IngredientSection] {
        let flat = [IngredientSection(id: "flat-ingredients", heading: nil, headingIsGenerated: false, ingredients: detail.ingredients)]
        guard !detail.ingredientGroups.isEmpty else { return flat }
        let byKey = Dictionary(detail.ingredients.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var grouped = Set<String>()
        struct Raw { var key: String; var label: String?; var items: [RecipeDetail.Ingredient]; var orphaned: Bool }
        var raw: [Raw] = []
        for group in detail.ingredientGroups {
            let items = group.ingredientKeys.compactMap { byKey[$0] }
            items.forEach { grouped.insert($0.key) }
            if !items.isEmpty { raw.append(Raw(key: group.key, label: group.label, items: items, orphaned: false)) }
        }
        let orphans = detail.ingredients.filter { !grouped.contains($0.key) }
        if !orphans.isEmpty { raw.append(Raw(key: "other-ingredients", label: nil, items: orphans, orphaned: true)) }
        guard !raw.isEmpty else { return flat }
        return raw.enumerated().map { index, section in
            let heading = sectionHeading(section.label, index: index, count: raw.count, orphaned: section.orphaned)
            return IngredientSection(id: section.key, heading: heading?.label, headingIsGenerated: heading?.generated ?? false, ingredients: section.items)
        }
    }

    /// A group heading: its label, "Other Ingredients", nothing for a lone list, else "Section N" (web `recipeSectionHeading`).
    public static func sectionHeading(_ label: String?, index: Int, count: Int, orphaned: Bool = false) -> (label: String, generated: Bool)? {
        if let label { return (label, false) }
        if orphaned { return ("Other Ingredients", true) }
        if count == 1 { return nil }
        return ("Section \(index + 1)", true)
    }

    // MARK: - General

    /// One fact on the General tab.
    public struct Fact: Equatable, Identifiable, Sendable {
        public var id: String { label }
        public var label: String
        public var value: String
        /// SF Symbol.
        public var symbol: String
        /// Spoken value when it differs from the shown one.
        public var spokenValue: String?
    }

    /// The General tab's facts, in web order (`GeneralTab`); metadata facts only when the server has them.
    public static func facts(_ detail: RecipeDetail, locale: Locale = .current) -> [Fact] {
        let general = detail.general
        var facts: [Fact] = []
        func add(_ label: String, _ value: String?, _ symbol: String, spoken: String? = nil) {
            if let value, !value.isEmpty { facts.append(Fact(label: label, value: value, symbol: symbol, spokenValue: spoken)) }
        }
        if detail.capabilities.general != .none {
            add("Yield", yield(quantity: general.yieldQuantity, unit: general.yieldUnit, locale: locale), "person.2")
            add("Prep Time", duration(seconds: general.prepTimeSeconds), "timer", spoken: spokenDuration(seconds: general.prepTimeSeconds))
            add("Cook Time", duration(seconds: general.cookTimeSeconds), "flame", spoken: spokenDuration(seconds: general.cookTimeSeconds))
            add("Active Time", duration(seconds: general.activeTimeSeconds), "hand.raised", spoken: spokenDuration(seconds: general.activeTimeSeconds))
            add("Inactive / Rest Time", duration(seconds: general.inactiveTimeSeconds), "pause.circle", spoken: spokenDuration(seconds: general.inactiveTimeSeconds))
            add("Total Time", duration(seconds: general.totalTimeSeconds), "clock", spoken: spokenDuration(seconds: general.totalTimeSeconds))
            add("Difficulty", general.difficulty, "gauge.with.dots.needle.50percent")
            add("Category", general.primaryCategory, "fork.knife")
        }
        add("Source", detail.source.displayName, "book")
        add("Locale", detail.source.locale, "mappin.and.ellipse")
        add("Content Language", detail.source.contentLanguage, "character.bubble")
        if let freshness = freshness(detail, locale: locale) { add("Freshness", freshness, "arrow.clockwise") }
        return facts
    }

    /// `Current · Oct 3, 2026`, `Stale`, `Unknown · …`, or nil (web `GeneralTab` freshness pill).
    public static func freshness(_ detail: RecipeDetail, locale: Locale = .current) -> String? {
        let updated = detail.freshness.updatedAt.flatMap(parseDate).map { $0.formatted(.dateTime.month(.abbreviated).day().year().locale(locale)) }
        let state: String
        switch detail.freshness.isStale {
        case true?: state = "Stale"
        case false?: state = "Current"
        case nil:
            guard updated != nil else { return nil }
            state = "Unknown"
        }
        return [state, updated].compactMap { $0 }.joined(separator: " · ")
    }

    static func parseDate(_ text: String) -> Date? {
        if let date = HassDates.iso8601(text) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(text.prefix(10)))
    }
}
