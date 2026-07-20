//
//  FineToggle.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
public struct FineToggle: FinePrimitiveRenderable {
    private static let actionKey = "FineUIKit.FineToggle.valueChanged"

    private let isOn: FineBinding<Bool>
    private var isEnabled = true

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(isOn: FineBinding<Bool>) {
        self.isOn = isOn
    }

    /// Sets whether the toggle responds to user interaction.
    public func enabled(_ isEnabled: Bool = true) -> FineToggle {
        var copy = self
        copy.isEnabled = isEnabled
        return copy
    }

    func _makeView() -> UIView {
        UISwitch(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is UISwitch
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let uiSwitch = view as? UISwitch else { return }

        if uiSwitch.isOn != isOn.value {
            uiSwitch.isOn = isOn.value
        }
        if uiSwitch.isEnabled != isEnabled {
            uiSwitch.isEnabled = isEnabled
        }

        uiSwitch.fineSetHandler(Self.actionKey, for: .valueChanged) { [isOn] control in
            guard let uiSwitch = control as? UISwitch else { return }
            isOn.value = uiSwitch.isOn
        }
    }
}
