import Foundation

/// Normalizes `evershelf.recipe_*` responses into ``RecipeModels`` the way the web does
/// (`ha-sfenton-react-dash@9ac2a46:src/components/hass/recipes/recipeTypes.ts`): tolerant of snake or camel
/// keys and loose types, strict about identifiers, and bounded so a bad payload cannot flood the UI.
public enum RecipeParsing {
    // MARK: - Limits (recipeTypes.ts:500-515)

    static let maxIngredients = 200
    static let maxIngredientGroups = 50
    static let maxInstructionGroups = 50
    static let maxInstructionSteps = 100

    // MARK: - Envelopes

    /// The service result's payload: Home Assistant wraps it in `response` (web `recipeServiceResponse`).
    public static func payload(_ result: JSONValue) -> JSONValue {
        guard case .object = result else { return result }
        return result.first("response", "service_response") ?? result
    }

    /// A card, or nil when it lacks a positive id or a title (web `normalizeRecipeCard`).
    public static func card(_ value: JSONValue) -> RecipeCard? {
        guard case .object = value else { return nil }
        guard let rawId = value.first("id", "recipe_id")?.finiteNumber else { return nil }
        let id = Int(rawId.rounded())
        let title = value.first("title", "name")?.text ?? ""
        guard id > 0, !title.isEmpty else { return nil }
        let requiredTotal = value.first("required_total", "requiredTotal").nonNegativeInt ?? 0
        let rawMatched = value.first("matched_required", "matchedRequired").nonNegativeInt ?? 0
        let soonest = value.first("soonest_expiry_days", "soonestExpiryDays")?.finiteNumber
        return RecipeCard(
            id: id,
            dedupeKey: value.first("dedupe_key", "dedupeKey")?.text,
            title: title,
            imageURL: value.first("image_url", "imageUrl")?.text.flatMap(httpURL),
            thumbnailURL: value.first("thumbnail_url", "thumbnailUrl")?.text.flatMap(httpURL),
            source: value.first("source", "provider")?.text ?? "Unknown source",
            coverage: coveragePercent(value.first("coverage")?.finiteNumber ?? 0),
            matchedRequired: requiredTotal > 0 ? min(requiredTotal, rawMatched) : rawMatched,
            requiredTotal: requiredTotal,
            soonestExpiryDays: soonest.map { Int($0.rounded()) },
            cookable: value.first("cookable")?.flag ?? false
        )
    }

    /// A browse page (web `normalizeRecipeBrowseEnvelope`).
    public static func browsePage(_ result: JSONValue) -> RecipeBrowsePage {
        let record = payload(result)
        let items = cards(record.first("items", "recipes"))
        let cursor = record.first("next_cursor", "nextCursor")?.text
        return RecipeBrowsePage(
            items: items,
            nextCursor: cursor,
            hasMore: record.first("has_more", "hasMore")?.flag ?? (cursor != nil),
            total: record.first("total").nonNegativeInt ?? items.count
        )
    }

    /// Recommended cards for the Food hub carousel (web `normalizeRecipeRecommendationsEnvelope`).
    public static func recommendations(_ result: JSONValue) -> [RecipeCard] {
        cards(payload(result).first("items", "recipes"))
    }

    /// A hydration poll (web `normalizeRecipeHydrationEnvelope`).
    public static func hydration(_ result: JSONValue) -> RecipeHydration {
        let record = payload(result)
        let poll = record.first("next_poll_ms", "nextPollMs")?.finiteNumber
        return RecipeHydration(
            searchId: record.first("search_id", "searchId")?.text ?? "",
            status: record.first("status")?.text ?? "complete",
            exhausted: record.first("remote_exhausted", "remoteExhausted", "exhausted")?.flag ?? false,
            nextPollMilliseconds: poll.map { max(0, Int($0.rounded())) },
            newItems: cards(record.first("new_items", "newItems", "items"))
        )
    }

