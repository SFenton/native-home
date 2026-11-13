import Foundation
import HassCore
@testable import HassUI
import Testing

/// The Recipes grid: criteria, first page, infinite scroll, search debounce and the remote-catalog hydration.
@MainActor
struct RecipeCollectionModelTests {
    /// A model on a fast clock whose browse answers one page unless the test says otherwise.
    private func model(_ service: FakeRecipeService?) -> RecipeCollectionModel {
        let model = RecipeCollectionModel()
        model.service = service
        model.debounce = .milliseconds(1)
        model.hydrationSettle = .zero
        return model
    }

    private func service(pages: [String?: RecipeBrowsePage]) -> FakeRecipeService {
        let service = FakeRecipeService()
        service.browseHandler = { _, cursor in pages[cursor] ?? RecipeBrowsePage(items: []) }
        return service
    }

    private func loaded(_ items: ClosedRange<Int> = 1...3, hasMore: Bool = false) async -> (RecipeCollectionModel, FakeRecipeService) {
        let service = service(pages: [nil: RecipeBrowsePage(items: recipeCards(items), nextCursor: hasMore ? "c1" : nil, hasMore: hasMore, total: 40)])
        let model = model(service)
        model.appear()
        await model.settle()
        return (model, service)
    }

    /// Gives a released, stale request time to run its tail so a wrongly applied answer would show.
    private func drain() async {
        for _ in 0..<30 { await Task.yield() }
    }

    // MARK: Controls

    @Test func startsIdleWithDefaultCriteria() {
        let model = RecipeCollectionModel()
        #expect(model.phase == .idle)
        #expect(model.criteria == RecipeBrowseCriteria())
        #expect(!model.sortActive)
        #expect(!model.filterActive)
    }

    @Test func criteriaFollowSortAndFiltersAndOnlyAskForExpiryWhenExpiringOnly() {
        let model = RecipeCollectionModel()
        model.apply(sort: .alphabetical)
        #expect(model.sortActive)
        #expect(model.criteria.sort == .alphabetical)

        var filters = RecipeFilters.defaults
        filters.minimumCoverage = 40
        filters.availabilityWeight = 80
        filters.expiryWeight = 10
        filters.expiringWithinDays = 30
        model.apply(filters: filters)
        #expect(model.filterActive)
        #expect(model.criteria.minimumCoverage == 40)
        #expect(model.criteria.availabilityWeight == 80)
        #expect(model.criteria.expiryWeight == 10)
        #expect(model.criteria.expiringWithinDays == nil)

        filters.expiringOnly = true
        model.apply(filters: filters)
        #expect(model.criteria.expiringWithinDays == 30)
    }

    @Test func applyingTheSameSortOrFiltersDoesNotReload() async {
        let (model, service) = await loaded()
        model.apply(sort: .availability)
        model.apply(filters: .defaults)
        await model.settle()
        #expect(service.browseCalls.count == 1)

        model.apply(sort: .expiry)
        await model.settle()
        #expect(service.browseCalls.count == 2)
        #expect(service.browseCalls[1].criteria.sort == .expiry)
        var filters = RecipeFilters.defaults
        filters.minimumCoverage = 25
        model.apply(filters: filters)
        await model.settle()
        #expect(service.browseCalls.count == 3)
        #expect(service.browseCalls[2].criteria.minimumCoverage == 25)
    }

    // MARK: First page

    @Test func firstAppearanceLoadsAndLaterOnesKeepWhatIsShown() async {
        let (model, service) = await loaded()
        #expect(model.phase == .loaded)
        #expect(model.items.map(\.id) == [1, 2, 3])
        #expect(model.announcement == "40 recipes.")
        #expect(service.browseCalls == [.init(criteria: RecipeBrowseCriteria(), cursor: nil)])
        model.appear()
        await model.settle()
        #expect(service.browseCalls.count == 1)
    }

    @Test func anEmptyResultAnnouncesThatNothingWasFound() async {
        let service = service(pages: [nil: RecipeBrowsePage(items: [])])
        let model = model(service)
        model.appear()
        await model.settle()
        #expect(model.phase == .loaded)
        #expect(model.announcement == "No recipes found.")
    }

    @Test func reloadingWithoutAServiceLeavesTheGridLoading() async {
        let model = model(nil)
        model.reload()
        await model.settle()
        #expect(model.phase == .loading)
    }

    @Test func aPageClaimingMoreWithoutACursorHasNoMore() async {
        let service = service(pages: [nil: RecipeBrowsePage(items: recipeCards(1...2), nextCursor: nil, hasMore: true)])
        let model = model(service)
        model.reload()
        await model.settle()
        #expect(!model.hasMore)
    }

    @Test func aFailedFirstPageIsFailedWithNoItemsAndAnAnnouncement() async {
        let service = FakeRecipeService()
        service.browseHandler = { _, _ in throw RecipeTestError(errorDescription: "down") }
        let model = model(service)
        model.reload()
        await model.settle()
        #expect(model.phase == .failed)
        #expect(model.items.isEmpty)
        #expect(model.announcement == "Unable to load recipes.")
    }

