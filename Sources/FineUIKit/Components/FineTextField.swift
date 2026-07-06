//
//  FineTextField.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
public struct FineTextField: Renderable {
    private static let actionIdentifier = UIAction.Identifier("FineUIKit.FineTextField.editingChanged")

    private let text: FineBinding<String>
    private let placeholder: String?

    public init(text: FineBinding<String>, placeholder: String? = nil) {
        self.text = text
        self.placeholder = placeholder
    }

    public func _makeView() -> UIView {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .roundedRect
        return textField
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UITextField
    }

    public func _update(_ view: UIView) {
        guard let textField = view as? UITextField else { return }

        textField.placeholder = placeholder

        // Only write when the value actually differs, so re-renders during
        // typing don't reset the cursor.
        if textField.text != text.value {
            textField.text = text.value
        }

        textField.removeAction(identifiedBy: Self.actionIdentifier, for: .editingChanged)
        textField.addAction(.init(identifier: Self.actionIdentifier, handler: { [text] action in
            guard let textField = action.sender as? UITextField else { return }
            text.value = textField.text ?? ""
        }), for: .editingChanged)
    }
}