    /// A detail result: the detail, or the failure the server reported (web `normalizeRecipeDetailServiceResult`).
    public static func detailResult(_ result: JSONValue) -> Result<RecipeDetail, RecipeServiceFailure> {
        let record = payload(result)
        guard case .object = record else { return .failure(invalid("recipe detail")) }
        if record.first("success")?.bool == false { return .failure(failure(record)) }
        guard let detail = record.first("detail", "recipe_detail", "recipeDetail").flatMap(detail) else {
            return .failure(invalid("recipe detail"))
        }
        return .success(detail)
    }

    /// A grocery add result (web `normalizeRecipeGroceryServiceResult`).
    public static func groceryResult(_ result: JSONValue) -> Result<RecipeGroceryResult, RecipeServiceFailure> {
        let record = payload(result)
        guard case .object = record else { return .failure(invalid("grocery")) }
        let partial = record.first("partial_failure", "partialFailure")?.flag ?? false
        if record.first("success")?.bool == false, !partial { return .failure(failure(record)) }

        let summary = record.first("summary") ?? .object([:])
        let rawBackend = summary.first("backend").flatMap(\.objectValue).map(JSONValue.object) ?? summary
        let haMirror = record.first("ha_mirror", "haMirror") ?? .object([:])
        let rawMirror = summary.first("ha_mirror", "haMirror").flatMap(\.objectValue).map(JSONValue.object)
            ?? haMirror.first("summary") ?? .object([:])
        let backendRecord = record.first("backend") ?? .object([:])
        let hasMirror = !(rawMirror.objectValue ?? [:]).isEmpty || !(haMirror.objectValue ?? [:]).isEmpty
        func count(_ value: JSONValue, _ keys: String...) -> Int { keys.lazy.compactMap { value[$0].nonNegativeInt }.first ?? 0 }

        return .success(RecipeGroceryResult(
            success: record.first("success")?.flag ?? false,
            outcomesTruncated: record.first("outcomes_truncated", "outcomesTruncated")?.flag ?? false,
            backend: .init(
                added: count(rawBackend, "added"),
                alreadyListed: count(rawBackend, "already_listed", "alreadyListed"),
                nowInStock: count(rawBackend, "now_in_stock", "nowInStock"),
                unresolved: count(rawBackend, "unresolved"),
                failed: count(rawBackend, "failed")
            ),
            backendMessage: (backendRecord.first("message", "error") ?? rawBackend.first("message", "error")
                ?? record.first("backend_message", "backendMessage", "backend_error", "backendError"))?.text.map { bounded($0, 500) },
            mirror: hasMirror ? .init(
                added: count(rawMirror, "added"),
                alreadyPresent: count(rawMirror, "already_present", "alreadyPresent"),
                skipped: count(rawMirror, "skipped"),
                failed: count(rawMirror, "failed")
            ) : nil,
            mirrorMessage: (haMirror.first("message", "error") ?? rawMirror.first("message", "error")
                ?? record.first("ha_mirror_message", "haMirrorMessage"))?.text.map { bounded($0, 500) }
        ))
    }

    // MARK: - Detail

