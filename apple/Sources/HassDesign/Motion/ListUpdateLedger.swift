import Foundation

/// The bookkeeping behind one list's updates: tickets for removals and insertions a person caused, and when the store last handed
/// its state back as a whole. ``plan(removed:inserted:isFirstApply:hasWindow:cause:reduceMotion:generation:now:)`` turns an apply
/// into a ``Plan``; the UIKit applier executes it. Pure (time is passed in), so every rule is unit-tested.
public struct ListUpdateLedger<ID: Hashable & Sendable>: Sendable {
    /// What an apply should do.
    public struct Plan: Equatable, Sendable {
        /// Motion for the apply.
        public var transition: ListUpdateTransition
        /// The cause after tickets are read: a live apply whose changes a person ticketed is `person`.
        public var cause: ListUpdateCause
        /// The titles of ticketed removals that happened, for the "<title> deleted" announcement, in registration order.
        public var removedTitles: [String]
        /// Whether a ticketed removal happened (focus moves to the next row).
        public var removedByPerson: Bool
    }

    private struct Ticket: Sendable {
        var id: ID
        var title: String?
        var isRemoval: Bool
        var expires: TimeInterval
    }

    /// How long a ticket waits for the change it expects before it is dropped (a failure that never reports).
    public static var ticketLifetime: TimeInterval { 10 }

    private var tickets: [Ticket] = []
    private var seenGeneration: Int?
    private var reappliedAt: TimeInterval?

    public init() {}

    /// Registers that a person is about to remove `ids`; `title` is announced when each leaves ("<title> deleted").
    public mutating func expectRemoval(of ids: [ID], title: String? = nil, now: TimeInterval) {
        tickets.removeAll { $0.isRemoval && ids.contains($0.id) }
        tickets += ids.map { Ticket(id: $0, title: title, isRemoval: true, expires: now + Self.ticketLifetime) }
    }

    /// Registers that a person is about to bring `ids` back (a failed action, an undo).
    public mutating func expectInsertion(of ids: [ID], now: TimeInterval) {
        tickets.removeAll { !$0.isRemoval && ids.contains($0.id) }
        tickets += ids.map { Ticket(id: $0, title: nil, isRemoval: false, expires: now + Self.ticketLifetime) }
    }

    /// Drops the tickets for `ids` (the call failed and the rows stay).
    public mutating func cancelExpectation(of ids: [ID]) {
        tickets.removeAll { ids.contains($0.id) }
    }

    /// Whether any ticket is waiting.
    public var hasTickets: Bool { !tickets.isEmpty }

    /// Notes the store's reapply counter; a change starts the reapply window at `now`. Call it on every apply and whenever the counter
    /// is observed. nil (a list that does not read the store) never reapplies.
    public mutating func observe(generation: Int?, now: TimeInterval) {
        defer { seenGeneration = generation }
        guard let generation else { return }
        if let seenGeneration, seenGeneration != generation { reappliedAt = now }
    }

    /// Whether `now` is inside the reapply window.
    public func isReapplying(now: TimeInterval) -> Bool {
        guard let reappliedAt else { return false }
        return ListUpdateTransition.isReapply(elapsedSinceReapply: .seconds(max(0, now - reappliedAt)))
    }

    /// Decides one apply and consumes the tickets it satisfies; expired tickets are dropped. `reloaded`: a section or row is reloaded
    /// (a header's words changed), which cross-fades like a structural change.
    public mutating func plan(
        removed: Set<ID>, inserted: Set<ID>, reloaded: Bool = false, isFirstApply: Bool, hasWindow: Bool,
        cause: ListUpdateCause, reduceMotion: Bool, generation: Int?, now: TimeInterval
    ) -> Plan {
        observe(generation: generation, now: now)
        tickets.removeAll { $0.expires <= now }
        var titles: [String] = []
        var ticketed = false
        var removalTicketed = false
        tickets.removeAll { ticket in
            let matches = ticket.isRemoval ? removed.contains(ticket.id) : inserted.contains(ticket.id)
            guard matches else { return false }
            ticketed = true
            if ticket.isRemoval {
                removalTicketed = true
                if let title = ticket.title { titles.append(title) }
            }
            return true
        }
        let effective: ListUpdateCause = cause == .live && ticketed ? .person : cause
        let transition = ListUpdateTransition.decide(
            hasWindow: hasWindow, isFirstApply: isFirstApply, isReapply: isReapplying(now: now),
            isStructural: reloaded || !removed.isEmpty || !inserted.isEmpty, cause: effective, reduceMotion: reduceMotion)
        let removedByPerson = removalTicketed && effective == .person
        return Plan(transition: transition, cause: effective, removedTitles: removedByPerson ? titles : [], removedByPerson: removedByPerson)
    }
}
