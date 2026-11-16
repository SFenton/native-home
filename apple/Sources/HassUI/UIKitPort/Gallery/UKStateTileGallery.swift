#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

/// Gallery page for the state-styled tile (`.agents/design/state-styled-tile.md`): a door tile with a disc and a robot tile with none, each
/// stepped through its states by a button, on fixture state and no server, for `FENTON_GALLERY=state-tile`. A journey presses
/// `stateTile.set.<state>` and reads the tile (`stateTile.door`, `stateTile.robot`), its disc (`stateTile.door.action.door`) and
/// `gallery.lastCall`. The arcs are held still while `UKDesign.animationsPaused` is set (a UI test launch), so XCUITest sees the app go idle.
///
/// States of the door: `closed`, `open`, `opening` and `closing` (the arc stands in), `stop` (in progress with a Stop disc that keeps its
/// disc), `error`, `warning`, `unknown`. States of the robot: `docked`, `returning` (the compact arc replaces the glyph), `cleaning`, `paused`.
@MainActor
enum UKStateTileGallery {
    static func make() -> UIViewController {
        UKGalleryChrome.wrap(UKStateTileGalleryViewController(), context: UKGalleryChrome.context())
    }
}

@MainActor
final class UKStateTileGalleryViewController: UIViewController {
    // MARK: Scripted states

    /// A scripted state of the door tile.
    private struct Door {
        var words: String
        var symbol: String
        var stateClass: StateTileLook.Class
        var active = false
        var hasAction = false
        var verb = "Open"
        var disc = "door.garage.closed"
    }

    private static let doors: [String: Door] = [
        "closed": Door(words: "Closed", symbol: "door.garage.closed", stateClass: .resting, hasAction: true),
        "open": Door(words: "Open", symbol: "door.garage.open", stateClass: .resting, active: true, hasAction: true, verb: "Close", disc: "door.garage.open"),
        "opening": Door(words: "Opening", symbol: "door.garage.open", stateClass: .inProgress, active: true, verb: "Reverse", disc: "arrow.uturn.down"),
        "closing": Door(words: "Closing", symbol: "door.garage.open", stateClass: .inProgress, active: true, verb: "Reverse", disc: "arrow.uturn.up"),
        "stop": Door(words: "Opening", symbol: "door.garage.open", stateClass: .inProgress, active: true, hasAction: true, verb: "Stop", disc: "stop.fill"),
        "error": Door(words: "Error", symbol: "door.garage.closed", stateClass: .error, hasAction: true),
        "warning": Door(words: "Open", symbol: "door.garage.open", stateClass: .warning, active: true, hasAction: true, verb: "Close", disc: "door.garage.open"),
        "unknown": Door(words: "Unavailable", symbol: "door.garage.closed", stateClass: .unknown),
    ]

    private static let robots: [String: (words: String, class: StateTileLook.Class, active: Bool)] = [
        "docked": ("Docked", .resting, false), "returning": ("Returning", .inProgress, false), "cleaning": ("Cleaning", .resting, true),
        "paused": ("Paused", .warning, false),
    ]

    // MARK: Parts

