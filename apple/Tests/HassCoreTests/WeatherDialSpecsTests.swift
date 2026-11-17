import Foundation
import Testing
@testable import HassCore

// MARK: - The weather panel's dials as documents

/// ``WeatherDialSpecs`` must draw what the hand-written weather views drew: the numbers below are the corpus's own for the compass, the barometer
/// and the sun arc (`ContractCorpus/evaluation/dial-compass-*`, `dial-barometer-*`, `arc-track-marker-*`), which were written from those views.
struct WeatherDialSpecsTests {
    @Test func theCompassIsTheSameDialAsTheCorpusCompass() {
        let compass = WeatherDialSpecs.compass()
        let layout = ServerUIDialLayout.layoutDial(compass.layoutInput(width: 104, value: 90, rtl: false))
        #expect(layout.ticks.count == 47, "48 ticks and the north one is a flag")
        #expect(layout.flag == [.init(x: 52, y: 3.12), .init(x: 55.12, y: 8.32), .init(x: 48.88, y: 8.32)])
        #expect(layout.labels.map(\.text) == ["N", "E", "S", "W"])
        #expect(layout.labels[1] == .init(text: "E", x: 82.16, y: 52, fontSize: 10.4))
        #expect(layout.needle == .init(rotation: 90, angle: 0))
        #expect(layout.ticks[0] == .init(x1: 57.7693, y1: 8.1781, x2: 58.2444, y2: 4.5693), "the first drawn tick is the short odd one")
        #expect(layout.ticks[1] == .init(x1: 62.7669, y1: 11.8175, x2: 64.3819, y2: 5.7901), "and the next is the long even one")
    }

    @Test func theCompassSizeScalesWithTheFootnoteStyleUpToOneHundredSixty() {
        let size = WeatherDialSpecs.compass().size
        #expect(size == .init(points: 104, relativeTo: .footnote, maxPoints: 160))
    }

    @Test func eastAndWestNeedADirection() {
        let layout = ServerUIDialLayout.layoutDial(WeatherDialSpecs.compass().layoutInput(width: 104, value: nil, rtl: false))
        #expect(layout.labels.map(\.text) == ["N", "S"])
        #expect(layout.needle == nil)
        #expect(layout.flag != nil, "the north flag stays")
    }

    @Test func theBarometerLightsTheTickOfItsShareOfTheSweep() {
        let barometer = WeatherDialSpecs.barometer(hasUnit: true)
        let layout = ServerUIDialLayout.layoutDial(barometer.layoutInput(width: 140, value: 53.75, rtl: false))
        #expect(layout.ticks.count == 49)
        #expect(layout.lit == .init(x1: 77.9819, y1: 7.6545, x2: 81.1746, y2: -11.6837))
        #expect(layout.height == 100 && layout.cy == 56, "1.4 wide to 1 tall, the centre 0.56 down")
        let held = ServerUIDialLayout.layoutDial(barometer.layoutInput(width: 140, value: 250, rtl: false))
        #expect(held.share == 1, "a reading past the sweep is held at its end")
    }

    @Test func theBarometerCentreLinesAreTheValueAndTheUnit() {
        let both = WeatherDialSpecs.barometer(hasUnit: true).center
        #expect(both.map(\.style) == [.title3, .caption1])
        #expect(both[0].look.weight == .bold && both[0].look.digits == .monospaced)
        #expect(both.allSatisfy { $0.look.lines == 1 && $0.look.align == .center && $0.look.isDeclared && $0.look.ink != nil })
        #expect(WeatherDialSpecs.barometer(hasUnit: false).center.count == 1)
    }

    @Test func theSunArcMarkerStandsWhereTheHandWrittenArcPutIt() {
        let arc = WeatherDialSpecs.sunArc()
        let layout = ServerUIArcLayout.layoutArc(arc.layoutInput(width: 100, value: 25, rtl: false))
        #expect(layout.marker == .init(x: 29, y: 26.5, t: 0.25))
        #expect(ServerUIArcLayout.layoutArc(arc.layoutInput(width: 300, value: 25, rtl: false)).width == 200, "200 pt at most")
        #expect(ServerUIArcLayout.layoutArc(arc.layoutInput(width: 100, value: nil, rtl: false)).marker == nil, "below the horizon: no marker")
        let rtl = ServerUIArcLayout.layoutArc(arc.layoutInput(width: 100, value: 25, rtl: true))
        #expect(rtl.marker?.x == 29, "the sun's east to west is a place: the weather arc never mirrors")
    }

