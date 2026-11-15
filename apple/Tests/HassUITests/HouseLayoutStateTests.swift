import CoreGraphics
import HassCore
@testable import HassUI
import Testing

/// The missing-layout states: what a page draws for each store status, document and role (rules 10 to 12), the copy, the skeleton's
/// shapes, the Home Assistant modal's House Layout row (rule 16) and the debug switches. `.agents/design/house-config-states.md`.
struct HouseLayoutStateTests {
    private static let statuses: [HouseConfigStore.Status] = [
        .idle, .loading, .ready, .notConfigured, .integrationMissing, .newerSchema(found: 9), .invalid, .timedOut,
    ]
    private static let roles: [HouseLayoutState.Role] = [.admin, .member, .unknown]

    // MARK: - resolve

    @Test func aDocumentAlwaysWinsWhateverTheStatusAndRole() {
        for status in Self.statuses {
            for role in Self.roles {
                #expect(HouseLayoutState.resolve(hasDocument: true, status: status, role: role) == .content, "\(status) \(role)")
            }
        }
    }

    @Test func noDocumentNeverDrawsContent() {
        for status in Self.statuses {
            for role in Self.roles {
                #expect(HouseLayoutState.resolve(document: nil, status: status, role: role) != .content)
            }
        }
    }

    @Test func noDocumentWhileAskingIsTheSkeleton() {
        for status in [HouseConfigStore.Status.idle, .loading, .ready] {
            for role in Self.roles {
                #expect(HouseLayoutState.resolve(document: nil, status: status, role: role) == .skeleton)
            }
        }
    }

    @Test func noDocumentAndAProblemIsAMessageWhoseActionFollowsTheRole() {
        let actions: [(HouseConfigStore.Status, HouseLayoutState.Kind)] = [
            (.integrationMissing, .integrationMissing), (.notConfigured, .notConfigured), (.invalid, .invalid),
        ]
        for (status, kind) in actions {
            #expect(HouseLayoutState.resolve(document: nil, status: status, role: .admin) == .message(kind, showsAction: true))
            #expect(HouseLayoutState.resolve(document: nil, status: status, role: .member) == .message(kind, showsAction: false))
            #expect(HouseLayoutState.resolve(document: nil, status: status, role: .unknown) == .message(kind, showsAction: false))
        }
    }

    @Test func aNewerSchemaNeverHasAnAction() {
        for role in Self.roles {
            #expect(HouseLayoutState.resolve(document: nil, status: .newerSchema(found: 9), role: role) == .message(.newerSchema, showsAction: false))
        }
    }

    @Test func aTimeoutOffersTryAgainToEveryone() {
        for role in Self.roles {
            #expect(HouseLayoutState.resolve(document: nil, status: .timedOut, role: role) == .message(.timedOut, showsAction: true))
        }
    }

    @Test func theRoleComesFromTheUser() {
        #expect(HouseLayoutState.Role(nil) == .unknown)
        #expect(HouseLayoutState.Role(HassUser(id: "1", name: nil, isOwner: false, isAdmin: true)) == .admin)
        #expect(HouseLayoutState.Role(HassUser(id: "2", name: nil, isOwner: true, isAdmin: false)) == .admin)
        #expect(HouseLayoutState.Role(HassUser(id: "3", name: nil, isOwner: false, isAdmin: false)) == .member)
    }

    // MARK: - Copy

    @Test func theCopyIsTheDecidedTable() {
        #expect(HouseConfigCopy.integrationName == "S+H Home Integration")
        let missing = HouseConfigCopy.entry(.integrationMissing)
        #expect(missing.symbol == "puzzlepiece.extension" && missing.title == "Add the S+H Home Integration")
        #expect(missing.actionTitle == "Open Integrations" && missing.action == .open(.integrations))
        #expect(missing.message(for: .admin).hasSuffix("Install or update it there; S+H picks it up by itself."))
        #expect(missing.message(for: .member).hasSuffix("Ask whoever manages your Home Assistant to install or update it."))
        #expect(missing.message(for: .unknown) == missing.message(for: .member))
        let notSetUp = HouseConfigCopy.entry(.notConfigured)
        #expect(notSetUp.symbol == "house" && notSetUp.title == "Home Isn't Set Up Yet")
        #expect(notSetUp.actionTitle == "Open S+H Home Integration" && notSetUp.action == .open(.houseIntegration))
        let invalid = HouseConfigCopy.entry(.invalid)
        #expect(invalid.symbol == "exclamationmark.triangle" && invalid.title == "Unable to Read the House Layout")
        #expect(invalid.actionTitle == "Open Repairs" && invalid.action == .open(.repairs))
        #expect(invalid.memberMessage == "Ask whoever manages your Home Assistant to check Repairs.")
        let newer = HouseConfigCopy.entry(.newerSchema)
        #expect(newer.symbol == "arrow.down.circle" && newer.title == "Update S+H" && newer.action == nil && newer.actionTitle == nil)
        #expect(newer.adminMessage == newer.memberMessage)
        let timeout = HouseConfigCopy.entry(.timedOut)
        #expect(timeout.title == "Unable to Load the House Layout" && timeout.actionTitle == "Try Again" && timeout.action == .tryAgain)
        #expect(HouseConfigCopy.tryAgainBusy == "Trying Again…")
        #expect(HouseConfigCopy.skeletonLabel == "Getting your home from Home Assistant")
    }

