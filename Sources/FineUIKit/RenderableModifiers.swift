//
//  RenderableModifiers.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

public extension Renderable {
    func padding(_ length: CGFloat = 16) -> any Renderable {
        padding(.init(top: length, leading: length, bottom: length, trailing: length))
    }

    func padding(_ insets: NSDirectionalEdgeInsets) -> any Renderable {
        FinePadded(content: self, insets: insets)
    }

    func frame(width: CGFloat? = nil, height: CGFloat? = nil) -> any Renderable {
        FineFramed(content: self, width: width, height: height)
    }

    func backgroundColor(_ color: UIColor) -> any Renderable {
        _styled("backgroundColor") { view in
            view.backgroundColor = color
        }
    }

    func cornerRadius(_ radius: CGFloat) -> any Renderable {
        _styled("cornerRadius") { view in
            view.layer.cornerRadius = radius
            view.clipsToBounds = true
        }
    }

    func border(_ color: UIColor, width: CGFloat) -> any Renderable {
        _styled("border") { view in
            view.layer.borderColor = color.cgColor
            view.layer.borderWidth = width
        }
    }

    func opacity(_ value: CGFloat) -> any Renderable {
        _styled("opacity") { view in
            view.alpha = value
        }
    }

    func tintColor(_ color: UIColor) -> any Renderable {
        _styled("tintColor") { view in
            view.tintColor = color
        }
    }
}
