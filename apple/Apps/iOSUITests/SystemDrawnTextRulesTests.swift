import XCTest

/// The rules that tell system-drawn or glyph-misread recognised text from a real unlabelled string. No app launches.
final class SystemDrawnTextRulesTests: XCTestCase {
    func testTimeChipsWithAndWithoutSpace() {
        XCTAssertTrue(SystemDrawnTextRules.isTimeChip("9:00 AM"))
        XCTAssertTrue(SystemDrawnTextRules.isTimeChip("9:00AM"))
        XCTAssertTrue(SystemDrawnTextRules.isTimeChip("12:30PM"))
        XCTAssertFalse(SystemDrawnTextRules.isTimeChip("9:00"))
        XCTAssertFalse(SystemDrawnTextRules.isTimeChip("Dinner 9:00PM"))
    }

    func testChipCountsOnlyOnADatePicker() {
        let picker = CGRect(x: 600, y: 230, width: 200, height: 60)
        let chip = CGRect(x: 724, y: 237, width: 71, height: 20)
        XCTAssertTrue(SystemDrawnTextRules.isPickerTime("9:00AM", frame: chip, pickers: [picker]))
        XCTAssertFalse(SystemDrawnTextRules.isPickerTime("9:00AM", frame: chip, pickers: []))
        XCTAssertFalse(SystemDrawnTextRules.isPickerTime("9:00AM", frame: CGRect(x: 20, y: 600, width: 70, height: 20), pickers: [picker]))
        XCTAssertFalse(SystemDrawnTextRules.isPickerTime("Alex", frame: chip, pickers: [picker]))
    }

    func testInfoGlyphMisread() {
        let labels = ["alex away", "away modes"]
        XCTAssertTrue(SystemDrawnTextRules.isInfoGlyphMisread("i alex away", labels: labels))
        XCTAssertTrue(SystemDrawnTextRules.isInfoGlyphMisread("i alex", labels: labels), "a whole-word prefix of a label")
        XCTAssertTrue(SystemDrawnTextRules.isInfoGlyphMisread("i alex away", labels: ["alex away, since nine"]), "punctuation ends a word")
        XCTAssertFalse(SystemDrawnTextRules.isInfoGlyphMisread("x away", labels: labels), "only an i")
        XCTAssertFalse(SystemDrawnTextRules.isInfoGlyphMisread("i al", labels: labels), "the rest is too short")
        XCTAssertFalse(SystemDrawnTextRules.isInfoGlyphMisread("i lex away", labels: labels), "a substring is not enough")
        XCTAssertFalse(SystemDrawnTextRules.isInfoGlyphMisread("i alexa", labels: labels), "a partial word is not a prefix")
        XCTAssertFalse(SystemDrawnTextRules.isInfoGlyphMisread("alex away", labels: labels))
        XCTAssertFalse(SystemDrawnTextRules.isInfoGlyphMisread("is away", labels: labels))
    }
}
