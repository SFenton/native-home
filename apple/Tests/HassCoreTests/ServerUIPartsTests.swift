import Foundation
import Testing
@testable import HassCore

// MARK: - The generic parts (TC3)

/// A reader over fixed reads, with a state for each source and attributes by path.
private struct Reader: ServerUIReading {
    var reads: [String: ServerUIReadResult] = [:]
    func read(sourceId: String, path: [String]) -> ServerUIReadResult { reads[([sourceId] + path).joined(separator: "/")] ?? .unavailable }
    var viewer: ServerUIViewer? { nil }
    func viewerPersonState() -> ServerUIReadResult { .unavailable }
}

private func strings(_ items: JSONValue...) -> ServerUIReadResult { .value(.array(items)) }

@MainActor
struct ServerUIPartsTests {
    typealias D = ServerUICompositionDocument

    private static var house: HouseConfigSource {
        let source = HouseConfigSource()
        source.set(DemoHouse.config)
        return source
    }

    /// The component at `index` of the third page of an accepted corpus case.
    private func component(_ file: String, at index: Int = 0) throws -> D.Component {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent("accept/\(file).json")
        let publication = try HouseConfigSource.$scoped.withValue(Self.house) {
            try ServerUICompositionPublication.decode(Data(contentsOf: url))
        }
        return publication.document.pages[2].surface.components[index]
    }

    private func boundControl(_ file: String) throws -> D.BoundControl {
        guard case .boundControl(let control) = try component(file) else { Issue.record("not a bound control"); throw CancellationError() }
        return control
    }

    private func tile(_ file: String) throws -> D.StateTile {
        guard case .stateTile(let tile) = try component(file) else { Issue.record("not a state tile"); throw CancellationError() }
        return tile
    }

    // MARK: Ids

    @Test func theFiveIdsAreShippedAndListedOnce() {
        let ids = ["sh.bound-options-read@1", "sh.tile-disc-rules@1", "sh.grid-min-columns@1", "sh.bound-row-parts@1", "sh.check-face@1"]
        for id in ids {
            #expect(ServerUIIngestedCapabilities.grammar.contains(id))
            #expect(ServerUICompositionPublication.supportedCapabilities.contains(id))
        }
        #expect(Set(ServerUIIngestedCapabilities.all).count == ServerUIIngestedCapabilities.all.count)
    }

    // MARK: Options read from an entity (`sh.bound-options-read@1`)

    @Test func optionsFromDecodesTheListTheCurrentValueTheLabelsAndTheCall() throws {
        let control = try boundControl("parts-options-from-attribute")
        let read = try #require(control.optionsFrom)
        #expect(read.sourceId == "speed" && read.path == ["attributes", "options"])
        #expect(read.labels == .titleCase)
        #expect(read.action.service == "select_option")
        #expect(control.options.count == 2, "the authored options stay as the fallback")
        #expect(control.sourceIds.contains("speed"))
        #expect(control.actions.contains(read.action))
    }

    @Test func asIsLabelsKeepTheItemAndAnExpressionGivesTheCurrentValue() throws {
        #expect(try boundControl("parts-options-as-is-labels").optionsFrom?.labels == .asIs)
        let byExpression = try #require(try boundControl("parts-options-current-by-expression").optionsFrom)
        let reader = Reader(reads: ["speed/state": .value(.string("turbo"))])
        #expect(byExpression.currentValue(in: reader) != nil)
    }

    @Test func theOptionsAreTheTextItemsOnceInOrderTitleCasedOnRequest() {
        let items: [JSONValue] = [.string("quiet"), .string("max_power"), .number(3), .string("   "), .string("quiet"), .null, .string("auto")]
        let titled = ServerUIOptionsRead.options(from: items, labels: .titleCase)
        #expect(titled?.map(\.value) == ["quiet", "max_power", "auto"])
        #expect(titled?.map(\.label) == ["Quiet", "Max Power", "Auto"])
        #expect(ServerUIOptionsRead.options(from: items, labels: .asIs)?.map(\.label) == ["quiet", "max_power", "auto"])
    }

