#if os(iOS)
import HassCore

// MARK: - Private authenticated projection

/// Display-only values from the existing authenticated model. The session owner applies
/// `HomeAssistantSettingsView` formatting and screenshot redaction before constructing this value.
struct UKServerUIHomeAssistantSnapshot {
    let address: String
    let connection: String
    let version: String?
    let houseLayout: HouseLayoutSummary
    let account: String
    let role: String?
    let canAdminister: Bool

    func value(for key: String) -> String? {
        switch key {
        case "address": address
        case "connection": connection
        case "version": version
        case "house-layout": houseLayout.value
        case "account": account
        case "role": role
        default: nil
        }
    }
}
#endif