    @Test func aReloadDuringAFirstPageDiscardsTheStaleAnswer() async {
        let service = FakeRecipeService()
        let gate = RecipeGate()
        var first = true
        service.browseHandler = { _, _ in
            if first {
                first = false
                await gate.hold()
                return RecipeBrowsePage(items: recipeCards(1...2))
            }
            return RecipeBrowsePage(items: recipeCards(10...11))
        }
        let model = model(service)
        model.reload()
        await gate.waitUntilHeld()
        model.reload()
        await model.settle()
        gate.release()
        await drain()
        #expect(model.items.map(\.id) == [10, 11])
    }

    @Test func aReloadDuringAFailingFirstPageIgnoresTheStaleError() async {
        let service = FakeRecipeService()
        let gate = RecipeGate()
        var first = true
        service.browseHandler = { _, _ in
            if first {
                first = false
                await gate.hold()
                throw RecipeTestError(errorDescription: "late")
            }
            return RecipeBrowsePage(items: recipeCards(1...2))
        }
        let model = model(service)
        model.reload()
        await gate.waitUntilHeld()
        model.reload()
        await model.settle()
        gate.release()
        await drain()
        #expect(model.phase == .loaded)
        #expect(model.items.count == 2)
    }

    // MARK: Paging

    @Test func onlyTheLastCardsTriggerTheNextPage() async {
        let service = service(pages: [
            nil: RecipeBrowsePage(items: recipeCards(1...20), nextCursor: "c1", hasMore: true, total: 22),
            "c1": RecipeBrowsePage(items: recipeCards(21...22), total: 22),
        ])
        let model = model(service)
        model.appear()
        await model.settle()
        model.itemAppeared(model.items[0])
        await model.settle()
        #expect(service.browseCalls.count == 1)

        model.itemAppeared(model.items[19])
        #expect(model.nextPageLoading)
        await model.settle()
        #expect(service.browseCalls.map(\.cursor) == [nil, "c1"])
        #expect(model.items.count == 22)
        #expect(!model.hasMore)
        #expect(!model.nextPageLoading)
        #expect(model.announcement == "2 more recipes loaded; 22 total.")
        // With nothing more, further appearances do nothing.
        model.itemAppeared(model.items[21])
        await model.settle()
        #expect(service.browseCalls.count == 2)
    }

    @Test func aPageOfDuplicatesAddsNothingAndKeepsTheAnnouncement() async {
        let service = service(pages: [
            nil: RecipeBrowsePage(items: recipeCards(1...3), nextCursor: "c1", hasMore: true, total: 3),
            "c1": RecipeBrowsePage(items: recipeCards(2...3), nextCursor: "c2", hasMore: true, total: 3),
        ])
        let model = model(service)
        model.appear()
        await model.settle()
        model.loadNextPage()
        await model.settle()
        #expect(model.items.count == 3)
        #expect(model.hasMore)
        #expect(model.announcement == "3 recipes.")
    }

    @Test func aSecondNextPageRequestWhileOneLoadsIsIgnored() async {
        let service = FakeRecipeService()
        let gate = RecipeGate()
        service.browseHandler = { _, cursor in
            if cursor == nil { return RecipeBrowsePage(items: recipeCards(1...3), nextCursor: "c1", hasMore: true) }
            await gate.hold()
            return RecipeBrowsePage(items: recipeCards(4...5))
        }
        let model = model(service)
        model.appear()
        await model.settle()
        model.loadNextPage()
        await gate.waitUntilHeld()
        model.loadNextPage()
        gate.release()
        await model.settle()
        #expect(service.browseCalls.count == 2)
    }

    @Test func aFailedNextPageStopsPagingUntilRetried() async {
        let service = FakeRecipeService()
        var failing = true
        service.browseHandler = { _, cursor in
            if cursor == nil { return RecipeBrowsePage(items: recipeCards(1...3), nextCursor: "c1", hasMore: true) }
            if failing { throw RecipeTestError(errorDescription: "down") }
            return RecipeBrowsePage(items: recipeCards(4...5))
        }
        let model = model(service)
        model.appear()
        await model.settle()
        model.loadNextPage()
        await model.settle()
        #expect(model.nextPageFailed)
        #expect(!model.nextPageLoading)
        model.loadNextPage()
        await model.settle()
        #expect(service.browseCalls.count == 2)

        failing = false
        model.retryNextPage()
        await model.settle()
        #expect(!model.nextPageFailed)
        #expect(model.items.count == 5)
    }

