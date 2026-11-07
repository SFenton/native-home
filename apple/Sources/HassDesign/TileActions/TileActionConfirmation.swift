import SwiftUI

/// A question asked before an action runs (owner, 2026-10-27: a disc keeps today's confirmation where one exists). HassDesign's
/// twin of HassCore's `TileActionSpec.Confirmation`, so ``GlassTile`` can present it without a service call in sight.
///
/// The tile presents it for a disc tap **and** for a body tap that runs that action, and runs the action only on confirm
/// (Cancel does nothing, not even a failed face). The alert follows `.agents/patterns/alerts.md`: Title Case question, Cancel
/// leading with the cancel role, a plain confirming button as the bold default, destructive only for a loss.
public struct TileActionConfirmation: Equatable, Sendable {
    /// How the question is presented.
    public enum Style: Equatable, Sendable {
        /// A centred alert (Disarm, Vacation Mode, Solo Trip, High AQI).
        case alert
        /// A confirmation dialog attached to the tile: an action sheet on iPhone, a popover on iPad (a bed turning off).
        case dialog
    }

    /// The question.
    public var title: String
    /// The explanation under it.
    public var message: String?
    /// The confirming button.
    public var confirmVerb: String
    /// The confirming button takes the destructive role and is never the default.
    public var isDestructive: Bool
    /// Alert or dialog.
    public var style: Style

    /// Creates a confirmation.
    public init(title: String, message: String? = nil, confirmVerb: String, isDestructive: Bool = false, style: Style = .alert) {
        self.title = title
        self.message = message
        self.confirmVerb = confirmVerb
        self.isDestructive = isDestructive
        self.style = style
    }

    /// The question to ask before running action `id`, or nil to run it at once: the item exists, can run now, and carries one.
    /// A waiting or unavailable action never asks (it cannot run).
    public static func required(forPerforming id: TileActionItem.ID, in items: [TileActionItem]) -> TileActionConfirmation? {
        guard let item = items.first(where: { $0.id == id }), item.phase == .ready else { return nil }
        return item.confirmation
    }

    /// Whether the answer to `ask` still applies: the action it asked about is still shown, still ready, still carries the same
    /// question, and has not flipped state or verb (Disarm asked, the panel disarmed elsewhere). Anything else drops the answer and
    /// runs nothing, so a confirm never runs a different action than the one the person read.
    static func holds(for ask: TileConfirmationRequest, in items: [TileActionItem]) -> Bool {
        guard let now = items.first(where: { $0.id == ask.item.id }),
              now.isOn == ask.item.isOn, now.verb == ask.item.verb,
              required(forPerforming: ask.item.id, in: items) == ask.confirmation else { return false }
        return true
    }

    /// The accessibility identifier of the confirming button: `<tile-id>.confirm`.
    public static func confirmIdentifier(_ tileIdentifier: String?) -> String { [tileIdentifier, "confirm"].compactMap { $0 }.joined(separator: ".") }

    /// The accessibility identifier of the Cancel button: `<tile-id>.cancel`.
    public static func cancelIdentifier(_ tileIdentifier: String?) -> String { [tileIdentifier, "cancel"].compactMap { $0 }.joined(separator: ".") }
}

/// An action waiting on its question.
struct TileConfirmationRequest: Identifiable, Equatable {
    /// The action as it was when asked about, so the answer applies to that and nothing else.
    var item: TileActionItem
    var confirmation: TileActionConfirmation

    var id: TileActionItem.ID { item.id }
}
