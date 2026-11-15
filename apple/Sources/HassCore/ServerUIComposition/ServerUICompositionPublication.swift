import Foundation

// MARK: - Compiler boundary

/// A sanitized compiler diagnostic. It never includes authored values or decoder descriptions.
public struct ServerUICompositionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: Code
    public let pointer: String
    public let capability: String?

    /// The authored code choices.
    public enum Code: String, Sendable {
        case unsupportedSchema = "unsupported_schema"
        case unknownField = "unknown_field"
        case unknownVariant = "unknown_variant"
        case missingRequired = "missing_required"
        case invalidValue = "invalid_value"
        case duplicateKey = "duplicate_key"
        case limitExceeded = "limit_exceeded"
        case duplicateID = "duplicate_id"
        case invalidReference = "invalid_reference"
        case bindingType = "binding_type"
        case invalidCombination = "invalid_combination"
        case capabilityManifestMismatch = "capability_manifest_mismatch"
        case unsupportedCapability = "unsupported_capability"
        case assetIntegrity = "asset_integrity"
    }

    init(_ code: Code, _ pointer: String, capability: String? = nil) {
        self.code = code
        self.pointer = pointer
        self.capability = capability
    }

    public var description: String {
        "\(code.rawValue) at \(pointer)\(capability.map { " [\($0)]" } ?? "")"
    }
}

/// An immutable, shape/reference/capability-validated schema-2 publication.
///
/// This is **pure compiler acceptance**, not native renderer certification. Before promotion,
/// the parent must verify exact SF Symbol availability and supported UIKit combinations on the
/// actual OS, stage and verify asset bytes/signatures/dimensions and the initial backdrop,
/// coordinate interaction guards, and durably save the accepted plan. No network, UI, state
/// mutation, account trust, revision ordering, or service dispatch happens here.
///
/// Models intentionally have no public initializer or `Decodable` conformance that bypasses
/// ``decode(_:)``. Schema 1 APIs remain separate and unchanged.
public struct ServerUICompositionPublication: Equatable, Sendable {
    public let envelopeVersion: String
    public let publisherId: String
    public let revision: Int
    public let updatedAt: String
    public let publishedAt: String
    public let capabilities: [String]
    public let assetManifestSha256: String
    public let document: ServerUICompositionDocument
    /// SHA-256 of the compiler's canonical document bytes, independent of publication metadata.
    public let documentSha256: String

    /// The exact semantic profile understood by this compiler, not a UIKit support claim.
    public static let firstSliceCapabilities = [
        "sh.actions.navigation@1", "sh.assets.publisher@1", "sh.backdrop@1",
        "sh.bindings@1", "sh.chrome@1", "sh.composition@1", "sh.grid@1",
        "sh.page@1", "sh.power-toggle@1", "sh.sheet@1", "sh.shell@1",
        "sh.symbols@1", "sh.text@1", "sh.tiles@1"
    ]

    /// Additional strictly negotiated extensions understood by the pure compiler.
    public static let supportedCapabilities = firstSliceCapabilities + [
        "sh.supporting-text-styles@1",
        "sh.section-title@1",
        "sh.surface-title-source@1",
        "sh.grid-dynamic-type@1", "sh.sheet-fit@1", "sh.tile-presentation@1",
        "sh.alarm-mode@1", "sh.inventory-summary@1", "sh.section@1",
        "sh.rows@1", "sh.local-tabs@1", "sh.local-state@1",
        "sh.local-controls@1", "sh.primary-button@1", "sh.row-collection@1",
        "sh.collection@1", "sh.form@1", "sh.recipe-part@1", "sh.pinned-actions@1",
        "sh.modal-handoff@1", "sh.bedroom-collection-links@1",
        "sh.navigation-columns@1",
        "sh.adaptive-presentation@1",
        "sh.pinned-tabs@1",
        "sh.shell-header@1",
        "sh.collection-navigation@1",
        "sh.info-box@1", "sh.status-pill@1", "sh.paged-row@1",
        "sh.schedule-date-fields@1",
        "sh.presentation-providers@1", "sh.pinned-form-actions@1", "sh.section-grid@1", "sh.full-screen-modal@1", "sh.module-settings-rows@1",
        "sh.home-status@1", "sh.status-chip@1", "sh.status-rail@1",
        "sh.room-overview-tile@1", "sh.home-light@1", "sh.light-group-tile@1", "sh.room-light-power@1", "sh.power-labels@1",
        "sh.home-weather@1", "sh.weather-panel@1", "sh.alarm-panel@1",
        "sh.security-door@1", "sh.climate-source@1", "sh.climate-dial@1",
        "sh.climate-toggle@1", "sh.climate-check@1", "sh.climate-mode@1", "sh.climate-link@1", "sh.climate-room-tile@1",
        "sh.climate-fan@1", "sh.climate-preset@1", "sh.climate-options@1",
        "sh.climate-status@1", "sh.climate-hub@1", "sh.climate-notice@1",
        "sh.todo-counts@1", "sh.settings-link@1", "sh.room-navigation@1",
        "sh.room-card@1", "sh.room-chip@1", "sh.room-section@1",
        "sh.room-visibility@1", "sh.air-purifier@1", "sh.bathroom-fan@1",
        "sh.grill@1", "sh.humidifier@1", "sh.humidifier-scheduling@1",
        "sh.media-remote@1", "sh.remote-keys@1", "sh.remote-volume@1",
        "sh.remote-keyboard@1", "sh.remote-app@1", "sh.remote-device@1",
        "sh.remote-hue-toggle@1", "sh.remote-hue-choice@1", "sh.remote-hue-brightness@1",
        "sh.remote-hue-input@1", "sh.remote-card@1", "sh.sprinkler-state@1",
        "sh.vacuum@1", "sh.vacuum-map@1", "sh.vacuum-controls@1", "sh.vacuum-auto-clean@1",
        "sh.vacuum-outcomes@1", "sh.vacuum-area@1", "sh.inventory-list@1",
        "sh.household-away-status@1", "sh.profile-account@1", "sh.camera-stream@1", "sh.settings-controls@1",
        "sh.camera-tile@1", "sh.camera-video@1", "sh.camera-controls@1",
        "sh.camera-viewer@1", "sh.bootstrap-policy@1", "sh.bootstrap-message@1",
        "sh.bootstrap-notifications@1", "sh.activity-presentation@1", "sh.native-extensions@1", "sh.route-links@1",
        "sh.media-remote-config@1", "sh.bedroom-config@1", "sh.custom-lights@1", "sh.sprinkler-controller@1",
        "sh.remote-speaker-targets@1",
        // Generic actions, bound controls and per-node rules: a document requires them only when it uses them.
        "sh.call-service@1", "sh.bound-control@1", "sh.visible-when@1", "sh.selected-when@1", "sh.operands@1",
        // The record pages house configuration used to define; a document requires it only when it declares one.
        "sh.todo-collection@1",
        // Authored state styles: a document-level library and the `state-tile` node; required only when a document uses them.
        serverUIStateStyleCapability,
    ] + ServerUIBedroomControl.capabilities

    /// Parses bounded, duplicate-key-aware JSON and compiles every definition, including hidden
    /// and unreachable ones. All failures are sanitized ``ServerUICompositionError`` values.
    /// Schema 2 allows a 2 MiB document, 64 KiB envelope overhead, 100,000 JSON values,
    /// 256 pages, 256 modals and 1,000 sources. Schema-1 decoding retains its own limits.
    public static func decode(_ bytes: Data) throws -> Self {
        try ServerUICompositionCompiler.decode(bytes)
    }
}
