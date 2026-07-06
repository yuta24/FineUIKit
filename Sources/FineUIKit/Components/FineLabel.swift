//
//  FineLabel.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineLabel: Renderable {
    private let text: String?
    private var font: UIFont?
    private var textColor: UIColor?
    private var textAlignment: NSTextAlignment?
    private var numberOfLines: Int?

    public init(text: String?) {
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

    public func _makeView() -> UIView {
        UILabel(frame: .zero)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UILabel
    }

    public func _update(_ view: UIView) {
        guard let label = view as? UILabel else { return }

        label.text = text
        label.font = font ?? .systemFont(ofSize: UIFont.labelFontSize)
        label.textColor = textColor ?? .label
        label.textAlignment = textAlignment ?? .natural
        label.numberOfLines = numberOfLines ?? 1
    }
}
