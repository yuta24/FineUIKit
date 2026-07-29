//
//  FineActivityIndicator.swift
//  FineUIKit
//
//  Created by nova on 2026/07/28.
//

import UIKit

@MainActor
public struct FineActivityIndicator: FinePrimitiveRenderable {
    private let isAnimating: @MainActor () -> Bool
    private var style: UIActivityIndicatorView.Style?
    private var color: UIColor?
    private var hidesWhenStopped: Bool?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    /// Creates a spinner that animates while `isAnimating` is `true`.
    ///
    /// `isAnimating` is an autoclosure, so the state it reads is tracked by
    /// this component's own node: starting and stopping the spinner does not
    /// re-evaluate the surrounding `body`.
    public init(isAnimating: @autoclosure @escaping @MainActor () -> Bool = true) {
        self.isAnimating = isAnimating
    }

    public func style(_ style: UIActivityIndicatorView.Style) -> FineActivityIndicator {
        var copy = self
        copy.style = style
        return copy
    }

    public func color(_ color: UIColor) -> FineActivityIndicator {
        var copy = self
        copy.color = color
        return copy
    }

    /// Sets whether the view hides itself while stopped. Defaults to `true`,
    /// matching `UIActivityIndicatorView`.
    public func hidesWhenStopped(_ hides: Bool = true) -> FineActivityIndicator {
        var copy = self
        copy.hidesWhenStopped = hides
        return copy
    }

    func _makeView() -> UIView {
        UIActivityIndicatorView(style: .medium)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UIActivityIndicatorView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let indicator = view as? UIActivityIndicatorView else { return }

        let resolvedStyle = style ?? .medium
        let resolvedHidesWhenStopped = hidesWhenStopped ?? true

        if indicator.style != resolvedStyle {
            indicator.style = resolvedStyle
        }
        if let color, indicator.color != color {
            indicator.color = color
        }
        if indicator.hidesWhenStopped != resolvedHidesWhenStopped {
            indicator.hidesWhenStopped = resolvedHidesWhenStopped
        }

        if isAnimating() {
            if !indicator.isAnimating {
                indicator.startAnimating()
            }
        } else if indicator.isAnimating {
            indicator.stopAnimating()
        }
    }

    // `color` reads back as the resolved tint rather than as "unset", so a
    // dropped `.color(_:)` cannot be undone by writing the default back. The
    // modifier is part of the signature instead, which rebuilds the view.
    var _modifierSignature: String {
        color == nil ? "" : "activityIndicator.color"
    }
}
