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
    private let alignment: UIStackView.Alignment
    private let distribution: UIStackView.Distribution
    private let content: () -> [any Renderable]

    private init(
        axis: NSLayoutConstraint.Axis,
        spacing: CGFloat,
        alignment: UIStackView.Alignment,
        distribution: UIStackView.Distribution,
        content: @escaping @MainActor () -> [any Renderable]
    ) {
        self.axis = axis
        self.spacing = spacing
        self.alignment = alignment
        self.distribution = distribution
        self.content = content
    }

    public static func vertical(
        spacing: CGFloat = 0,
        alignment: UIStackView.Alignment = .fill,
        distribution: UIStackView.Distribution = .fill,
        @FineBuilder content: @escaping @MainActor () -> [any Renderable]
    ) -> FineStack {
        .init(axis: .vertical, spacing: spacing, alignment: alignment, distribution: distribution, content: content)
    }

    public static func horizontal(
        spacing: CGFloat = 0,
        alignment: UIStackView.Alignment = .fill,
        distribution: UIStackView.Distribution = .fill,
        @FineBuilder content: @escaping @MainActor () -> [any Renderable]
    ) -> FineStack {
        .init(axis: .horizontal, spacing: spacing, alignment: alignment, distribution: distribution, content: content)
    }

    public func _makeView() -> UIView {
        UIStackView(frame: .zero)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UIStackView
    }

    public func _update(_ view: UIView) {
        guard let stackView = view as? UIStackView else { return }

        if stackView.axis != axis {
            stackView.axis = axis
        }
        if stackView.spacing != spacing {
            stackView.spacing = spacing
        }
        if stackView.alignment != alignment {
            stackView.alignment = alignment
        }
        if stackView.distribution != distribution {
            stackView.distribution = distribution
        }

        let oldViews = stackView.arrangedSubviews
        var keyedOldViews: [AnyHashable: UIView] = [:]
        var unkeyedOldViews: [UIView] = []

        for oldView in oldViews {
            if let key = oldView.fineKey {
                keyedOldViews[key] = oldView
            } else {
                unkeyedOldViews.append(oldView)
            }
        }

        var seenKeys = Set<AnyHashable>()
        var unkeyedIndex = 0
        let newViews = content().map { node in
            if let key = node._key {
                guard seenKeys.insert(key).inserted else {
                    assertionFailure("Duplicate FineUIKit key: \(key)")
                    return FineRenderer.render(node, reusing: nil)
                }

                return FineRenderer.render(node, reusing: keyedOldViews.removeValue(forKey: key))
            }

            let reusable = unkeyedIndex < unkeyedOldViews.count ? unkeyedOldViews[unkeyedIndex] : nil
            unkeyedIndex += 1
            return FineRenderer.render(node, reusing: reusable)
        }

        for oldView in oldViews where !newViews.contains(where: { $0 === oldView }) {
            stackView.removeArrangedSubview(oldView)
            oldView.removeFromSuperview()
        }

        for (index, newView) in newViews.enumerated() {
            if index >= stackView.arrangedSubviews.count || stackView.arrangedSubviews[index] !== newView {
                stackView.insertArrangedSubview(newView, at: index)
            }
        }
    }
}
