//
//  FineState.swift
//  FineUIKit
//
//  Created by nova on 2026/07/08.
//

import Observation
import UIKit

final class FineStateStorage<Value>: Observable {
    private let observationRegistrar = ObservationRegistrar()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        get {
            observationRegistrar.access(self, keyPath: \.value)
            return storedValue
        }
        set {
            observationRegistrar.withMutation(of: self, keyPath: \.value) {
                storedValue = newValue
            }
        }
    }
}

@MainActor
final class FineStateReaderView: UIView {
    var hosted: UIView?
}

@MainActor
struct FineStateReader<Value>: FinePrimitiveRenderable {
    let initialValue: Value
    let content: @MainActor (FineBinding<Value>) -> any Renderable

    func _makeView() -> UIView {
        FineStateReaderView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FineStateReaderView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let host = view as? FineStateReaderView else { return }

        let storage: FineStateStorage<Value>
        if let existing = host.fineNode.localState as? FineStateStorage<Value> {
            storage = existing
        } else {
            storage = FineStateStorage(initialValue)
            host.fineNode.localState = storage
        }

        let binding = FineBinding<Value>(
            get: { storage.value },
            set: { storage.value = $0 }
        )

        let node = content(binding)
        let rendered = context.render(node, reusing: host.hosted)

        if rendered !== host.hosted {
            host.hosted?.removeFromSuperview()
            host.hosted = rendered

            rendered.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(rendered)

            NSLayoutConstraint.activate([
                rendered.topAnchor.constraint(equalTo: host.topAnchor),
                rendered.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                rendered.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                rendered.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        }
    }

    var _modifierSignature: String {
        "stateReader"
    }
}

@MainActor
public func FineState<Value>(
    _ initialValue: Value,
    content: @escaping @MainActor (FineBinding<Value>) -> any Renderable
) -> any Renderable {
    FineStateReader(initialValue: initialValue, content: content)
}
