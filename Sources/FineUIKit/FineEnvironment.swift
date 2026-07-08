//
//  FineEnvironment.swift
//  FineUIKit
//
//  Created by nova on 2026/07/08.
//

import UIKit

public protocol FineEnvironmentKey {
    associatedtype Value

    static var defaultValue: Value { get }
}

public struct FineEnvironmentValues {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<K: FineEnvironmentKey>(key: K.Type) -> K.Value {
        get {
            storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue
        }
        set {
            storage[ObjectIdentifier(key)] = newValue
        }
    }
}

@MainActor
struct FineEnvironmentWriter: FinePrimitiveRenderable {
    let content: any Renderable
    let mutate: @MainActor (inout FineEnvironmentValues) -> Void

    private var contentPrimitive: any FinePrimitiveRenderable {
        FineRenderer.primitive(for: content)
    }

    func _makeView() -> UIView {
        contentPrimitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        contentPrimitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        let childContext = context.withEnvironment { mutate(&$0) }
        contentPrimitive._update(view, context: childContext)
    }

    var _modifierSignature: String {
        contentPrimitive._modifierSignature
    }

    var _key: AnyHashable? {
        contentPrimitive._key
    }
}

@MainActor
final class FineEnvironmentReaderView: UIView {
    var hosted: UIView?
}

@MainActor
struct FineEnvironmentReaderPrimitive: FinePrimitiveRenderable {
    let content: @MainActor (FineEnvironmentValues) -> any Renderable

    func _makeView() -> UIView {
        FineEnvironmentReaderView(frame: .zero)
    }

    func _canUpdate(_ view: UIView) -> Bool {
        view is FineEnvironmentReaderView
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let host = view as? FineEnvironmentReaderView else { return }

        let node = content(context.environment)
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
        "environmentReader"
    }
}

public extension Renderable {
    func environment<Value>(
        _ keyPath: WritableKeyPath<FineEnvironmentValues, Value>,
        _ value: Value
    ) -> any Renderable {
        FineEnvironmentWriter(content: self) { $0[keyPath: keyPath] = value }
    }
}

@MainActor
public func FineEnvironmentReader(
    _ content: @escaping @MainActor (FineEnvironmentValues) -> any Renderable
) -> any Renderable {
    FineEnvironmentReaderPrimitive(content: content)
}
