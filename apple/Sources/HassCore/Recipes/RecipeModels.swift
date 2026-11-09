import Foundation

// Recipe data from the EverShelf integration's `evershelf.recipe_*` services, normalized the way the web
// dashboard does (`ha-sfenton-react-dash@9ac2a46:src/components/hass/recipes/recipeTypes.ts`).

// MARK: - Browse

/// How the Recipes grid is ranked (web `RecipeSort`).
public enum RecipeSort: String, CaseIterable, Sendable, Hashable, Identifiable {
    case availability, expiry, alphabetical
    public var id: String { rawValue }

    /// Option title in the Sort sheet (web `RecipeFloatingActions.tsx` `SORT_OPTIONS`).
    public var title: String {
        switch self {
        case .availability: "Ingredients Available"
        case .expiry: "Expiring Soon"
        case .alphabetical: "Alphabetical"
        }
    }

    /// Option description in the Sort sheet.
    public var subtitle: String {
        switch self {
        case .availability: "Prioritize recipes you can make from current inventory."
        case .expiry: "Prioritize recipes that use ingredients nearing expiration."
        case .alphabetical: "Sort recipe titles from A to Z."
        }
    }
}

/// One recipe card (web `RecipeCardSummary`).
public struct RecipeCard: Sendable, Hashable, Identifiable {
    public var id: Int
    /// Key used to de-duplicate pages and hydrated results.
    public var dedupeKey: String
    public var title: String
    public var imageURL: URL?
    public var thumbnailURL: URL?
    public var source: String
    /// Percent of required ingredients in stock, 0...100.
    public var coverage: Double
    public var matchedRequired: Int
    public var requiredTotal: Int
    public var soonestExpiryDays: Int?
    public var cookable: Bool

    public init(
        id: Int, dedupeKey: String? = nil, title: String, imageURL: URL? = nil, thumbnailURL: URL? = nil,
        source: String = "Unknown source", coverage: Double = 0, matchedRequired: Int = 0, requiredTotal: Int = 0,
        soonestExpiryDays: Int? = nil, cookable: Bool = false
    ) {
        self.id = id
        self.dedupeKey = dedupeKey ?? "recipe:\(id)"
        self.title = title
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.source = source
        self.coverage = coverage
        self.matchedRequired = matchedRequired
        self.requiredTotal = requiredTotal
        self.soonestExpiryDays = soonestExpiryDays
        self.cookable = cookable
    }

    /// The card's subtitle, e.g. `4 of 6 Ingredients` (web `RecipeCard.tsx`, in Title Case: direction G, Copy).
    public var coverageText: String { "\(matchedRequired) of \(requiredTotal) Ingredients" }

    /// The smaller image first, falling back to the full one.
    public var cardImageURL: URL? { thumbnailURL ?? imageURL }
}

/// The Recipes grid's query (web `RecipeBrowseCriteria`).
public struct RecipeBrowseCriteria: Sendable, Hashable {
    public var query: String
    public var sort: RecipeSort
    public var availabilityWeight: Double
    public var expiryWeight: Double
    public var minimumCoverage: Double
    /// When set, only recipes using ingredients that expire within this many days.
    public var expiringWithinDays: Int?

    public init(
        query: String = "", sort: RecipeSort = .availability, availabilityWeight: Double = 100,
        expiryWeight: Double = 25, minimumCoverage: Double = 0, expiringWithinDays: Int? = nil
    ) {
        self.query = query
        self.sort = sort
        self.availabilityWeight = availabilityWeight
        self.expiryWeight = expiryWeight
        self.minimumCoverage = minimumCoverage
        self.expiringWithinDays = expiringWithinDays
    }

    /// The query trimmed with runs of whitespace collapsed (web `normalizeRecipeQuery`).
    public var normalizedQuery: String {
        query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether a hydrated card still satisfies the filters (web `recipeMatchesCriteriaFilters`).
    public func matchesFilters(_ recipe: RecipeCard) -> Bool {
        if recipe.coverage < minimumCoverage { return false }
        if let days = expiringWithinDays {
            guard let soonest = recipe.soonestExpiryDays else { return false }
            return soonest >= 0 && soonest <= days
        }
        return true
    }
}

/// One page of browse results.
public struct RecipeBrowsePage: Sendable, Equatable {
    public var items: [RecipeCard]
    public var nextCursor: String?
    public var hasMore: Bool
    public var total: Int

