//
//  FineDebugToast.swift
//  FineUIKit
//
//  Created by nova on 2026/07/29.
//

#if DEBUG
import UIKit

/// Confirms on screen that a code injection reached the runtime.
///
/// Hot reload fails in two ways that look identical from the simulator: the
/// injection never arrived (a toolchain problem), or it arrived and re-rendered
/// but the description did not change (a code problem). Only the first is
/// silent, so saying "the runtime reloaded" out loud tells the two apart
/// without a debugger.
///
/// Every live tree re-renders on the same notification, so the toast counts the
/// trees it was asked about instead of stacking one banner per controller.
/// DEBUG builds only, and only when `FineDiagnostics.showsInjectionToast`.
@MainActor
final class FineDebugToast: UIView {
    private static let visibleDuration: Duration = .milliseconds(1200)

    private let label = UILabel()
    private var reloadCount = 0
    private var dismissal: Task<Void, Never>?
    /// Distinguishes the fade this presentation started from an earlier one,
    /// so a completion that a re-presentation overtook cannot reset the count
    /// that is on screen.
    private var presentation = 0

    /// What the banner currently reads, for tests.
    var message: String? {
        label.text
    }

    /// Shows (or re-shows) the toast in `window`, coalescing repeat calls.
    ///
    /// Does nothing without a window: a tree built into a detached view has
    /// nowhere to put a banner, and that is not worth reporting.
    static func show(_ message: String, in window: UIWindow?) {
        guard let window else { return }

        let toast = window.subviews.compactMap { $0 as? FineDebugToast }.first ?? .init(in: window)
        toast.present(message)
    }

    private init(in window: UIWindow) {
        super.init(frame: .zero)

        // A debug banner that swallowed a tap would be worse than no banner.
        isUserInteractionEnabled = false
        alpha = 0
        backgroundColor = UIColor.systemGreen.withAlphaComponent(0.92)
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .white
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(self)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            centerXAnchor.constraint(equalTo: window.centerXAnchor),
            topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FineDebugToast does not support initialization from a coder")
    }

    private func present(_ message: String) {
        reloadCount += 1
        label.text = reloadCount > 1 ? "\(message) ×\(reloadCount)" : message

        // Above whatever the app added to the window since the last reload.
        superview?.bringSubviewToFront(self)

        dismissal?.cancel()
        presentation += 1
        let presentation = presentation

        // An injection that lands mid-fade has to stop the fade, not just set
        // the property: the running animation owns what is on screen, and
        // assigning `alpha` under it makes the banner blink out while it says
        // a reload just happened.
        layer.removeAllAnimations()
        alpha = 1

        dismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled, let self else { return }

            UIView.animate(withDuration: 0.25) {
                self.alpha = 0
            } completion: { finished in
                // Counting restarts with the next injection, not with the next
                // tree of this one — and not at all if this fade was overtaken.
                guard finished, self.presentation == presentation else { return }

                self.reloadCount = 0
            }
        }
    }
}
#endif
