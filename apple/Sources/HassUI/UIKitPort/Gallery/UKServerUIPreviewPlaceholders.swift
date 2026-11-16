#if os(iOS) && DEBUG
import HassCore
import HassDemoHouse

// MARK: - Preview stand-ins

/// Stand-ins that let the preview route accept every document the live route accepts.
///
/// The live route validates against the signed-in house and its connection. The preview has neither, so it supplies placeholders
/// shaped by the document itself, and the renderer's validators are untouched. Each placeholder draws the surface's own
/// documented unavailable state (a camera that is offline, weather that is not connected, a checklist row that is unavailable)
/// rather than any new UI. Debug builds only.
@MainActor
enum UKServerUIPreviewPlaceholders {
    /// The demo house with the document's own vacation checklist items added after the demo house's, so the away provider
    /// accepts them. Items already present keep the demo house's title; the entities stay absent from the store, so each row
    /// draws unavailable.
    static func houseConfig(for document: ServerUICompositionDocument, awayProviderId: String,
                            base: HouseConfig = DemoHouse.config) -> HouseConfig {
        var configuration = base
        var known = Set(configuration.vacation.checklist.map(\.entityId))
        for control in document.settingsControls(overProvider: awayProviderId) where control.kind == .vacationCheck {
            guard known.insert(control.item).inserted else { continue }
            configuration.vacation.checklist.append(.init(title: control.node.title, entityId: control.item))
        }
        return configuration
    }

    /// A camera reader that approves the document's camera sources and holds no connection: it reports offline, which the
    /// camera face draws as its offline state. It leases nothing and has no snapshot.
    static func cameraReader(for document: ServerUICompositionDocument) -> UKCameraReadProvider {
        let descriptors = document.dataSources.compactMap { source -> ServerUICameraDescriptor? in
            guard case .camera(_, let configuration) = source else { return nil }
            return configuration
        }
        return UKCameraReadProvider(descriptors: descriptors, appear: { _ in }, disappear: { _ in }, retry: { _ in },
                                    snapshotURL: { _ in nil }, offline: { true })
    }

    /// A weather reader that approves the document's weather entities and reports no connection, so the panel draws its
    /// offline state over whatever the entity's own state holds. It never fetches a forecast.
    static func weatherReader(for document: ServerUICompositionDocument) -> ServerUIWeatherReader {
        let ids = document.dataSources.compactMap { source -> String? in
            guard case .homeWeather(_, let configuration) = source else { return nil }
            return configuration.weatherEntityId
        }
        return ServerUIWeatherReader(entityIds: Set(ids), connected: { false },
                                     fetch: { _, _ in throw ServerUIWeatherReader.Failure.unapprovedEntity })
    }
}
#endif
