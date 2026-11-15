import Foundation

// MARK: - Collection and form composition

extension ServerUICompositionDocument {
    /// A keyed native collection. The provider owns data and commands; the document owns presentation.
    public struct Collection: Equatable, Sendable {
        public let node: Node
        public let providerId: String
        public let template: Template
        public let loadingText: String
        public let emptyText: String
        public let selection: Action?
        public var bedroomLinks: [BedroomLink] = []
        /// Whether the page offers pull-to-refresh for this collection. Off unless the document opts in, so a
        /// collection the former compiled screen did not refresh (Chores, Recipes) never gains the gesture.
        public var pullsToRefresh: Bool = false
        /// The authored template choices.
        public enum Template: String, Sendable { case rows, todo, inventory, recipes, carousel }
        /// A mirrored alarm keeps its originating bed and authored navigation separate from its link toggle.
        public struct BedroomLink: Equatable, Sendable {
            public let side: BedSide
            public let label: String
            public let action: Action
        }
    }

    /// Ordered fields repeated for each stable group supplied by a native draft.
    public struct Form: Equatable, Sendable {
        public let node: Node
        public let providerId: String
        public let fields: [Field]
        public let saveLabel: String
        public let selectionOnly: Bool
        public let success: Action?

        /// The authored field.
        public struct Field: Equatable, Sendable {
            public let key: String
            public let label: String
            public let control: Control
        }
        /// The authored control choices.
        public enum Control: String, Sendable {
            case text, multiline, number, toggle, choice, date, time, weekdays, attachment, options, percent, segmented
            case scanCamera = "scan-camera"
            case scheduleDateTime = "schedule-date-time"
        }
    }

    /// The canonical recipe's independent atoms, composed with ordinary local tabs.
    public struct RecipePart: Equatable, Sendable {
        public let node: Node
        public let providerId: String
        public let part: Part
        /// The authored part choices.
        public enum Part: String, Sendable { case hero, general, ingredients, instructions }
    }

    /// Uses the page's canonical safe-area/keyboard-aware bar, never a body overlay.
    public struct PinnedActions: Equatable, Sendable {
        public let node: Node
        public let searchProviderId: String?
        public let searchPrompt: String
        public let items: [Item]
        public var style: Style = .floating
        public var children: [Component] = []
        /// The authored style choices.
        public enum Style: String, Sendable { case floating, form }
        /// The authored item.
        public struct Item: Equatable, Sendable {
            public let id: String
            public let title: String
            public let icon: Symbol
            public let prominent: Bool
            public let showsTitle: Bool
            public let action: Action
            public var role: Role? = nil
            public var stateProviderId: String? = nil
        }
        /// The authored role choices.
        public enum Role: String, Sendable { case sort, filter, create }
    }
}

// MARK: - Injectable draft boundary

/// One editable value with native constraints and conditional visibility. No downloaded expressions.
public struct ServerUIFormValue: Equatable, Sendable {
    public let key: String
    public var label: String
    public let control: ServerUICompositionDocument.Form.Control
    public let rule: ServerUICompositionDocument.LocalField.Rule
    public var value: ServerUICompositionDocument.LocalValue
    public var visible: Bool
    public let required: Bool
    public var enabled: Bool = true
    public var optionDetails: [String: String] = [:]

    /// Creates a server uiform value.
    public init(key: String, label: String, control: ServerUICompositionDocument.Form.Control,
                rule: ServerUICompositionDocument.LocalField.Rule, value: ServerUICompositionDocument.LocalValue,
                visible: Bool = true, required: Bool = false) {
        self.key = key; self.label = label; self.control = control; self.rule = rule
        self.value = value; self.visible = visible; self.required = required
    }

    /// Whether the value satisfies the field rule.
    public func accepts(_ value: ServerUICompositionDocument.LocalValue) -> Bool {
        if !required, value == .string(""), case .choice(let options) = rule {
            return !options.isEmpty && Set(options.map(\.id)).count == options.count
        }
        return ServerUICompositionDocument.LocalField(id: key, initial: self.value, rule: rule).accepts(value)
    }

