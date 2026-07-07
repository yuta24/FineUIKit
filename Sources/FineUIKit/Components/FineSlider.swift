//
//  FineSlider.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
public struct FineSlider: Renderable {
    private static let actionKey = "FineUIKit.FineSlider.valueChanged"

    private let value: FineBinding<Float>
    private let range: ClosedRange<Float>

    public init(value: FineBinding<Float>, in range: ClosedRange<Float> = 0...1) {
        self.value = value
        self.range = range
    }

    public func _makeView() -> UIView {
        UISlider(frame: .zero)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UISlider
    }

    public func _update(_ view: UIView) {
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

        slider.fineSetHandler(Self.actionKey, for: .valueChanged) { [value] control in
            guard let slider = control as? UISlider else { return }
            value.value = slider.value
        }
    }
}
