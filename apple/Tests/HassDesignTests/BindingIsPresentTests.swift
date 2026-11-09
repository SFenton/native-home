@testable import HassDesign
import SwiftUI
import Testing

struct BindingIsPresentTests {
    @Test func tracksTheOptional() {
        var value: String? = "x"
        let source = Binding(get: { value }, set: { value = $0 })
        let present = source.isPresent()
        #expect(present.wrappedValue)
        value = nil
        #expect(!present.wrappedValue)
    }

    @Test func clearsOnDismissAndIgnoresTrue() {
        var value: Int? = 3
        let present = Binding(get: { value }, set: { value = $0 }).isPresent()
        present.wrappedValue = true
        #expect(value == 3)
        present.wrappedValue = false
        #expect(value == nil)
    }

    @Test func setMembershipInsertsAndRemoves() {
        var days: Set<Int> = [1]
        let source = Binding(get: { days }, set: { days = $0 })
        let two = source.contains(2)
        #expect(!two.wrappedValue)
        two.wrappedValue = true
        #expect(days == [1, 2])
        #expect(two.wrappedValue)
        two.wrappedValue = false
        #expect(days == [1])
    }

    @Test func projectionReadsAndFoldsBack() {
        var text = "hello"
        let source = Binding(get: { text }, set: { text = $0 })
        let limited = source.projected(read: { $0 }, write: { _, new in String(new.prefix(3)) })
        #expect(limited.wrappedValue == "hello")
        limited.wrappedValue = "abcdef"
        #expect(text == "abc")
    }
}
