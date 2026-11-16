#if os(iOS)
import Foundation
import HassCore

// MARK: - Drawn symbols

/// Resolves a document symbol to one this device draws.
///
/// HassCore keeps the authored name (``ServerUICompositionDocument/Symbol/name``) and holds no device state; this UIKit-layer
/// resolver answers from the facts ``UKServerUIPreflight`` installs, so a widget or the Watch, which never install one, read the
/// authored name deterministically. Reads come from any thread a renderer builds on, so the check and its memo sit behind a lock.
enum ServerUISymbolFallback {
    private struct State {
        var check: (@Sendable (String) -> Bool)?
        var memo: [String: String] = [:]
    }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    /// Installs the device's symbol check and forgets earlier answers. `nil` draws every name as written.
    static func install(_ check: (@Sendable (String) -> Bool)?) {
        lock.lock(); defer { lock.unlock() }
        state = State(check: check)
    }

    /// The symbol to draw for `name`: the name itself, or ``ServerUIDeviceFacts/fallbackSymbol`` when the installed check fails it.
    static func resolve(_ name: String) -> String {
        lock.lock()
        let (check, known) = (state.check, state.memo[name])
        lock.unlock()
        if let known { return known }
        guard let check else { return name }
        let resolved = check(name) ? name : ServerUIDeviceFacts.fallbackSymbol
        lock.lock(); state.memo[name] = resolved; lock.unlock()
        return resolved
    }
}

extension ServerUICompositionDocument.Symbol {
    /// The name to draw on this device: ``name``, or the fallback symbol when the OS lacks it.
    var drawn: String { ServerUISymbolFallback.resolve(name) }
}
#endif
