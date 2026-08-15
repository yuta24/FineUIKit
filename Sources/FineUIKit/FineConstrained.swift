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
    let content: FineResolvedRenderable
    let specs: [FineConstraintSpec]

    init(content: any Renderable, specs: [FineConstraintSpec]) {
        self.content = FineResolvedRenderable(content)
        self.specs = specs
    }

    /// Re-wraps content whose resolution another wrapper already paid for, so
    /// a chain of constraint modifiers walks `body` once between them.
    init(content: FineResolvedRenderable, specs: [FineConstraintSpec]) {
        self.content = content
        self.specs = specs
    }

    func _makeView() -> UIView {
        content.primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content.primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        content.primitive._update(view, context: context)

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
        content.primitive._modifierSignature + "|" + specs.map(\.key).joined(separator: "|")
    }

    var _key: AnyHashable? {
        content.primitive._key
    }

    var _viewProvider: any FinePrimitiveRenderable {
        content.primitive._viewProvider
    }
}

@MainActor
struct FineCustomConstrained: FinePrimitiveRenderable {
    let content: FineResolvedRenderable
    let id: String
    let make: @MainActor (UIView) -> [NSLayoutConstraint]

    init(content: any Renderable, id: String, make: @escaping @MainActor (UIView) -> [NSLayoutConstraint]) {
        self.content = FineResolvedRenderable(content)
        self.id = id
        self.make = make
    }

    func _makeView() -> UIView {
        content.primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content.primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        content.primitive._update(view, context: context)

        let key = "custom:\(id)"
        var constraints = view.fineCustomConstraints
        NSLayoutConstraint.deactivate(constraints[key] ?? [])

        let newConstraints = make(view)
        NSLayoutConstraint.activate(newConstraints)
        constraints[key] = newConstraints
        view.fineCustomConstraints = constraints
    }

    var _modifierSignature: String {
        content.primitive._modifierSignature + "|custom:\(id)"
    }

    var _key: AnyHashable? {
        content.primitive._key
    }

    var _viewProvider: any FinePrimitiveRenderable {
        content.primitive._viewProvider
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
