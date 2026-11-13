import Foundation
import HassCore
@testable import HassUI
import Testing

/// One open recipe: loading its detail, what a failure reads as, and the grocery action with its retry key.
@MainActor
struct RecipeDetailModelTests {
    private let card = RecipeCard(id: 7, title: "Soup")

    private func ingredient(_ n: Int, _ state: RecipeDetail.InventoryState = .missing) -> RecipeDetail.Ingredient {
        RecipeDetail.Ingredient(key: "ri:\(n):000000000000000\(n)", position: n, name: "Item \(n)", inventoryState: state)
    }

    /// A detail with two missing ingredients and the grocery feature on.
    private func detail(missing: Int = 2, present: Int = 0) -> RecipeDetail {
        let all = (0..<missing).map { ingredient($0 + 1) } + (0..<present).map { ingredient(50 + $0, .inStock) }
        return RecipeDetail(
            id: 7, title: "Soup", ingredients: all, grocery: .init(confirmedMissingCount: missing),
            capabilities: .init(general: .full, ingredients: .checklist, groceryAdd: true)
        )
    }

    private func model(_ service: FakeRecipeService?, cached: RecipeDetail? = nil, onLoad: @escaping (RecipeDetail) -> Void = { _ in }) -> RecipeDetailModel {
        RecipeDetailModel(recipe: card, service: service, cached: cached, onLoad: onLoad)
    }

    // MARK: Basics

    @Test func tabsCarryATitleASymbolAndAnId() {
        #expect(RecipeDetailModel.Tab.allCases.map(\.title) == ["General", "Ingredients", "Instructions"])
        #expect(RecipeDetailModel.Tab.allCases.map(\.symbol) == ["info.circle", "checklist", "frying.pan"])
        #expect(RecipeDetailModel.Tab.allCases.map(\.id) == ["general", "ingredients", "instructions"])
        #expect(model(nil).tab == .general)
    }

    @Test func aModelIsIdentifiedByItsRecipe() {
        #expect(model(nil).id == 7)
    }

    @Test func startsLoadingOrAsTheCachedDetail() {
        let cold = model(nil)
        #expect(cold.phase == .loading)
        #expect(cold.detail == nil)
        let warm = model(nil, cached: detail())
        #expect(warm.detail?.id == 7)
        #expect(warm.grocery == .idle)
    }

    // MARK: Loading

    @Test func loadFetchesTheDetailAndReportsIt() async {
        let service = FakeRecipeService()
        var reported: [Int] = []
        let model = model(service, onLoad: { reported.append($0.id) })
        model.load()
        await model.settle()
        #expect(model.detail?.id == 7)
        #expect(service.detailIds == [7])
        #expect(reported == [7])
    }

    @Test func loadWithoutAServiceDoesNothing() async {
        let model = model(nil)
        model.load()
        await model.settle()
        #expect(model.phase == .loading)
    }

    @Test func loadWhileOneIsInFlightIsIgnored() async {
        let service = FakeRecipeService()
        let gate = RecipeGate()
        service.detailHandler = { id in
            await gate.hold()
            return RecipeDetail(id: id, title: "Soup")
        }
        let model = model(service)
        model.load()
        await gate.waitUntilHeld()
        model.load()
        gate.release()
        await model.settle()
        #expect(service.detailIds.count == 1)
    }

    @Test func anUnsupportedServerFailsWithTheVersionMessage() async {
        let service = FakeRecipeService()
        service.detailHandler = { _ in throw RecipeServiceFailure(unsupported: true, message: "ignored") }
        let model = model(service)
        model.load()
        await model.settle()
        #expect(model.phase == .failed(message: RecipeDetailModel.unsupportedMessage, unsupported: true))
    }

    @Test func aServiceFailureFailsWithItsOwnMessage() async {
        let service = FakeRecipeService()
        service.detailHandler = { _ in throw RecipeServiceFailure(unsupported: false, message: "Recipe is gone.") }
        let model = model(service)
        model.load()
        await model.settle()
        #expect(model.phase == .failed(message: "Recipe is gone.", unsupported: false))
    }

    @Test func otherErrorsReadTheirDescriptionOrTheFallback() async {
        let service = FakeRecipeService()
        service.detailHandler = { _ in throw RecipeTestError(errorDescription: "Offline.") }
        let described = model(service)
        described.load()
        await described.settle()
        #expect(described.phase == .failed(message: "Offline.", unsupported: false))

        service.detailHandler = { _ in throw RecipeTestError(errorDescription: "") }
        let blank = model(service)
        blank.load()
        await blank.settle()
        #expect(blank.phase == .failed(message: "Unable to load recipe details.", unsupported: false))
    }

    @Test func aFailedRefreshKeepsTheCachedDetail() async {
        let service = FakeRecipeService()
        service.detailHandler = { _ in throw RecipeServiceFailure(unsupported: false, message: "nope") }
        let model = model(service, cached: detail())
        model.load()
        await model.settle()
        #expect(model.detail?.id == 7)
    }

    // MARK: Grocery

