//
//  FineSlider.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
public struct FineSlider: FinePrimitiveRenderable {
    private static let actionKey = "FineUIKit.FineSlider.valueChanged"

    private let value: FineBinding<Float>
    private let range: ClosedRange<Float>
    private var isEnabled = true

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(value: FineBinding<Float>, in range: ClosedRange<Float> = 0...1) {
        self.value = value
        self.range = range
    }

    /// Sets whether the slider responds to user interaction.
    public func enabled(_ isEnabled: Bool = true) -> FineSlider {
        var copy = self
        copy.isEnabled = isEnabled
        return copy
    }

    func _makeView() -> UIView {
        UISlider(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UISlider
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let slider = view as? UISlider else { return }

        if slider.minimumValue != range.lowerBound {
            slider.minimumValue = range.lowerBound
        }
        if slider.maximumValue != range.upperBound {
            slider.maximumValue = range.upperBound
        }

        if slider.value != value.value {
            slider.value = value.value
        }
        if slider.isEnabled != isEnabled {
            slider.isEnabled = isEnabled
        }

        slider.fineSetHandler(Self.actionKey, for: .valueChanged) { [value] control in
            guard let slider = control as? UISlider else { return }
            value.value = slider.value
        }
    }
}
