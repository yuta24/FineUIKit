//
//  FineStyled.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
struct FineStyle {
    let key: String
    let apply: @MainActor (UIView) -> Void
}

@MainActor
struct FineStyled: FinePrimitiveRenderable {
    let content: FineResolvedRenderable
    let styles: [FineStyle]

    init(content: any Renderable, styles: [FineStyle]) {
        self.content = FineResolvedRenderable(content)
        self.styles = styles
    }

    /// Re-wraps content whose resolution another wrapper already paid for, so
    /// a chain of style modifiers walks `body` once between them.
    init(content: FineResolvedRenderable, styles: [FineStyle]) {
        self.content = content
        self.styles = styles
    }

    func _makeView() -> UIView {
        content.primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content.primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        content.primitive._update(view, context: context)

        for style in styles {
            style.apply(view)
        }
    }

    var _modifierSignature: String {
        content.primitive._modifierSignature + "|" + styles.map(\.key).joined(separator: "|")
    }

    var _key: AnyHashable? {
        content.primitive._key
    }

    var _viewProvider: any FinePrimitiveRenderable {
        content.primitive._viewProvider
    }
}

extension Renderable {
    func _styled(_ key: String, _ apply: @escaping @MainActor (UIView) -> Void) -> any Renderable {
        let style = FineStyle(key: key, apply: apply)

        if let styled = self as? FineStyled {
            return FineStyled(content: styled.content, styles: styled.styles + [style])
        }

        return FineStyled(content: self, styles: [style])
    }
}
