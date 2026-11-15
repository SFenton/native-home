import Foundation

/// A non-fatal copy fault: the user sees the fallback, and the fault is recorded for the Performance screen and telemetry.
///
/// Missing copy never rejects a layout; the table records the fault and answers with a default.
public enum CopyDiagnostic: Equatable, Hashable, Sendable {
    /// Neither an inline value, an override nor a compiled default exists for the id; the supplied fallback was returned.
    case missingKey(String)
    /// The template names a `{{placeholder}}` the caller supplied no value for; the placeholder was left in the text.
    case unfilledPlaceholder(id: String, name: String)

    /// The id the fault concerns.
    public var id: String {
        switch self {
        case .missingKey(let id): id
        case .unfilledPlaceholder(let id, _): id
        }
    }
}
