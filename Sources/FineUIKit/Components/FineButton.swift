//
//  FineButton.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineButton: Renderable {
    private static let actionIdentifier = UIAction.Identifier("FineUIKit.FineButton.primaryAction")

    private let title: String?
    private let action: () -> Void

    public init(title: String?, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public func _makeView() -> UIView {
        UIButton(type: .system)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UIButton
    }

    public func _update(_ view: UIView) {
        guard let button = view as? UIButton else { return }

        button.setTitle(title, for: .normal)

        // Replace the previous description's handler so actions don't stack up on reuse.
        button.removeAction(identifiedBy: Self.actionIdentifier, for: .primaryActionTriggered)
        button.addAction(.init(identifier: Self.actionIdentifier, handler: { [action] _ in
            action()
        }), for: .primaryActionTriggered)
    }
}
