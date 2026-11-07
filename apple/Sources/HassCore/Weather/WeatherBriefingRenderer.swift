import Foundation

/// Turns a briefing into text with the weather copy deck.
public enum WeatherBriefingRenderer {
    /// Renders one reference, resolving nested references first.
    public static func render(_ ref: WeatherBriefingRef) -> String {
        var values: [String: String] = [:]
        for (name, value) in ref.values {
            switch value {
            case let .text(text): values[name] = text
            case let .number(number): values[name] = number == number.rounded() ? String(Int(number)) : String(number)
            case let .ref(nested): values[name] = render(nested)
            }
        }
        return WeatherCopy.text(ref.key, values)
    }

    /// All sentences joined by a space.
    public static func text(_ briefing: WeatherDayBriefing) -> String {
        briefing.sentences.map(render).joined(separator: " ")
    }

    /// The headline: a hazard or condition label.
    public static func headline(_ briefing: WeatherDayBriefing) -> String {
        if let headline = briefing.headline { return render(headline) }
        return briefing.headlineText ?? ""
    }
}
