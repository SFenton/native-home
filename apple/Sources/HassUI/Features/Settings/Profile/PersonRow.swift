import HassCore
import HassDesign
import SwiftUI

/// One person: their photo, or a monogram in their colour, their name and Home, Away or the zone.
struct PersonRow {
    var person: ProfileSummary.Person
    /// The person's photo from Home Assistant; nil draws their initials.
    var avatar: AvatarBox?
    @ScaledMetric(relativeTo: .body) private var monogramSize: CGFloat = 36

    /// A resident's monogram colour: their chore family (the same blue and magenta their chores carry); a guest's is a
    /// neutral grey (white initials on it measure 5.7:1).
    static func fill(for person: ProfileSummary.Person) -> Color { Color(fillToken(for: person)) }

    /// ``fill(for:)`` as raw sRGB.
    static func fillToken(for person: ProfileSummary.Person) -> HassRGB {
        switch person.resident?.key {
        case Resident.resident1.key: ColorFamily.choreResident1.fillToken ?? HassTokens.RGB.Ink.actionFill
        case Resident.resident2.key: ColorFamily.choreResident2.fillToken ?? HassTokens.RGB.Ink.actionFill
        default: HassRGB(red: 0.4, green: 0.4, blue: 0.4)
        }
    }

}
