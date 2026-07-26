//
//  FineUI.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import Observation
import UIKit

/// Traits a description can branch on, and whose change therefore has to
/// re-evaluate it.
///
/// `UIFont.preferredFont(forTextStyle:)` resolves against the content size
/// category at the moment the description is built, so without re-rendering, a
/// Dynamic Type change would leave the tree describing the old sizes. Reading
/// any other trait through `environment.traitCollection` works, but only these
/// re-render on their own.
enum FineObservedTraits {
    static let all: [any UITraitDefinition.Type] = [
        UITraitPreferredContentSizeCategory.self,
        UITraitUserInterfaceStyle.self,
        UITraitHorizontalSizeClass.self,
        UITraitVerticalSizeClass.self,
        UITraitLayoutDirection.self,
        UITraitAccessibilityContrast.self,
        UITraitLegibilityWeight.self,
    ]
}

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
    /// Constraints pinning `rootView` to `container`. Held so that moving the
    /// tree to another container can take them down: they reference the former
    /// container's layout guides, which the new hierarchy cannot satisfy.
    private var rootConstraints: [NSLayoutConstraint] = []
    private var generation = 0
    private let renderGate = FineRenderGate()
    private var traitRegistration: (any UITraitChangeRegistration)?
    private weak var traitRegistrationTarget: UIView?

    #if DEBUG
    /// Runs after an injection-triggered re-render so owners can refresh
    /// tracked work that lives outside the view tree (navigation items).
    var onInjectionReload: (@MainActor () -> Void)?
    #endif

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
    ///
    /// Calling this again with a different container moves the tree: the root
    /// view is re-parented and re-constrained, and trait observation follows
    /// the new container. Calling it again with the same container re-renders
    /// without disturbing the hierarchy.
    public func build(to container: UIView) {
        self.container = container
        renderGate.onFlush = { [weak self] in
            self?.render()
        }
        observeTraitChanges(of: container)
        render()

        #if DEBUG
        observeInjection()
        #endif
    }

    /// Re-renders when a trait the tree can branch on changes.
    ///
    /// Trait changes reach cells through the environment: the trait collection
    /// is an environment value, so a list republishes it to its visible rows.
    private func observeTraitChanges(of container: UIView) {
        // A registration outlives the token that represents it, so building
        // into a second container would otherwise leave the first one
        // re-rendering this tree on its own trait changes.
        if let traitRegistration, let traitRegistrationTarget {
            traitRegistrationTarget.unregisterForTraitChanges(traitRegistration)
        }

        traitRegistrationTarget = container
        traitRegistration = container.registerForTraitChanges(FineObservedTraits.all) { [weak self] (_: UIView, _) in
            guard let self,
                  self.renderGate.allowsObservedWork()
            else { return }

            self.render()
        }
    }

    /// Stops re-rendering in response to observed state changes.
    ///
    /// Use this while the tree is off screen: a covered or detached hierarchy
    /// still receives observation callbacks, and acting on them re-diffs views
    /// nobody can see. Changes that arrive while suspended are recorded, and
    /// `resume()` applies them in a single render.
    ///
    /// Suspension only affects observation-driven renders. `build(to:)` always
    /// renders, and a catch-up render is never animated, because animating
    /// changes that happened off screen is not meaningful.
    public func suspend() {
        renderGate.suspend()
    }

    /// Resumes re-rendering, applying any change recorded while suspended.
    public func resume() {
        renderGate.resume()
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
                self?.onInjectionReload?()
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
                      self.generation == expectedGeneration,
                      self.renderGate.allowsObservedWork()
                else { return }

                self.render()
            }
        }

        let scheduler = FineNodeScheduler()
        var environment = FineEnvironmentValues()
        environment.traitCollection = container.traitCollection
        let context = FineRenderContext(
            nodeScheduler: scheduler,
            renderGate: renderGate,
            environment: environment
        )
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
        // Already installed here: the render was enough. A reused root view
        // still has to be attached when `build(to:)` named a different
        // container, which is why the superview is checked too.
        guard view !== rootView || view.superview !== container else { return }

        UIView.performWithoutAnimation {
            if case .animate = transaction {
                removeAllAnimations(in: view)
            }

            // These reference the previous container's layout guides, so they
            // go before the view moves.
            NSLayoutConstraint.deactivate(rootConstraints)
            rootConstraints = []

            if rootView !== view {
                rootView?.removeFromSuperview()
            }
            rootView = view

            view.translatesAutoresizingMaskIntoConstraints = false
            // Re-parents the view when it still belongs to another container.
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

            rootConstraints = [
                view.topAnchor.constraint(equalTo: guide.topAnchor),
                view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                view.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                fillBottom,
            ]
            NSLayoutConstraint.activate(rootConstraints)
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