    /// A `recipe_detail_v1` detail, or nil when the schema, id or title is missing (web `normalizeRecipeDetail`).
    public static func detail(_ value: JSONValue) -> RecipeDetail? {
        guard case .object = value,
              value.first("schema_version", "schemaVersion")?.text == "recipe_detail_v1",
              let id = value.first("id", "recipe_id", "recipeId").integer(minimum: 1),
              let title = value.first("title", "name")?.text.map({ bounded($0, 400) }) else { return nil }

        let sourceRecord = value.first("source") ?? .object([:])
        let images = value.first("images") ?? .object([:])
        let general = value.first("general") ?? .object([:])
        let yield = general.first("yield") ?? .object([:])
        let instructionRecord = value.first("instructions") ?? .object([:])
        let freshness = value.first("freshness") ?? .object([:])
        let caps = value.first("capabilities") ?? .object([:])

        let connector = sourceRecord.first("connector")?.text.map { bounded($0, 80) } ?? ""
        let canonicalURL = sourceRecord.first("canonical_url", "canonicalUrl")?.text.flatMap(httpURL)
        let fallbackURL = instructionRecord.first("fallback_url", "fallbackUrl")?.text.flatMap(httpURL)
        let cookidoo = connector.lowercased() == "cookidoo"
        let requestedInstructions = RecipeDetail.Capabilities.Instructions(rawValue: caps.first("instructions")?.string ?? "") ?? .none
        let instructionCapability: RecipeDetail.Capabilities.Instructions = cookidoo
            ? ((fallbackURL ?? canonicalURL) != nil ? .externalLink : .none)
            : requestedInstructions

        var groups: [RecipeDetail.StepGroup] = []
        var instructionsTruncated = false
        if !cookidoo, instructionCapability == .local {
            let flat = steps(instructionRecord.first("steps"))
            let grouped = stepGroups(
                instructionRecord.first("groups", "instruction_groups", "instructionGroups", "authorized_groups", "authorizedGroups")
                    ?? value.first("instruction_groups", "instructionGroups"),
                flatSteps: flat.steps
            )
            instructionsTruncated = flat.unsafe || grouped.unsafe
            groups = grouped.groups.isEmpty && !flat.steps.isEmpty
                ? [RecipeDetail.StepGroup(key: "flat-instructions", label: nil, steps: flat.steps.enumerated().map {
                    RecipeDetail.Step(key: "flat-instruction-\($0.offset)", number: $0.offset + 1, text: $0.element)
                })]
                : grouped.groups
        }

        let parsedIngredients = ingredients(value.first("ingredients"))
        let ingredientGroups = ingredientGroups(value.first("ingredient_groups", "ingredientGroups"), ingredients: parsedIngredients.ingredients)
        let grocery = grocery(value.first("grocery", "grocery_state", "groceryState"), ingredients: parsedIngredients.ingredients)
        let devices = textList(general.first("devices"))
        let deviceKeys = Set(devices.map { $0.lowercased() })

        return RecipeDetail(
            id: id,
            title: title,
            source: .init(
                connector: connector,
                label: sourceRecord.first("label")?.text.map { bounded($0, 160) } ?? "",
                attribution: sourceRecord.first("attribution")?.text.map { bounded($0, 160) } ?? "",
                canonicalURL: canonicalURL,
                locale: sourceRecord.first("locale")?.text.map { bounded($0, 16) },
                contentLanguage: sourceRecord.first("content_language", "contentLanguage")?.text.map { bounded($0, 20) }
            ),
            primaryImageURL: images.first("primary")?.text.flatMap(httpURL),
            thumbnailURL: images.first("thumbnail")?.text.flatMap(httpURL),
            general: .init(
                yieldQuantity: yield.first("quantity")?.finiteNumber.flatMap { $0 >= 0 ? $0 : nil },
                yieldUnit: yield.first("unit")?.text.map { bounded($0, 80) },
                prepTimeSeconds: general.first("prep_time_seconds", "prepTimeSeconds").integer(minimum: 0),
                cookTimeSeconds: general.first("cook_time_seconds", "cookTimeSeconds").integer(minimum: 0),
                activeTimeSeconds: general.first("active_time_seconds", "activeTimeSeconds").integer(minimum: 0),
                inactiveTimeSeconds: general.first("inactive_time_seconds", "inactiveTimeSeconds").integer(minimum: 0),
                totalTimeSeconds: general.first("total_time_seconds", "totalTimeSeconds").integer(minimum: 0),
                difficulty: general.first("difficulty")?.text.map { bounded($0, 80) },
                primaryCategory: general.first("primary_category", "primaryCategory")?.text.map { bounded($0, 160) },
                devices: devices,
                optionalDevices: textList(general.first("optional_devices", "optionalDevices")).filter { !deviceKeys.contains($0.lowercased()) },
                equipment: (general.first("equipment")?.array ?? []).prefix(50).compactMap { $0.text.map { bounded($0, 120) } }
            ),
            ingredients: parsedIngredients.ingredients,
            ingredientGroups: ingredientGroups,
            ingredientsTruncated: parsedIngredients.unsafe || (value.first("ingredients_truncated", "ingredientsTruncated")?.flag ?? false),
            grocery: grocery,
            instructions: .init(
                available: instructionCapability == .local && !groups.isEmpty && (instructionRecord.first("available")?.flag ?? true),
                groups: groups,
                fallbackURL: cookidoo ? (fallbackURL ?? canonicalURL) : fallbackURL,
                truncated: cookidoo ? false : (instructionsTruncated || (instructionRecord.first("truncated")?.flag ?? false))
            ),
            freshness: .init(
                updatedAt: (freshness.first("updated_at", "updatedAt") ?? freshness.first("retrieved_at", "retrievedAt"))?.text,
                isStale: freshness.first("is_stale", "isStale")?.flag
            ),
            capabilities: .init(
                general: .init(rawValue: caps.first("general")?.string ?? "") ?? .none,
                ingredients: .init(rawValue: caps.first("ingredients")?.string ?? "") ?? .none,
                instructions: instructionCapability,
                quantities: .init(rawValue: caps.first("quantities")?.string ?? "") ?? .unknown,
                groceryAdd: caps.first("grocery_add", "groceryAdd")?.flag ?? false,
                groceryAddState: .init(rawValue: caps.first("grocery_add_state", "groceryAddState")?.string ?? ""),
                groceryAddReason: caps.first("grocery_add_reason", "groceryAddReason")?.text.map { bounded($0, 160) }
            )
        )
    }

