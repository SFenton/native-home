import Foundation

// MARK: - Retained canonical provider factory

/// A prepared provider set is immutable until the host commits it with its accepted publication.
@MainActor
public final class ServerUIDeviceProviders {
    /// The authored failure choices.
    public enum Failure: Error, Equatable { case missingTransport(String), busy(String), duplicateProvider(String), storeMismatch, transportMismatch }
    public private(set) var remotes: [String: ServerUIRemoteSession] = [:]
    public private(set) var bedrooms: [String: ServerUIBedroomSession] = [:]
    public private(set) var lights: [String: ServerUICustomLightsSource] = [:]
    public private(set) var sprinklers: [String: ServerUISprinklerSource] = [:]
    private var descriptors: [String: ServerUIDeviceProviderDescriptor] = [:]
    private let store: EntityStore
    private let canEditBedroom: Bool
    private let caller: (any HassServiceCalling)?
    private let responder: (any HassServiceResponding)?

    /// Creates a server uidevice providers.
    public init(sources: [ServerUICompositionDocument.Source], store: EntityStore,
                caller: (any HassServiceCalling)?, responder: (any HassServiceResponding)? = nil,
                canEditBedroom: Bool = false, retaining old: ServerUIDeviceProviders? = nil) throws {
        self.store = store
        self.canEditBedroom = canEditBedroom
        self.caller = caller
        self.responder = responder ?? (caller as? any HassServiceResponding)
        guard old == nil || old?.store === store else { throw Failure.storeMismatch }
        if let old, old.caller !== caller || old.responder !== self.responder { throw Failure.transportMismatch }
        var next: [String: ServerUIDeviceProviderDescriptor] = [:]
        for source in sources {
            guard case .deviceProvider(let id, let descriptor) = source else { continue }
            guard next.updateValue(descriptor, forKey: id) == nil else { throw Failure.duplicateProvider(id) }
        }
        if let old {
            for (id, descriptor) in old.descriptors where next[id] != descriptor || old.canEditBedroom != canEditBedroom {
                if old.protects(id) { throw Failure.busy(id) }
            }
        }
        descriptors = next
        var providerIDs = Set<String>()
        for (id, descriptor) in next.sorted(by: { $0.key < $1.key }) {
            let unchanged = old?.descriptors[id] == descriptor
            switch descriptor {
            case .remote(let config):
                guard providerIDs.insert(id).inserted else { throw Failure.duplicateProvider(id) }
                if unchanged, let existing = old?.remotes[id] { remotes[id] = existing }
                else {
                    guard let caller else { throw Failure.missingTransport(id) }
                    remotes[id] = ServerUIRemoteSession(controller: MediaRemoteController(config: config.controllerConfiguration, store: store, caller: caller))
                }
            case .bedroom(let room):
                for providerID in room.beds.map(\.providerId) + [room.wakeProviderId] {
                    guard providerIDs.insert(providerID).inserted else { throw Failure.duplicateProvider(providerID) }
                }
                if unchanged, old?.canEditBedroom == canEditBedroom, let existing = old?.bedrooms[id] { bedrooms[id] = existing }
                else {
                    guard let responder = responder ?? (caller as? any HassServiceResponding) else { throw Failure.missingTransport(id) }
                    bedrooms[id] = ServerUIBedroomSession(descriptor: room, store: store, caller: responder, canEdit: canEditBedroom)
                }
            case .lights(let group):
                if unchanged, let existing = old?.lights[id] { lights[id] = existing }
                else {
                    guard let caller else { throw Failure.missingTransport(id) }
                    lights[id] = ServerUICustomLightsSource(settings: try group.settings(), store: store, caller: caller)
                }
            case .sprinkler(let config):
                if unchanged, let existing = old?.sprinklers[id] { sprinklers[id] = existing }
                else {
                    guard let caller else { throw Failure.missingTransport(id) }
                    sprinklers[id] = ServerUISprinklerSource(descriptor: config, store: store, caller: caller)
                }
            }
        }
    }

    public var protectsPublication: Bool { descriptors.keys.contains(where: protects) }
    private func protects(_ id: String) -> Bool {
        remotes[id]?.hasInteraction == true || bedrooms[id]?.protectsPublication == true
            || lights[id]?.protectsPublication == true || sprinklers[id]?.protectsPublication == true
    }
}
