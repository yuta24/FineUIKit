//
//  Renderable.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

/// A value that describes a piece of UI.
///
/// A `Renderable` composes built-in components through `body`. `FineRenderer`
/// resolves that composition into primitive descriptions and turns them into
/// `UIView`s, reusing existing views when possible.
@MainActor
public protocol Renderable {
    /// Returns the composed UI description.
    var body: any Renderable { get }
}

@MainActor
protocol FinePrimitiveRenderable: Renderable {
    func _makeView() -> UIView
    func _canUpdate(_ view: UIView) -> Bool
    func _update(_ view: UIView, context: FineRenderContext)
    var _modifierSignature: String { get }
    var _key: AnyHashable? { get }
}

extension FinePrimitiveRenderable {
    var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    var _modifierSignature: String {
        ""
    }

    var _key: AnyHashable? {
        nil
    }
}
