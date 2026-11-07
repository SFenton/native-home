import CoreGraphics

/// The shared thermostat dial's size and gutter tokens (drawn by `UKThermostatDial`; pattern: `.agents/patterns/thermostat-dial.md`; web source
/// `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:4188` `ThermostatDial` over
/// `src/components/hass/CircularControlDial.tsx`).
///
/// Pure UI: callers pass a ``ThermostatDialConfiguration`` and receive setpoint commits; they map those to
/// `climate.set_temperature`. Dragging a handle shows the new setpoint at once and commits on release;
/// tapping the ring moves the nearest handle there. VoiceOver users adjust each handle by one step with
/// swipe up and down (HIG: Accessibility › VoiceOver, adjustable elements).
public enum ThermostatDial {
    /// How large the dial may grow (web `data-size`).
    public enum Size: Sendable {
        /// A page hero (web 316 px).
        case page
        /// Inside a sheet (web 300 px).
        case modal
        /// A small preview (web 250 px).
        case compact

        /// Largest ring diameter box, in points.
        public var maxSide: CGFloat {
            switch self {
            case .page: 316
            case .modal: 300
            case .compact: 250
            }
        }
    }

    /// Space outside the ring so a handle's 64 pt target never leaves the view (web modal dial gutter).
    public static let gutter: CGFloat = 20
}
