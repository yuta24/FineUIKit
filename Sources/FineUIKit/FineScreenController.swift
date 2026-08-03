//
//  FineScreenController.swift
//  FineUIKit
//
//  Created by nova on 2026/08/03.
//

import UIKit

/// Hosts a `FineScreen`: renders its description into a view controller and
/// keeps the two observation scopes running.
///
/// ```swift
/// let screen = ToDoScreen()
/// screen.delegate = self
/// navigationController.pushViewController(FineScreenController(screen), animated: true)
/// ```
///
/// Subclassing is allowed and safe. The cycle this design avoids came from the
/// description living on the controller, not from the controller being
/// subclassable — a subclass here has no way to put itself into the view tree.
/// The one rule is the screen's: it must not hold this controller strongly.
///
/// `body()` is dispatched through the screen's class, so code injection can
/// replace it and the injection-triggered re-render picks it up. That is why
/// `FineScreen` is a protocol with a method rather than a closure handed to
/// this initialiser: a stored closure is fixed at the moment it is made, and no
/// injection can replace it.
open class FineScreenController: UIViewController {
    /// The screen this controller renders.
    public let screen: any FineScreen

    private let avoidsKeyboard: Bool
    private var fineUI: FineUI<any FineScreen>?
    private var navigationScope: FineObservedScope?

    /// - Parameter avoidsKeyboard: When `true` (the default), the tree's bottom
    ///   edge follows `keyboardLayoutGuide`, so content compresses above the
    ///   keyboard instead of being covered by it.
    public init(_ screen: any FineScreen, avoidsKeyboard: Bool = true) {
        self.screen = screen
        self.avoidsKeyboard = avoidsKeyboard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("FineScreenController does not support initialization from a coder")
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

        // The closure is stored, but what it does is call through the screen's
        // class, so an injected `body()` takes effect on the next render.
        let fineUI = FineUI(screen, avoidsKeyboard: avoidsKeyboard) { screen in
            screen.body()
        }
        fineUI.build(to: view)
        self.fineUI = fineUI

        // Navigation gets its own observation scope: reads that only navigation
        // performs must not invalidate the tree.
        let navigationScope = FineObservedScope { [unowned self] in
            guard let navigation = self.screen.navigation() else { return }
            navigation.apply(to: self.navigationItem)
        }
        navigationScope.run()
        self.navigationScope = navigationScope

        #if DEBUG
        // Injection replaces `navigation()` too, and it does not run inside the
        // tree's render pass, so refresh it alongside the re-render.
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
