import Foundation
import HassCore
@testable import HassUI
import Testing

/// The Food hub carousel's loading: first load, quiet refresh when stale, and what a failure leaves on screen.
@MainActor
struct SuggestedRecipesModelTests {
    private func model(_ service: FakeRecipeService?) -> SuggestedRecipesModel {
        let model = SuggestedRecipesModel()
        model.service = service
        return model
    }

    @Test func startsIdleAndEmpty() {
        let model = SuggestedRecipesModel()
        #expect(model.phase == .idle)
        #expect(model.items.isEmpty)
    }

    @Test func firstAppearanceLoadsTheCardsAndAsksForTheFullLimit() async {
        let service = FakeRecipeService()
        service.recommendationsHandler = { _ in recipeCards(1...3) }
        let model = model(service)
        model.appear()
        #expect(model.phase == .loading)
        await model.settle()
        #expect(model.phase == .ready)
        #expect(model.items.map(\.id) == [1, 2, 3])
        #expect(service.recommendationLimits == [SuggestedRecipesModel.limit])
    }

    @Test func loadWithoutAServiceDoesNothing() async {
        let model = model(nil)
        model.appear()
        await model.settle()
        #expect(model.phase == .idle)
        #expect(model.items.isEmpty)
    }

    @Test func appearingWhileALoadIsInFlightDoesNotStartAnother() async {
        let service = FakeRecipeService()
        let gate = RecipeGate()
        service.recommendationsHandler = { _ in
            await gate.hold()
            return recipeCards(1...2)
        }
        let model = model(service)
        model.appear()
        await gate.waitUntilHeld()
        model.appear()
        gate.release()
        await model.settle()
        #expect(service.recommendationLimits.count == 1)
    }

    @Test func aFreshLoadIsNotRefreshedWhenTheHubReappears() async {
        let service = FakeRecipeService()
        service.recommendationsHandler = { _ in recipeCards(1...2) }
        let model = model(service)
        model.appear()
        await model.settle()
        model.appear(now: .now.addingTimeInterval(SuggestedRecipesModel.staleAfter - 60))
        await model.settle()
        #expect(service.recommendationLimits.count == 1)
    }

    @Test func aStaleLoadRefreshesInPlaceKeepingTheCardsOnScreen() async {
        let service = FakeRecipeService()
        let gate = RecipeGate()
        service.recommendationsHandler = { _ in recipeCards(1...2) }
        let model = model(service)
        model.appear()
        await model.settle()
        service.recommendationsHandler = { _ in
            await gate.hold()
            return recipeCards(7...9)
        }
        model.appear(now: .now.addingTimeInterval(SuggestedRecipesModel.staleAfter + 60))
        await gate.waitUntilHeld()
        // The old cards stay and the phase never drops back to loading.
        #expect(model.phase == .ready)
        #expect(model.items.map(\.id) == [1, 2])
        gate.release()
        await model.settle()
        #expect(model.items.map(\.id) == [7, 8, 9])
    }

    @Test func aFailureWithNothingOnScreenIsFailedAndRetriesOnTheNextAppearance() async {
        let service = FakeRecipeService()
        service.recommendationsHandler = { _ in throw RecipeTestError(errorDescription: "down") }
        let model = model(service)
        model.appear()
        await model.settle()
        #expect(model.phase == .failed)
        #expect(model.items.isEmpty)
        service.recommendationsHandler = { _ in recipeCards(1...1) }
        model.appear()
        await model.settle()
        #expect(model.phase == .ready)
        #expect(model.items.count == 1)
    }

    @Test func aFailedRefreshKeepsTheCardsAndStaysReady() async {
        let service = FakeRecipeService()
        service.recommendationsHandler = { _ in recipeCards(1...2) }
        let model = model(service)
        model.appear()
        await model.settle()
        service.recommendationsHandler = { _ in throw RecipeTestError(errorDescription: "down") }
        model.load()
        await model.settle()
        #expect(model.phase == .ready)
        #expect(model.items.map(\.id) == [1, 2])
    }
}
