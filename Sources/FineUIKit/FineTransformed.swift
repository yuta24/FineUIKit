//
//  FineTransformed.swift
//  FineUIKit
//
//  Created by nova on 2026/08/16.
//

import UIKit

/// The transform a description asks for, gathered before it is applied.
///
/// `.scale()` and `.offset()` write the same `UIView.transform`, so they cannot
/// each set it: the second would undo the first. They merge into one of these
/// instead, and the transform is built once from the result.
struct FineTransformSpec: Equatable {
    var scale: CGSize?
    var offset: CGPoint?
    var rotation: CGFloat?

    /// Offset, then rotation, then scale — the order that makes each modifier
    /// mean what it says on its own. Scaling first would multiply the offset by
    /// the scale, so moving something 10 points would move it 12 once it was
    /// also enlarged.
    var transform: CGAffineTransform {
        var transform = CGAffineTransform.identity

        if let offset {
            transform = transform.translatedBy(x: offset.x, y: offset.y)
        }
        if let rotation {
            transform = transform.rotated(by: rotation)
        }
        if let scale {
            transform = transform.scaledBy(x: scale.width, y: scale.height)
        }

        return transform
    }

    /// This spec over one from further in, so the modifier written later wins
    /// the properties it names and leaves the rest alone.
    func merged(onto inner: FineTransformSpec?) -> FineTransformSpec {
        guard var merged = inner else { return self }

        if let scale { merged.scale = scale }
        if let offset { merged.offset = offset }
        if let rotation { merged.rotation = rotation }
        return merged
    }

    /// The key the modifier signature carries: which of the three were asked
    /// for, not what they were set to. Values change without changing the
    /// composition, and a signature that moved with them would rebuild the view
    /// on every frame of the very animation this exists to allow.
    var signatureKey: String {
        var parts = ["transform"]
        if scale != nil { parts.append("s") }
        if offset != nil { parts.append("o") }
        if rotation != nil { parts.append("r") }
        return parts.joined(separator: ".")
    }
}

public extension Renderable {
    /// Scales the rendered view around its centre.
    ///
    /// A compositor-friendly property: UIKit animates it on the layer without
    /// laying anything out again, so a scale under `.animation(_:)` costs the
    /// render nothing per frame.
    func scale(_ scale: CGFloat) -> any Renderable {
        self.scale(width: scale, height: scale)
    }

    /// Scales the rendered view around its centre, by axis.
    func scale(width: CGFloat, height: CGFloat) -> any Renderable {
        _transformed { $0.scale = CGSize(width: width, height: height) }
    }

    /// Moves the rendered view from where layout put it, without disturbing
    /// layout — the neighbours stay where they are.
    func offset(x: CGFloat = 0, y: CGFloat = 0) -> any Renderable {
        _transformed { $0.offset = CGPoint(x: x, y: y) }
    }

    /// Rotates the rendered view around its centre, in radians.
    func rotation(_ radians: CGFloat) -> any Renderable {
        _transformed { $0.rotation = radians }
    }

    /// Merges into the transform already asked for, rather than adding a style
    /// that would overwrite it.
    private func _transformed(_ mutate: (inout FineTransformSpec) -> Void) -> any Renderable {
        var spec = (self as? FineTransformed)?.spec ?? FineTransformSpec()
        mutate(&spec)

        let content = (self as? FineTransformed)?.content
        return content.map { FineTransformed(content: $0, spec: spec) }
            ?? FineTransformed(content: self, spec: spec)
    }
}

/// Applies the gathered transform to the view the content renders into.
@MainActor
struct FineTransformed: FinePrimitiveRenderable {
    let content: FineResolvedRenderable
    let spec: FineTransformSpec

    init(content: any Renderable, spec: FineTransformSpec) {
        self.content = FineResolvedRenderable(content)
        self.spec = spec
    }

    init(content: FineResolvedRenderable, spec: FineTransformSpec) {
        self.content = content
        self.spec = spec
    }

    func _makeView() -> UIView {
        content.primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content.primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        content.primitive._update(view, context: context)

        // Everything asked of this view, not only what this wrapper carries.
        // Another modifier can sit between two transform modifiers, leaving two
        // of these to write one property — and the one that writes last has to
        // write the whole answer or it erases the other.
        let transform = (_transformSpec ?? spec).transform
        if view.transform != transform {
            view.transform = transform
        }
    }

    var _modifierSignature: String {
        content.primitive._modifierSignature + "|" + spec.signatureKey
    }

    var _transformSpec: FineTransformSpec? {
        spec.merged(onto: content.primitive._transformSpec)
    }

    var _key: AnyHashable? {
        content.primitive._key
    }

    var _viewProvider: any FinePrimitiveRenderable {
        content.primitive._viewProvider
    }
}
