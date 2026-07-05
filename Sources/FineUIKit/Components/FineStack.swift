//
//  FineStack.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineStack: Renderable {
    private let axis: NSLayoutConstraint.Axis
    private let spacing: CGFloat
    private let content: () -> [any Renderable]

    private init(axis: NSLayoutConstraint.Axis, spacing: CGFloat, content: @escaping @MainActor () -> [any Renderable]) {
        self.axis = axis
        self.spacing = spacing
        self.content = content
    }

    public static func vertical(spacing: CGFloat = 0, content: @escaping @MainActor () -> [any Renderable]) -> FineStack {
        .init(axis: .vertical, spacing: spacing, content: content)
    }

    public static func horizontal(spacing: CGFloat = 0, content: @escaping @MainActor () -> [any Renderable]) -> FineStack {
        .init(axis: .horizontal, spacing: spacing, content: content)
    }

    public func _makeView() -> UIView {
        UIStackView(frame: .zero)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UIStackView
    }

    public func _update(_ view: UIView) {
        guard let stackView = view as? UIStackView else { return }

        stackView.axis = axis
        stackView.spacing = spacing

        // Reconcile children positionally: reuse the arranged subview at the
        // same index when compatible, otherwise a new view takes its place.
        let oldViews = stackView.arrangedSubviews
        let newViews = content().enumerated().map { index, node in
            FineRenderer.render(node, reusing: index < oldViews.count ? oldViews[index] : nil)
        }

        for oldView in oldViews where !newViews.contains(where: { $0 === oldView }) {
            stackView.removeArrangedSubview(oldView)
            oldView.removeFromSuperview()
        }

        for (index, newView) in newViews.enumerated() {
            stackView.insertArrangedSubview(newView, at: index)
        }
    }
}