    @Test func atMostTwelveOptionsAreKept() {
        let items = (0..<20).map { JSONValue.string("option_\($0)") }
        #expect(ServerUIOptionsRead.options(from: items, labels: .asIs)?.count == ServerUIOptionsRead.maximumOptions)
        #expect(ServerUIOptionsRead.options(from: items, labels: .asIs)?.last?.value == "option_11")
    }

    @Test func fewerThanTwoUsableItemsUseTheAuthoredOptions() {
        #expect(ServerUIOptionsRead.options(from: [], labels: .asIs) == nil)
        #expect(ServerUIOptionsRead.options(from: [.string("only")], labels: .asIs) == nil)
        #expect(ServerUIOptionsRead.options(from: [.string("a"), .string("a"), .number(1)], labels: .asIs) == nil)
    }

    @Test func aListThatIsMissingLoadingOrNotAListLeavesTheAuthoredOptions() throws {
        let read = try #require(try boundControl("parts-options-from-attribute").optionsFrom)
        let path = "speed/attributes/options"
        #expect(read.options(in: Reader()) == nil)
        #expect(read.options(in: Reader(reads: [path: .loading])) == nil)
        #expect(read.options(in: Reader(reads: [path: .value(.string("quiet"))])) == nil)
        #expect(read.options(in: Reader(reads: [path: strings("quiet", "turbo")]))?.map(\.label) == ["Quiet", "Turbo"])
    }

    @Test func theCurrentValueIsTextOrNil() throws {
        let read = try #require(try boundControl("parts-options-from-attribute").optionsFrom)
        #expect(read.currentValue(in: Reader(reads: ["speed/state": .value(.string("quiet"))])) == "quiet")
        #expect(read.currentValue(in: Reader(reads: ["speed/state": .loading])) == nil)
        #expect(read.currentValue(in: Reader()) == nil)
    }

    // MARK: A tile button that follows a rule (`sh.tile-disc-rules@1`)

    @Test func aDiscKeepsItsPlainSymbolAndLabelWhenNothingFollowsARule() throws {
        let disc = try #require(try tile("tile-parts-two-discs-enabled-when").parts.discs.first)
        #expect(disc.iconRule == nil && disc.labelValue == nil && !disc.namesTile)
        #expect(disc.resolvedIcon(in: Reader()) == disc.icon)
        #expect(disc.resolvedLabel(read: { _ in .unavailable }, in: Reader()) == disc.label)
    }

    @Test func aConditionalSymbolFollowsTheEntityAndFallsToItsOtherwise() throws {
        let disc = try #require(try tile("parts-disc-conditional-symbol").parts.discs.first)
        #expect(disc.iconRule != nil)
        #expect(disc.icon.name == "play.fill", "the slot's own value is the otherwise")
        #expect(disc.resolvedIcon(in: Reader(reads: ["robot/state": .value(.string("cleaning"))])).name == "pause.fill")
        #expect(disc.resolvedIcon(in: Reader(reads: ["robot/state": .value(.string("docked"))])).name == "play.fill")
        #expect(disc.ruleSourceIds.contains("robot"))
    }

    @Test func aSymbolNamedByTheEntityFallsBackWhenItCannotBeRead() throws {
        let disc = try #require(try tile("parts-disc-symbol-from-entity").parts.discs.first)
        #expect(disc.resolvedIcon(in: Reader(reads: ["robot/attributes/button_icon": .value(.string("stop.fill"))])).name == "stop.fill")
        #expect(disc.resolvedIcon(in: Reader()).name == "play.fill")
    }

    @Test func aLoadingRuleKeepsWhatTheDiscLastShowed() throws {
        let disc = try #require(try tile("parts-disc-symbol-from-entity").parts.discs.first)
        let shown = D.Symbol(name: "stop.fill", rendering: disc.icon.rendering, unavailable: disc.icon.unavailable)
        let loading = Reader(reads: ["robot/attributes/button_icon": .loading])
        #expect(disc.resolvedIcon(in: loading, keeping: shown) == shown)
        #expect(disc.resolvedIcon(in: loading).name == "play.fill", "with nothing shown yet, the otherwise stands")
    }

