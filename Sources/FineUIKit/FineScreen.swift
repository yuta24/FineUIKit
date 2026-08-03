//
//  FineScreen.swift
//  FineUIKit
//
//  Created by nova on 2026/08/03.
//

import UIKit

/// The UIKit operations a description may perform on the controller hosting it.
///
/// `body(_:_:)` is a type method, so the controller is not in scope and a
/// description cannot capture it. This is what makes the runtime leak-free by
/// construction: the tree holds every closure a description carries for as long
/// as the view lives, and the view belongs to the controller, so a captured
/// controller could never be released.
///
/// `FineScreen` is the sanctioned way back to the controller, and it holds it
/// weakly. Capturing a `FineScreen` in a handler is safe — capturing the
/// controller is what is not, which is why this type exposes operations rather
/// than the controller itself. Handing out the controller as a value would put
/// it back in scope for a closure to retain, and the guarantee would be gone:
///
/// ```swift
/// // What this type deliberately makes impossible.
/// let controller = screen.controller
/// return FineButton(title: "Close") { controller?.dismiss() }
/// ```
///
/// An operation performed after the controller has gone away does nothing.
@MainActor
public struct FineScreen {
    private weak var controller: UIViewController?

    init(_ controller: UIViewController?) {
        self.controller = controller
    }

    /// Pushes onto the enclosing navigation stack, if there is one.
    public func push(_ viewController: UIViewController, animated: Bool = true) {
        controller?.navigationController?.pushViewController(viewController, animated: animated)
    }

    /// Pops this screen off the enclosing navigation stack, if there is one.
    public func pop(animated: Bool = true) {
        controller?.navigationController?.popViewController(animated: animated)
    }

    /// Presents modally from this screen.
    public func present(_ viewController: UIViewController, animated: Bool = true) {
        controller?.present(viewController, animated: animated)
    }

    /// Dismisses whatever this screen presented, or this screen itself when it
    /// presented nothing — the same resolution `UIViewController.dismiss` uses.
    public func dismiss(animated: Bool = true) {
        controller?.dismiss(animated: animated)
    }

    /// Resigns first responder anywhere in this screen's view.
    public func endEditing() {
        controller?.view.endEditing(true)
    }

    /// Runs `body` with the controller, for UIKit surface this type does not
    /// cover.
    ///
    /// `body` is non-escaping, so the controller cannot be stored in a
    /// description by accident. Letting it escape by hand — assigning it to a
    /// captured variable — reopens the cycle this type exists to prevent.
    public func withController(_ body: (UIViewController) -> Void) {
        guard let controller else { return }

        body(controller)
    }
}
