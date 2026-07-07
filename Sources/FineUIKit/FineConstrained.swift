//
//  FineConstrained.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
struct FineConstraintSpec {
    let key: String
    let constant: CGFloat
    let priority: UILayoutPriority
    let make: @MainActor (UIView) -> NSLayoutConstraint
}

@MainActor
struct FineConstrained: FinePrimitiveRenderable {
    let content: any Renderable
    let specs: [FineConstraintSpec]

    func _makeView() -> UIView {
        FineRenderer.primitive(for: content)._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        FineRenderer.primitive(for: content)._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        FineRenderer.primitive(for: content)._update(view, context: context)

        let activeKeys = Set(specs.map(\.key))
        var installed = view.fineInstalledConstraints

        for (key, constraint) in installed where key.hasPrefix("constraint.") && !activeKeys.contains(key) {
            constraint.isActive = false
            installed.removeValue(forKey: key)
        }

        for spec in specs {
            if let constraint = installed[spec.key] {
                constraint.constant = spec.constant
            } else {
                let constraint = spec.make(view)
                constraint.priority = spec.priority
                constraint.isActive = true
                installed[spec.key] = constraint
            }
        }

        view.fineInstalledConstraints = installed
    }

    var _modifierSignature: String {
        FineRenderer.primitive(for: content)._modifierSignature + "|" + specs.map(\.key).joined(separator: "|")
    }

    var _key: AnyHashable? {
        FineRenderer.primitive(for: content)._key
    }
}

@MainActor
struct FineCustomConstrained: FinePrimitiveRenderable {
    let content: any Renderable
    let id: String
    let make: @MainActor (UIView) -> [NSLayoutConstraint]

    func _makeView() -> UIView {
        FineRenderer.primitive(for: content)._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        FineRenderer.primitive(for: content)._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        FineRenderer.primitive(for: content)._update(view, context: context)

        let key = "custom:\(id)"
        var constraints = view.fineCustomConstraints
        NSLayoutConstraint.deactivate(constraints[key] ?? [])

        let newConstraints = make(view)
        NSLayoutConstraint.activate(newConstraints)
        constraints[key] = newConstraints
        view.fineCustomConstraints = constraints
    }

    var _modifierSignature: String {
        FineRenderer.primitive(for: content)._modifierSignature + "|custom:\(id)"
    }

    var _key: AnyHashable? {
        FineRenderer.primitive(for: content)._key
    }
}

extension Renderable {
    func _constrained(_ spec: FineConstraintSpec) -> any Renderable {
        if let constrained = self as? FineConstrained {
            return FineConstrained(content: constrained.content, specs: constrained.specs + [spec])
        }

        return FineConstrained(content: self, specs: [spec])
    }
}
