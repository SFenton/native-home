import Foundation
import Testing
@testable import HassCore

// MARK: - App state, dates and colors

@Suite struct ServerUIAppStateTests {
    /// The Studio's `appStateFields`: the vocabulary a document may read, held here as data so a drift fails.
    @Test func theFieldTablesAreTheStudiosAndEveryTopicHasAPhase() {
        let studio: [ServerUIAppState.Topic: [String: String]] = [
            .window: ["widthClass": "string", "heightClass": "string", "width": "number", "height": "number", "orientation": "string", "phase": "string"],
            .clock: ["hour": "number", "minute": "number", "weekday": "number", "minuteOfDay": "number", "today": "string", "phase": "string"],
            .os: ["major": "number", "supportsAlternateIcons": "boolean", "reduceMotion": "boolean", "reduceTransparency": "boolean",
                  "canSendMail": "boolean", "phase": "string"],
            .notifications: ["permission": "string", "timeSensitive": "string", "phase": "string"],
            .preferences: ["showCountOnIcon": "boolean", "notificationBannerDismissed": "boolean", "phase": "string"],
        ]
        for topic in ServerUIAppState.Topic.allCases {
            #expect(ServerUIAppState.fields(topic).mapValues(\.rawValue) == studio[topic], "\(topic)")
        }
    }

    @Test func aTopicThatHasNotBeenGatheredReadsLoadingAndItsPhaseSaysSo() {
        let empty = ServerUIAppState()
        for topic in ServerUIAppState.Topic.allCases {
            #expect(empty.read(topic, field: "phase") == .value(.string("loading")))
            for field in ServerUIAppState.fields(topic).keys where field != "phase" {
                #expect(empty.read(topic, field: field) == .loading, "\(topic).\(field)")
            }
        }
        #expect(empty.read(.window, field: "hour") == .unavailable)
    }

    @Test func theWindowReadsAsClassesAndGeometryWithNoDeviceKind() {
        let window = ServerUIAppState.Window(widthClass: .regular, heightClass: .compact, width: 1024, height: 700)
        let state = ServerUIAppState(window: window)
        #expect(state.read(.window, field: "widthClass") == .value(.string("regular")))
        #expect(state.read(.window, field: "heightClass") == .value(.string("compact")))
        #expect(state.read(.window, field: "width") == .value(.number(1024)))
        #expect(state.read(.window, field: "orientation") == .value(.string("landscape")))
        #expect(state.read(.window, field: "phase") == .value(.string("ready")))
        #expect(ServerUIAppState.Window(widthClass: .compact, heightClass: .regular, width: 390, height: 844).orientation == "portrait")
        #expect(!ServerUIAppState.fields(.window).keys.contains("device"))
    }

    @Test func theClockReadsHourMinuteWeekdayMinuteOfDayAndToday() {
        // 2026-11-15 is a Sunday: weekday 7, the last of 1 (Monday) to 7.
        let state = ServerUIAppState(clock: ServerUIClock(now: "2026-11-15T09:30:45", utcOffsetMinutes: -480))
        #expect(state.read(.clock, field: "hour") == .value(.number(9)))
        #expect(state.read(.clock, field: "minute") == .value(.number(30)))
        #expect(state.read(.clock, field: "minuteOfDay") == .value(.number(570)))
        #expect(state.read(.clock, field: "weekday") == .value(.number(7)))
        #expect(state.read(.clock, field: "today") == .value(.string("2026-11-15")))
        let monday = ServerUIAppState(clock: ServerUIClock(now: "2026-11-16T00:00:00", utcOffsetMinutes: 0))
        #expect(monday.read(.clock, field: "weekday") == .value(.number(1)))
        #expect(ServerUIAppState(clock: ServerUIClock(now: "junk", utcOffsetMinutes: 0)).read(.clock, field: "hour") == .unavailable)
    }

    @Test func theClockForADateIsTheWallTimeAndOffsetOfItsZone() throws {
        let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = Date(timeIntervalSince1970: 1_794_763_800)  // 2026-11-15T17:30:00Z
        #expect(ServerUIAppState.clock(at: date, timeZone: zone) == ServerUIClock(now: "2026-11-15T09:30:00", utcOffsetMinutes: -480))
        let london = try #require(TimeZone(identifier: "Europe/London"))
        #expect(ServerUIAppState.clock(at: date, timeZone: london) == ServerUIClock(now: "2026-11-15T17:30:00", utcOffsetMinutes: 0))
        let before = Date(timeIntervalSince1970: -1)  // 1969-12-31T23:59:59Z
        #expect(ServerUIAppState.clock(at: before, timeZone: try #require(TimeZone(secondsFromGMT: 0))).now == "1969-12-31T23:59:59")
    }

