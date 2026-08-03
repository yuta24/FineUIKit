//
//  FineContentController.swift
//  FineUIKit
//
//  Created by nova on 2026/08/03.
//

import UIKit

/// Hosts a `FineContent` as a screen: renders its description into a view
/// controller, drives suspend/resume from the appearance transitions, and — when
/// the content is also `FineNavigating` — keeps `navigationItem` up to date in
/// an observation scope of its own.
///
/// ```swift
/// let list = ToDoList()
/// list.delegate = self
/// navigationController.pushViewController(FineContentController(list), animated: true)
/// ```
///
/// To put content inside a controller you already own, add one of these as a
/// child — the whole containment sequence, since `addChild(_:)` establishes the
/// relationship but does not add the view:
///
/// ```swift
/// let child = FineContentController(content)
/// addChild(child)
/// containerView.addSubview(child.view)
/// // …constraints…
/// child.didMove(toParent: self)
/// ```
///
/// Done that way the appearance transitions are forwarded, so the render loop
/// still pauses off screen. `navigation()` has no bar to write to in that
/// position, which is why it lives on `FineNavigating` rather than on all
/// content.
///
/// Subclassing is allowed and safe. The cycle this design avoids came from the
/// description living on the controller, not from the controller being
/// subclassable — a subclass here has no way to put itself into the view tree.
/// The one rule is the content's: it must not hold this controller strongly.
///
/// `body()` is dispatched through the content's class, so code injection can
/// replace it and the injection-triggered re-render picks it up. That is why
/// `FineContent` is a protocol with a method rather than a closure handed to
/// this initialiser: a stored closure is fixed at the moment it is made, and no
/// injection can replace it.
open class FineContentController: UIViewController {
    /// The content this controller renders.
    public let content: any FineContent

    private let avoidsKeyboard: Bool
    private var fineUI: FineUI?
    private var navigationScope: FineObservedScope?
    /// Whether `suspendRendering()` was called. Recorded rather than only
    /// forwarded, because the runtime does not exist until `viewDidLoad`: a
    /// controller suspended before its view loads — which is exactly the
    /// "loaded and driven without ever appearing" case — would otherwise start
    /// rendering the moment it does load.
    private var isSuspended = false

    /// - Parameter avoidsKeyboard: When `true` (the default), the tree's bottom
    ///   edge follows `keyboardLayoutGuide`, so content compresses above the
    ///   keyboard instead of being covered by it.
    public init(_ content: any FineContent, avoidsKeyboard: Bool = true) {
        self.content = content
        self.avoidsKeyboard = avoidsKeyboard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("FineContentController does not support initialization from a coder")
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
        isSuspended = true
        fineUI?.suspend()
    }

    /// Resumes rendering, applying in one render whatever changed while paused.
    public func resumeRendering() {
        isSuspended = false
        fineUI?.resume()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        let fineUI = FineUI(content, avoidsKeyboard: avoidsKeyboard)
        fineUI.build(to: view)
        self.fineUI = fineUI

        // A suspension asked for before the view loaded had nothing to act on
        // at the time, so it is applied now. The initial render still happens:
        // suspension only ever governs observation-driven ones.
        if isSuspended {
            fineUI.suspend()
        }

        // Navigation gets its own observation scope: reads that only navigation
        // performs must not invalidate the tree. Content that does not describe
        // a bar gets no scope at all.
        if let navigating = content as? any FineNavigating {
            // Weak rather than unowned: the scope re-arms itself from an
            // observation callback, so what it holds has to tolerate being
            // asked after this controller has gone. Nothing keeps the scope
            // alive past the controller today, but `unowned` would turn any
            // future arrangement that does into a trap.
            let navigationScope = FineObservedScope { [weak self] in
                guard let self, let navigation = navigating.navigation() else { return }
                navigation.apply(to: self.navigationItem)
            }
            navigationScope.run()
            self.navigationScope = navigationScope

            #if DEBUG
            // Injection replaces `navigation()` too, and it does not run inside
            // the tree's render pass, so refresh it alongside the re-render.
            fineUI.onInjectionReload = { [weak navigationScope] in
                navigationScope?.run()
            }
            #endif
        }
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