    @Test func aLabelFollowsAnExpressionAndKeepsItsLastWordsWhileLoading() throws {
        let disc = try #require(try tile("parts-disc-label-by-expression").parts.discs.first)
        #expect(disc.labelValue != nil)
        func words(_ state: String?, keeping: String? = nil, loading: Bool = false) -> String {
            var reads: [String: ServerUIReadResult] = [:]
            if loading { reads["robot/state"] = .loading } else if let state { reads["robot/state"] = .value(.string(state)) }
            return disc.resolvedLabel(read: { _ in .unavailable }, in: Reader(reads: reads), keeping: keeping)
        }
        #expect(words("cleaning") == "Pause")
        #expect(words("paused") == "Resume")
        #expect(words("docked") == "Start")
        #expect(words(nil, keeping: "Pause", loading: true) == "Pause")
    }

    @Test func aLabelThatIsAnObjectLiteralSaysItsText() throws {
        let disc = try #require(try tile("parts-disc-label-object-literal").parts.discs.first)
        #expect(disc.labelValue != nil && !disc.label.isEmpty)
        #expect(disc.resolvedLabel(read: { _ in .unavailable }, in: Reader()) == disc.label)
    }

    @Test func namesTileIsReadFromTheDisc() throws {
        let discs = try tile("parts-disc-all-three").parts.discs
        #expect(discs.count == 2 && discs.allSatisfy(\.namesTile))
        #expect(try tile("parts-disc-label-names-tile").parts.discs.first?.namesTile == true)
    }

    @Test func aDiscNeedsTheCapabilityOnlyForARuleASlotOrNamesTile() throws {
        let plain = try tile("tile-parts-two-discs-enabled-when")
        #expect(plain.parts.discs.allSatisfy { $0.iconRule == nil && $0.labelValue == nil && !$0.namesTile })
    }

    // MARK: The grid's least columns (`sh.grid-min-columns@1`)

    @Test func minimumColumnsDecodesAndAnAbsentOneStaysNil() throws {
        guard case .grid(let robots) = try component("parts-columns-two-robots-across") else { Issue.record("not a grid"); return }
        #expect(robots.minimumColumns == 2)
        guard case .grid(let wide) = try component("parts-columns-on-a-wide-section-grid") else { Issue.record("not a grid"); return }
        #expect(wide.minimumColumns == 2 && wide.minimum == .sectionWide)
        guard case .grid(let equal) = try component("parts-columns-equal-to-the-most") else { Issue.record("not a grid"); return }
        #expect(equal.minimumColumns == equal.maxColumns)
    }

    // MARK: A toggle row's parts and face (`sh.bound-row-parts@1`, `sh.check-face@1`)

    @Test func theAutoCleanRowDecodesEveryPart() throws {
        let control = try boundControl("parts-row-auto-clean-row")
        let row = control.row
        #expect(control.icon?.name == "clock.arrow.circlepath")
        #expect(row.hint == "Turns automatic cleaning on or off.")
        #expect(row.failureText == "Automatic cleaning did not respond.")
        #expect(row.metrics == .module && row.face == .switch && row.checkTint == nil)
        #expect(row.glyph == .solidRGB(red: 175, green: 82, blue: 222))
        #expect(row.subtitle != nil)
        #expect(control.sourceIds.contains("auto-clean"))
    }

    @Test func theSubtitleIsATextSlotThatSaysWhatTheEntityDoes() throws {
        let row = try boundControl("parts-row-auto-clean-row").row
        let subtitle = try #require(row.subtitle)
        func said(_ state: String) -> ServerUIReadResult {
            ServerUIStringResolver.resolve(subtitle, read: { _ in .unavailable }, in: Reader(reads: ["auto-clean/state": .value(.string(state))]))
        }
        #expect(said("on") == .value(.string("Paused")))
        #expect(said("off") == .value(.string("Off")))
        // A rule whose entity cannot be read says nothing new: the row keeps the line it showed (and says its unavailable words itself).
        #expect(ServerUIStringResolver.resolve(subtitle, read: { _ in .unavailable }, in: Reader()) == .loading)
    }

