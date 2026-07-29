//
//  FineProgressView.swift
//  FineUIKit
//
//  Created by nova on 2026/07/28.
//

import UIKit

@MainActor
public struct FineProgressView: FinePrimitiveRenderable {
    private let value: @MainActor () -> Float
    private let total: Float
    private var progressViewStyle: UIProgressView.Style?
    private var progressTintColor: UIColor?
    private var trackTintColor: UIColor?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    /// Creates a progress view showing `value` out of `total`.
    ///
    /// `value` is an autoclosure, so the state it reads is tracked by this
    /// component's own node: progress updates refresh the bar without
    /// re-evaluating the surrounding `body`.
    public init(value: @autoclosure @escaping @MainActor () -> Float, total: Float = 1) {
        self.value = value
        self.total = total
    }

    public func progressViewStyle(_ style: UIProgressView.Style) -> FineProgressView {
        var copy = self
        copy.progressViewStyle = style
        return copy
    }

    public func progressTintColor(_ color: UIColor) -> FineProgressView {
        var copy = self
        copy.progressTintColor = color
        return copy
    }

    public func trackTintColor(_ color: UIColor) -> FineProgressView {
        var copy = self
        copy.trackTintColor = color
        return copy
    }

    func _makeView() -> UIView {
        UIProgressView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UIProgressView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let progressView = view as? UIProgressView else { return }

        let resolvedStyle = progressViewStyle ?? .default
        // A zero or negative total has no meaningful fraction to show; an empty
        // bar beats dividing by zero. NaN is filtered out before clamping —
        // `min`/`max` propagate it, and `UIProgressView` renders a NaN progress
        // as a *full* bar, the opposite of what an undefined fraction means.
        let fraction = total > 0 ? value() / total : 0
        let resolvedProgress = fraction.isNaN ? 0 : min(max(fraction, 0), 1)

        if progressView.progressViewStyle != resolvedStyle {
            progressView.progressViewStyle = resolvedStyle
        }
        if progressView.progress != resolvedProgress {
            progressView.progress = resolvedProgress
        }
        if progressView.progressTintColor != progressTintColor {
            progressView.progressTintColor = progressTintColor
        }
        if progressView.trackTintColor != trackTintColor {
            progressView.trackTintColor = trackTintColor
        }
    }
}
