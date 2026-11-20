import Foundation

// MARK: - Answerer

/// Resolves a spoken question, routes it, and answers.
///
/// Code retrieves; the model only phrases. Decline, "which one", "no such device" and "unavailable" are fixed sentences. Where
/// code already holds the complete answer (a state, a reading, a count, a duration, a comparison) it writes the sentence
/// itself. Only a path listed in ``AskConfiguration/modelPaths`` builds a slice and calls the injected `phrase` closure; when
/// no closure is given, or it throws, the code-written draft stands, so the answer never depends on the model being there.
public struct AskAnswerer: Sendable {
    /// Phrases a slice: `instructions` and the `prompt` slice in, the answer out. The app wires it to Foundation Models.
    public typealias Phrase = @Sendable (_ instructions: String, _ prompt: String) async throws -> String

    /// The index answers read.
    public let index: AskableIndex
    /// The resolver.
    public let resolver: AskResolver
    let composer: AskComposer
    let causes: AskCauseResolver
    let durations: AskDurationResolver
    let lastTimes: AskLastTimeResolver
    let slicer: AskSliceBuilder
    let phrase: Phrase?

    /// Creates an answerer.
    /// - Parameters:
    ///   - index: The index to read.
    ///   - dataSource: Logbook and history reads (``AskNoDataSource`` answers from states alone).
    ///   - phrase: The model hook, or nil for code-written answers only.
    ///   - tokenCount: The model's token counter; the default estimates from characters.
    public init(
        index: AskableIndex, dataSource: AskDataSource = AskNoDataSource(), phrase: Phrase? = nil,
        tokenCount: (@Sendable (String) -> Int)? = nil
    ) {
        self.index = index
        resolver = AskResolver(index: index)
        composer = AskComposer(index: index)
        causes = AskCauseResolver(index: index, dataSource: dataSource)
        durations = AskDurationResolver(index: index, dataSource: dataSource)
        lastTimes = AskLastTimeResolver(index: index, dataSource: dataSource)
        slicer = AskSliceBuilder(budget: index.configuration.budget, tokenCount: tokenCount)
        self.phrase = phrase
    }

    // MARK: Answer

    /// Answers one question.
    /// - Parameters:
    ///   - question: The spoken question.
    ///   - allowing: The most private class the caller may reveal (a locked phone passes ``AskSensitivity/home``).
    public func answer(_ question: String, allowing: AskSensitivity = .security) async -> AskResult {
        let clock = ContinuousClock()
        let started = clock.now
        var result = await compute(question, allowing: allowing, clock: clock, started: started)
        result.timings.totalMs = Self.ms(clock.now - started)
        return result
    }

