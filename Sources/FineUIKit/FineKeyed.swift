//
//  FineKeyed.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
struct FineKeyed: FinePrimitiveRenderable {
    let key: AnyHashable
    let content: FineResolvedRenderable

    init(key: AnyHashable, content: any Renderable) {
        self.key = key
        self.content = FineResolvedRenderable(content)
    }

    func _makeView() -> UIView {
        content.primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content.primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        content.primitive._update(view, context: context)
    }

    var _modifierSignature: String {
        content.primitive._modifierSignature
    }

    var _key: AnyHashable? {
        key
    }

    var _viewProvider: any FinePrimitiveRenderable {
        content.primitive._viewProvider
    }
}

@MainActor
public func FineForEach<Element: Identifiable>(
    _ elements: [Element],
    content: @MainActor (Element) -> any Renderable
) -> [any Renderable] {
    elements.map { element in
        FineKeyed(key: AnyHashable(element.id), content: content(element))
    }
}