    public init(items: [RecipeCard], nextCursor: String? = nil, hasMore: Bool = false, total: Int? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.total = total ?? items.count
    }
}

/// One poll of a remote-catalog hydration (web `RecipeHydrationEnvelope`).
public struct RecipeHydration: Sendable, Equatable {
    public var searchId: String
    public var status: String
    public var exhausted: Bool
    /// Milliseconds the server asks the client to wait before polling again.
    public var nextPollMilliseconds: Int?
    public var newItems: [RecipeCard]

    public init(searchId: String, status: String = "complete", exhausted: Bool = false, nextPollMilliseconds: Int? = nil, newItems: [RecipeCard] = []) {
        self.searchId = searchId
        self.status = status
        self.exhausted = exhausted
        self.nextPollMilliseconds = nextPollMilliseconds
        self.newItems = newItems
    }

    /// The hydration has nothing more to import.
    public var isComplete: Bool {
        exhausted || searchId.isEmpty || ["complete", "completed", "done", "exhausted"].contains(status.lowercased())
    }

    /// The hydration failed on the server.
    public var isFailed: Bool { status.lowercased() == "failed" }
}

// MARK: - Detail

/// A recipe's detail (web `RecipeDetail`, `schema_version` `recipe_detail_v1`). Only fields the app shows.
public struct RecipeDetail: Sendable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var source: Source
    public var primaryImageURL: URL?
    public var thumbnailURL: URL?
    public var general: General
    public var ingredients: [Ingredient]
    public var ingredientGroups: [IngredientGroup]
    public var ingredientsTruncated: Bool
    public var grocery: Grocery
    public var instructions: Instructions
    public var freshness: Freshness
    public var capabilities: Capabilities

    public init(
        id: Int, title: String, source: Source = .init(), primaryImageURL: URL? = nil, thumbnailURL: URL? = nil,
        general: General = .init(), ingredients: [Ingredient] = [], ingredientGroups: [IngredientGroup] = [],
        ingredientsTruncated: Bool = false, grocery: Grocery = .init(), instructions: Instructions = .init(),
        freshness: Freshness = .init(), capabilities: Capabilities = .init()
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.primaryImageURL = primaryImageURL
        self.thumbnailURL = thumbnailURL
        self.general = general
        self.ingredients = ingredients
        self.ingredientGroups = ingredientGroups
        self.ingredientsTruncated = ingredientsTruncated
        self.grocery = grocery
        self.instructions = instructions
        self.freshness = freshness
        self.capabilities = capabilities
    }

    /// Where the recipe came from.
    public struct Source: Sendable, Equatable {
        public var connector = ""
        public var label = ""
        public var attribution = ""
        public var canonicalURL: URL?
        public var locale: String?
        public var contentLanguage: String?

        public init(connector: String = "", label: String = "", attribution: String = "", canonicalURL: URL? = nil, locale: String? = nil, contentLanguage: String? = nil) {
            self.connector = connector
            self.label = label
            self.attribution = attribution
            self.canonicalURL = canonicalURL
            self.locale = locale
            self.contentLanguage = contentLanguage
        }

        /// Recipes from Cookidoo keep their steps on Cookidoo.
        public var isCookidoo: Bool { connector.lowercased() == "cookidoo" }

        /// The name shown as Source (web `GeneralTab`).
        public var displayName: String? {
            [attribution, label, connector].first { !$0.isEmpty }
        }
    }

    /// Yield, times and equipment.
    public struct General: Sendable, Equatable {
        public var yieldQuantity: Double?
        public var yieldUnit: String?
        public var prepTimeSeconds: Int?
        public var cookTimeSeconds: Int?
        public var activeTimeSeconds: Int?
        public var inactiveTimeSeconds: Int?
        public var totalTimeSeconds: Int?
        public var difficulty: String?
        public var primaryCategory: String?
        public var devices: [String] = []
        public var optionalDevices: [String] = []
        public var equipment: [String] = []

