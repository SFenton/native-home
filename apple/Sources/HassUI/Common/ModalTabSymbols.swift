import HassCore
import HassDesign

/// The icon of each modal section, the web's (`ModalIconTabNav` over the tab lists in
/// `ha-sfenton-react-dash@9ac2a46:src/constants/surfaceSemantics.ts`), mapped to SF Symbols through ``SymbolMap``.
/// ``ModalTabBar`` shows them in place of titles on iPhone (owner, 2026-10-16: "show icons like the web app"); the
/// titles stay the segments' accessible names.
enum ModalTabSymbols {
    /// The web's Material Design Icon for each section.
    static func mdi(for tab: MediaRemoteTab) -> String {
        switch tab {
        case .controls: "mdi:remote" // surfaceSemantics.ts:37
        case .apps: "mdi:play-box" // :44
        case .devices: "mdi:projector" // :56
        case .hueSync: "mdi:lightbulb-multiple" // :63
        }
    }

    static func mdi(for tab: HumidifierTab) -> String {
        switch tab {
        case .controls: "mdi:air-humidifier" // :131
        case .schedules: "mdi:calendar" // :137
        case .info: "mdi:information-outline" // :143
        }
    }

    static func mdi(for tab: BedSideSheet.Tab) -> String {
        switch tab {
        case .temperature: "mdi:thermostat" // SLEEPYPOD_MODAL_TABS, :233
        case .specialModes: "mdi:snowflake" // :239
        case .alarms: "mdi:alarm" // :245
        case .status: "mdi:information-outline" // :251
        }
    }

    static func mdi(for tab: WakeLightSheet.Tab) -> String {
        switch tab {
        case .alarms: "mdi:alarm" // components/hass/wakeLights/WakeLightModalContent.tsx:135
        case .defaults: "mdi:tune-vertical" // :136
        }
    }

    /// THERMOSTAT_MODAL_TABS, surfaceSemantics.ts:177-189.
    static func mdi(for tab: ClimateConfig.Tab) -> String { tab.icon }

    /// The SF Symbol for a section.
    static func symbol(for tab: MediaRemoteTab) -> String { SymbolMap.symbol(for: mdi(for: tab)) }
    static func symbol(for tab: HumidifierTab) -> String { SymbolMap.symbol(for: mdi(for: tab)) }
    static func symbol(for tab: BedSideSheet.Tab) -> String { SymbolMap.symbol(for: mdi(for: tab)) }
    static func symbol(for tab: WakeLightSheet.Tab) -> String { SymbolMap.symbol(for: mdi(for: tab)) }
    static func symbol(for tab: ClimateConfig.Tab) -> String { SymbolMap.symbol(for: mdi(for: tab)) }
}