    @Test func aReloadDuringANextPageDiscardsItsAnswerAndItsError() async {
        for failure in [false, true] {
            let service = FakeRecipeService()
            let gate = RecipeGate()
            var reloaded = false
            service.browseHandler = { _, cursor in
                if cursor == "c1" {
                    await gate.hold()
                    if failure { throw RecipeTestError(errorDescription: "late") }
                    return RecipeBrowsePage(items: recipeCards(4...5))
                }
                return reloaded ? RecipeBrowsePage(items: recipeCards(8...9)) : RecipeBrowsePage(items: recipeCards(1...3), nextCursor: "c1", hasMore: true)
            }
            let model = model(service)
            model.appear()
            await model.settle()
            model.loadNextPage()
            await gate.waitUntilHeld()
            reloaded = true
            model.reload()
            // The reload keeps no handle on the old page task, so let the new first page land, then free the old request.
            await drain()
            #expect(model.items.map(\.id) == [8, 9])
            gate.release()
            await model.settle()
            await drain()
            #expect(model.items.map(\.id) == [8, 9])
            #expect(!model.nextPageFailed)
        }
    }

    // MARK: Search

    @Test func searchReloadsOnceWithTheNormalizedQuery() async {
        let (model, service) = await loaded()
        model.searchText = "  pasta   bake "
        await model.settle()
        #expect(model.appliedQuery == "pasta bake")
        #expect(service.browseCalls.last?.criteria.query == "pasta bake")
        let calls = service.browseCalls.count

        // Different spacing, same query: nothing reloads.
        model.searchText = "pasta bake"
        await model.settle()
        #expect(service.browseCalls.count == calls)
        // Assigning the same text again does not even schedule a search.
        model.searchText = "pasta bake"
        await model.settle()
        #expect(service.browseCalls.count == calls)
    }

    @Test func typingQuicklyOnlyLoadsTheLastQuery() async {
        let (model, service) = await loaded()
        model.debounce = .milliseconds(100)
        model.searchText = "pa"
        model.searchText = "pas"
        model.searchText = "pasta"
        await model.settle()
        let queries = service.browseCalls.dropFirst().map(\.criteria.query)
        #expect(queries == ["pasta"])
    }

    // MARK: Hydration

    @Test func shortQueriesDoNotHydrate() async {
        let (model, service) = await loaded()
        model.searchText = "pa"
        await model.settle()
        #expect(model.appliedQuery == "pa")
        #expect(service.hydrateCalls.isEmpty)
    }

    @Test func hydrationPollsUntilCompleteAppendingOnlyNewMatchingCards() async {
        let (model, service) = await loaded(1...3)
        service.hydrateHandler = { _, searchId in
            if searchId == nil {
                // Card 3 is already shown, so only card 4 is new.
                return RecipeHydration(searchId: "s1", status: "running", nextPollMilliseconds: 0, newItems: recipeCards(3...4))
            }
            return RecipeHydration(searchId: "s1", status: "complete", newItems: recipeCards(5...5))
        }
        model.searchText = "pasta"
        await model.settle()
        #expect(service.hydrateCalls == [nil, "s1"])
        #expect(model.items.map(\.id) == [1, 2, 3, 4, 5])
        #expect(!model.hydrating)
        #expect(model.announcement == "1 more recipes hydrated; 5 total.")
    }

    @Test func hydratedCardsFailingTheFiltersAreDropped() async {
        let (model, service) = await loaded(1...3)
        var filters = RecipeFilters.defaults
        filters.minimumCoverage = 60
        model.apply(filters: filters)
        await model.settle()
        service.hydrateHandler = { _, _ in
            RecipeHydration(searchId: "s1", status: "complete", newItems: recipeCards(6...6, coverage: 30) + recipeCards(7...7, coverage: 90))
        }
        model.searchText = "pasta"
        await model.settle()
        #expect(model.items.map(\.id).contains(7))
        #expect(!model.items.map(\.id).contains(6))
    }

    @Test func hydrationStopsOnAServerFailureAndOnAnError() async {
        let (model, service) = await loaded()
        service.hydrateHandler = { _, _ in RecipeHydration(searchId: "s1", status: "failed", newItems: recipeCards(9...9)) }
        model.searchText = "pasta"
        await model.settle()
        #expect(service.hydrateCalls.count == 1)
        #expect(!model.hydrating)

        service.hydrateHandler = { _, _ in throw RecipeTestError(errorDescription: "down") }
        model.searchText = "noodle"
        await model.settle()
        #expect(!model.hydrating)
        #expect(model.phase == .loaded)
    }

    @Test func aReloadDuringHydrationDropsTheStalePoll() async {
        for failure in [false, true] {
            let (model, service) = await loaded()
            let gate = RecipeGate()
            var held = false
            service.hydrateHandler = { _, _ in
                if !held {
                    held = true
                    await gate.hold()
                    if failure { throw RecipeTestError(errorDescription: "late") }
                    return RecipeHydration(searchId: "s1", status: "complete", newItems: recipeCards(30...31))
                }
                return RecipeHydration(searchId: "", newItems: [])
            }
            model.searchText = "pasta"
            await gate.waitUntilHeld()
            model.apply(sort: .alphabetical)
            await model.settle()
            gate.release()
            await drain()
            #expect(!model.items.map(\.id).contains(30))
        }
    }
}
