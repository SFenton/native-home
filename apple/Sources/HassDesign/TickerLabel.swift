import Foundation

/// The ticker's launch switch (pattern: `.agents/patterns/ticker.md`). The scrolling label itself is `UKTickerLabel`; the plan it
/// follows is ``TickerPlan``.
public enum TickerLabel {
    /// Whether this launch adds the probe elements (UI tests set `FENTON_TICKER_PROBE=1`; hosted tests set it directly).
    nonisolated(unsafe) public static var probeEnabled = ProcessInfo.processInfo.environment["FENTON_TICKER_PROBE"] == "1"
}