    @Test func theTickFiresOnTheMinuteAndNotBefore() {
        #expect(ServerUIAppState.secondsToNextMinute(from: Date(timeIntervalSince1970: 120)) == 60)
        #expect(abs(ServerUIAppState.secondsToNextMinute(from: Date(timeIntervalSince1970: 150.25)) - 29.75) < 0.001)
    }

    @Test func notificationsAndPreferencesReadTheirValues() {
        let state = ServerUIAppState(notifications: .init(permission: "authorized", timeSensitive: "not-supported"),
                                     preferences: .init(showCountOnIcon: false, notificationBannerDismissed: true))
        #expect(state.read(.notifications, field: "permission") == .value(.string("authorized")))
        #expect(state.read(.notifications, field: "timeSensitive") == .value(.string("not-supported")))
        #expect(state.read(.preferences, field: "showCountOnIcon") == .value(.bool(false)))
        #expect(state.read(.preferences, field: "notificationBannerDismissed") == .value(.bool(true)))
        let system = ServerUIAppState(os: .init(major: 27, supportsAlternateIcons: true, reduceMotion: false, reduceTransparency: true,
                                                canSendMail: false))
        #expect(system.read(.os, field: "major") == .value(.number(27)))
        #expect(system.read(.os, field: "reduceTransparency") == .value(.bool(true)))
    }
}

@Suite struct ServerUIModelReadsTests {
    typealias D = ServerUICompositionDocument

    @Test func aModelsFieldsAndKindsAreCheckedAndTheCountsNameTheirCapability() {
        let power = D.Source.powerToggle(id: "p", entityId: .literal("switch.demo_lamp"))
        #expect(ServerUIModelReads.check(power, path: ["isOn"], kind: .boolean) == nil)
        #expect(ServerUIModelReads.check(power, path: ["isOn"], kind: .string) == .issue(.bindingType, suffix: "/as"))
        #expect(ServerUIModelReads.check(power, path: ["nope"], kind: .string) == .issue(.invalidReference, suffix: "/from/path"))
        // A condition leaf names no kind, so its pointer is the leaf's own path.
        #expect(ServerUIModelReads.check(power, path: ["nope"], kind: nil) == .issue(.invalidReference, suffix: "/path"))
        #expect(ServerUIModelReads.check(power, path: ["isOn", "deeper"], kind: nil) == .issue(.invalidReference, suffix: "/path"))
        let window = D.Source.appState(id: "w", topic: .window)
        #expect(ServerUIModelReads.check(window, path: ["widthClass"], kind: .string) == nil)
        #expect(ServerUIModelReads.check(window, path: ["hour"], kind: .number) == .issue(.invalidReference, suffix: "/from/path"))
        #expect(ServerUIModelReads.check(.appState(id: "c", topic: .clock), path: ["hour"], kind: .string) == .issue(.bindingType, suffix: "/as"))
    }

    @Test func aSourceWithNoReadFieldsCannotBeReadByAnOperand() {
        #expect(ServerUIModelReads.check(.profileAccount(id: "a"), path: ["state"], kind: .string) == .notReadable)
        #expect(ServerUIModelReads.check(.mediaRemote(id: "m", providerId: "x"), path: ["state"], kind: nil) == .notReadable)
    }
}

@Suite struct ServerUIHomeStatusCountsTests {
    typealias D = ServerUICompositionDocument

    private func configuration(_ projection: D.HomeStatus.Projection, ids: [String]) -> D.HomeStatus {
        .init(projection: projection, format: .summary, entityIds: ids, rangeEntityId: nil, secondaryEntityId: nil,
              alarmEntityId: nil, awayEntityIds: [],
              labels: .init(idle: "Idle", active: "Detected", countSuffix: " On", loading: "Reading",
                            unavailable: "Unavailable", empty: "None", hidden: "Hidden"))
    }

    @Test func countTotalAndUnavailableCountReflectTheMembers() {
        let ids = ["light.demo_a", "light.demo_b", "light.demo_c"]
        let states = ["light.demo_a": "on", "light.demo_b": "off", "light.demo_c": "unavailable"]
        let value = ServerUIHomeStatus.project(configuration(.lights, ids: ids)) { EntityState(entityId: $0, state: states[$0] ?? "off") }
        #expect(value.count == 1 && value.total == 3 && value.unavailableCount == 1)
    }

    @Test func aMissingMemberIsUnavailableAndAllMissingMeansNoCount() {
        let ids = ["light.demo_a", "light.demo_b"]
        let partial = ServerUIHomeStatus.project(configuration(.lights, ids: ids)) { $0 == "light.demo_a" ? EntityState(entityId: $0, state: "on") : nil }
        #expect(partial.count == 1 && partial.total == 2 && partial.unavailableCount == 1)
        let none = ServerUIHomeStatus.project(configuration(.lights, ids: ids)) { _ in nil }
        #expect(none.count == nil && none.total == 2 && none.unavailableCount == 2)
    }

