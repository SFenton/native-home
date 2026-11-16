#if os(iOS)
import UIKit

// MARK: - Native stack exit admission

/// Admits Back, ancestor-menu and interactive pops before UIKit changes the stack.
/// A deferred approval becomes a normal pop; stale or repeated approvals do nothing.
@MainActor
class UKNativeExitNavigationController: UINavigationController {
    var requestPop: (([UIViewController], @escaping () -> Void) -> Void)?
    private var approvingPop = false

    override func popViewController(animated: Bool) -> UIViewController? {
        guard !approvingPop, viewControllers.count > 1, let requestPop else { return super.popViewController(animated: animated) }
        let expected = topViewController
        var result: UIViewController?
        var responded = false
        requestPop(Array(viewControllers.suffix(1))) { [weak self, weak expected] in
            guard !responded else { return }
            responded = true
            guard let self, let expected, self.topViewController === expected else { return }
            result = self.approvedPop(animated: animated)
        }
        return result
    }

    override func popToViewController(_ target: UIViewController, animated: Bool) -> [UIViewController]? {
        guard !approvingPop, topViewController !== target, let index = viewControllers.firstIndex(of: target), let requestPop else {
            return super.popToViewController(target, animated: animated)
        }
        let expected = topViewController
        var result: [UIViewController]?
        var responded = false
        requestPop(Array(viewControllers.dropFirst(index + 1))) { [weak self, weak expected, weak target] in
            guard !responded else { return }
            responded = true
            guard let self, let expected, let target, self.topViewController === expected,
                  self.viewControllers.contains(target) else { return }
            result = self.approvedPop(to: target, animated: animated)
        }
        return result
    }

    override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        guard let root = viewControllers.first else { return nil }
        return popToViewController(root, animated: animated)
    }

    private func approvedPop(animated: Bool) -> UIViewController? {
        approvingPop = true
        defer { approvingPop = false }
        return super.popViewController(animated: animated)
    }

    private func approvedPop(to target: UIViewController, animated: Bool) -> [UIViewController]? {
        approvingPop = true
        defer { approvingPop = false }
        return super.popToViewController(target, animated: animated)
    }
}
#endif
