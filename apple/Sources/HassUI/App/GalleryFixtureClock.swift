#if DEBUG
import Foundation
import os

// MARK: - Paired fixture time

/// Pins synthetic data generation without changing animation clocks or the live account.
final class GalleryFixtureClock: Sendable {
    static let shared = GalleryFixtureClock()
    private let reference = OSAllocatedUnfairLock<Date?>(initialState: nil)

    var now: Date { reference.withLock { $0 } ?? Date() }

    func setReferenceDate(_ date: Date?) {
        reference.withLock { $0 = date }
    }
}
#endif
