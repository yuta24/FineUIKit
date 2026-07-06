//
//  FineTextField.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
public struct FineTextField: Renderable {
    private static let editingChangedActionIdentifier = UIAction.Identifier("FineUIKit.FineTextField.editingChanged")
    private static let editingDidEndOnExitActionIdentifier = UIAction.Identifier("FineUIKit.FineTextField.editingDidEndOnExit")

    private let text: FineBinding<String>
    private let placeholder: String?
    private var keyboardType: UIKeyboardType?
    private var returnKeyType: UIReturnKeyType?
    private var isSecureTextEntry: Bool?
    private var onSubmit: (@MainActor () -> Void)?

    public init(text: FineBinding<String>, placeholder: String? = nil) {
        self.text = text
        self.placeholder = placeholder
    }

    /// Sets the keyboard type for text entry.
    public func keyboardType(_ type: UIKeyboardType) -> FineTextField {
        var copy = self
        copy.keyboardType = type
        return copy
    }

    /// Sets the return key type shown by the keyboard.
    public func returnKeyType(_ type: UIReturnKeyType) -> FineTextField {
        var copy = self
        copy.returnKeyType = type
        return copy
    }

    /// Sets whether the text field hides entered text.
    public func secureTextEntry(_ isSecure: Bool = true) -> FineTextField {
        var copy = self
        copy.isSecureTextEntry = isSecure
        return copy
    }

    /// Runs `handler` when the Return key ends editing.
    ///
    /// UIKit automatically dismisses the keyboard on Return when the text field
    /// has an `.editingDidEndOnExit` action target.
    public func onSubmit(_ handler: @escaping @MainActor () -> Void) -> FineTextField {
        var copy = self
        copy.onSubmit = handler
        return copy
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
        textField.keyboardType = keyboardType ?? .default
        textField.returnKeyType = returnKeyType ?? .default
        textField.isSecureTextEntry = isSecureTextEntry ?? false

        // Only write when the value actually differs, so re-renders during
        // typing don't reset the cursor.
        if textField.text != text.value {
            textField.text = text.value
        }

        textField.removeAction(identifiedBy: Self.editingChangedActionIdentifier, for: .editingChanged)
        textField.addAction(.init(identifier: Self.editingChangedActionIdentifier, handler: { [text] action in
            guard let textField = action.sender as? UITextField else { return }
            text.value = textField.text ?? ""
        }), for: .editingChanged)

        textField.removeAction(identifiedBy: Self.editingDidEndOnExitActionIdentifier, for: .editingDidEndOnExit)
        if let onSubmit {
            textField.addAction(.init(identifier: Self.editingDidEndOnExitActionIdentifier, handler: { _ in
                onSubmit()
            }), for: .editingDidEndOnExit)
        }
    }
}
