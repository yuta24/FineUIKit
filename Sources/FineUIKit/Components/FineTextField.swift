//
//  FineTextField.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

/// UITextField subclass that applies a deferred focus request when it joins
/// a window; renders can run before the tree is attached, where
/// `becomeFirstResponder` is a no-op.
@MainActor
final class FineTextFieldView: UITextField {
    var pendingFocus: (@MainActor (UITextField) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil, let pendingFocus else { return }
        self.pendingFocus = nil
        pendingFocus(self)
    }
}

@MainActor
public struct FineTextField: FinePrimitiveRenderable {
    private static let editingChangedActionKey = "FineUIKit.FineTextField.editingChanged"
    private static let editingDidEndOnExitActionKey = "FineUIKit.FineTextField.editingDidEndOnExit"
    private static let editingDidBeginActionKey = "FineUIKit.FineTextField.editingDidBegin"
    private static let editingDidEndActionKey = "FineUIKit.FineTextField.editingDidEnd"

    private let text: FineBinding<String>
    private let placeholder: String?
    private var keyboardType: UIKeyboardType?
    private var returnKeyType: UIReturnKeyType?
    private var isSecureTextEntry: Bool?
    private var isEnabled: Bool?
    private var isFocused: FineBinding<Bool>?
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

    /// Sets whether the text field accepts input.
    public func enabled(_ isEnabled: Bool = true) -> FineTextField {
        var copy = self
        copy.isEnabled = isEnabled
        return copy
    }

    /// Binds the text field's first-responder status.
    ///
    /// Setting the bound value to `true` focuses the field (once its view is
    /// attached to a window); setting it to `false` dismisses the keyboard.
    /// User-driven focus changes write back through the binding.
    public func focused(_ isFocused: FineBinding<Bool>) -> FineTextField {
        var copy = self
        copy.isFocused = isFocused
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
        let textField = FineTextFieldView(frame: .zero)
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
        let resolvedEnabled = isEnabled ?? true

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
        if textField.isEnabled != resolvedEnabled {
            textField.isEnabled = resolvedEnabled
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

        if let isFocused {
            textField.fineSetHandler(Self.editingDidBeginActionKey, for: .editingDidBegin) { [isFocused] _ in
                if !isFocused.value {
                    isFocused.value = true
                }
            }
            textField.fineSetHandler(Self.editingDidEndActionKey, for: .editingDidEnd) { [isFocused] _ in
                if isFocused.value {
                    isFocused.value = false
                }
            }

            applyFocus(isFocused, to: textField)
        } else {
            textField.fineSetHandler(Self.editingDidBeginActionKey, for: .editingDidBegin, handler: nil)
            textField.fineSetHandler(Self.editingDidEndActionKey, for: .editingDidEnd, handler: nil)
            (textField as? FineTextFieldView)?.pendingFocus = nil
        }
    }

    private func applyFocus(_ isFocused: FineBinding<Bool>, to textField: UITextField) {
        if isFocused.value {
            guard !textField.isFirstResponder else { return }

            if textField.window != nil {
                textField.becomeFirstResponder()
            } else if let field = textField as? FineTextFieldView {
                // Applied from didMoveToWindow whenever the view lands in a
                // window; every re-render replaces or clears this request, so
                // a reused field never applies a stale binding.
                field.pendingFocus = { field in
                    guard isFocused.value, !field.isFirstResponder else { return }
                    field.becomeFirstResponder()
                }
            }
        } else {
            (textField as? FineTextFieldView)?.pendingFocus = nil
            if textField.isFirstResponder {
                textField.resignFirstResponder()
            }
        }
    }
}
