import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Closed service vocabulary

/// A published device provider may name any service (its shape is checked), and the bedroom's
/// scripts and MQTT topic come from the house document by role, never from the publication.
@Suite @MainActor struct ServerUIServiceVocabularyTests {
    private typealias Vocabulary = ServerUIServiceVocabulary

    private func descriptor(button: MediaRemoteAction? = nil, app: MediaRemoteAction? = nil,
                            device: MediaRemoteAction? = nil, card: MediaRemoteAction? = nil) -> ServerUIRemoteDescriptor {
        var config = ServerUIRemoteTestProvider.config()
        if let button { config.power = .init("Power", icon: "", action: button) }
        if let app { config.apps = [.init("App", action: app)] }
        if let device { config.devices[0].action = device }
        var cards: [ServerUIRemoteDescriptor.Card] = []
        if let card {
            var configuration = config.devices[0]
            configuration.action = card
            cards.append(.init(key: "page-card", configuration: configuration))
        }
        return .init(configuration: config, cards: cards)
    }

    private func issues(_ descriptor: ServerUIRemoteDescriptor, house: HouseConfigSource? = nil) -> [String] {
        HouseConfigSource.$scoped.withValue(house ?? ServerUIRemoteTestProvider.houseSource()) {
            ServerUIDeviceProviderValidation.validate(.remote(descriptor), at: "").map { String($0.pointer.drop { $0 == "/" }) }
        }
    }

    // MARK: Remote commands

    @Test func acceptsAnyServiceTheDocumentNames() {
        #expect(issues(descriptor(button: .service("media_player", "reload_config_entry", target: "media_player.demo_unit"))).isEmpty)
        #expect(issues(descriptor(app: .service("switch", "turn_on", target: "switch.demo_unit"))).isEmpty)
        #expect(issues(descriptor(device: .service("input_select", "reload"))).isEmpty)
        #expect(issues(descriptor(button: .service("light", "turn_on", target: "light.demo_lounge"))).isEmpty)
    }

    @Test func rejectsATargetFromAnotherDomain() {
        #expect(issues(descriptor(button: .service("media_player", "turn_off", target: "lock.front_door"))) == ["power"])
        #expect(issues(descriptor(device: .service("switch", "toggle", target: "media_player.demo_unit"))) == ["devices/0"])
    }

    @Test func pageCardsAreCheckedLikeDeviceTiles() {
        #expect(issues(descriptor(card: .service("remote", "send_command", target: "remote.demo_unit"))).isEmpty)
        #expect(issues(descriptor(card: .service("media_player", "volume_up", target: "lock.demo_front_door"))) == ["cards/0/configuration"])
    }

    @Test func anyScriptIsAcceptedButNeverWithATarget() {
        let declared = ServerUIRemoteTestProvider.houseSource(scripts: ["house_launch"])
        #expect(issues(descriptor(app: .service("script", "house_launch")), house: declared).isEmpty)
        // The room cards call scripts the remote's own house block does not declare.
        #expect(issues(descriptor(card: .service("script", "demo_room_scene_one")), house: declared).isEmpty)
        #expect(issues(descriptor(card: .service("script", "demo_room_scene_two")), house: HouseConfigSource()).isEmpty)
        #expect(issues(descriptor(app: .service("script", "publication_invented")), house: declared).isEmpty)
        // A script cannot carry a target entity.
        #expect(issues(descriptor(app: .service("script", "house_launch", target: "script.demo_launch")), house: declared) == ["apps/0"])
    }

    // MARK: Bedroom roles

    private func bedroomDescriptor() -> ServerUIBedroomDescriptor {
        let bedroom = DemoHouse.config.bedroom
        return .init(wakeProviderId: "demo-wake", beds: bedroom.beds.map {
            .init(providerId: "demo-" + $0.side.rawValue, configuration: $0)
        }, environment: .init(scheduleEntityId: bedroom.scheduleEntityId, scheduleSetTopic: "authored/topic",
                              hotFlashBrokerScript: "authored_broker", householdAwayEntityId: bedroom.householdAwayEntityId,
                              householdAwayScript: "authored_away", wakeLight: bedroom.wakeLight))
    }