        public init(
            yieldQuantity: Double? = nil, yieldUnit: String? = nil, prepTimeSeconds: Int? = nil, cookTimeSeconds: Int? = nil,
            activeTimeSeconds: Int? = nil, inactiveTimeSeconds: Int? = nil, totalTimeSeconds: Int? = nil, difficulty: String? = nil,
            primaryCategory: String? = nil, devices: [String] = [], optionalDevices: [String] = [], equipment: [String] = []
        ) {
            self.yieldQuantity = yieldQuantity
            self.yieldUnit = yieldUnit
            self.prepTimeSeconds = prepTimeSeconds
            self.cookTimeSeconds = cookTimeSeconds
            self.activeTimeSeconds = activeTimeSeconds
            self.inactiveTimeSeconds = inactiveTimeSeconds
            self.totalTimeSeconds = totalTimeSeconds
            self.difficulty = difficulty
            self.primaryCategory = primaryCategory
            self.devices = devices
            self.optionalDevices = optionalDevices
            self.equipment = equipment
        }
    }

    /// Whether an ingredient is in the house, per EverShelf.
    public enum InventoryState: String, Sendable, Equatable { case inStock = "in_stock", missing, uncertain, staple }

    /// What the user said about an ingredient's availability.
    public enum AvailabilityOverride: String, Sendable, Equatable { case have, missing }

    /// EverShelf's confidence in the quantity on hand.
    public enum QuantityState: String, Sendable, Equatable { case known, displayOnly = "display_only", unknown }

    /// Whether the quantity on hand covers the recipe.
    public enum QuantitySufficiency: String, Sendable, Equatable { case sufficient, insufficient, unknown }

    /// One ingredient line.
    public struct Ingredient: Sendable, Equatable, Identifiable {
        /// `ri:<n>:<16 hex>`; sent back with grocery adds.
        public var key: String
        public var position: Int
        public var name: String
        public var displayName: String
        public var sourceText: String?
        public var optional: Bool?
        public var closestMatchLabel: String?
        public var overrideAvailability: AvailabilityOverride?
        public var overrideProductName: String?
        public var amountQuantity: Double?
        public var amountQuantityMax: Double?
        public var amountUnit: String?
        public var amountText: String?
        public var inventoryState: InventoryState
        public var inventoryRelation: String?
        public var matchedProductName: String?
        public var quantityState: QuantityState
        public var quantitySufficiency: QuantitySufficiency

        public var id: String { key }

        public init(
            key: String, position: Int, name: String, displayName: String? = nil, sourceText: String? = nil, optional: Bool? = nil,
            closestMatchLabel: String? = nil, overrideAvailability: AvailabilityOverride? = nil, overrideProductName: String? = nil,
            amountQuantity: Double? = nil, amountQuantityMax: Double? = nil, amountUnit: String? = nil, amountText: String? = nil,
            inventoryState: InventoryState = .uncertain, inventoryRelation: String? = nil, matchedProductName: String? = nil,
            quantityState: QuantityState = .unknown, quantitySufficiency: QuantitySufficiency = .unknown
        ) {
            self.key = key
            self.position = position
            self.name = name
            self.displayName = displayName ?? name
            self.sourceText = sourceText
            self.optional = optional
            self.closestMatchLabel = closestMatchLabel
            self.overrideAvailability = overrideAvailability
            self.overrideProductName = overrideProductName
            self.amountQuantity = amountQuantity
            self.amountQuantityMax = amountQuantityMax
            self.amountUnit = amountUnit
            self.amountText = amountText
            self.inventoryState = inventoryState
            self.inventoryRelation = inventoryRelation
            self.matchedProductName = matchedProductName
            self.quantityState = quantityState
            self.quantitySufficiency = quantitySufficiency
        }
    }

    /// A labelled run of ingredients, e.g. "For the sauce".
    public struct IngredientGroup: Sendable, Equatable {
        public var key: String
        public var label: String?
        public var ingredientKeys: [String]

        public init(key: String, label: String?, ingredientKeys: [String]) {
            self.key = key
            self.label = label
            self.ingredientKeys = ingredientKeys
        }
    }

    /// Grocery counts from the server.
    public struct Grocery: Sendable, Equatable {
        public var confirmedMissingCount = 0
        public var uncertainCount = 0
        public var blockedReason: String?

        public init(confirmedMissingCount: Int = 0, uncertainCount: Int = 0, blockedReason: String? = nil) {
            self.confirmedMissingCount = confirmedMissingCount
            self.uncertainCount = uncertainCount
            self.blockedReason = blockedReason
        }
    }

    /// One instruction step.
    public struct Step: Sendable, Equatable, Identifiable {
        public var key: String
        public var number: Int
        public var text: String
        public var id: String { key }

        public init(key: String, number: Int, text: String) {
            self.key = key
            self.number = number
            self.text = text
        }
    }

