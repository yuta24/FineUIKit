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
    let content: any Renderable
    let styles: [FineStyle]

    func _makeView() -> UIView {
        FineRenderer.primitive(for: content)._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        FineRenderer.primitive(for: content)._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        FineRenderer.primitive(for: content)._update(view, context: context)

        for style in styles {
            style.apply(view)
        }
    }

    var _modifierSignature: String {
        FineRenderer.primitive(for: content)._modifierSignature + "|" + styles.map(\.key).joined(separator: "|")
    }

    var _key: AnyHashable? {
        FineRenderer.primitive(for: content)._key
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