    @Test func everyKindHasCopyAndOnlyActionsHaveTitles() {
        for kind in HouseLayoutState.Kind.allCases {
            let entry = HouseConfigCopy.entry(kind)
            #expect(!entry.symbol.isEmpty && !entry.title.isEmpty && !entry.adminMessage.isEmpty && !entry.memberMessage.isEmpty)
            #expect((entry.action == nil) == (entry.actionTitle == nil))
        }
    }

    // MARK: - The House Layout row

    @Test func loadedWithEverythingFound() {
        let row = HouseLayoutSummary(hasDocument: true, status: .ready, missing: [])
        #expect(row.value == "Loaded" && row.footer == nil)
    }

    @Test func loadedWithSomeNotFoundListsThemInTheFooter() {
        let row = HouseLayoutSummary(hasDocument: true, status: .ready, missing: ["light.demo_a", "sensor.demo_b"])
        #expect(row.value == "Loaded, 2 not found")
        #expect(row.footer == "Not found in Home Assistant: light.demo_a, sensor.demo_b. Their tiles show Unavailable.")
    }

    @Test func theFooterCutsAtFiveAndCountsTheRest() {
        let ids = (1...8).map { "light.demo_x\($0)" }
        let row = HouseLayoutSummary(hasDocument: true, status: .ready, missing: ids)
        #expect(row.value == "Loaded, 8 not found")
        #expect(row.footer == "Not found in Home Assistant: light.demo_x1, light.demo_x2, light.demo_x3, light.demo_x4, light.demo_x5, and 3 more. Their tiles show Unavailable.")
        let six = HouseLayoutSummary(hasDocument: true, status: .ready, missing: Array(ids.prefix(6)))
        #expect(six.footer?.contains("light.demo_x5, and 1 more.") == true)
        let five = HouseLayoutSummary(hasDocument: true, status: .ready, missing: Array(ids.prefix(5)))
        #expect(five.footer?.contains("more") == false)
    }

    @Test func aSavedCopyGivesTheReasonInWords() {
        let reasons: [(HouseConfigStore.Status, String)] = [
            (.integrationMissing, "the S+H Home Integration is missing or out of date"),
            (.notConfigured, "it has no house layout set up"),
            (.invalid, "the layout can't be read"),
            (.newerSchema(found: 9), "the layout is newer than this version of S+H"),
            (.timedOut, "it didn't answer"),
        ]
        for (status, reason) in reasons {
            let row = HouseLayoutSummary(hasDocument: true, status: status, missing: ["light.demo_ignored"])
            #expect(row.value == "Saved copy")
            #expect(row.footer == "Home Assistant can't send the house layout right now (\(reason)), so S+H shows the copy it saved.")
        }
    }

    @Test func aDocumentStillBeingConfirmedIsWaiting() {
        for status in [HouseConfigStore.Status.idle, .loading] {
            #expect(HouseLayoutSummary(hasDocument: true, status: status, missing: []).value == "Waiting for Home Assistant")
        }
    }

    @Test func withNoDocumentTheRowIsTheStatesTitle() {
        #expect(HouseLayoutSummary(hasDocument: false, status: .integrationMissing, missing: []).value == "Add the S+H Home Integration")
        #expect(HouseLayoutSummary(hasDocument: false, status: .notConfigured, missing: []).value == "Home Isn't Set Up Yet")
        #expect(HouseLayoutSummary(hasDocument: false, status: .invalid, missing: []).value == "Unable to Read the House Layout")
        #expect(HouseLayoutSummary(hasDocument: false, status: .newerSchema(found: 3), missing: []).value == "Update S+H")
        #expect(HouseLayoutSummary(hasDocument: false, status: .timedOut, missing: []).value == "Unable to Load the House Layout")
        #expect(HouseLayoutSummary(hasDocument: false, status: .loading, missing: []).value == "Waiting for Home Assistant")
        #expect(HouseLayoutSummary(hasDocument: false, status: nil, missing: []).value == "Waiting for Home Assistant")
        #expect(HouseLayoutSummary(hasDocument: false, status: .invalid, missing: []).footer == nil)
    }
}
