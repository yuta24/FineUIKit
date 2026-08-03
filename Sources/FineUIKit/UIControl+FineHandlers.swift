//
//  UIControl+FineHandlers.swift
//  FineUIKit
//
//  Created by nova on 2026/07/07.
//

import UIKit

@MainActor
extension UIControl {
    /// Installs `handler` for `event` under `key`, replacing whatever was
    /// installed for the same key and event before. Passing `nil` removes it.
    ///
    /// Adding a `UIAction` whose identifier is already registered replaces that
    /// action, so a render can hand over a fresh closure without actions piling
    /// up, and without a box kept in an associated object to mutate in place.
    ///
    /// The event is folded into the identifier because UIKit scopes identifiers
    /// to the control, not to the control and event: registering one key for
    /// two events otherwise leaves the second registration running the first
    /// one's closure.
    ///
    /// Replacing a handler moves its action to the end of the control's list
    /// for that event, so handlers under different keys run in order of last
    /// assignment rather than of first registration. No component depends on
    /// that order.
    func fineSetHandler(_ key: String, for event: UIControl.Event, handler: (@MainActor (UIControl) -> Void)?) {
        let identifier = UIAction.Identifier("\(key)#\(event.rawValue)")

        guard let handler else {
            removeAction(identifiedBy: identifier, for: event)
            return
        }

        addAction(
            UIAction(identifier: identifier) { action in
                guard let control = action.sender as? UIControl else { return }
                handler(control)
            },
            for: event
        )
    }
}