    // MARK: - Ingredients

    nonisolated(unsafe) static let ingredientKeyPattern = #/^ri:\d+:[a-f0-9]{16}$/#
    nonisolated(unsafe) static let safeKeyPattern = #/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/#

    static func ingredient(_ value: JSONValue) -> RecipeDetail.Ingredient? {
        guard case .object = value else { return nil }
        let key = value.first("key", "ingredient_key", "ingredientKey")?.text.map { bounded($0, 128) } ?? ""
        guard key.wholeMatch(of: ingredientKeyPattern) != nil,
              let position = value.first("position").integer(minimum: 0),
              let name = value.first("name")?.text.map({ bounded($0, 200) }) else { return nil }
        let amount = value.first("amount") ?? .object([:])
        let inventory = value.first("inventory") ?? .object([:])
        let override = value.first("user_override", "userOverride")
        let matched = inventory.first("matched_product", "matchedProduct")
        let selected = override?.first("selected_product", "selectedProduct")
        let closest = value.first("closest_match", "closestMatch")
        let closestSource = closest?.first("mapping_source", "mappingSource")?.string
        return RecipeDetail.Ingredient(
            key: key,
            position: position,
            name: name,
            displayName: value.first("display_name", "displayName")?.text.map { bounded($0, 200) },
            sourceText: value.first("source_text", "sourceText")?.text.map { bounded($0, 500) },
            optional: value.firstPresent("source_optional", "sourceOptional", "optional")?.flag,
            closestMatchLabel: ["taxonomy_alias", "taxonomy_slug", "canonical_slug"].contains(closestSource ?? "")
                ? closest?.first("label")?.text.map { bounded($0, 200) } : nil,
            overrideAvailability: override?.first("availability")?.string.flatMap(RecipeDetail.AvailabilityOverride.init(rawValue:)),
            overrideProductName: selected?.first("id", "product_id", "productId").integer(minimum: 1) != nil
                ? selected?.first("name")?.text.map { bounded($0, 200) } : nil,
            amountQuantity: amount.first("quantity")?.finiteNumber.flatMap { $0 >= 0 ? $0 : nil },
            amountQuantityMax: amount.first("quantity_max", "quantityMax")?.finiteNumber.flatMap { $0 >= 0 ? $0 : nil },
            amountUnit: amount.first("unit")?.text.map { bounded($0, 80) },
            amountText: amount.first("text")?.text.map { bounded($0, 160) },
            inventoryState: inventory.first("state")?.string.flatMap(RecipeDetail.InventoryState.init(rawValue:)) ?? .uncertain,
            inventoryRelation: inventory.first("relation")?.text.map { bounded($0, 80) },
            matchedProductName: matched?.first("id", "product_id", "productId").integer(minimum: 1) != nil
                ? matched?.first("name")?.text.map { bounded($0, 200) } : nil,
            quantityState: inventory.first("quantity_state", "quantityState")?.string.flatMap(RecipeDetail.QuantityState.init(rawValue:)) ?? .unknown,
            quantitySufficiency: inventory.first("quantity_sufficiency", "quantitySufficiency")?.string
                .flatMap(RecipeDetail.QuantitySufficiency.init(rawValue:)) ?? .unknown
        )
    }

