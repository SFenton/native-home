#if os(iOS) && DEBUG
import HassCore
import HassDesign
import UIKit

/// `FENTON_GALLERY=room-devices`: the grill sheet on fixture state with a recording caller (`RoomDevicesGallery`).
/// `FENTON_GALLERY_DEVICE=<id>` opens a fixture at launch.
@MainActor
final class UKRoomDevicesGalleryViewController: UKPageViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let fixtures = RoomDeviceFixture.all().filter { $0.kind == .grill }
    private let recorder = RoomDeviceGalleryRecorder()
    private var initial: RoomDeviceFixture?
    private let footer = UKGalleryLastCallView()

    init() {
        let environment = ProcessInfo.processInfo.environment
        let all = RoomDeviceFixture.all().filter { $0.kind == .grill }
        initial = environment["FENTON_GALLERY_DEVICE"].flatMap { id in all.first { $0.id == id } }
        super.init(context: UKGalleryChrome.context(), title: "Room Devices")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        install(scrollView: tableView)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "device")
        bag.observe { [recorder, footer] in footer.record(recorder.lastCall) }
        footer.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        tableView.tableFooterView = footer
    }

    private let opener = UKGalleryAutoOpener(label: "room-devices")

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let initial else { return }
        opener.start(on: self) { [weak self] in self?.open(initial) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if presentedViewController == nil { opener.cancel() }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { fixtures.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "device", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = fixtures[indexPath.row].name
        content.textProperties.color = UKInk.action
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "gallery.device.\(fixtures[indexPath.row].id)"
        cell.accessibilityTraits = .button
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        open(fixtures[indexPath.row])
    }

    private func open(_ fixture: RoomDeviceFixture) {
        let caller = recorder.caller(for: fixture.store)
        let context = UKGalleryChrome.context(store: fixture.store, caller: caller).with { $0.surface = .sheet }
        let accessory: UIView? = GalleryEnvironment.isClean ? nil : UKLastCallBar { [recorder] in recorder.lastCall }
        guard case .grill = fixture.kind else { return }
        let modal = UKGrillSheet.make(controller: GrillController(store: fixture.store, caller: caller), accessory: accessory)
        modal.present(from: self)
    }
}
#endif
