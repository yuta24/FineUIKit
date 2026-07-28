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

        // The ceiling is raised before the floor moves up, so the two bounds
        // never cross while a range that moved entirely upwards is written.
        if slider.maximumValue < range.upperBound {
            slider.maximumValue = range.upperBound
        }
        if slider.minimumValue != range.lowerBound {
            slider.minimumValue = range.lowerBound
        }
        if slider.maximumValue != range.upperBound {
            slider.maximumValue = range.upperBound
        }

        if slider.value != value.value {
            slider.value = value.value
        }
        // UIKit clamps the written value to the slider's own range. The state
        // follows what is actually shown, so a value outside the range is
        // corrected once instead of disagreeing with the UI forever — and the
        // guard above keeps working, which it would not against a value the
        // slider can never take.
        if value.value != slider.value {
            value.value = slider.value
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
