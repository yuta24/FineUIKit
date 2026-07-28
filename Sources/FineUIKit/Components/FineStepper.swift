//
//  FineStepper.swift
//  FineUIKit
//
//  Created by nova on 2026/07/28.
//

import UIKit

@MainActor
public struct FineStepper: FinePrimitiveRenderable {
    private static let actionKey = "FineUIKit.FineStepper.valueChanged"

    private let value: FineBinding<Double>
    private let range: ClosedRange<Double>
    private let step: Double
    private var isEnabled = true

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(value: FineBinding<Double>, in range: ClosedRange<Double> = 0...100, step: Double = 1) {
        self.value = value
        self.range = range
        self.step = step
    }

    /// Sets whether the stepper responds to user interaction.
    public func enabled(_ isEnabled: Bool = true) -> FineStepper {
        var copy = self
        copy.isEnabled = isEnabled
        return copy
    }

    func _makeView() -> UIView {
        UIStepper(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UIStepper
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let stepper = view as? UIStepper else { return }

        // The ceiling is raised before the floor moves up, so the two bounds
        // never cross while a range that moved entirely upwards is written.
        if stepper.maximumValue < range.upperBound {
            stepper.maximumValue = range.upperBound
        }
        if stepper.minimumValue != range.lowerBound {
            stepper.minimumValue = range.lowerBound
        }
        if stepper.maximumValue != range.upperBound {
            stepper.maximumValue = range.upperBound
        }

        if stepper.stepValue != step {
            stepper.stepValue = step
        }
        if stepper.value != value.value {
            stepper.value = value.value
        }
        // UIKit clamps the written value to the stepper's own range. The state
        // follows what is actually shown, so a value outside the range is
        // corrected once instead of disagreeing with the UI forever (same rule
        // as `FineSlider`).
        if value.value != stepper.value {
            value.value = stepper.value
        }
        if stepper.isEnabled != isEnabled {
            stepper.isEnabled = isEnabled
        }

        stepper.fineSetHandler(Self.actionKey, for: .valueChanged) { [value] control in
            guard let stepper = control as? UIStepper else { return }
            value.value = stepper.value
        }
    }
}
