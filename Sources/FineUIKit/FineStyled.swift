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
struct FineStyled: Renderable {
    let content: any Renderable
    let styles: [FineStyle]

    func _makeView() -> UIView {
        content._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content._canUpdate(view)
    }

    func _update(_ view: UIView) {
        content._update(view)

        for style in styles {
            style.apply(view)
        }
    }

    var _modifierSignature: String {
        content._modifierSignature + "|" + styles.map(\.key).joined(separator: "|")
    }

    var _key: AnyHashable? {
        content._key
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
