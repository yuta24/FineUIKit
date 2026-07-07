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

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(isOn: FineBinding<Bool>) {
        self.isOn = isOn
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

        uiSwitch.fineSetHandler(Self.actionKey, for: .valueChanged) { [isOn] control in
            guard let uiSwitch = control as? UISwitch else { return }
            isOn.value = uiSwitch.isOn
        }
    }
}
