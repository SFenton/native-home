@preconcurrency import CoreSpotlight
import Foundation
import HassCore

#if canImport(UIKit)
import UIKit
#endif

/// Core Spotlight's default index, filled with one `CSSearchableItem` per authored route (``SpotlightEntry``).
///
/// Items carry the entry's words as `keywords` so a search for "Home Assistant" or "HASS" lists them
/// (`CSSearchableItemAttributeSet.keywords`), and open the app through `CSSearchableItemActionType`
/// (``PushCoordinator/open(spotlightUserInfo:)``). Refreshed whenever the accepted routes change and removed at sign-out.
/// On iOS 18 and later the app's `decorate` closure associates each item with its App Entity, so Spotlight lists one result per
/// route and opens it through the same intent Siri uses.
@MainActor
public final class CoreSpotlightIndexer: SpotlightIndexing {
    /// The key that records an older build's items were cleared once.
    public static let routesMigratedKey = "spotlight.routeItemsMigrated"

    private let index: CSSearchableIndex
    /// Adds what only the app target can: the entity association (iOS 18 and later).
    private let decorate: (@Sendable (CSSearchableItemAttributeSet, SpotlightEntry) -> Void)?
    /// Keeps the batches in order: the last call wins and nothing indexes after `removeAll`.
    private let queue = SpotlightBatchQueue()

    /// Creates an indexer.
    /// - Parameters:
    ///   - index: The index to fill; the app's default one unless a test supplies its own.
    ///   - defaults: Where the one-time clearing of an older build's items (`section.*`, `room.*`, `authored.*`) is recorded.
    ///   - decorate: Called for each item's attributes; the app associates the route's App Entity here.
    public init(index: CSSearchableIndex = .default(), defaults: UserDefaults = .standard,
                decorate: (@Sendable (CSSearchableItemAttributeSet, SpotlightEntry) -> Void)? = nil) {
        self.index = index
        self.decorate = decorate
        if !defaults.bool(forKey: Self.routesMigratedKey) {
            defaults.set(true, forKey: Self.routesMigratedKey)
            removeAll()
        }
    }

    public func indexPages(_ entries: [SpotlightEntry]) {
        // One batch replaces the last: delete the domain, then index, so a page dropped from the catalog disappears.
        // Failures are ignored; the next session start indexes again.
        // Detached: a plain `Task` here would inherit the main actor, and building the items renders a PNG thumbnail per page,
        // which cost the main thread about 50 ms inside the launch and arrival windows (`tools/ios_launchperf.sh`).
        queue.enqueue { [index, decorate] in
            try? await index.deleteSearchableItems(withDomainIdentifiers: [SpotlightCatalog.domainIdentifier])
            try? await index.indexSearchableItems(entries.map { Self.item(for: $0, decorate: decorate) })
        }
    }

    public func removeAll() {
        queue.enqueue { [index] in
            try? await index.deleteSearchableItems(withDomainIdentifiers: [SpotlightCatalog.domainIdentifier])
        }
    }

    /// The searchable item for an entry.
    /// - Parameter entry: The page.
    /// - Parameter decorate: The app's hook for the entity association.
    nonisolated static func item(for entry: SpotlightEntry,
                                 decorate: (@Sendable (CSSearchableItemAttributeSet, SpotlightEntry) -> Void)? = nil) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entry.title
        attributes.displayName = entry.title
        attributes.contentDescription = "\(AppBranding.displayName) · \(entry.summary)"
        attributes.keywords = entry.keywords
        #if canImport(UIKit)
        attributes.thumbnailData = thumbnail(symbol: entry.symbol)
        #endif
        decorate?(attributes, entry)
        return CSSearchableItem(uniqueIdentifier: entry.id, domainIdentifier: SpotlightCatalog.domainIdentifier,
                                attributeSet: attributes)
    }

    #if canImport(UIKit)
    /// An SF Symbol on the app's blue, as the result's icon.
    private nonisolated static func thumbnail(symbol: String) -> Data? {
        let size = CGSize(width: 120, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { context in
            UIColor.systemBlue.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 26).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: 60, weight: .semibold)
            guard let image = UIImage(systemName: ServerUISymbolFallback.resolve(symbol), withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            image.draw(at: CGPoint(x: (size.width - image.size.width) / 2, y: (size.height - image.size.height) / 2))
        }
    }
    #endif
}