    /// Ingredients with duplicates and bad rows dropped; `unsafe` marks a list that lost rows (web `normalizeRecipeIngredients`).
    static func ingredients(_ value: JSONValue?) -> (ingredients: [RecipeDetail.Ingredient], unsafe: Bool) {
        guard let array = value?.array else { return ([], value != nil && value != .null) }
        var keys = Set<String>(), positions = Set<Int>()
        var unsafe = array.count > maxIngredients
        var result: [RecipeDetail.Ingredient] = []
        for candidate in array.prefix(maxIngredients) {
            guard let item = ingredient(candidate), !keys.contains(item.key), !positions.contains(item.position) else {
                unsafe = true
                continue
            }
            keys.insert(item.key)
            positions.insert(item.position)
            result.append(item)
        }
        return (result, unsafe)
    }

    /// Ingredient groups; any inconsistency drops grouping entirely (web `normalizeRecipeIngredientGroups`).
    static func ingredientGroups(_ value: JSONValue?, ingredients: [RecipeDetail.Ingredient]) -> [RecipeDetail.IngredientGroup] {
        guard let array = value?.array, !array.isEmpty, array.count <= maxIngredientGroups else { return [] }
        let index = Dictionary(uniqueKeysWithValues: ingredients.enumerated().map { ($0.element.key, ($0.offset, $0.element)) })
        var seenGroups = Set<String>(), seenIngredients = Set<String>()
        var prior = -1, references = 0
        var groups: [RecipeDetail.IngredientGroup] = []
        for (arrayIndex, candidate) in array.enumerated() {
            let key = candidate.first("key", "group_key", "groupKey")?.text.map { bounded($0, 128) } ?? ""
            guard case .object = candidate, key.wholeMatch(of: safeKeyPattern) != nil, !seenGroups.contains(key),
                  candidate.first("index").integer(minimum: 0) == arrayIndex,
                  let rawKeys = candidate.first("ingredient_keys", "ingredientKeys")?.array,
                  !rawKeys.isEmpty, rawKeys.count <= maxIngredients else { return [] }
            let positions = candidate.first("positions")
            if let positions, positions.array == nil { return [] }
            if let positions = positions?.array, positions.count != rawKeys.count { return [] }
            var keys: [String] = []
            for (referenceIndex, raw) in rawKeys.enumerated() {
                let ingredientKey = raw.text.map { bounded($0, 128) } ?? ""
                guard ingredientKey.wholeMatch(of: ingredientKeyPattern) != nil, let match = index[ingredientKey],
                      !seenIngredients.contains(ingredientKey), match.0 > prior else { return [] }
                if let positions = positions?.array, positions[referenceIndex].integer(minimum: 0) != match.1.position { return [] }
                keys.append(ingredientKey)
                seenIngredients.insert(ingredientKey)
                prior = match.0
                references += 1
                if references > maxIngredients { return [] }
            }
            seenGroups.insert(key)
            groups.append(.init(key: key, label: candidate.firstPresent("label", "title")?.text.map { bounded($0, 160) }, ingredientKeys: keys))
        }
        return groups
    }

