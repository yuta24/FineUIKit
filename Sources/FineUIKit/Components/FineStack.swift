//
//  FineStack.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineStack: FinePrimitiveRenderable {
    private let axis: NSLayoutConstraint.Axis
    private let spacing: CGFloat
    private let alignment: UIStackView.Alignment
    private let distribution: UIStackView.Distribution
    private let content: () -> [any Renderable]

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

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

    func _makeView() -> UIView {
        UIStackView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UIStackView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
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
        // The primitive is resolved once and handed to `render`: resolving walks
        // `body`, and looking the key up here only to let the renderer resolve
        // the same node again would rebuild every child's subtree twice.
        let newViews = content().map { node in
            let primitive = FineRenderer.primitive(for: node)
            if let key = primitive._key {
                guard seenKeys.insert(key).inserted else {
                    // A structural key can repeat when two independently built
                    // child arrays are concatenated in one builder statement:
                    // each numbered its slots from its own start, and the
                    // builder cannot see that they were joined. Those children
                    // still render, they just cannot be matched by identity —
                    // not something the caller can act on, so it is not
                    // asserted. A key the caller wrote twice is a mistake.
                    if !(key.base is FineStructuralKey) {
                        assertionFailure("Duplicate FineUIKit key: \(key)")
                    }
                    return context.render(resolved: primitive, reusing: nil)
                }

                return context.render(resolved: primitive, reusing: keyedOldViews.removeValue(forKey: key))
            }

            let reusable = unkeyedIndex < unkeyedOldViews.count ? unkeyedOldViews[unkeyedIndex] : nil
            unkeyedIndex += 1
            return context.render(resolved: primitive, reusing: reusable)
        }

        // Membership through a set: scanning `newViews` for every old view
        // makes removal quadratic in the number of children.
        let survivors = Set(newViews.map(ObjectIdentifier.init))
        for oldView in oldViews where !survivors.contains(ObjectIdentifier(oldView)) {
            stackView.removeArrangedSubview(oldView)
            oldView.removeFromSuperview()
        }

        // `arrangedSubviews` builds a new array on every access, so it is read
        // once and re-read only after an insertion actually changes it. A
        // render that reorders nothing then costs one read instead of two per
        // child.
        var arranged = stackView.arrangedSubviews
        for (index, newView) in newViews.enumerated() {
            if index < arranged.count, arranged[index] === newView {
                continue
            }

            stackView.insertArrangedSubview(newView, at: index)
            arranged = stackView.arrangedSubviews
        }
    }
}