    @Test func loadingAndRedactedHaveNoCountAndAnEmptyStatusCountsZero() {
        let ids = ["light.demo_a"]
        #expect(ServerUIHomeStatus.project(configuration(.lights, ids: ids), pending: true) { _ in nil }.count == nil)
        #expect(ServerUIHomeStatus.project(configuration(.occupancy, ids: ids), redacted: true) { _ in nil }.count == nil)
        let empty = ServerUIHomeStatus.project(configuration(.lights, ids: [])) { _ in nil }
        #expect(empty.count == 0 && empty.total == 0 && empty.unavailableCount == 0)
    }

    @Test func contactsCountOpenMembersAndAProjectionWithNoNotionOfActiveHasNoCount() {
        let ids = ["binary_sensor.demo_a", "binary_sensor.demo_b"]
        let open = ServerUIHomeStatus.project(configuration(.contacts, ids: ids)) { EntityState(entityId: $0, state: $0 == ids[0] ? "on" : "off") }
        #expect(open.count == 1)
        let climate = ServerUIHomeStatus.project(configuration(.climate, ids: ["sensor.demo_a"])) { EntityState(entityId: $0, state: "70") }
        #expect(climate.count == nil && climate.total == 1)
    }
}

@Suite struct ServerUIDateFormatTests {
    private let clock = ServerUIClock(now: "2026-11-15T09:30:00", utcOffsetMinutes: -480)

    @Test func theSixStylesDrawUnitedStatesEnglishAndTheYearOnlyWhenItIsNotThisOne() {
        func draw(_ style: ServerUIDateStyle, _ value: String) -> String? { ServerUIDateFormat.text(style, of: value, clock: clock) }
        #expect(draw(.shortDate, "2026-11-12") == "Nov 12")
        #expect(draw(.shortDate, "2025-11-12") == "Nov 12, 2025")
        #expect(draw(.longDate, "2026-11-12") == "November 12, 2026")
        #expect(draw(.weekdayDate, "2026-11-12") == "Thu, Nov 12")
        #expect(draw(.time, "2026-11-12T21:05:00") == "9:05 PM")
        #expect(draw(.time, "2026-11-12") == "12:00 AM")
        #expect(draw(.time, "2026-11-12T12:00:00") == "12:00 PM")
        #expect(draw(.dateTime, "2026-11-12T09:41:00") == "Nov 12 at 9:41 AM")
        #expect(draw(.relative, "2026-11-15") == "Today" && draw(.relative, "2026-11-14") == "Yesterday" && draw(.relative, "2026-11-16") == "Tomorrow")
        #expect(draw(.relative, "2026-11-10") == "5 days ago" && draw(.relative, "2026-11-18") == "In 3 days")
        #expect(draw(.longDate, "2026-02-30") == nil && draw(.longDate, "not a date") == nil)
    }

    @Test func aTimeWithAnOffsetIsMovedToTheClocksWall() {
        // 2026-11-16T03:00 at +02:00 is 01:00 UTC, which is 17:00 the day before on a clock at -08:00.
        #expect(ServerUIDateFormat.text(.time, of: "2026-11-16T03:00:00+02:00", clock: clock) == "5:00 PM")
        #expect(ServerUIDateFormat.text(.relative, of: "2026-11-16T03:00:00+02:00", clock: clock) == "Today")
    }

    @Test func anotherLocaleIsDrawnByTheSystemsFormattersAndTheStylesThatAskForTodayNeedTheClock() throws {
        let german = Locale(identifier: "de_DE")
        let drawn = try #require(ServerUIDateFormat.text(.longDate, of: "2026-11-12", clock: clock, locale: german))
        #expect(drawn.contains("November") && drawn.contains("12") && drawn != "November 12, 2026")
        let relative = try #require(ServerUIDateFormat.text(.relative, of: "2026-11-14", clock: clock, locale: german))
        #expect(relative.lowercased().contains("gestern"))
        #expect(ServerUIDateFormat.text(.relative, of: "2026-11-14", clock: nil, locale: german) == nil)
        #expect(ServerUIDateFormat.isPinned(Locale(identifier: "en_US")) && !ServerUIDateFormat.isPinned(Locale(identifier: "en_GB")))
    }