    private let doorTile = UKGlassTileView(model: UKGlassTileModel(title: "Door", symbol: "door.garage.closed", isActive: false, identifier: "stateTile.door"))
    private let robotTile = UKGlassTileView(model: UKGlassTileModel(title: "Robot", symbol: "fan", isActive: false, identifier: "stateTile.robot"))
    private let lastCall = UILabel()
    private var calls = 0
    private var doorState = "closed"
    private var robotState = "docked"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "State Tile"
        // Still arcs, so XCUITest sees the app go idle; `-stateTileAnimate YES` turns them.
        UKDesign.animationsPaused = !UserDefaults.standard.bool(forKey: "stateTileAnimate")
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        lastCall.text = "Last call: none"
        lastCall.textColor = .white
        lastCall.accessibilityIdentifier = "gallery.lastCall"
        lastCall.font = UKFont.preferred(.footnote, traits: traitCollection)
        stack.addArrangedSubview(lastCall)
        stack.addArrangedSubview(doorTile)
        stack.addArrangedSubview(buttons(for: Self.doors.keys.sorted(), prefix: "door") { [weak self] in self?.setDoor($0, animated: true) })
        stack.addArrangedSubview(robotTile)
        stack.addArrangedSubview(buttons(for: Self.robots.keys.sorted(), prefix: "robot") { [weak self] in self?.setRobot($0, animated: true) })
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: HassTokens.Spacing.l),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: HassTokens.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -HassTokens.Spacing.l),
        ])
        setDoor(ProcessInfo.processInfo.environment["FENTON_GALLERY_STATE_TILE_DOOR"] ?? "closed", animated: false)
        setRobot("docked", animated: false)
    }

    /// A wrapping row of buttons, one per state, named `stateTile.set.<prefix>.<state>`.
    private func buttons(for states: [String], prefix: String, action: @escaping (String) -> Void) -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = HassTokens.Spacing.s
        for state in states {
            let button = UKPrimaryButton(state) { action(state) }
            button.accessibilityIdentifier = "stateTile.set.\(prefix).\(state)"
            column.addArrangedSubview(button)
        }
        return column
    }

    // MARK: States

    private func setDoor(_ state: String, animated: Bool) {
        guard let door = Self.doors[state] else { return }
        doorState = state
        let unavailable = door.stateClass == .unknown
        let phase: TileActionItem.Phase = unavailable ? .unavailable : (door.hasAction ? .ready : .inFlight)
        let item = TileActionItem(id: "door", verb: door.verb, symbol: door.disc, isOn: door.active, phase: phase, feedback: .tracked)
        let look = StateTileLook(icon: door.disc, colour: .init(door.stateClass, active: door.active),
                                 indicator: indicator(for: door.stateClass, hasAction: door.hasAction), text: door.words, hasAction: door.hasAction)
        var model = UKGlassTileModel(title: "Door", subtitle: door.words, symbol: door.symbol, family: .contact, isActive: door.active,
                                     isUnavailable: unavailable, isError: door.stateClass == .error, behavior: .perform("door"), actions: [item],
                                     identifier: "stateTile.door")
        model.isWarning = door.stateClass == .warning
        model.look = look
        model.stateCandidates = Self.doors.values.map(\.words)
        doorTile.configure(model, environment: UKTileEnvironment(), animated: animated, perform: { [weak self] id in self?.record("door \(id)") })
    }

    private func setRobot(_ state: String, animated: Bool) {
        guard let robot = Self.robots[state] else { return }
        robotState = state
        let look = StateTileLook(icon: "fan", colour: .init(robot.class, active: robot.active),
                                 indicator: indicator(for: robot.class, hasAction: false), text: robot.words, hasAction: false)
        var model = UKGlassTileModel(title: "Robot", subtitle: robot.words, symbol: "fan", family: .cleaning, isActive: robot.active,
                                     kind: .navigate, identifier: "stateTile.robot")
        model.isWarning = robot.class == .warning
        model.look = look
        model.stateCandidates = Self.robots.values.map(\.words)
        robotTile.configure(model, environment: UKTileEnvironment(), animated: animated, action: { [weak self] in self?.record("robot opened") })
    }

    /// The class's default indicator, as ``StateStyle/defaultIndicator(_:hasAction:)`` gives it.
    private func indicator(for stateClass: StateTileLook.Class, hasAction: Bool) -> StateTileLook.Indicator {
        switch stateClass {
        case .inProgress: hasAction ? .none : .arc
        case .warning: .pulse
        case .error: .wiggle
        case .resting, .unknown: .none
        }
    }

    private func record(_ call: String) {
        calls += 1
        lastCall.text = "Last call: \(call) (\(calls))"
    }
}
#endif
