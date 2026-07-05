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

    public init(text: String?) {
        self.text = text
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
    }
}
