import Foundation
import HassCore
import Observation

/// One open recipe: its detail and the grocery action (web `useRecipeDetailModalController`).
@MainActor
@Observable
final class RecipeDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded(RecipeDetail)
        case failed(message: String, unsupported: Bool)
    }

    enum Grocery: Equatable {
        case idle
        case adding
        case added(message: String)
        case failed(message: String)
    }

    /// The detail sheet's tabs (web `RECIPE_DETAIL_TABS`).
    enum Tab: String, CaseIterable, Identifiable {
        case general, ingredients, instructions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .ingredients: "Ingredients"
            case .instructions: "Instructions"
            }
        }
        var symbol: String {
            switch self {
            case .general: "info.circle"
            case .ingredients: "checklist"
            case .instructions: "frying.pan"
            }
        }
    }

    let recipe: RecipeCard
    private(set) var phase: Phase
    private(set) var grocery: Grocery = .idle
    /// Ingredients this sheet already sent to groceries.
    private(set) var addedKeys: Set<String> = []
    var tab: Tab = .general

    @ObservationIgnored private let service: (any RecipeServing)?
    @ObservationIgnored private let onLoad: (RecipeDetail) -> Void
    @ObservationIgnored private var commandKey: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var groceryTask: Task<Void, Never>?

    /// The detail when loaded.
    var detail: RecipeDetail? { if case let .loaded(detail) = phase { detail } else { nil } }

    init(recipe: RecipeCard, service: (any RecipeServing)?, cached: RecipeDetail? = nil, onLoad: @escaping (RecipeDetail) -> Void = { _ in }) {
        self.recipe = recipe
        self.service = service
        self.onLoad = onLoad
        phase = cached.map(Phase.loaded) ?? .loading
    }

    /// Loads (or quietly refreshes) the detail.
    func load() {
        guard let service, task == nil else { return }
        let id = recipe.id
        task = Task { [weak self] in
            do {
                let detail = try await service.detail(recipeId: id)
                guard let self else { return }
                self.phase = .loaded(detail)
                self.onLoad(detail)
            } catch let failure as RecipeServiceFailure {
                self?.failIfEmpty(failure.unsupported ? Self.unsupportedMessage : failure.message, unsupported: failure.unsupported)
            } catch {
                self?.failIfEmpty(Self.message(error, fallback: "Unable to load recipe details."), unsupported: false)
            }
            self?.task = nil
        }
    }

    /// Why the grocery button is disabled, or nil.
    var groceryDisabledReason: String? {
        guard let detail else { return nil }
        if case .added = grocery { return nil }
        return RecipeGroceryPolicy.disabledReason(detail, loading: grocery == .adding, added: addedKeys)
    }

    /// Sends the effectively missing ingredients to the grocery list (web `addMissingIngredients`).
    func addMissingToGroceries() {
        guard let detail, let service, grocery != .adding, RecipeGroceryPolicy.disabledReason(detail, added: addedKeys) == nil else { return }
        let missing = RecipeGroceryPolicy.actionableMissing(detail, added: addedKeys)
        guard !missing.isEmpty, missing.count <= RecipeGroceryPolicy.maxSelections else { return }
        // Reused across retries so a repeated tap after a lost response is replayed, not doubled.
        let key = commandKey ?? RecipeServiceData.idempotencyKey(recipeId: detail.id)
        commandKey = key
        grocery = .adding
        groceryTask = Task { [weak self] in
            do {
                let result = try await service.addToGroceries(recipeId: detail.id, ingredients: missing, idempotencyKey: key)
                guard let self else { return }
                let feedback = RecipeGroceryPolicy.feedback(result)
                if result.backend.failed > 0 || result.backend.unresolved > 0 || feedback.success { self.commandKey = nil }
                if feedback.success {
                    self.addedKeys.formUnion(missing.map(\.key))
                    self.grocery = .added(message: feedback.message)
                } else {
                    self.grocery = .failed(message: feedback.message)
                }
            } catch let failure as RecipeServiceFailure {
                self?.grocery = .failed(message: failure.unsupported ? RecipeGroceryPolicy.unsupportedMessage : failure.message)
            } catch {
                self?.grocery = .failed(message: Self.message(error, fallback: "Unable to add missing ingredients to groceries."))
            }
        }
    }

    /// Waits for an in-flight load or grocery add (tests).
    func settle() async {
        await task?.value
        await groceryTask?.value
    }

    static let unsupportedMessage = "The installed EverShelf/ha-evershelf version does not support recipe details yet."

    private func failIfEmpty(_ message: String, unsupported: Bool) {
        if detail == nil { phase = .failed(message: message, unsupported: unsupported) }
    }

    private static func message(_ error: Error, fallback: String) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? ""
        return text.isEmpty ? fallback : text
    }
}

/// Sheets present an open recipe by its model.
extension RecipeDetailModel: @MainActor Identifiable {
    var id: Int { recipe.id }
}
