//
//  FineButton.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineButton: FinePrimitiveRenderable {
    private static let actionKey = "FineUIKit.FineButton.primaryAction"

    private let title: String?
    private let action: () -> Void
    private var image: UIImage?
    private var configuration: UIButton.Configuration?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

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

    func _makeView() -> UIView {
        UIButton(type: .system)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UIButton
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let button = view as? UIButton else { return }

        if var configuration {
            configuration.title = title
            configuration.image = image
            if button.configuration != configuration {
                button.configuration = configuration
            }
        } else {
            if button.configuration != nil {
                button.configuration = nil
            }
            if button.title(for: .normal) != title {
                button.setTitle(title, for: .normal)
            }
            if button.image(for: .normal) !== image {
                button.setImage(image, for: .normal)
            }
        }

        button.fineSetHandler(Self.actionKey, for: .primaryActionTriggered) { [action] _ in
            action()
        }
    }

    var _modifierSignature: String {
        configuration == nil ? "" : "button.cfg"
    }
}
