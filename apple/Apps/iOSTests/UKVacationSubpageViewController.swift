import UIKit
@testable import HassUI

/// Hosts one Vacation or Solo Trip content view in a page, as the server-driven host does: the content takes the page as
/// its host and reports appearing and disappearing.
@MainActor
final class UKVacationSubpageViewController: UKPageViewController {
    private let content: UKVacationContent

    init(content: UKVacationContent, context: UKContext) {
        self.content = content
        super.init(context: context, title: content.title)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        content.host = self
        install(scrollView: content.scrollView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        content.hostDidAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        content.hostDidDisappear()
    }
}
