#if os(iOS)
import HassCore

// MARK: - UIKit provider preparation

/// Projects the typed canonical factory into existing renderer interfaces; never dispatches a page ID.
@MainActor
struct UKServerUIDeviceProviders {
    let domain: ServerUIDeviceProviders
    let bedrooms: [String: UKServerUIBedroomProvider]
    let remotes: [String: ServerUIRemoteSession]
    let collections: [String: ServerUIRowCollection]
    let bedroomRegistry: UKServerUIBedroomRegistry

    init(sources: [ServerUICompositionDocument.Source], context: UKContext,
         responder: (any HassServiceResponding)?, canEditBedroom: Bool,
         bedrooms suppliedBedrooms: [String: UKServerUIBedroomProvider],
         remotes suppliedRemotes: [String: ServerUIRemoteSession],
         collections suppliedCollections: [String: ServerUIRowCollection],
         retaining old: ServerUIDeviceProviders?,
         retainingBedrooms: UKServerUIBedroomRegistry? = nil) throws {
        do {
            domain = try ServerUIDeviceProviders(sources: sources, store: context.store,
                caller: context.caller ?? context.connection, responder: responder,
                canEditBedroom: canEditBedroom, retaining: old)
        } catch ServerUIDeviceProviders.Failure.busy {
            throw UKServerUIRendererError(code: .interactionBlocked, pointer: "/document/dataSources")
        } catch {
            throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
        }
        var bedrooms = suppliedBedrooms
        var remotes = suppliedRemotes
        var collections = suppliedCollections
        func insert<T>(_ value: T, id: String, into values: inout [String: T]) throws {
            guard values[id] == nil else {
                throw UKServerUIRendererError(code: .unavailableSource, pointer: "/document/dataSources")
            }
            values[id] = value
        }
        for (id, remote) in domain.remotes { try insert(remote, id: id, into: &remotes) }
        for session in domain.bedrooms.values {
            try insert(.wake(session.devices.wakeLight), id: session.descriptor.wakeProviderId, into: &bedrooms)
            for (index, bed) in session.descriptor.beds.enumerated() {
                try insert(.bed(session.devices.beds[index]), id: bed.providerId, into: &bedrooms)
            }
            for (id, collection) in session.collections { try insert(collection, id: id, into: &collections) }
        }
        self.bedrooms = bedrooms
        self.remotes = remotes
        self.collections = collections
        bedroomRegistry = try UKServerUIBedroomRegistry(domain: domain, retaining: retainingBedrooms)
        try bedroomRegistry.validate(sources, supplied: bedrooms)
    }
}
#endif