    @Test func calendarMathAgreesWithTheKnownDates() {
        #expect(ServerUIDates.daysFromCivil(year: 1970, month: 1, day: 1) == 0)
        #expect(ServerUIDates.civil(fromDays: 0) == (1970, 1, 1))
        #expect(ServerUIDates.civil(fromDays: ServerUIDates.daysFromCivil(year: 2024, month: 2, day: 29)) == (2024, 2, 29))
        #expect(ServerUIDates.isCalendarDate(year: 2024, month: 2, day: 29) && !ServerUIDates.isCalendarDate(year: 2026, month: 2, day: 29))
        #expect(ServerUIDates.isCalendarDate(year: 2000, month: 2, day: 29) && !ServerUIDates.isCalendarDate(year: 1900, month: 2, day: 29))
        #expect(ServerUIDates.wallTime("2026-11-15T09:30:00.250", utcOffsetMinutes: 0)?.seconds == 34_200)
        #expect(ServerUIDates.wallTime("2026-11-15T24:00:00", utcOffsetMinutes: 0) == nil)
        #expect(ServerUIDates.wallTime("2026-11-15T09:30:00+25:00", utcOffsetMinutes: 0) == nil)
        #expect(ServerUIDates.wallTime("2026-11-15 09:30", utcOffsetMinutes: 0)?.seconds == 34_200)
        #expect(ServerUIDates.wallTime("2026-11-15T09:30:00 ", utcOffsetMinutes: 0) == nil)
        #expect(ServerUIDates.daysBetween("2026-12-31", "2027-01-01", utcOffsetMinutes: 0) == 1)
    }
}

@Suite struct ServerUIColorTextTests {
    @Test func theTierOneSyntaxesParseAndEverythingElseIsNotAColor() {
        #expect(ServerUIColorText.parse("#0f8") == ServerUIRGB(red: 0, green: 255, blue: 136))
        #expect(ServerUIColorText.parse("  #FF8800  ") == ServerUIRGB(red: 255, green: 136, blue: 0))
        #expect(ServerUIColorText.parse("rgb(10, 20, 30)") == ServerUIRGB(red: 10, green: 20, blue: 30))
        #expect(ServerUIColorText.parse("rgb(10 20 30 / 50%)") == ServerUIRGB(red: 10, green: 20, blue: 30))
        #expect(ServerUIColorText.parse("rgb(100%, 0%, 50%)") == ServerUIRGB(red: 255, green: 0, blue: 128))
        #expect(ServerUIColorText.parse("hsl(120deg, 100%, 25%)") == ServerUIRGB(red: 0, green: 128, blue: 0))
        #expect(ServerUIColorText.parse("#00968800") == nil)
        #expect(ServerUIColorText.parse("rgba(1, 2, 3, 0)") == nil)
        for text in ["red", "", "#12", "rgb(1,2)", "rgb(256, 0, 0)", "rgb((1), 2, 3)", "rgb(1, 2, 3) x", "rgb(1, 2, 3 / 4)", "hsl(1, 2, 3)"] {
            #expect(ServerUIColorText.parse(text) == nil, "\(text)")
        }
    }

    @Test func theClampKeepsWhiteTextReadableOnTheFillAndTheGlyphVisible() throws {
        for text in ["#ffff00", "#00ff00", "#ffffff", "#000000", "#ff0000"] {
            let color = try #require(ServerUIColorText.parse(text))
            let fill = ServerUIColorText.clamped(color, role: .fill)
            #expect(ServerUIColorText.contrast(0xFFFFFF, ServerUIColorText.liftedFill(fill.packed)) >= 4.5, "\(text)")
            let glyph = ServerUIColorText.clamped(color, role: .glyph)
            #expect(ServerUIColorText.contrast(glyph.packed, fill.packed) >= 3, "\(text)")
        }
    }
}

@Suite struct ServerUIMinuteTickTests {
    @Test func noReadMeansNoTick() {
        let tick = ServerUIMinuteTick()
        #expect(!tick.isRunning)
    }

    @Test func theFirstReadStartsTheTickAndLaterReadsDoNotStartAnother() {
        var tick = ServerUIMinuteTick()
        let first = tick.noteRead(), second = tick.noteRead()
        #expect(first && !second)
        #expect(tick.isRunning)
    }

    @Test func aReaderThatReadsAgainKeepsTheTickAlive() {
        var tick = ServerUIMinuteTick()
        _ = tick.noteRead()
        let firstTick = tick.fire()
        // The minute moved and the observation re-ran, reading the clock again.
        _ = tick.noteRead()
        let secondTick = tick.fire()
        #expect(firstTick && secondTick && tick.isRunning)
    }

    @Test func aTickThatFindsNoReadStopsAndTheNextReadStartsItAgain() {
        var tick = ServerUIMinuteTick()
        _ = tick.noteRead()
        let kept = tick.fire(), stopped = !tick.fire()
        #expect(kept && stopped && !tick.isRunning)
        let restarted = tick.noteRead()
        #expect(restarted)
    }
}
