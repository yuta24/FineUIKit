//
//  FineViewController.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

/// A view controller that renders a `Renderable` tree from its `body(_:)`
/// method.
///
/// Subclass it, pass your `@Observable` state to `init(state:)`, and
/// override `body(_:)`. The view rebuilds in place whenever observed state
/// changes.
///
/// Because `body` is an overridable method dispatched through the class
/// vtable (not a closure captured at init), code injection can replace its
/// implementation, and the injection-triggered re-render in `FineUI` picks
/// it up — no per-controller hot-reload wiring required.
open class FineViewController<State>: UIViewController {
    public let state: State

    private var fineUI: FineUI<State>?
    private var navigationScope: FineObservedScope?

    public init(state: State) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("FineViewController does not support initialization from a coder")
    }

    /// The UI description for the current state. Subclasses must override.
    open func body(_ state: State) -> any Renderable {
        fatalError("Subclasses of FineViewController must override body(_:)")
    }

    /// The navigation bar description for the current state.
    ///
    /// Return `nil` to leave `navigationItem` untouched so it can be managed
    /// manually. Returning a value gives FineUIKit ownership of the managed
    /// properties. This method is tracked and vtable-dispatched like `body(_:)`,
    /// so observed state changes and hot reload update navigation as well.
    ///
    /// Navigation is tracked in its own observation scope, separate from
    /// `body(_:)`: a value read only here — a title, a button's enabled state —
    /// updates `navigationItem` without re-evaluating or re-diffing the tree.
    open func navigation(_ state: State) -> FineNavigation? {
        nil
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
    open var suspendsWhenDisappeared: Bool {
        true
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

    open override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)

        fineUI?.resume()
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if suspendsWhenDisappeared {
            fineUI?.suspend()
        }
    }
}
