//
//  FineTextView.swift
//  FineUIKit
//
//  Created by nova on 2026/07/28.
//

import UIKit

/// UITextView subclass that owns its delegate, draws a placeholder (UIKit has
/// none), and applies a deferred focus request when it joins a window — renders
/// can run before the tree is attached, where `becomeFirstResponder` is a no-op.
@MainActor
final class FineTextViewView: UITextView, UITextViewDelegate, FineIdentityScopedView {
    var onTextChange: (@MainActor (String) -> Void)?
    var onFocusChange: (@MainActor (Bool) -> Void)?
    var pendingFocus: (@MainActor (UITextView) -> Void)?

    let placeholderLabel = UILabel(frame: .zero)

    /// Width the placeholder was last laid out for, so `layoutSubviews` can
    /// tell a real width change from a repeated pass.
    private var lastPlaceholderWidth: CGFloat = -1

    var placeholder: String? {
        get { placeholderLabel.text }
        set {
            guard placeholderLabel.text != newValue else { return }
            placeholderLabel.text = newValue
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    var placeholderFont: UIFont {
        get { placeholderLabel.font }
        set {
            guard !placeholderLabel.font.isEqual(newValue) else { return }
            placeholderLabel.font = newValue
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }

    var placeholderAlignment: NSTextAlignment {
        get { placeholderLabel.textAlignment }
        set {
            guard placeholderLabel.textAlignment != newValue else { return }
            placeholderLabel.textAlignment = newValue
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)

        placeholderLabel.numberOfLines = 0
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the placeholder only while the text is empty. Called from the
    /// delegate for typing, and from the description for programmatic writes.
    func updatePlaceholderVisibility() {
        let shouldHide = !(text?.isEmpty ?? true)
        if placeholderLabel.isHidden != shouldHide {
            placeholderLabel.isHidden = shouldHide
            invalidateIntrinsicContentSize()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Laid out by frame rather than by constraints: the placeholder has to
        // sit exactly where the first glyph would, and that origin depends on
        // the text container's own insets, which UIKit may change on its own.
        let inset = textContainerInset
        let width = placeholderWidth
        let height = placeholderHeight(fitting: width)

        placeholderLabel.frame = CGRect(
            x: inset.left + textContainer.lineFragmentPadding,
            y: inset.top,
            width: width,
            height: height
        )

        // The intrinsic size below is a function of the available width, which
        // is only known once laid out. Invalidating on an actual width change
        // settles after one extra pass rather than looping.
        if width != lastPlaceholderWidth {
            lastPlaceholderWidth = width
            if !placeholderLabel.isHidden {
                invalidateIntrinsicContentSize()
            }
        }
    }

    /// Keeps an empty, non-scrolling text view tall enough for its placeholder:
    /// UIKit sizes it from the (empty) text alone, which clips a placeholder
    /// that wraps.
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize

        guard !placeholderLabel.isHidden, size.height != UIView.noIntrinsicMetric else {
            return size
        }

        let inset = textContainerInset
        let height = placeholderHeight(fitting: placeholderWidth) + inset.top + inset.bottom
        size.height = max(size.height, height)
        return size
    }

    private var placeholderWidth: CGFloat {
        let inset = textContainerInset
        let padding = textContainer.lineFragmentPadding
        return max(bounds.width - inset.left - inset.right - padding * 2, 0)
    }

    private func placeholderHeight(fitting width: CGFloat) -> CGFloat {
        placeholderLabel.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil, let pendingFocus else { return }
        self.pendingFocus = nil
        pendingFocus(self)
    }

    /// Gives up the keyboard, for the same reason `FineTextFieldView` does: it
    /// was being held for a row that is over, and a recycled cell keeps its
    /// views, so nothing else would take it back.
    func fineStopIdentityWork() {
        pendingFocus = nil

        if isFirstResponder {
            resignFirstResponder()
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        onTextChange?(textView.text ?? "")
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        onFocusChange?(true)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        onFocusChange?(false)
    }
}

/// Multi-line text entry.
///
/// Unlike `UITextView`, scrolling is off by default: the view then reports an
/// intrinsic content size and grows with its text inside a stack. Turn it back
/// on with `.scrollEnabled()` for a fixed-height editor.
@MainActor
public struct FineTextView: FinePrimitiveRenderable {
    private let text: FineBinding<String>
    private let placeholder: String?
    private var font: UIFont?
    private var textColor: UIColor?
    private var textAlignment: NSTextAlignment?
    private var isEditable: Bool?
    private var isScrollEnabled: Bool?
    private var keyboardType: UIKeyboardType?
    private var isFocused: FineBinding<Bool>?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(text: FineBinding<String>, placeholder: String? = nil) {
        self.text = text
        self.placeholder = placeholder
    }

    public func font(_ font: UIFont) -> FineTextView {
        var copy = self
        copy.font = font
        return copy
    }

    public func textColor(_ textColor: UIColor) -> FineTextView {
        var copy = self
        copy.textColor = textColor
        return copy
    }

    public func textAlignment(_ textAlignment: NSTextAlignment) -> FineTextView {
        var copy = self
        copy.textAlignment = textAlignment
        return copy
    }

    /// Sets whether the text can be edited. A non-editable text view still
    /// allows selection, which is what makes it useful for read-only text.
    public func editable(_ isEditable: Bool = true) -> FineTextView {
        var copy = self
        copy.isEditable = isEditable
        return copy
    }

    /// Sets whether the text view scrolls its own content. Defaults to `false`,
    /// where the view instead grows to fit its text.
    public func scrollEnabled(_ isScrollEnabled: Bool = true) -> FineTextView {
        var copy = self
        copy.isScrollEnabled = isScrollEnabled
        return copy
    }

    /// Sets the keyboard type for text entry.
    public func keyboardType(_ type: UIKeyboardType) -> FineTextView {
        var copy = self
        copy.keyboardType = type
        return copy
    }

    /// Binds the text view's first-responder status.
    ///
    /// Setting the bound value to `true` focuses the view (once it is attached
    /// to a window); setting it to `false` dismisses the keyboard. User-driven
    /// focus changes write back through the binding.
    public func focused(_ isFocused: FineBinding<Bool>) -> FineTextView {
        var copy = self
        copy.isFocused = isFocused
        return copy
    }

    func _makeView() -> UIView {
        let textView = FineTextViewView(frame: .zero, textContainer: nil)
        textView.backgroundColor = .clear
        return textView
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FineTextViewView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let textView = view as? FineTextViewView else { return }

        let resolvedFont = font ?? UIFont.preferredFont(forTextStyle: .body)
        let resolvedTextColor = textColor ?? UIColor.label
        let resolvedTextAlignment = textAlignment ?? NSTextAlignment.natural
        let resolvedEditable = isEditable ?? true
        let resolvedScrollEnabled = isScrollEnabled ?? false
        let resolvedKeyboardType = keyboardType ?? .default

        if textView.font?.isEqual(resolvedFont) != true {
            textView.font = resolvedFont
        }
        // Preferred fonts carry metrics, so UIKit rescales them in place when
        // the content size category changes (same rule as `FineLabel`).
        if !textView.adjustsFontForContentSizeCategory {
            textView.adjustsFontForContentSizeCategory = true
        }
        if textView.textColor?.isEqual(resolvedTextColor) != true {
            textView.textColor = resolvedTextColor
        }
        if textView.textAlignment != resolvedTextAlignment {
            textView.textAlignment = resolvedTextAlignment
        }
        if textView.isEditable != resolvedEditable {
            textView.isEditable = resolvedEditable
        }
        if textView.isScrollEnabled != resolvedScrollEnabled {
            textView.isScrollEnabled = resolvedScrollEnabled
        }
        if textView.keyboardType != resolvedKeyboardType {
            textView.keyboardType = resolvedKeyboardType
        }

        textView.placeholder = placeholder
        textView.placeholderFont = resolvedFont
        textView.placeholderAlignment = resolvedTextAlignment

        // Only write when the value actually differs, so re-renders during
        // typing don't reset the cursor.
        if textView.text != text.value {
            textView.text = text.value
        }
        textView.updatePlaceholderVisibility()

        textView.onTextChange = { [text] value in
            text.value = value
        }

        if let isFocused {
            textView.onFocusChange = { [isFocused] focused in
                if isFocused.value != focused {
                    isFocused.value = focused
                }
            }

            applyFocus(isFocused, to: textView)
        } else {
            textView.onFocusChange = nil
            textView.pendingFocus = nil
        }
    }

    private func applyFocus(_ isFocused: FineBinding<Bool>, to textView: FineTextViewView) {
        if isFocused.value {
            guard !textView.isFirstResponder else { return }

            if textView.window != nil {
                textView.becomeFirstResponder()
            } else {
                // Applied from didMoveToWindow whenever the view lands in a
                // window; every re-render replaces or clears this request, so
                // a reused view never applies a stale binding.
                textView.pendingFocus = { textView in
                    guard isFocused.value, !textView.isFirstResponder else { return }
                    textView.becomeFirstResponder()
                }
            }
        } else {
            textView.pendingFocus = nil
            if textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }
}