    static func grocery(_ value: JSONValue?, ingredients: [RecipeDetail.Ingredient]) -> RecipeDetail.Grocery {
        let record = value ?? .object([:])
        let counts = record.first("state_counts", "stateCounts", "counts") ?? .object([:])
        let missing = (record.first("confirmed_missing_count", "confirmedMissingCount", "missing_count", "missingCount",
                                    "confirmed_missing", "confirmedMissing", "missing")
            ?? counts.first("confirmed_missing", "confirmedMissing", "missing")).integer(minimum: 0)
        let uncertain = (record.first("uncertain_count", "uncertainCount", "uncertain") ?? counts.first("uncertain")).integer(minimum: 0)
        return .init(
            confirmedMissingCount: missing ?? ingredients.filter { $0.inventoryState == .missing }.count,
            uncertainCount: uncertain ?? ingredients.filter { $0.inventoryState == .uncertain }.count,
            blockedReason: record.first("blocked_reason", "blockedReason")?.text.map { bounded($0, 160) }
        )
    }

    // MARK: - Instructions

    static func steps(_ value: JSONValue?) -> (steps: [String], unsafe: Bool) {
        guard let value, value != .null else { return ([], false) }
        guard let array = value.array else { return ([], true) }
        var unsafe = array.count > maxInstructionSteps
        var result: [String] = []
        for candidate in array.prefix(maxInstructionSteps) {
            let raw = candidate.objectValue != nil ? candidate.first("text") : candidate
            guard let text = raw?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                unsafe = true
                continue
            }
            if text.count > 2000 { unsafe = true }
            result.append(String(text.prefix(2000)))
        }
        return (result, unsafe)
    }

    /// Instruction groups as explicit steps or positions into the flat list (web `normalizeRecipeInstructionGroups`).
    static func stepGroups(_ value: JSONValue?, flatSteps: [String]) -> (groups: [RecipeDetail.StepGroup], unsafe: Bool) {
        guard let value, value != .null else { return ([], false) }
        guard let array = value.array, array.count <= maxInstructionGroups else { return ([], true) }
        if array.isEmpty { return ([], false) }
        var seenGroups = Set<String>(), seenSteps = Set<String>(), seenPositions = Set<Int>()
        var total = 0
        var groups: [RecipeDetail.StepGroup] = []
        for (groupIndex, candidate) in array.enumerated() {
            let key = candidate.first("key", "group_key", "groupKey")?.text.map { bounded($0, 128) } ?? ""
            let rawSteps = candidate["steps"]
            let rawPositions = candidate.first("step_positions", "stepPositions")?.array
            let usesPositions = rawSteps == nil && rawPositions != nil
            guard case .object = candidate, key.wholeMatch(of: safeKeyPattern) != nil, !seenGroups.contains(key),
                  candidate.first("index").integer(minimum: 0) == groupIndex,
                  rawSteps?.array.map({ !$0.isEmpty }) ?? (usesPositions && !(rawPositions ?? []).isEmpty) else { return ([], true) }
            var steps: [RecipeDetail.Step] = []
            if usesPositions {
                var previous = -1
                for raw in rawPositions ?? [] {
                    guard let position = raw.integer(minimum: 0), position > previous, position < flatSteps.count,
                          !seenPositions.contains(position) else { return ([], true) }
                    total += 1
                    if total > maxInstructionSteps { return ([], true) }
                    seenPositions.insert(position)
                    steps.append(.init(key: "instruction-step-\(groupIndex)-\(position)", number: position + 1, text: flatSteps[position]))
                    previous = position
                }
            } else {
                for (stepIndex, raw) in (rawSteps?.array ?? []).enumerated() {
                    let stepKey = raw.first("key", "step_key", "stepKey")?.text.map { bounded($0, 128) } ?? ""
                    let rawNumber = raw.firstPresent("number")
                    let number = rawNumber.integer(minimum: 1)
                    guard case .object = raw, stepKey.wholeMatch(of: safeKeyPattern) != nil, !seenSteps.contains(stepKey),
                          raw.first("index").integer(minimum: 0) == stepIndex,
                          rawNumber == nil || rawNumber == .null || rawNumber == .string("") || number != nil,
                          let text = raw.first("text")?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          text.count <= 2000 else { return ([], true) }
                    total += 1
                    if total > maxInstructionSteps { return ([], true) }
                    seenSteps.insert(stepKey)
                    steps.append(.init(key: stepKey, number: number ?? stepIndex + 1, text: text))
                }
            }
            seenGroups.insert(key)
            groups.append(.init(key: key, label: candidate.firstPresent("label", "title")?.text.map { bounded($0, 160) }, steps: steps))
        }
        if !seenPositions.isEmpty, seenPositions.count != flatSteps.count { return ([], true) }
        return (groups, false)
    }

    // MARK: - Failures

    /// The failure a `success: false` body describes (web `normalizeRecipeServiceFailure`).
    static func failure(_ record: JSONValue) -> RecipeServiceFailure {
        let kind = record.first("error_kind", "errorKind")?.text
        let code = record.first("error")?.text
        let unsupported = kind == "unsupported" || (kind == nil && code == "unsupported_capability")
        let fallback = unsupported
            ? "The installed EverShelf/ha-evershelf version does not support this recipe feature."
            : "EverShelf could not complete the recipe request."
        return .init(unsupported: unsupported, message: record.first("message", "error")?.text.map { bounded($0, 500) } ?? fallback)
    }

    static func invalid(_ what: String) -> RecipeServiceFailure {
        .init(unsupported: false, message: "EverShelf returned an invalid \(what) response.")
    }

    // MARK: - Values

    static func cards(_ value: JSONValue?) -> [RecipeCard] { (value?.array ?? []).compactMap(card) }

    /// 0...1 fractions become percentages; the result is clamped to 0...100.
    static func coveragePercent(_ value: Double) -> Double {
        let percent = value >= 0 && value <= 1 ? value * 100 : value
        return min(100, max(0, percent))
    }

    static func bounded(_ text: String, _ maximum: Int) -> String { String(text.prefix(maximum)) }

    /// An http(s) URL, or nil.
    static func httpURL(_ text: String) -> URL? {
        guard text.count <= 2048, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// Up to 50 distinct (case-insensitive) non-empty strings of at most 120 characters.
    static func textList(_ value: JSONValue?) -> [String] {
        var seen = Set<String>()
        return (value?.array ?? []).prefix(50).compactMap { $0.text.map { bounded($0, 120) } }.filter { seen.insert($0.lowercased()).inserted }
    }
}

