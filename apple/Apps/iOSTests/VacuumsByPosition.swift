import HassCore

/// The demo house's vacuums by position in its document, for hosted tests that name a vacuum by role. Read these while the
/// demo document is installed (`DemoHouseTestCase`); with no document there is no vacuum.
extension Vacuums {
    /// The demo house's first vacuum (the multi-room floor).
    static var mainFloor: VacuumConfig { all[0] }
    /// The demo house's second vacuum.
    static var musicRoom: VacuumConfig { all[1] }
}
