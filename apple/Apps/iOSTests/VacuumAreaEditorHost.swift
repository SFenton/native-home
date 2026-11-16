import HassCore
import UIKit
@testable import HassUI

/// Hosts the server-driven area editor surface (`UKVacuumAreaEditorContent`) in a plain page, wired the way the
/// renderer wires it: the selection lives on the controller and Use pops the page.
@MainActor
final class VacuumAreaEditorHost: UIViewController {
    private let controller: VacuumController
    private let mapState: VacuumMapState

    init(controller: VacuumController, mapState: VacuumMapState) {
        self.controller = controller
        self.mapState = mapState
        super.init(nibName: nil, bundle: nil)
        title = "\(controller.vacuum.title) Cleaning Area"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let editor = UKVacuumAreaEditorContent(vacuum: controller.vacuum, mapState: mapState,
            selection: { [controller] in controller.areaSelection },
            setSelection: { [controller] in controller.areaSelection = $0 },
            onUse: { [weak self] in self?.navigationController?.popViewController(animated: true) })
        view.addSubview(editor)
        editor.ukPin(to: view)
    }
}
