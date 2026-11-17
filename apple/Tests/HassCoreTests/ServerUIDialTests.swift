import Foundation
import Testing
@testable import HassCore

// MARK: - Dial and arc track (`sh.dial@1`, `sh.arc-track@1`)

/// What the dial and the arc track decode to, case by case over the Studio's corpus, and the arithmetic that places their parts.
///
/// The evaluation cases (`ContractCorpus/evaluation/dial-*.json`, `arc-track-*.json`) run in ``ServerUIExpressionCorpusTests``; here the
/// publications (`accept/dial-*`, `reject/dial-*`, `arc-track-*`) are decoded one by one, and the edges the corpus does not name are pinned.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIDialTests {
    nonisolated static let family: [ServerUIContractCorpusTests.Case] = ServerUIContractCorpusTests.cases.filter {
        let name = $0.file.split(separator: "/").last.map(String.init) ?? ""
        return name.hasPrefix("dial-") || name.hasPrefix("arc-track-")
    }

    private static func decode(_ file: String) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(file)))
    }

    /// Every dial and arc in a document, wherever a container holds it.
    private static func parts(of publication: ServerUICompositionPublication) -> (dials: [ServerUIDial], arcs: [ServerUIArcTrack]) {
        var dials: [ServerUIDial] = [], arcs: [ServerUIArcTrack] = []
        func visit(_ components: [ServerUICompositionDocument.Component]) {
            for component in components {
                _ = component.mapped { found in
                    if case .dial(let dial) = found { dials.append(dial) }
                    if case .arcTrack(let arc) = found { arcs.append(arc) }
                    return found
                }
            }
        }
        for page in publication.document.pages { visit(page.surface.components) }
        for modal in publication.document.modals { visit(modal.surface.components) }
        return (dials, arcs)
    }

    private static func dial(_ file: String) throws -> ServerUIDial { try #require(parts(of: try decode("accept/\(file).json")).dials.first) }
    private static func arc(_ file: String) throws -> ServerUIArcTrack { try #require(parts(of: try decode("accept/\(file).json")).arcs.first) }

    // MARK: The corpus, case by case

    @Test func theCorpusHoldsTheWholeFamilyAndNothingIsPending() {
        #expect(Self.family.filter { $0.outcome == "accept" }.count == 28)
        #expect(Self.family.filter { $0.outcome == "reject" }.count == 78)
        #expect(Self.family.allSatisfy { $0.pending != true }, "both ids are shipped, so no case is pending")
    }

    @Test(arguments: family.filter { $0.outcome == "accept" })
    func anAcceptedCaseDecodesAndDrawsAPart(_ item: ServerUIContractCorpusTests.Case) throws {
        let found = Self.parts(of: try Self.decode(item.file))
        if item.file.contains("/dial-") { #expect(!found.dials.isEmpty, "\(item.file)") }
        if item.file.contains("/arc-track-") { #expect(!found.arcs.isEmpty, "\(item.file)") }
    }

    @Test(arguments: family.filter { $0.outcome == "reject" })
    func aRefusedCaseGivesTheStudiosFirstIssue(_ item: ServerUIContractCorpusTests.Case) throws {
        let issue = try #require(item.issue)
        do {
            _ = try Self.decode(item.file)
            Issue.record("\(item.file) must be refused")
        } catch let thrown as ServerUICompositionError {
            #expect(thrown.code.rawValue == issue.code, "\(item.file): \(thrown)")
            #expect(thrown.pointer == issue.pointer, "\(item.file): \(thrown)")
        }
    }

    // MARK: What a dial decodes to

    @Test func aTickDialKeepsItsRingAndItsLitTick() throws {
        let dial = try Self.dial("dial-tick")
        #expect(dial.sweep.length == 250 && !dial.sweep.isFullTurn)
        #expect(dial.scale == .unit)
        #expect(dial.aspect == 1 && dial.centerY == 0.5, "absent aspect and centre are 1 and the middle")
        #expect(dial.mirrors == false, "a dial does not mirror unless it says so")
        guard case .tick(_, let inner, let outer, _, _)? = dial.pointer else { Issue.record("a tick pointer"); return }
        #expect(outer > inner)
        #expect(dial.ticks != nil)
    }

    @Test func aNeedleDialKeepsItsInksLettersAndFlag() throws {
        let dial = try Self.dial("dial-needle")
        #expect(dial.scale == .degrees && dial.sweep.isFullTurn)
        guard case .needle(_, _, _, _, let animates)? = dial.pointer else { Issue.record("a needle"); return }
        #expect(animates, "a needle turns unless it says it does not")
        #expect(dial.labels?.items.count == 4)
        #expect(dial.labels?.items.filter(\.needsValue).count == 2)
        #expect(dial.flag != nil)
        #expect(dial.ticks?.ring.skip == [0])
        #expect(dial.ticks?.ring.alternateInner != nil)
    }

    @Test func aStillNeedleSaysSo() throws {
        guard case .needle(_, _, _, _, let animates)? = try Self.dial("dial-needle-still").pointer else { Issue.record("a needle"); return }
        #expect(animates == false)
    }

    @Test func aDialDrawnWideKeepsItsShapeAndCentre() throws {
        let dial = try Self.dial("dial-aspect-and-centre")
        #expect(dial.aspect == 1.4 && dial.centerY == 0.56)
    }

    @Test func aScaledDialKeepsItsSize() throws {
        let size = try #require(try Self.dial("dial-size-scaled").size)
        #expect(size.relativeTo != nil && size.maxPoints != nil)
        #expect(try #require(size.maxPoints) >= size.points)
    }

    @Test func theMiddleHoldsOneLineEachWithTheRulesOfAText() throws {
        let dial = try Self.dial("dial-center-text")
        #expect(dial.center.count == 2)
        #expect(dial.center.allSatisfy { !$0.unavailableText.isEmpty })
    }

    @Test func aDialThatMirrorsSaysSo() throws {
        #expect(try Self.dial("dial-mirrors").mirrors)
        #expect(try Self.dial("dial-no-pointer").pointer == nil)
        #expect(try Self.dial("dial-no-ticks").ticks == nil)
    }

    @Test func aDialReadsTheEntitiesItsPointerAndNameSay() throws {
        #expect(try Self.dial("dial-pointer-bound").sourceIds.isEmpty == false)
        let named = try Self.dial("dial-a11y-bound-label")
        guard case .value = named.accessibility else { Issue.record("a spoken dial"); return }
        #expect(named.sourceIds.isEmpty == false)
        let spoken = try Self.dial("dial-a11y-value")
        guard case .value(_, let value) = spoken.accessibility else { Issue.record("a spoken dial"); return }
        #expect(value != nil)
    }

    @Test func aDialWithNoNameIsHiddenFromAssistiveTechnology() throws {
        #expect(try Self.dial("dial-tick").accessibility == .hidden)
    }

    // MARK: What an arc decodes to

    @Test func anArcKeepsItsCurveBoxAndMarker() throws {
        let arc = try Self.arc("arc-track-minimal")
        #expect(arc.marker != nil && arc.progress != nil)
        #expect(arc.mirrors, "an arc mirrors in a right-to-left layout unless it says it does not")
        #expect(arc.box.width > 0 && arc.box.height > 0)
        #expect(arc.dash != nil)
    }

    @Test func anArcMayHaveAHorizonNoDashesAndNoMarker() throws {
        #expect(try Self.arc("arc-track-horizon").horizon != nil)
        #expect(try Self.arc("arc-track-solid").dash == nil)
        let bare = try Self.arc("arc-track-no-marker")
        #expect(bare.marker == nil && bare.progress == nil)
        #expect(bare.layoutInput(width: 100, value: 0.5, rtl: false).progress == nil, "no marker, so no progress to place")
    }

    @Test func anArcMayKeepItsPlaceInARightToLeftLayout() throws {
        #expect(try Self.arc("arc-track-mirrors-off").mirrors == false)
        #expect(try Self.arc("arc-track-percent-scale").scale == .percent)
        #expect(try Self.arc("arc-track-progress-bound").sourceIds.isEmpty == false)
        let named = try Self.arc("arc-track-a11y-bound-label")
        #expect(named.sourceIds.isEmpty == false)
        guard case .value = named.accessibility else { Issue.record("a spoken arc"); return }
        #expect(try Self.arc("arc-track-minimal").accessibility == .hidden)
    }

    // MARK: Dial arithmetic

    private static let barometer = ServerUIDialLayout.Input(
        width: 140, aspect: 1.4, centerY: 0.56, sweep: .init(start: 145, length: 250),
        ring: .init(count: 49, inner: 0.78, outer: 0.92), pointer: .init(kind: .tick, value: 0.5, inner: 0.7, outer: 0.98))

    @Test func theShareIsHeldOnAPartialSweepAndWrapsOnAFullTurn() {
        let partial = ServerUIDialLayout.Sweep(start: 145, length: 250), full = ServerUIDialLayout.Sweep(start: -90, length: 360)
        #expect(ServerUIDialLayout.dialShare(1.4, scale: .unit, sweep: partial) == 1)
        #expect(ServerUIDialLayout.dialShare(-3, scale: .unit, sweep: partial) == 0)
        #expect(ServerUIDialLayout.dialShare(50, scale: .percent, sweep: partial) == 0.5)
        #expect(ServerUIDialLayout.dialShare(90, scale: .degrees, sweep: full) == 0.25)
        #expect(ServerUIDialLayout.dialShare(-90, scale: .degrees, sweep: full) == 0.75, "a bearing of -90 is 270")
        #expect(ServerUIDialLayout.dialShare(1, scale: .unit, sweep: full) == 0, "one turn is the start")
        #expect(ServerUIDialLayout.dialShare(nil, scale: .unit, sweep: partial) == nil)
        #expect(ServerUIDialLayout.dialShare(.nan, scale: .unit, sweep: partial) == nil)
        #expect(ServerUIDialLayout.dialShare(.infinity, scale: .unit, sweep: full) == nil)
    }

    @Test func aNeedleTurnsTheShortWayRound() {
        #expect(ServerUIDialLayout.shortestTurn(from: 350, to: 10) == 20)
        #expect(ServerUIDialLayout.shortestTurn(from: 10, to: 350) == -20)
        #expect(ServerUIDialLayout.shortestTurn(from: 0, to: 180) == 180, "half a turn goes the positive way")
        #expect(ServerUIDialLayout.shortestTurn(from: 0, to: -180) == 180)
        #expect(ServerUIDialLayout.shortestTurn(from: 720, to: 10) == 10)
        #expect(ServerUIDialLayout.normalizeDegrees(-10) == 350)
        #expect(ServerUIDialLayout.nextTurn(previous: nil, target: 350) == 350, "the first draw is placed at once")
        #expect(ServerUIDialLayout.nextTurn(previous: 350, target: 10) == 370, "unwrapped, so it keeps turning on")
        #expect(ServerUIDialLayout.nextTurn(previous: 370, target: 350) == 350)
        #expect(WeatherPresentation.shortestBearingDelta(from: 350, to: 10) == ServerUIDialLayout.shortestTurn(from: 350, to: 10))
    }

    @Test func theTicksOfAPartialSweepStandAtBothEndsAndAFullTurnDoesNotRepeat() {
        let partial = ServerUIDialLayout.layoutDial(Self.barometer)
        #expect(partial.ticks.count == 49)
        #expect(ServerUIDialLayout.tickShare(index: 48, count: 49, sweep: .init(start: 145, length: 250)) == 1)
        #expect(ServerUIDialLayout.tickShare(index: 47, count: 48, sweep: .init(start: 0, length: 360)) == 47.0 / 48)
        var compass = Self.barometer
        compass.sweep = .init(start: -90, length: 360)
        compass.ring = .init(count: 48, inner: 0.8, outer: 0.92, alternateInner: 0.85, skip: [0])
        let full = ServerUIDialLayout.layoutDial(compass)
        #expect(full.ticks.count == 47, "the north tick is a flag, not a tick")
        func length(_ tick: ServerUIDialLayout.Segment) -> Double { ((tick.x2 - tick.x1) * (tick.x2 - tick.x1) + (tick.y2 - tick.y1) * (tick.y2 - tick.y1)).squareRoot() }
        #expect(abs(length(full.ticks[0]) - 4.9) < 0.01, "the odd ticks are the short ones: 0.07 of a 70 point radius")
        #expect(abs(length(full.ticks[1]) - 8.4) < 0.01, "the even ones are the long ones: 0.12 of it")
    }

    @Test func aTickPointerLightsOneTickAndNoValueLightsNone() {
        #expect(ServerUIDialLayout.layoutDial(Self.barometer).lit != nil)
        var none = Self.barometer
        none.pointer?.value = nil
        let layout = ServerUIDialLayout.layoutDial(none)
        #expect(layout.lit == nil && layout.share == nil)
        none.pointer = nil
        #expect(ServerUIDialLayout.layoutDial(none).share == nil)
    }

    @Test func aMirroredDialFlipsOnlyInARightToLeftLayout() {
        var input = Self.barometer
        input.pointer?.value = 0.25
        let plain = ServerUIDialLayout.layoutDial(input)
        input.mirrors = true
        #expect(ServerUIDialLayout.layoutDial(input) == plain, "left to right: nothing changes")
        input.rtl = true
        let flipped = ServerUIDialLayout.layoutDial(input)
        #expect(flipped.lit != plain.lit)
        input.mirrors = false
        #expect(ServerUIDialLayout.layoutDial(input) == plain, "a dial that does not mirror keeps its places")
    }

    @Test func theLettersDropWithoutAValueAndKeepAFloorSize() {
        var input = ServerUIDialLayout.Input(
            width: 40, sweep: .init(start: -90, length: 360), scale: .degrees, pointer: .init(kind: .needle, value: nil),
            labels: [.init(at: 0, text: "N"), .init(at: 0.25, text: "E", needsValue: true)], flag: 0)
        let without = ServerUIDialLayout.layoutDial(input)
        #expect(without.labels.map(\.text) == ["N"])
        #expect(without.labels.first?.fontSize == 10, "never below 10 points")
        #expect(without.needle == nil)
        #expect(without.flag?.count == 3)
        input.pointer?.value = 90
        let with = ServerUIDialLayout.layoutDial(input)
        #expect(with.labels.map(\.text) == ["N", "E"])
        #expect(with.needle == ServerUIDialLayout.NeedleTurn(rotation: 90, angle: 0))
        #expect(ServerUIDialLayout.labelFontSize(radius: 80) == 16)
    }

    @Test func theNeedleShapeIsTheClosedOneTheCompassDraws() {
        #expect(ServerUIDialLayout.Needle.head.count == 3 && ServerUIDialLayout.Needle.tail.count == 4)
        #expect(ServerUIDialLayout.Needle.dotAt == (0.5, 0.29))
        #expect(ServerUIDialLayout.Needle.dotSize == 0.07)
    }

    @Test func aDialsLayoutInputCarriesItsPartsAndTheReading() throws {
        let tick = try Self.dial("dial-tick")
        let input = tick.layoutInput(width: 120, value: 0.5, rtl: true)
        #expect(input.width == 120 && input.rtl)
        #expect(input.pointer?.kind == .tick && input.pointer?.value == 0.5)
        #expect(input.ring == tick.ticks?.ring)
        let needle = try Self.dial("dial-needle")
        #expect(needle.layoutInput(width: 104, value: 10, rtl: false).pointer?.kind == .needle)
        #expect(try Self.dial("dial-no-pointer").layoutInput(width: 100, value: 1, rtl: false).pointer == nil)
    }

    // MARK: Arc arithmetic

    private static let daylight = ServerUIArcLayout.Input(
        curve: .init(from: .init(8, 40), control: .init(50, 4), to: .init(92, 40)), box: .init(width: 100, height: 48), maxWidth: 200,
        horizon: .init(from: .init(4, 40), to: .init(96, 40)), width: 300, progress: 0.5)

    @Test func theArcIsCappedAtItsMaxWidthAndKeepsItsShape() {
        let layout = ServerUIArcLayout.layoutArc(Self.daylight)
        #expect(layout.width == 200 && layout.height == 96)
        var narrow = Self.daylight
        narrow.width = 100
        #expect(ServerUIArcLayout.layoutArc(narrow).height == 48)
        narrow.maxWidth = nil
        narrow.width = 300
        #expect(ServerUIArcLayout.layoutArc(narrow).width == 300, "no cap fills the room")
    }

    @Test func theMarkerStandsOnTheCurveAndIsHeldAtTheEnds() throws {
        var input = Self.daylight
        input.width = 100
        let half = try #require(ServerUIArcLayout.layoutArc(input).marker)
        #expect(half.x == 50 && half.y == 22 && half.t == 0.5)
        input.progress = 7
        #expect(ServerUIArcLayout.layoutArc(input).marker?.t == 1)
        input.progress = -1
        #expect(ServerUIArcLayout.layoutArc(input).marker?.t == 0)
        input.progress = 50
        input.scale = .percent
        #expect(ServerUIArcLayout.layoutArc(input).marker?.t == 0.5)
        input.progress = nil
        #expect(ServerUIArcLayout.layoutArc(input).marker == nil)
        input.progress = .nan
        #expect(ServerUIArcLayout.layoutArc(input).marker == nil)
        #expect(ServerUIArcLayout.progress(.infinity) == nil)
    }

    @Test func theArcMirrorsInARightToLeftLayoutUnlessItSaysNot() throws {
        var input = Self.daylight
        input.width = 100
        input.progress = 0.25
        let plain = try #require(ServerUIArcLayout.layoutArc(input).marker)
        input.rtl = true
        let mirrored = try #require(ServerUIArcLayout.layoutArc(input).marker)
        #expect(mirrored.x == 100 - plain.x && mirrored.y == plain.y)
        #expect(ServerUIArcLayout.layoutArc(input).curve.from == .init(92, 40))
        input.mirrors = false
        #expect(ServerUIArcLayout.layoutArc(input).marker == plain)
        #expect(ServerUIArcLayout.layoutArc(input).horizon?.from == .init(4, 40))
    }

    @Test func theAppsMarkerMatchesTheSunArcsHandWrittenOne() throws {
        for percent in stride(from: 0.0, through: 100, by: 12.5) {
            let hand = WeatherPresentation.sunArcMarker(percent: percent)
            var input = Self.daylight
            input.width = 100
            input.progress = percent
            input.scale = .percent
            let marker = try #require(ServerUIArcLayout.layoutArc(input).marker)
            #expect(abs(marker.x - hand.x) < 0.0001 && abs(marker.y - hand.y) < 0.0001, "at \(percent)")
        }
    }

    @Test func theAppsMarkerSitsWhereTheCurveBendsAtItsMiddle() {
        let middle = ServerUIArcLayout.curvePoint(Self.daylight.curve, t: 0.5)
        #expect(middle == .init(50, 22))
    }
}