    @Test func theGroceryButtonHasNoReasonWithoutADetailAndOneWhenNothingIsMissing() {
        #expect(model(nil).groceryDisabledReason == nil)
        let none = model(nil, cached: detail(missing: 0, present: 2))
        #expect(none.groceryDisabledReason == "No missing ingredients to add.")
        #expect(model(nil, cached: detail()).groceryDisabledReason == nil)
    }

    @Test func addingSendsTheMissingIngredientsAndRemembersThem() async {
        let service = FakeRecipeService()
        service.groceryHandler = { _ in RecipeGroceryResult(success: true, backend: .init(added: 2), mirror: .init(added: 2)) }
        let model = model(service, cached: detail(missing: 2, present: 1))
        model.addMissingToGroceries()
        await model.settle()
        #expect(service.groceryCalls.count == 1)
        #expect(service.groceryCalls[0].recipeId == 7)
        #expect(service.groceryCalls[0].keys.count == 2)
        guard case let .added(message) = model.grocery else { Issue.record("not added: \(model.grocery)"); return }
        #expect(message.hasPrefix("EverShelf: 2 added."))
        #expect(model.addedKeys.count == 2)
        // Added is not a reason to disable, and a second tap has nothing left to send.
        #expect(model.groceryDisabledReason == nil)
        model.addMissingToGroceries()
        await model.settle()
        #expect(service.groceryCalls.count == 1)
    }

    @Test func whileAddingTheButtonExplainsAndAnotherTapIsIgnored() async {
        let service = FakeRecipeService()
        let gate = RecipeGate()
        service.groceryHandler = { _ in
            await gate.hold()
            return RecipeGroceryResult(success: true, backend: .init(added: 2), mirror: .init(added: 2))
        }
        let model = model(service, cached: detail())
        model.addMissingToGroceries()
        await gate.waitUntilHeld()
        #expect(model.grocery == .adding)
        #expect(model.groceryDisabledReason == "Adding missing ingredients…")
        model.addMissingToGroceries()
        gate.release()
        await model.settle()
        #expect(service.groceryCalls.count == 1)
    }

    @Test func addingDoesNothingWithoutAServiceADetailOrAnAllowedAction() async {
        let service = FakeRecipeService()
        let noService = model(nil, cached: detail())
        noService.addMissingToGroceries()
        #expect(noService.grocery == .idle)
        let noDetail = model(service)
        noDetail.addMissingToGroceries()
        #expect(noDetail.grocery == .idle)
        let nothingMissing = model(service, cached: detail(missing: 0, present: 1))
        nothingMissing.addMissingToGroceries()
        #expect(nothingMissing.grocery == .idle)
        #expect(service.groceryCalls.isEmpty)
    }

    @Test func aRetryAfterAnUnreportedFailureReusesTheKeyButAReportedFailureStartsFresh() async {
        let service = FakeRecipeService()
        // The server answered without success and without counting a failure: the response may have been lost.
        service.groceryHandler = { _ in RecipeGroceryResult(success: false) }
        let model = model(service, cached: detail())
        model.addMissingToGroceries()
        await model.settle()
        guard case .failed = model.grocery else { Issue.record("not failed: \(model.grocery)"); return }
        model.addMissingToGroceries()
        await model.settle()
        #expect(service.groceryCalls.count == 2)
        #expect(service.groceryCalls[0].idempotencyKey == service.groceryCalls[1].idempotencyKey)

        // A counted failure is final for that key.
        service.groceryHandler = { _ in RecipeGroceryResult(success: false, backend: .init(failed: 1)) }
        model.addMissingToGroceries()
        await model.settle()
        service.groceryHandler = { _ in RecipeGroceryResult(success: false) }
        model.addMissingToGroceries()
        await model.settle()
        #expect(service.groceryCalls.count == 4)
        #expect(service.groceryCalls[3].idempotencyKey != service.groceryCalls[2].idempotencyKey)
        #expect(model.addedKeys.isEmpty)
    }

    @Test func aThrownUnsupportedFailureSaysSo() async {
        let service = FakeRecipeService()
        service.groceryHandler = { _ in throw RecipeServiceFailure(unsupported: true, message: "ignored") }
        let model = model(service, cached: detail())
        model.addMissingToGroceries()
        await model.settle()
        #expect(model.grocery == .failed(message: RecipeGroceryPolicy.unsupportedMessage))
    }

    @Test func aThrownServiceFailureUsesItsMessage() async {
        let service = FakeRecipeService()
        service.groceryHandler = { _ in throw RecipeServiceFailure(unsupported: false, message: "List is locked.") }
        let model = model(service, cached: detail())
        model.addMissingToGroceries()
        await model.settle()
        #expect(model.grocery == .failed(message: "List is locked."))
    }

    @Test func otherThrownErrorsReadTheirDescriptionOrTheFallback() async {
        let service = FakeRecipeService()
        service.groceryHandler = { _ in throw RecipeTestError(errorDescription: "Offline.") }
        let model = model(service, cached: detail())
        model.addMissingToGroceries()
        await model.settle()
        #expect(model.grocery == .failed(message: "Offline."))

        service.groceryHandler = { _ in throw RecipeTestError(errorDescription: nil) }
        model.addMissingToGroceries()
        await model.settle()
        #expect(model.grocery == .failed(message: "Unable to add missing ingredients to groceries."))
    }
}
