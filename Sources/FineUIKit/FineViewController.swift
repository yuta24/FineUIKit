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

    open override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let fineUI = FineUI(state) { [unowned self] state in
            self.body(state)
        }
        fineUI.build(to: view)
        self.fineUI = fineUI
    }
}