    private func compute(_ question: String, allowing: AskSensitivity, clock: ContinuousClock, started: ContinuousClock.Instant) async -> AskResult {
        let resolution = resolver.resolve(question)
        var timings = AskResult.Timings()
        timings.resolveMs = Self.ms(clock.now - started)
        var result = AskResult(
            question: question, resolution: resolution, path: .code, answer: "", draft: "", facts: [], usedModel: false,
            modelSkipped: false, inputTokens: nil, sensitivity: .everyday, timings: timings, error: nil
        )

        switch resolution.route {
        case .declineAction:
            return finish(&result, .fixedDecline, composer.declineAction)
        case .declineOfftopic:
            return finish(&result, .fixedDecline, composer.declineOfftopic)
        case .none:
            return finish(&result, .fixedNone, composer.none(resolution.unmatchedPhrase))
        case .notConfigured:
            return finish(&result, .fixedNotConfigured, composer.notConfigured(resolution.parts))
        case .several:
            result.sensitivity = Self.sensitivity(of: resolution.candidateIds, index: index)
            return finish(&result, .fixedSeveral, composer.several(resolution.candidateIds))
        case .unavailable:
            result.sensitivity = Self.sensitivity(of: resolution.entityIds, index: index)
            if let held = held(result.sensitivity, allowing: allowing) { return finish(&result, held.path, held.text) }
            let text = resolution.entityIds.first.flatMap(index.entry).map(composer.unavailable) ?? composer.none(nil)
            return finish(&result, .fixedUnavailable, text)
        case .found, .group:
            break
        }
        result.sensitivity = Self.sensitivity(of: resolution.entityIds, index: index)
        if let held = held(result.sensitivity, allowing: allowing) { return finish(&result, held.path, held.text) }

        // Gather what the answer needs beyond the states.
        let dataStart = clock.now
        let facts = await gather(resolution)
        result.timings.dataMs = Self.ms(clock.now - dataStart)
        // A cause can name another configured entity; the answer is as private as the stricter of the two.
        result.sensitivity = max(result.sensitivity, facts.causes.values.map(\.sensitivity).max() ?? .everyday)
        if let held = held(result.sensitivity, allowing: allowing) { return finish(&result, held.path, held.text) }
        let draft = composer.sentence(resolution, facts: facts)
        result.draft = draft
        result.facts = factLines(resolution, facts: facts)
        guard wantsModel(resolution, facts: facts) else {
            result.answer = draft
            result.path = .code
            return result
        }
        guard let phrase else {
            result.answer = draft
            result.path = .code
            result.modelSkipped = true
            return result
        }
        let slice = buildSlice(resolution, facts: facts, question: question)
        result.inputTokens = slice.tokens
        if slice.overCap {
            result.answer = "That matches too many things to read out; name a room."
            result.path = .code
            return result
        }
        let phraseStart = clock.now
        do {
            let text = try await phrase(AskInstructions.text(houseName: index.houseName), slice.prompt)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw AskPhraseError.empty }
            result.answer = trimmed
            result.usedModel = true
            result.path = .model
        } catch {
            result.answer = draft
            result.path = .code
            result.error = String(describing: error)
        }
        result.timings.phraseMs = Self.ms(clock.now - phraseStart)
        return result
    }

    // MARK: Pieces

    /// The fixed sentence that stands in for an answer of class `sensitivity`, or nil when it may be spoken.
    ///
    /// The highest class is withheld outright while ``AskConfiguration/withholdSecurityState`` is on; any class above what
    /// the caller allows needs an unlocked phone.
    private func held(_ sensitivity: AskSensitivity, allowing: AskSensitivity) -> (path: AskAnswerPath, text: String)? {
        if index.configuration.withholdSecurityState, sensitivity >= .security { return (.fixedWithheld, composer.withheld) }
        if sensitivity > allowing { return (.fixedLocked, composer.locked) }
        return nil
    }

    private func finish(_ r: inout AskResult, _ path: AskAnswerPath, _ text: String) -> AskResult {
        r.path = path
        r.answer = text
        r.draft = text
        return r
    }

    private func gather(_ r: AskResolution) async -> AskFacts {
        var facts = AskFacts()
        let entries = r.parts.flatMap(\.entityIds).compactMap(index.entry)
        let i = r.intent
        if i.wantsWhy { for e in entries.prefix(4) { facts.causes[e.id] = await causes.resolve(e) } }
        if i.wantsHowLong { for e in entries.prefix(4) { facts.durations[e.id] = await durations.resolve(e) } }
        if i.wantsLast { for e in entries.prefix(4) { facts.lastTimes[e.id] = await lastTimes.resolve(e, predicate: i.predicate) } }
        if i.comparison == .longest {
            for e in entries where !e.isUnavailable && AskStateWords.matches(e, .on) == true && !e.excludedFromAggregates {
                facts.durations[e.id] = await durations.resolve(e)
            }
        }
        return facts
    }

    /// Whether this answer goes through the model: only a configured path whose facts need phrasing.
    func wantsModel(_ r: AskResolution, facts: AskFacts) -> Bool {
        let paths = index.configuration.modelPaths
        if paths.contains(.everything) { return true }
        if paths.contains(.cause), r.intent.wantsWhy {
            return facts.causes.values.contains { $0.cause.isNamed || !$0.annotatorLines.isEmpty }
        }
        if paths.contains(.compound), r.parts.count > 1 { return true }
        if paths.contains(.listing), r.parts.contains(where: { $0.kind == .group && $0.entityIds.count > 6 }) { return true }
        return false
    }

    private func factLines(_ r: AskResolution, facts: AskFacts) -> [String] {
        let entries = r.parts.flatMap(\.entityIds).compactMap(index.entry)
        let cap = index.configuration.budget.maxEntityLines
        return entries.prefix(cap).map { composer.lines.line($0, duration: facts.durations[$0.id]) }
    }

    /// The slice the model phrases from.
    func buildSlice(_ r: AskResolution, facts: AskFacts, question: String) -> AskSlice {
        let entries = r.parts.flatMap(\.entityIds).compactMap(index.entry)
        var header: [String] = []
        if r.route == .group, entries.count > 1 {
            header.append("RESULT: one group of \(entries.count): " + entries.prefix(index.configuration.budget.maxListedNames).map(\.displayName).joined(separator: ", "))
        } else {
            header.append("RESULT: found \(entries.count): " + entries.prefix(index.configuration.budget.maxListedNames).map(\.displayName).joined(separator: ", "))
        }
        let entityLines = entries.map { composer.lines.line($0, duration: facts.durations[$0.id]) }
        var causeLines: [String] = []
        var annotatorLines: [String] = []
        for e in entries {
            guard let result = facts.causes[e.id] else { continue }
            let prefix = entries.count == 1 ? "CAUSE" : "CAUSE (\(e.displayName))"
            causeLines.append("\(prefix): " + Self.causePhrase(result.cause, index: index))
            for line in result.annotatorLines { annotatorLines.append("NOTE (\(e.displayName)): \(line)") }
        }
        return slicer.build(
            instructions: AskInstructions.text(houseName: index.houseName), header: header, entityLines: entityLines,
            causeLines: causeLines, annotatorLines: annotatorLines, question: question
        )
    }

    static func causePhrase(_ cause: AskCause, index: AskableIndex) -> String {
        func ago(_ s: TimeInterval) -> String { AskDuration.phrase(seconds: s) + " ago" }
        switch cause {
        case .automation(let name, let message, let s): return "\(ago(s)) by automation \"\(name)\"\(message.map { " (\($0))" } ?? "")"
        case .script(let name, let s): return "\(ago(s)) by script \"\(name)\""
        case .person(let name, let s): return "\(ago(s)) by \(name)"
        case .entity(let name, let state, let s): return "\(name) turned \(state ?? "it") \(ago(s))"
        case .other(let s): return "\(ago(s)), set by \(AskCause.otherWording)"
        case .service(let service, let s): return "a \(service) command \(ago(s)); who sent it is not recorded"
        case .physical(let s): return "\(ago(s)), the device itself reported the change (physical or manual); no automation or person is recorded"
        case .restart: return "re-reported when Home Assistant restarted; the cause is not recorded"
        case .none: return "not recorded"
        }
    }

    static func sensitivity(of ids: [String], index: AskableIndex) -> AskSensitivity {
        ids.compactMap(index.entry).map(\.sensitivity).max() ?? .everyday
    }

    private static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}

/// An error that makes the answerer keep its code-written draft.
enum AskPhraseError: Error { case empty }
