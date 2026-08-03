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

/// Mounts a `FineContent` into a view and keeps it up to date.
///
/// `FineUI` re-evaluates the smallest tracked description it can: `body()` for
/// structural reads, and primitive nodes for values read while updating those
/// nodes.
///
/// This is the runtime, and it mounts content anywhere — an arbitrary
/// container view, a cell, a section of an existing screen. `FineScreenController`
/// is the convenience on top for when the content is a whole screen.
///
/// Keep a strong reference to this object (e.g. in your view controller);
/// releasing it stops the render loop.
@MainActor
public final class FineUI {
    private let content: any FineContent
    private let avoidsKeyboard: Bool

    private weak var container: UIView?
    private var rootView: UIView?
    /// Constraints pinning `rootView` to `container`. Held so that moving the
    /// tree to another container can take them down: they reference the former
    /// container's layout guides, which the new hierarchy cannot satisfy.
    private var rootConstraints: [NSLayoutConstraint] = []
    /// The container `rootConstraints` were installed against. The root's
    /// superview alone cannot say whether they still hold: re-parenting the
    /// root by any other means makes UIKit drop every constraint that crossed
    /// the old hierarchy, leaving a root that is attached but unconstrained.
    private weak var rootConstraintTarget: UIView?
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
    public init(_ content: any FineContent, avoidsKeyboard: Bool = true) {
        self.content = content
        self.avoidsKeyboard = avoidsKeyboard
    }

    /// Renders a closure instead of a `FineContent`, for a tree that does not
    /// need an object of its own.
    ///
    /// Deliberately not public. The description lives in a stored closure, and
    /// a stored closure is fixed at the moment it is made, so **code injection
    /// cannot replace it** — a tree written this way silently gives up hot
    /// reload, which is half of what this library is for. Tests reach it
    /// through `@testable`, because a test has no use for injection and every
    /// use for saying a tree in one expression.
    ///
    /// The `state:` label keeps it from being mistaken for the content
    /// initialiser: without one, the two would differ only by a trailing
    /// closure.
    convenience init<State>(
        state: State,
        avoidsKeyboard: Bool = true,
        body: @escaping @MainActor (State) -> any Renderable
    ) {
        self.init(FineClosureContent(state, body), avoidsKeyboard: avoidsKeyboard)
    }

    deinit {
        #if DEBUG
        if let injectionObserver {
            NotificationCenter.default.removeObserver(injectionObserver)
        }
        #endif
    }

    /// Renders the tree into `container` and starts observing the content.
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
    /// The content's `body()` is a method, so an injected replacement takes
    /// effect on the next render. The closure initialiser is the exception:
    /// what it stores is fixed when it is made, so a tree written that way
    /// has to be rebuilt to pick up a change.
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

                if FineDiagnostics.showsInjectionToast {
                    FineDebugToast.show("FineUIKit reloaded", in: self?.container?.window)
                }
            }
        }
    }
    #endif

    private func render() {
        generation += 1
        let expectedGeneration = generation
        guard let container else { return }

        let signposter = FineSignpost.signposter
        let interval = signposter.beginInterval(
            "render",
            id: signposter.makeSignpostID(),
            "\(String(describing: type(of: self.content)), privacy: .public)"
        )
        defer { signposter.endInterval("render", interval) }

        let transaction = FineTransactionContext.current
        let description = withObservationTracking {
            self.content.body()
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
        // Attach unless the tree is already installed in this container under
        // constraints of ours that still hold. Checking the superview alone is
        // not enough: anything that re-parents the root — including code
        // outside the runtime — makes UIKit drop those constraints, and the
        // root would stay attached but unconstrained.
        let isInstalled = view === rootView
            && view.superview === container
            && rootConstraintTarget === container
            && rootConstraints.allSatisfy(\.isActive)
        guard !isInstalled else { return }

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
            rootConstraintTarget = container
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

/// Backs `FineUI`'s closure initialiser, so the runtime has a single shape to
/// mount. Its `body()` returns whatever the stored closure returns, which is
/// why that form cannot be hot-reloaded.
@MainActor
private final class FineClosureContent<State>: FineContent {
    private let state: State
    private let make: @MainActor (State) -> any Renderable

    init(_ state: State, _ make: @escaping @MainActor (State) -> any Renderable) {
        self.state = state
        self.make = make
    }

    func body() -> any Renderable {
        make(state)
    }
}
