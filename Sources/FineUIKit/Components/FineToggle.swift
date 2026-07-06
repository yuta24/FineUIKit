//
//  FineToggle.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

@MainActor
public struct FineToggle: Renderable {
    private static let actionIdentifier = UIAction.Identifier("FineUIKit.FineToggle.valueChanged")

    private let isOn: FineBinding<Bool>

    public init(isOn: FineBinding<Bool>) {
        self.isOn = isOn
    }

    public func _makeView() -> UIView {
        UISwitch(frame: .zero)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        view is UISwitch
    }

    public func _update(_ view: UIView) {
        guard let uiSwitch = view as? UISwitch else { return }

        if uiSwitch.isOn != isOn.value {
            uiSwitch.isOn = isOn.value
        }

        uiSwitch.removeAction(identifiedBy: Self.actionIdentifier, for: .valueChanged)
        uiSwitch.addAction(.init(identifier: Self.actionIdentifier, handler: { [isOn] action in
            guard let uiSwitch = action.sender as? UISwitch else { return }
            isOn.value = uiSwitch.isOn
        }), for: .valueChanged)
    }
}
