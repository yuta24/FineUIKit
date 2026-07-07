//
//  FineLabel.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineLabel: FinePrimitiveRenderable {
    private let text: @MainActor () -> String?
    private var font: UIFont?
    private var textColor: UIColor?
    private var textAlignment: NSTextAlignment?
    private var numberOfLines: Int?

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(text: @autoclosure @escaping @MainActor () -> String?) {
        self.text = text
    }

    public func font(_ font: UIFont) -> FineLabel {
        var copy = self
        copy.font = font
        return copy
    }

    public func textColor(_ textColor: UIColor) -> FineLabel {
        var copy = self
        copy.textColor = textColor
        return copy
    }

    public func textAlignment(_ textAlignment: NSTextAlignment) -> FineLabel {
        var copy = self
        copy.textAlignment = textAlignment
        return copy
    }

    public func numberOfLines(_ numberOfLines: Int) -> FineLabel {
        var copy = self
        copy.numberOfLines = numberOfLines
        return copy
    }

    func _makeView() -> UIView {
        UILabel(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UILabel
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let label = view as? UILabel else { return }

        let resolvedFont = font ?? UIFont.systemFont(ofSize: UIFont.labelFontSize)
        let resolvedTextColor = textColor ?? UIColor.label
        let resolvedTextAlignment = textAlignment ?? NSTextAlignment.natural
        let resolvedNumberOfLines = numberOfLines ?? 1
        let resolvedText = text()

        if label.text != resolvedText {
            label.text = resolvedText
        }
        if !label.font.isEqual(resolvedFont) {
            label.font = resolvedFont
        }
        if !label.textColor.isEqual(resolvedTextColor) {
            label.textColor = resolvedTextColor
        }
        if label.textAlignment != resolvedTextAlignment {
            label.textAlignment = resolvedTextAlignment
        }
        if label.numberOfLines != resolvedNumberOfLines {
            label.numberOfLines = resolvedNumberOfLines
        }
    }
}
