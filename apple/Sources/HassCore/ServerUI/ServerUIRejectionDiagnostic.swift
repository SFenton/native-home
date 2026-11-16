import Foundation

/// An error that can say what it is without carrying a value: a case name and, where there is one, a JSON pointer.
public protocol ServerUIDiagnosable: Error {
    /// A short, value-free description such as `unavailable_source at /document/dataSources`.
    var diagnostic: String { get }
}

extension ServerUICompositionError: ServerUIDiagnosable {
    public var diagnostic: String { description }
}

/// Describes why a publication was rejected in terms that are safe to log and to show in a debug build: case names, pointers
/// and type names only, never an associated value or a message from the system.
public enum ServerUIRejectionDiagnostic {
    /// - Parameter error: Whatever the acceptance threw.
    /// - Returns: The case and pointer, or the type name when the error is not one of ours.
    public static func describe(_ error: any Error) -> String {
        switch error {
        case let error as any ServerUIDiagnosable: return error.diagnostic
        case let error as ServerUIStoreError:
            if case let .composition(inner) = error { return "composition: \(inner.diagnostic)" }
            if case let .asset(inner) = error { return "asset: \(inner)" }
            return "store: \(error)"
        case let error as ServerUIAssetError: return "asset: \(error)"
        default: return "unclassified: \(String(reflecting: type(of: error)))"
        }
    }
}