    @Test func publicationCannotNameBedroomScriptsOrTheScheduleTopic() throws {
        let inputs = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(bedroomDescriptor()))
        let shape = ServerUICompositionShape.deviceProviderSource("bedroom-config@1")
        guard case .object(var source) = JSONValue.object(["id": "room", "kind": "model", "model": "bedroom-config@1"]) else { return }
        source["inputs"] = inputs
        let pointers = Set(ServerUICompositionShape.issues(of: .object(source), against: shape).filter { $0.code == .unknownField }.map(\.pointer))
        #expect(pointers.isSuperset(of: [
            "/inputs/environment/scheduleSetTopic", "/inputs/environment/hotFlashBrokerScript",
            "/inputs/environment/householdAwayScript", "/inputs/beds/0/configuration/tonightScript",
            "/inputs/beds/0/configuration/outsideScheduleScript", "/inputs/beds/1/configuration/tonightScript"
        ]))
    }

    @Test(.demoHouse) func controllersTakeScriptsAndTopicFromTheHouseDocumentByRole() throws {
        let authored = try JSONEncoder().encode(bedroomDescriptor())
        // Even if bytes that name scripts reach the decoder, none survives into the descriptor.
        guard case .bedroom(let descriptor) = try ServerUIDeviceProviderDescriptor.decode(model: "bedroom-config@1", data: authored) else {
            Issue.record("Expected a bedroom descriptor"); return
        }
        #expect(descriptor.environment.scheduleSetTopic.isEmpty && descriptor.environment.hotFlashBrokerScript.isEmpty)
        #expect(descriptor.beds.allSatisfy { $0.configuration.tonightScript.isEmpty && $0.configuration.outsideScheduleScript.isEmpty })

        let environment = descriptor.controllerEnvironment
        #expect(environment.scheduleSetTopic == MasterBedroom.scheduleSetTopic && !environment.scheduleSetTopic.isEmpty)
        #expect(environment.hotFlashBrokerScript == MasterBedroom.hotFlashBrokerScript)
        #expect(environment.householdAwayScript == MasterBedroom.householdAwayScript)
        for bed in descriptor.beds {
            let resolved = descriptor.controllerConfiguration(of: bed)
            #expect(resolved.tonightScript == MasterBedroom.bed(bed.configuration.side).tonightScript)
            #expect(resolved.outsideScheduleScript == MasterBedroom.bed(bed.configuration.side).outsideScheduleScript)
            #expect(!resolved.tonightScript.isEmpty && resolved.tonightScript != "authored_broker")
        }
    }

    @Test func withoutAHouseDocumentTheRolesAreEmptyNotAuthored() throws {
        let authored = try JSONEncoder().encode(bedroomDescriptor())
        guard case .bedroom(let descriptor) = try ServerUIDeviceProviderDescriptor.decode(model: "bedroom-config@1", data: authored) else {
            Issue.record("Expected a bedroom descriptor"); return
        }
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect(descriptor.controllerEnvironment.scheduleSetTopic.isEmpty)
            #expect(descriptor.controllerEnvironment.householdAwayScript.isEmpty)
        }
    }

    // MARK: Todo completion script

    @Test func todoCompletionScriptIsTheDocumentsAndNeedsOnlyToBeAScriptEntity() throws {
        // The publication's todo collection names the script; no house list is consulted, with or without a house document.
        HouseConfigSource.$scoped.withValue(HouseConfigSource()) {
            #expect((try? ServerUITodoProvider.Configuration(entityId: "todo.example", completionScript: "script.demo_any_name"))?
                .completionScript == "script.demo_any_name")
        }
        for bad in ["switch.demo_finish", "script.", "script.Finish", "script.demo_finish\n", "finish"] {
            #expect(throws: ServerUITodoProvider.Failure.invalidTarget) {
                try ServerUITodoProvider.Configuration(entityId: "todo.example", completionScript: bad)
            }
        }
    }
}
