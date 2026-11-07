import HassCore

/// The demo house's three vacuums by position in its document, for tests that name a vacuum by role. The positions are the
/// demo document's order (the first has the most zones and a coordinator, the second and third are single-map vacuums).
///
/// Read these inside a demo-house scope (`@Suite(.demoHouse)`); with no document they trap, because there is no vacuum.
public extension Vacuums {
    /// The demo house's first vacuum (the multi-room floor).
    static var mainFloor: VacuumConfig { all[0] }
    /// The demo house's second vacuum.
    static var musicRoom: VacuumConfig { all[1] }
    /// The demo house's third vacuum.
    static var theaterRoom: VacuumConfig { all[2] }
}