    /// A labelled run of steps.
    public struct StepGroup: Sendable, Equatable, Identifiable {
        public var key: String
        public var label: String?
        public var steps: [Step]
        public var id: String { key }

        public init(key: String, label: String?, steps: [Step]) {
            self.key = key
            self.label = label
            self.steps = steps
        }
    }

    /// The method.
    public struct Instructions: Sendable, Equatable {
        public var available = false
        public var groups: [StepGroup] = []
        public var fallbackURL: URL?
        public var truncated = false

        public init(available: Bool = false, groups: [StepGroup] = [], fallbackURL: URL? = nil, truncated: Bool = false) {
            self.available = available
            self.groups = groups
            self.fallbackURL = fallbackURL
            self.truncated = truncated
        }
    }

    /// When the recipe was last refreshed from its source.
    public struct Freshness: Sendable, Equatable {
        public var updatedAt: String?
        public var isStale: Bool?

        public init(updatedAt: String? = nil, isStale: Bool? = nil) {
            self.updatedAt = updatedAt
            self.isStale = isStale
        }
    }

    /// What the server can show or do for this recipe.
    public struct Capabilities: Sendable, Equatable {
        public enum General: String, Sendable { case full, partial, none }
        public enum Ingredients: String, Sendable { case checklist, namesOnly = "names_only", none }
        public enum Instructions: String, Sendable { case local, externalLink = "external_link", none }
        public enum Quantities: String, Sendable { case known, displayOnly = "display_only", unknown }
        public enum FeatureState: String, Sendable { case unsupported, unavailable }

        public var general: General = .none
        public var ingredients: Ingredients = .none
        public var instructions: Instructions = .none
        public var quantities: Quantities = .unknown
        public var groceryAdd = false
        public var groceryAddState: FeatureState?
        public var groceryAddReason: String?

        public init(
            general: General = .none, ingredients: Ingredients = .none, instructions: Instructions = .none,
            quantities: Quantities = .unknown, groceryAdd: Bool = false, groceryAddState: FeatureState? = nil, groceryAddReason: String? = nil
        ) {
            self.general = general
            self.ingredients = ingredients
            self.instructions = instructions
            self.quantities = quantities
            self.groceryAdd = groceryAdd
            self.groceryAddState = groceryAddState
            self.groceryAddReason = groceryAddReason
        }
    }
}

// MARK: - Results

/// A recipe service that answered with a failure body instead of data (web `RecipeServiceFailure`).
public struct RecipeServiceFailure: Error, Sendable, Equatable {
    /// The installed integration lacks the feature.
    public var unsupported: Bool
    public var message: String

    public init(unsupported: Bool, message: String) {
        self.unsupported = unsupported
        self.message = message
    }
}

/// The outcome of adding missing ingredients to the grocery list (web `RecipeGroceryResult`).
public struct RecipeGroceryResult: Sendable, Equatable {
    public struct Backend: Sendable, Equatable {
        public var added = 0, alreadyListed = 0, nowInStock = 0, unresolved = 0, failed = 0
        public init(added: Int = 0, alreadyListed: Int = 0, nowInStock: Int = 0, unresolved: Int = 0, failed: Int = 0) {
            self.added = added
            self.alreadyListed = alreadyListed
            self.nowInStock = nowInStock
            self.unresolved = unresolved
            self.failed = failed
        }
    }

    public struct Mirror: Sendable, Equatable {
        public var added = 0, alreadyPresent = 0, skipped = 0, failed = 0
        public init(added: Int = 0, alreadyPresent: Int = 0, skipped: Int = 0, failed: Int = 0) {
            self.added = added
            self.alreadyPresent = alreadyPresent
            self.skipped = skipped
            self.failed = failed
        }
    }

    public var success: Bool
    public var outcomesTruncated: Bool
    public var backend: Backend
    public var backendMessage: String?
    /// Home Assistant's grocery `todo` list mirror; nil when the server did not report one.
    public var mirror: Mirror?
    public var mirrorMessage: String?

    public init(success: Bool, outcomesTruncated: Bool = false, backend: Backend = .init(), backendMessage: String? = nil, mirror: Mirror? = nil, mirrorMessage: String? = nil) {
        self.success = success
        self.outcomesTruncated = outcomesTruncated
        self.backend = backend
        self.backendMessage = backendMessage
        self.mirror = mirror
        self.mirrorMessage = mirrorMessage
    }
}