    @Test func aGlyphTintFollowsARuleAndKeepsWhatItShowedWhileLoading() throws {
        let row = try boundControl("parts-row-glyph-by-rule").row
        let green = D.TileFill.solidRGB(red: 48, green: 209, blue: 88), grey = D.TileFill.solidRGB(red: 142, green: 142, blue: 147)
        #expect(row.resolvedGlyph(in: Reader(reads: ["auto-clean/state": .value(.string("on"))])) == green)
        #expect(row.resolvedGlyph(in: Reader(reads: ["auto-clean/state": .value(.string("off"))])) == grey)
        // A rule that cannot be answered yet stands at its `otherwise`, so the tint never flickers to a third value.
        #expect(row.resolvedGlyph(in: Reader(reads: ["auto-clean/state": .loading]), keeping: green) == grey)
        #expect(row.sourceIds.contains("auto-clean"))
    }

    @Test func formMetricsAndAPlainSubtitleDecode() throws {
        #expect(try boundControl("parts-row-form-metrics").row.metrics == .form)
        #expect(try boundControl("parts-row-subtitle-plain").row.subtitle != nil)
    }

    @Test func aCheckFaceKeepsTheHintTheFailureWordsAndTheTint() throws {
        let control = try boundControl("parts-check-room-row")
        #expect(control.row.isCheck && control.row.checkTint == .action)
        #expect(control.row.hint == "Includes the room in the cycle.")
        #expect(control.row.failureText == "The room did not respond.")
        #expect(control.icon == nil && control.row.subtitle == nil && control.row.glyph == nil && control.row.metrics == nil)
        #expect(try boundControl("parts-check-success-tint").row.checkTint == .success)
        let explicit = try boundControl("parts-check-explicit-switch-face")
        #expect(explicit.row.face == .switch && !explicit.row.isCheck)
    }

    @Test func aToggleWithNoPartsKeepsTheDefaults() throws {
        let plain = ServerUIRowParts()
        #expect(plain.subtitle == nil && plain.hint == nil && plain.metrics == nil && plain.failureText == nil && plain.glyph == nil)
        #expect(plain.face == .switch && plain.checkTint == nil && !plain.isCheck && plain.sourceIds.isEmpty)
        #expect(plain.resolvedGlyph(in: Reader()) == nil)
    }

    // MARK: Refusals

    /// The corpus case `file` with `capability` removed from its manifest.
    private func decode(_ file: String, without capability: String) throws -> Error? {
        let url = ServerUIContractCorpusTests.directory.appendingPathComponent("accept/\(file).json")
        var json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        guard case .object(var object) = json, case .array(let capabilities)? = object["capabilities"] else { Issue.record("no manifest"); return nil }
        object["capabilities"] = .array(capabilities.filter { $0 != .string(capability) })
        json = .object(object)
        do {
            _ = try HouseConfigSource.$scoped.withValue(Self.house) {
                try ServerUICompositionPublication.decode(JSONEncoder().encode(json))
            }
            return nil
        } catch { return error }
    }

    @Test(arguments: [
        ("parts-options-from-attribute", "sh.bound-options-read@1"), ("parts-disc-label-by-expression", "sh.tile-disc-rules@1"),
        ("parts-columns-two-robots-across", "sh.grid-min-columns@1"), ("parts-row-auto-clean-row", "sh.bound-row-parts@1"),
        ("parts-check-room-row", "sh.check-face@1"), ("parts-check-room-row", "sh.bound-row-parts@1"),
    ])
    func aDocumentThatUsesAPartMustDeclareItsCapability(file: String, capability: String) throws {
        let error = try decode(file, without: capability)
        #expect(error != nil, "\(file) decoded without \(capability)")
    }
}
