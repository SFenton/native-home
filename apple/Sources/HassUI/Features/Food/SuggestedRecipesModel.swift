import Foundation
import HassCore
import Observation

/// The Food hub's Suggested Recipes carousel (web `SuggestedRecipeCarousel`).
@MainActor
@Observable
final class SuggestedRecipesModel {
    enum Phase: Equatable { case idle, loading, ready, failed }

    private(set) var phase: Phase = .idle
    private(set) var items: [RecipeCard] = []
    @ObservationIgnored var service: (any RecipeServing)?
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Cards requested: five pages of the widest layout (web asks columns x rows x 5).
    static let limit = 40
    /// Suggestions older than this refresh quietly when the hub reappears.
    static let staleAfter: TimeInterval = 300

    /// Loads on first appearance; later appearances refresh in place only when stale, keeping the cards on screen.
    func appear(now: Date = .now) {
        guard task == nil else { return }
        if let loadedAt, now.timeIntervalSince(loadedAt) < Self.staleAfter { return }
        load()
    }

    /// Fetches suggestions. Existing cards stay visible until new ones arrive.
    func load() {
        guard let service else { return }
        if items.isEmpty { phase = .loading }
        task = Task { [weak self] in
            do {
                let cards = try await service.recommendations(limit: Self.limit)
                guard let self else { return }
                self.items = cards
                self.phase = .ready
                self.loadedAt = .now
            } catch {
                guard let self else { return }
                if self.items.isEmpty { self.phase = .failed }
            }
            self?.task = nil
        }
    }

    /// Waits for an in-flight load (tests).
    func settle() async { await task?.value }
}
