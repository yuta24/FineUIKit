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
    /// installed under the same key before. Passing `nil` removes it.
    ///
    /// Adding a `UIAction` whose identifier is already registered for an event
    /// replaces that action, so a render can hand over a fresh closure without
    /// actions piling up, and without a box kept in an associated object to
    /// mutate in place.
    func fineSetHandler(_ key: String, for event: UIControl.Event, handler: ((UIControl) -> Void)?) {
        let identifier = UIAction.Identifier(key)

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
