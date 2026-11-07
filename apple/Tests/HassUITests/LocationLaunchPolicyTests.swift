import Foundation
@testable import HassUI
import Testing

struct LocationLaunchPolicyTests {
    @Test func everyDeviceReportsButNotInJourneys() {
        #expect(LocationLaunchPolicy.isEnabled(environment: [:]), "phones and iPads both opt in (owner, 2026-10-27)")
        #expect(LocationLaunchPolicy.isEnabled(environment: ["FENTON_LOCATION": "1"]))
        for key in ["FENTON_HASS_TOKEN", "FENTON_UITEST_RESET", "FENTON_GALLERY"] {
            #expect(!LocationLaunchPolicy.isEnabled(environment: [key: "1"]))
            #expect(LocationLaunchPolicy.isEnabled(environment: [key: "1", "FENTON_LOCATION": "1"]))
        }
    }
}
