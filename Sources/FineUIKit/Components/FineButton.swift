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
    private var image: UIImage?
    private var configuration: UIButton.Configuration?

    public init(title: String?, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    /// Sets the image shown by the button.
    public func image(_ image: UIImage?) -> FineButton {
        var copy = self
        copy.image = image
        return copy
    }

    /// Sets the button configuration.
    ///
    /// `FineButton`'s `title` and `image(_:)` value are the source of truth:
    /// they overwrite any title or image already stored in `configuration`.
    public func configuration(_ configuration: UIButton.Configuration) -> FineButton {
        var copy = self
        copy.configuration = configuration
        return copy
    }

    public func _makeView() -> UIView {
        UIButton(type: .system)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UIButton
    }

    public func _update(_ view: UIView) {
        guard let button = view as? UIButton else { return }

        if var configuration {
            configuration.title = title
            configuration.image = image
            button.configuration = configuration
        } else {
            button.configuration = nil
            button.setTitle(title, for: .normal)
            button.setImage(image, for: .normal)
        }

        // Replace the previous description's handler so actions don't stack up on reuse.
        button.removeAction(identifiedBy: Self.actionIdentifier, for: .primaryActionTriggered)
        button.addAction(.init(identifier: Self.actionIdentifier, handler: { [action] _ in
            action()
        }), for: .primaryActionTriggered)
    }

    public var _modifierSignature: String {
        configuration == nil ? "" : "button.cfg"
    }
}
