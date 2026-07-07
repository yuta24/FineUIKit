//
//  FineTextField.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
public struct FineTextField: FinePrimitiveRenderable {
    private static let editingChangedActionKey = "FineUIKit.FineTextField.editingChanged"
    private static let editingDidEndOnExitActionKey = "FineUIKit.FineTextField.editingDidEndOnExit"

    private let text: FineBinding<String>
    private let placeholder: String?
    private var keyboardType: UIKeyboardType?
    private var returnKeyType: UIReturnKeyType?
    private var isSecureTextEntry: Bool?
    private var onSubmit: (@MainActor () -> Void)?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

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

    func _makeView() -> UIView {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .roundedRect
        return textField
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UITextField
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let textField = view as? UITextField else { return }

        let resolvedKeyboardType = keyboardType ?? .default
        let resolvedReturnKeyType = returnKeyType ?? .default
        let resolvedSecureTextEntry = isSecureTextEntry ?? false

        if textField.placeholder != placeholder {
            textField.placeholder = placeholder
        }
        if textField.keyboardType != resolvedKeyboardType {
            textField.keyboardType = resolvedKeyboardType
        }
        if textField.returnKeyType != resolvedReturnKeyType {
            textField.returnKeyType = resolvedReturnKeyType
        }
        if textField.isSecureTextEntry != resolvedSecureTextEntry {
            textField.isSecureTextEntry = resolvedSecureTextEntry
        }

        // Only write when the value actually differs, so re-renders during
        // typing don't reset the cursor.
        if textField.text != text.value {
            textField.text = text.value
        }

        textField.fineSetHandler(Self.editingChangedActionKey, for: .editingChanged) { [text] control in
            guard let textField = control as? UITextField else { return }
            text.value = textField.text ?? ""
        }

        if let onSubmit {
            textField.fineSetHandler(Self.editingDidEndOnExitActionKey, for: .editingDidEndOnExit) { [onSubmit] _ in
                onSubmit()
            }
        } else {
            textField.fineSetHandler(Self.editingDidEndOnExitActionKey, for: .editingDidEndOnExit, handler: nil)
        }
    }
}