// MARK: - Loose JSON access

extension JSONValue {
    /// The first non-null value among `keys` (web `firstValue`).
    func first(_ keys: String...) -> JSONValue? {
        for key in keys { if let value = self[key], value != .null { return value } }
        return nil
    }

    /// The first present value among `keys`, null included (web `firstPresentValue`).
    func firstPresent(_ keys: String...) -> JSONValue? {
        for key in keys { if let value = self[key] { return value } }
        return nil
    }

    /// The object's members, if this is an object.
    var objectValue: [String: JSONValue]? { if case let .object(value) = self { value } else { nil } }

    /// A trimmed non-empty string (web `textValue` / `nullableText`).
    var text: String? {
        guard case let .string(value) = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A boolean from a bool, number or yes/no style string (web `booleanValue`).
    var flag: Bool? {
        switch self {
        case let .bool(value): value
        case let .number(value): value != 0
        case let .string(value):
            switch value.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "on", "yes", "1": true
            case "false", "off", "no", "0": false
            default: nil
            }
        default: nil
        }
    }
}

extension Optional where Wrapped == JSONValue {
    /// A rounded, non-negative integer (web `nonNegativeInteger`).
    var nonNegativeInt: Int? { self?.finiteNumber.map { max(0, Int($0.rounded())) } }

    /// An exact integer at or above `minimum` (web `nullableInteger`).
    func integer(minimum: Int) -> Int? {
        guard let number = self?.finiteNumber, number == number.rounded(), number >= Double(minimum), abs(number) < 1e15 else { return nil }
        return Int(number)
    }
}

extension JSONValue {
    /// An exact integer at or above `minimum`.
    func integer(minimum: Int) -> Int? { Optional(self).integer(minimum: minimum) }
}
