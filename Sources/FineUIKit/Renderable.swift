//
//  Renderable.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

/// A value that describes a piece of UI.
///
/// A `Renderable` is a lightweight description, not a view. `FineRenderer`
/// turns descriptions into `UIView`s, reusing existing views when possible.
@MainActor
public protocol Renderable {
    /// Creates a fresh view for this description. Do not configure it here;
    /// configuration belongs in `_update(_:)` so it also runs on reuse.
    func _makeView() -> UIView

    /// Whether this description can be applied to `view` in place.
    func _canUpdate(_ view: UIView) -> Bool

    /// Applies this description to `view`.
    func _update(_ view: UIView)
}
