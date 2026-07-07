//
//  FineUI.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import Observation
import UIKit

/// Drives a `Renderable` tree from an observable state object.
///
/// `FineUI` re-evaluates the smallest tracked description it can: root `body`
/// for structural reads, and primitive nodes for values read while updating
/// those nodes.
///
/// Keep a strong reference to this object (e.g. in your view controller);
/// releasing it stops the render loop.
@MainActor
public final class FineUI<State> {
    private let state: State
    private let avoidsKeyboard: Bool
    private let body: (State) -> any Renderable

    private weak var container: UIView?
    private var rootView: UIView?
    private var generation = 0

    #if DEBUG
    // nonisolated(unsafe): only written on the main actor; deinit reads it
    // when no other references remain.
    private nonisolated(unsafe) var injectionObserver: (any NSObjectProtocol)?

    /// The notification that triggers an injection re-render. Overridable so
    /// tests can post to an instance-specific name instead of broadcasting to
    /// every live `FineUI` in the process. Read once in `build(to:)`.
    var injectionNotificationName = Notification.Name("INJECTION_BUNDLE_NOTIFICATION")
    #endif

    /// - Parameter avoidsKeyboard: When `true` (the default), the tree's
    ///   bottom edge follows `keyboardLayoutGuide`, so content compresses
    ///   above the keyboard instead of being covered by it. With the keyboard
    ///   hidden the guide matches the bottom safe area, so layout is
    ///   unchanged.
    public init(
        _ state: State,
        avoidsKeyboard: Bool = true,
        body: @escaping @MainActor (State) -> any Renderable
    ) {
        self.state = state
        self.avoidsKeyboard = avoidsKeyboard
        self.body = body
    }

    deinit {
        #if DEBUG
        if let injectionObserver {
            NotificationCenter.default.removeObserver(injectionObserver)
        }
        #endif
    }

    /// Renders the tree into `container` and starts observing `state`.
    public func build(to container: UIView) {
        self.container = container
        render()

        #if DEBUG
        observeInjection()
        #endif
    }

    #if DEBUG
    /// Re-renders after a code injection (InjectionIII / InjectionNext /
    /// InjectionLite) so updated component implementations take effect.
    /// Note: `body` itself is a closure captured at init; to pick up changes
    /// to the body's source, recreate the `FineUI` from the injection
    /// notification in your view controller.
    private func observeInjection() {
        guard injectionObserver == nil else { return }

        injectionObserver = NotificationCenter.default.addObserver(
            forName: injectionNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.render()
            }
        }
    }
    #endif

    private func render() {
        generation += 1
        let expectedGeneration = generation
        guard let container else { return }

        let transaction = FineTransactionContext.current
        let description = withObservationTracking {
            self.body(self.state)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.generation == expectedGeneration
                else { return }

                self.render()
            }
        }

        let scheduler = FineNodeScheduler()
        let context = FineRenderContext(nodeScheduler: scheduler)
        let apply = { [self] in
            let rendered = FineRenderer.render(description, reusing: self.rootView, context: context)
            scheduler.drain()
            return rendered
        }

        let view: UIView
        if case .animate(let animation) = transaction, rootView != nil {
            var rendered: UIView!
            animation.animate {
                rendered = apply()
                container.layoutIfNeeded()
            }
            view = rendered
        } else {
            view = apply()
        }
        guard view !== rootView else { return }

        UIView.performWithoutAnimation {
            if case .animate = transaction {
                removeAllAnimations(in: view)
            }

            rootView?.removeFromSuperview()
            rootView = view

            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)

            let guide = container.safeAreaLayoutGuide

            // With no keyboard on screen, keyboardLayoutGuide's top edge matches
            // the bottom safe area (usesBottomSafeArea defaults to true), so both
            // anchors produce the same resting layout.
            let bottomAnchor = avoidsKeyboard
                ? container.keyboardLayoutGuide.topAnchor
                : guide.bottomAnchor

            // Text-like content (hugging priority 251+) keeps its natural height;
            // views with no intrinsic height (lists, images) expand to fill.
            let fillBottom = view.bottomAnchor.constraint(equalTo: bottomAnchor)
            fillBottom.priority = .defaultLow

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: guide.topAnchor),
                view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                view.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                fillBottom,
            ])
            container.layoutIfNeeded()
        }
    }

    private func removeAllAnimations(in view: UIView) {
        view.layer.removeAllAnimations()
        for subview in view.subviews {
            removeAllAnimations(in: subview)
        }
    }
}