    @Test func theInksAreThePanelsOwn() {
        #expect(WeatherDialSpecs.amber.dark.rgb == .init(red: 255, green: 209, blue: 77))
        #expect(WeatherDialSpecs.sun.dark.rgb == .init(red: 255, green: 217, blue: 77))
        #expect(WeatherDialSpecs.amber.light == WeatherDialSpecs.amber.dark, "one ink for both appearances")
        let compass = WeatherDialSpecs.compass()
        #expect(compass.ticks?.ink.dark.alpha == 0.55)
        #expect(compass.flag?.ink.dark.alpha == 1)
        #expect(WeatherDialSpecs.sunArc().horizon?.ink.dark.alpha == 0.35)
        #expect(WeatherDialSpecs.sunArc().dash == .init(stroke: 3, gap: 4))
    }

    @Test func theSpecsAreDecorationForAssistiveTechnology() {
        #expect(WeatherDialSpecs.compass().accessibility == .hidden)
        #expect(WeatherDialSpecs.barometer(hasUnit: false).accessibility == .hidden)
        #expect(WeatherDialSpecs.sunArc().accessibility == .hidden)
        #expect(WeatherDialSpecs.compass().sourceIds.isEmpty)
    }

    @Test func theBarometersValueShrinksAsItDidAndItsUnitIsCut() {
        let lines = WeatherDialSpecs.barometer(hasUnit: true).center
        #expect(lines.count == 2)
        #expect(lines[0].look.overflow == nil, "a single line with no overflow shrinks to 0.6 first")
        #expect(lines[1].look.overflow == .truncate, "the unit never shrank")
    }

    @Test func theSunArcStaysAtItsLeftPlaceInARightToLeftLayout() {
        #expect(WeatherDialSpecs.sunArc().mirrors == false)
    }

    /// Production's arithmetic: `top = (height - total) / 2 + 4`, with each line's height rounded up.
    @Test(arguments: [(93.0, 21.0, 16.0), (140.0, 22.0, 16.0), (200.0, 40.0, 32.0)])
    func theBarometerTextStandsWhereTheHandBuiltViewPutIt(width: Double, value: Double, unit: Double) {
        let dial = WeatherDialSpecs.barometer(hasUnit: true)
        let height = width / 1.4, total = value + unit
        #expect(dial.textBlockTop(height: height, blockHeight: total) == (height - total) / 2 + 4)
        let single = WeatherDialSpecs.barometer(hasUnit: false)
        #expect(single.textBlockTop(height: height, blockHeight: value) == (height - value) / 2 + 4)
    }

    @Test func aDialWithNoPlaceCentresItsTextOnTheRing() {
        let plain = ServerUIDial(node: .init(id: "d", title: "d", span: 1), sweep: .init(start: 0, length: 360), aspect: 1.4, centerY: 0.56)
        #expect(plain.textPlace == nil)
        #expect(abs(plain.textBlockTop(height: 100, blockHeight: 20) - 46) < 0.000001)
        #expect(ServerUIDial.TextPlace().offset == 0)
    }

    /// Production's ring: radius `min(width, 1.4 * height) / 2`, centred `0.56` down the tile (iPhone, Duo, iPad with a unit, iPad without, iPad at AX3).
    @Test(arguments: [(338.0, 229.3), (402.0, 229.3), (306.0, 219.0), (476.0, 229.0), (476.0, 340.0)])
    func theBarometerRingFitsItsTileAsTheHandBuiltViewDid(tileWidth: Double, tileHeight: Double) {
        let dial = WeatherDialSpecs.barometer(hasUnit: true)
        let width = ServerUIDialLayout.fittedWidth(available: tileWidth, height: tileHeight, aspect: dial.aspect)
        let layout = ServerUIDialLayout.layoutDial(dial.layoutInput(width: width, value: 50, rtl: false))
        let top = (tileHeight - layout.height) / 2
        #expect(abs(layout.radius - min(tileWidth, 1.4 * tileHeight) / 2) < 0.3)
        #expect(abs(top + layout.cy - 0.56 * tileHeight) < 0.3)
        #expect(layout.height <= tileHeight + 0.5, "the ring does not clip at the bottom of the tile")
    }

    @Test func aRoomWithNoHeightLimitKeepsItsWidth() {
        #expect(ServerUIDialLayout.fittedWidth(available: 300, height: 0, aspect: 1.4) == 300)
        #expect(ServerUIDialLayout.fittedWidth(available: 300, height: 214.5, aspect: 1.4) == 300, "within half a point")
        #expect(ServerUIDialLayout.fittedWidth(available: 300, height: 100, aspect: 1.4) == 140)
    }
}
