//
//  FineViewController.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

/// A view controller that renders a `Renderable` tree from its `body(_:_:)`
/// method.
///
/// Subclass it, pass your `@Observable` state to `init(state:)`, and
/// override `body(_:_:)`. The view rebuilds in place whenever observed state
/// changes.
///
/// `body` is a *type* method, so the instance is not in scope and a
/// description cannot capture the controller. That is deliberate, and it is
/// what keeps the runtime leak-free without asking for capture lists: the tree
/// holds every closure a description carries for as long as the view lives, and
/// the view belongs to the controller, so a captured controller could never be
/// released. Behaviour belongs in `State`; the UIKit operations that genuinely
/// need the controller are reached through `FineHost`, which holds it weakly.
///
/// Because `body` is an overridable method dispatched through the class
/// vtable (not a closure captured at init), code injection can replace its
/// implementation, and the injection-triggered re-render in `FineUI` picks
/// it up — no per-controller hot-reload wiring required. A type method occupies
/// the same vtable as an instance method and is patched the same way, so
/// nothing about hot reload changes.
open class FineViewController<State>: UIViewController {
    public let state: State

    private var fineUI: FineUI<State>?
    private var navigationScope: FineObservedScope?

    /// Handed to `body(_:_:)` and `navigation(_:_:)`. Holds this controller
    /// weakly, so a description that captures it does not retain the controller.
    private lazy var host = FineHost(self)

    public init(state: State) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("FineViewController does not support initialization from a coder")
    }

    /// The UI description for the current state. Subclasses must override.
    ///
    /// Nothing here can reach the controller except through `host`, which is
    /// the point: a handler or builder that captured it would keep it alive for
    /// as long as the view tree it is stored in.
    open class func body(_ state: State, _ host: FineHost) -> any Renderable {
        fatalError("Subclasses of FineViewController must override body(_:_:)")
    }

    /// The pre-`FineHost` form of `body`, kept so subclasses that override it
    /// keep working. Overriding it opts out of the capture guarantee, because
    /// an instance method has the controller in scope.
    ///
    /// Not marked deprecated yet: the runtime still calls it, and the attribute
    /// would warn at that call site as well as at the ones it is meant for.
    /// It goes on once the migration is done.
    open func body(_ state: State) -> any Renderable {
        Self.body(state, host)
    }

    /// The navigation bar description for the current state.
    ///
    /// Return `nil` to leave `navigationItem` untouched so it can be managed
    /// manually. Returning a value gives FineUIKit ownership of the managed
    /// properties. This method is tracked and vtable-dispatched like `body(_:)`,
    /// so observed state changes and hot reload update navigation as well.
    ///
    /// Navigation is tracked in its own observation scope, separate from
    /// `body(_:_:)`: a value read only here — a title, a button's enabled state
    /// — updates `navigationItem` without re-evaluating or re-diffing the tree.
    ///
    /// A bar button's action is retained by `navigationItem`, which the
    /// controller owns, so this is a type method for the same reason `body` is.
    open class func navigation(_ state: State, _ host: FineHost) -> FineNavigation? {
        nil
    }

    /// The pre-`FineHost` form of `navigation`. See `body(_:)`.
    open func navigation(_ state: State) -> FineNavigation? {
        Self.navigation(state, host)
    }

    /// Whether the rendered tree's bottom edge follows the keyboard.
    ///
    /// Defaults to `true`: content compresses above the keyboard instead of
    /// being covered by it. Override to return `false` to keep the tree
    /// anchored to the bottom safe area. Read once in `viewDidLoad`.
    open var avoidsKeyboard: Bool {
        true
    }

    /// Whether rendering pauses while the view is off screen.
    ///
    /// Defaults to `true`: a controller covered by a pushed screen, or on an
    /// inactive tab, stops re-rendering on observed changes and catches up in a
    /// single render when it appears again. Override to return `false` for a
    /// controller that must stay current off screen — one whose view is
    /// snapshotted for a transition, for example. Read on every disappearance.
    ///
    /// Navigation is never paused, because the title of a covered controller
    /// still shows as the back-button label of the screen above it.
    ///
    /// Pausing is driven by `viewIsAppearing(_:)` and `viewDidDisappear(_:)`.
    /// An override of either **must call `super`**: without the resume, the
    /// controller renders once and then silently stops updating. UIKit also
    /// reports no disappearance for a controller covered by an
    /// `.overFullScreen` or `.overCurrentContext` presentation, or for one that
    /// was loaded but never shown — call `suspendRendering()` for those.
    open var suspendsWhenDisappeared: Bool {
        true
    }

    /// Pauses rendering until `resumeRendering()`.
    ///
    /// Appearance transitions drive this automatically. Call it for the cases
    /// they cannot see: a controller covered by an `.overFullScreen` or
    /// `.overCurrentContext` presentation, which UIKit does not report as a
    /// disappearance, or one that is loaded and driven without ever appearing.
    public func suspendRendering() {
        fineUI?.suspend()
    }

    /// Resumes rendering, applying in one render whatever changed while paused.
    public func resumeRendering() {
        fineUI?.resume()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let fineUI = FineUI(state, avoidsKeyboard: avoidsKeyboard) { [unowned self] state in
            self.body(state)
        }
        fineUI.build(to: view)
        self.fineUI = fineUI

        // Navigation gets its own observation scope: reads that only navigation
        // performs must not invalidate the tree.
        let navigationScope = FineObservedScope { [unowned self] in
            guard let navigation = self.navigation(self.state) else { return }
            navigation.apply(to: self.navigationItem)
        }
        navigationScope.run()
        self.navigationScope = navigationScope

        #if DEBUG
        // Injection replaces `navigation(_:)` too, and it no longer runs inside
        // the tree's render pass, so refresh it alongside the re-render.
        fineUI.onInjectionReload = { [weak navigationScope] in
            navigationScope?.run()
        }
        #endif
    }

    /// Resumes rendering. An override must call `super`, or the controller
    /// never resumes after its first disappearance.
    open override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        fineUI?.resume()
    }

    /// Pauses rendering when `suspendsWhenDisappeared` is `true`. An override
    /// must call `super`, or an off-screen controller keeps re-rendering.
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if suspendsWhenDisappeared {
            fineUI?.suspend()
        }
    }
}
