//
//  RenderableModifiers.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

public extension Renderable {
    func key(_ key: some Hashable) -> any Renderable {
        FineKeyed(key: AnyHashable(key), content: self)
    }

    func padding(_ length: CGFloat = 16) -> any Renderable {
        padding(.init(top: length, leading: length, bottom: length, trailing: length))
    }

    func padding(_ insets: NSDirectionalEdgeInsets) -> any Renderable {
        FinePadded(content: self, insets: insets)
    }

    func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: FineAlignment = .fill) -> any Renderable {
        FineFramed(content: self, width: width, height: height, alignment: alignment)
    }

    /// Constrains the view's width. The default priority is `999` so these
    /// self constraints yield to container-imposed required constraints.
    func width(_ constant: CGFloat, priority: UILayoutPriority = .init(999)) -> any Renderable {
        width(.equal, constant, priority: priority)
    }

    /// Constrains the view's width. The default priority is `999` so these
    /// self constraints yield to container-imposed required constraints.
    func width(
        _ relation: NSLayoutConstraint.Relation = .equal,
        _ constant: CGFloat,
        priority: UILayoutPriority = .init(999)
    ) -> any Renderable {
        _constrained(.init(
            key: "constraint.w\(relation.fineKey)@\(priority.rawValue)",
            constant: constant,
            priority: priority
        ) { view in
            switch relation {
            case .equal:
                view.widthAnchor.constraint(equalToConstant: constant)
            case .lessThanOrEqual:
                view.widthAnchor.constraint(lessThanOrEqualToConstant: constant)
            case .greaterThanOrEqual:
                view.widthAnchor.constraint(greaterThanOrEqualToConstant: constant)
            @unknown default:
                view.widthAnchor.constraint(equalToConstant: constant)
            }
        })
    }

    /// Constrains the view's height. The default priority is `999` so these
    /// self constraints yield to container-imposed required constraints.
    func height(_ constant: CGFloat, priority: UILayoutPriority = .init(999)) -> any Renderable {
        height(.equal, constant, priority: priority)
    }

    /// Constrains the view's height. The default priority is `999` so these
    /// self constraints yield to container-imposed required constraints.
    func height(
        _ relation: NSLayoutConstraint.Relation = .equal,
        _ constant: CGFloat,
        priority: UILayoutPriority = .init(999)
    ) -> any Renderable {
        _constrained(.init(
            key: "constraint.h\(relation.fineKey)@\(priority.rawValue)",
            constant: constant,
            priority: priority
        ) { view in
            switch relation {
            case .equal:
                view.heightAnchor.constraint(equalToConstant: constant)
            case .lessThanOrEqual:
                view.heightAnchor.constraint(lessThanOrEqualToConstant: constant)
            case .greaterThanOrEqual:
                view.heightAnchor.constraint(greaterThanOrEqualToConstant: constant)
            @unknown default:
                view.heightAnchor.constraint(equalToConstant: constant)
            }
        })
    }

    /// Constrains width to height times `ratio`. The default priority is `999`
    /// so this self constraint yields to container-imposed required constraints.
    func aspectRatio(_ ratio: CGFloat, priority: UILayoutPriority = .init(999)) -> any Renderable {
        _constrained(.init(
            key: "constraint.ar\(ratio)@\(priority.rawValue)",
            constant: 0,
            priority: priority
        ) { view in
            view.widthAnchor.constraint(equalTo: view.heightAnchor, multiplier: ratio)
        })
    }

    func hugging(_ priority: UILayoutPriority, axis: NSLayoutConstraint.Axis) -> any Renderable {
        _styled("hugging.\(axis.fineKey)") { view in
            view.setContentHuggingPriority(priority, for: axis)
        }
    }

    func compressionResistance(_ priority: UILayoutPriority, axis: NSLayoutConstraint.Axis) -> any Renderable {
        _styled("compressionResistance.\(axis.fineKey)") { view in
            view.setContentCompressionResistancePriority(priority, for: axis)
        }
    }

    func fixedSize() -> any Renderable {
        _styled("fixedSize") { view in
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentHuggingPriority(.required, for: .vertical)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
    }

    /// Recreates and activates custom constraints on every render. Constraints
    /// must target the view itself or its descendants; the superview may not be
    /// attached yet.
    func constraints(id: String, _ make: @escaping @MainActor (UIView) -> [NSLayoutConstraint]) -> any Renderable {
        FineCustomConstrained(content: self, id: id, make: make)
    }

    func backgroundColor(_ color: UIColor) -> any Renderable {
        _styled("backgroundColor") { view in
            if view.backgroundColor?.isEqual(color) != true {
                view.backgroundColor = color
            }
        }
    }

    func cornerRadius(_ radius: CGFloat) -> any Renderable {
        _styled("cornerRadius") { view in
            if view.layer.cornerRadius != radius {
                view.layer.cornerRadius = radius
            }
            if !view.clipsToBounds {
                view.clipsToBounds = true
            }
        }
    }

    func border(_ color: UIColor, width: CGFloat) -> any Renderable {
        _styled("border") { view in
            if view.layer.borderColor != color.cgColor {
                view.layer.borderColor = color.cgColor
            }
            if view.layer.borderWidth != width {
                view.layer.borderWidth = width
            }
        }
    }

    func opacity(_ value: CGFloat) -> any Renderable {
        _styled("opacity") { view in
            if view.alpha != value {
                view.alpha = value
            }
        }
    }

    func tintColor(_ color: UIColor) -> any Renderable {
        _styled("tintColor") { view in
            if view.tintColor?.isEqual(color) != true {
                view.tintColor = color
            }
        }
    }

    func accessibilityLabel(_ label: String) -> any Renderable {
        _styled("axLabel") { view in
            if view.accessibilityLabel != label {
                view.accessibilityLabel = label
            }
            if !view.isAccessibilityElement {
                view.isAccessibilityElement = true
            }
        }
    }

    func accessibilityValue(_ value: String) -> any Renderable {
        _styled("axValue") { view in
            if view.accessibilityValue != value {
                view.accessibilityValue = value
            }
        }
    }

    func accessibilityHint(_ hint: String) -> any Renderable {
        _styled("axHint") { view in
            if view.accessibilityHint != hint {
                view.accessibilityHint = hint
            }
        }
    }

    func accessibilityTraits(_ traits: UIAccessibilityTraits) -> any Renderable {
        _styled("axTraits") { view in
            if view.accessibilityTraits != traits {
                view.accessibilityTraits = traits
            }
        }
    }

    func accessibilityIdentifier(_ identifier: String) -> any Renderable {
        _styled("axIdentifier") { view in
            if view.accessibilityIdentifier != identifier {
                view.accessibilityIdentifier = identifier
            }
        }
    }

    func accessibilityHidden(_ hidden: Bool = true) -> any Renderable {
        _styled("axHidden") { view in
            if view.accessibilityElementsHidden != hidden {
                view.accessibilityElementsHidden = hidden
            }

            if hidden && view.isAccessibilityElement {
                view.isAccessibilityElement = false
            }
        }
    }
}

private extension NSLayoutConstraint.Relation {
    var fineKey: String {
        switch self {
        case .equal:
            "=="
        case .lessThanOrEqual:
            "<="
        case .greaterThanOrEqual:
            ">="
        @unknown default:
            "?"
        }
    }
}

private extension NSLayoutConstraint.Axis {
    var fineKey: String {
        switch self {
        case .horizontal:
            "h"
        case .vertical:
            "v"
        @unknown default:
            "?"
        }
    }
}