    /// Prevents native controls from accepting a mismatched scalar rule.
    public var isValidDescriptor: Bool {
        guard !key.isEmpty, accepts(value) else { return false }
        switch (control, rule) {
        case (.scheduleDateTime, .number(_, _, let step)): return step == 1
        case (.text, .string), (.multiline, .string), (.date, .string), (.time, .string),
             (.weekdays, .string), (.attachment, .string), (.scanCamera, .string),
             (.toggle, .boolean), (.number, .number), (.percent, .number),
             (.choice, .choice), (.options, .choice), (.segmented, .choice): return true
        default: return false
        }
    }
}

/// Snapshot identity is independent of collection order and survives a sort, refresh or publication.
public struct ServerUIFormGroup: Equatable, Sendable {
    public let id: String
    public let title: String
    public let footer: String
    public let fields: [ServerUIFormValue]
    /// Creates a server uiform group.
    public init(id: String, title: String = "", footer: String = "", fields: [ServerUIFormValue]) {
        self.id = id; self.title = title; self.footer = footer; self.fields = fields
    }
}

/// The generic host never needs an authenticated connection or a domain controller.
@MainActor
public protocol ServerUIFormSession: AnyObject {
    var identity: ServerUIDraft.Identity { get }
    var groups: [ServerUIFormGroup] { get }
    var hasChanges: Bool { get }
    var isBusy: Bool { get }
    var canSave: Bool { get }
    var error: String? { get }
    var canReset: Bool { get }
    var resetLabel: String { get }
    func set(_ value: ServerUICompositionDocument.LocalValue, group: String, field: String) throws
    func save() async throws
    func reset() throws
    func discard() throws
}

extension ServerUIFormSession {
    public var canReset: Bool { hasChanges && !isBusy }
    public var resetLabel: String { "Reset Changes" }
}

/// Provider-owned destructive intent. Authored content cannot manufacture a command target.
public struct ServerUIFormDeletion: Equatable, Sendable {
    public let title: String
    public let noun: String
    public let name: String
    /// Creates a server uiform deletion.
    public init(title: String, noun: String, name: String) {
        self.title = title; self.noun = noun; self.name = name
    }
}

/// A form session that can delete the record it edits.
@MainActor
public protocol ServerUIDeletableFormSession: ServerUIFormSession {
    var deletion: ServerUIFormDeletion? { get }
    func delete() async throws
}

/// Native multi-step providers expose progression without downloaded expressions or page dispatch.
public struct ServerUIFormProgress: Equatable, Sendable {
    public let subtitle: String
    public let forwardTitle: String?
    public let forwardEnabled: Bool
    public let hasPrevious: Bool
    public let canSubmit: Bool
    /// Creates a server uiform progress.
    public init(subtitle: String, forwardTitle: String?, forwardEnabled: Bool, hasPrevious: Bool, canSubmit: Bool) {
        self.subtitle = subtitle; self.forwardTitle = forwardTitle; self.forwardEnabled = forwardEnabled
        self.hasPrevious = hasPrevious; self.canSubmit = canSubmit
    }
}

/// A form session that moves through ordered steps.
@MainActor
public protocol ServerUISteppedFormSession: ServerUIFormSession {
    var progress: ServerUIFormProgress { get }
    func advance() throws
    func retreat() throws
}

/// A selection-only filter and a user-content draft share controls, not commit semantics.
public enum ServerUIRecordFailure: Error, Equatable, LocalizedError {
    case missingProvider, invalidField, invalidValue, staleSelection, busy, unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .missingProvider: "The required data provider is unavailable."
        case .invalidField: "This form no longer matches its data provider."
        case .invalidValue: "Check the entered value."
        case .staleSelection: "This item changed. Open it again."
        case .busy: "Wait for the current action to finish."
        case .unavailable(let message): message
        }
    }
}
