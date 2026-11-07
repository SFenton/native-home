#if os(iOS)
import HassDesign
import UIKit

/// Holds the header and tab bar back while Home arrives after a sign-in, then lets them in after the wallpaper and the first
/// cards have started (``HomeArrival``): the UIKit counterpart of ``ArrivalChromeProbe``. The bars fade in from 10 pt (navigation)
/// and 48 pt (tab) below their place over 0.4 s, 0.1 s and 0.22 s into the arrival; Reduce Motion cross-fades without the offset.
@MainActor
final class UKArrivalChrome {
    private weak var shell: UKShellViewController?
    private let bag = UKObservationBag()
    private var held = false

    init(shell: UKShellViewController, environment: UKShellEnvironment) {
        self.shell = shell
        bag.observe { [weak self] in
            let holding = environment.arrival.map { $0.isActive && !$0.isRevealed } ?? false
            self?.apply(isHolding: holding, reduceMotion: environment.reduceMotion)
        }
    }

    private var bars: (navigation: [UINavigationBar], tab: UITabBar)? {
        guard let shell else { return nil }
        return (shell.sectionControllers.map(\.navigationBar), shell.tabBar)
    }

    private func apply(isHolding: Bool, reduceMotion: Bool) {
        if isHolding, !held {
            guard let bars else { return }
            held = true
            for bar in bars.navigation {
                bar.alpha = 0
                bar.transform = CGAffineTransform(translationX: 0, y: reduceMotion ? 0 : 10)
            }
            bars.tab.alpha = 0
            bars.tab.transform = CGAffineTransform(translationX: 0, y: reduceMotion ? 0 : 48)
        } else if !isHolding, held {
            held = false
            guard let bars else { return }
            let fade = reduceMotion ? MotionTokens.crossFadeDuration : 0.4
            UIView.animate(withDuration: fade, delay: reduceMotion ? 0 : 0.1, options: [.curveEaseOut, .allowUserInteraction]) {
                for bar in bars.navigation { bar.alpha = 1; bar.transform = .identity }
            }
            UIView.animate(withDuration: fade, delay: reduceMotion ? 0 : 0.22, options: [.curveEaseOut, .allowUserInteraction]) {
                bars.tab.alpha = 1
                bars.tab.transform = .identity
            }
        }
    }
}
#endif
