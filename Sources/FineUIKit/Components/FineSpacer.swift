//
//  FineSpacer.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
final class FineSpacerView: UIView {
}

@MainActor
public struct FineSpacer: FinePrimitiveRenderable {
    private let minLength: CGFloat?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(minLength: CGFloat? = nil) {
        self.minLength = minLength
    }

    func _makeView() -> UIView {
        let view = FineSpacerView(frame: .zero)
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentHuggingPriority(.init(1), for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FineSpacerView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        var constraints = view.fineInstalledConstraints

        if let minLength {
            update(&constraints, key: "spacer.minW", on: view.widthAnchor, minLength: minLength)
            update(&constraints, key: "spacer.minH", on: view.heightAnchor, minLength: minLength)
        } else {
            for key in ["spacer.minW", "spacer.minH"] {
                constraints[key]?.isActive = false
                constraints.removeValue(forKey: key)
            }
        }

        view.fineInstalledConstraints = constraints
    }

    private func update(
        _ constraints: inout [String: NSLayoutConstraint],
        key: String,
        on anchor: NSLayoutDimension,
        minLength: CGFloat
    ) {
        if let constraint = constraints[key] {
            constraint.constant = minLength
        } else {
            let constraint = anchor.constraint(greaterThanOrEqualToConstant: minLength)
            constraint.isActive = true
            constraints[key] = constraint
        }
    }
}
