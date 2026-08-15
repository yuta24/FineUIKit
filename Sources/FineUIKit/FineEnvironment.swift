//
//  FineEnvironment.swift
//  FineUIKit
//
//  Created by nova on 2026/07/08.
//

import Observation
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

    /// Best-effort equality used to skip environment publishes that would
    /// re-render observing cells: equal only when both hold the same keys and
    /// every value pair compares equal via `Equatable`. Non-`Equatable`
    /// values are conservatively treated as changed.
    func fineIsApproximatelyEqual(to other: FineEnvironmentValues) -> Bool {
        guard storage.count == other.storage.count else { return false }

        for (key, value) in storage {
            guard let otherValue = other.storage[key],
                  fineDynamicEquals(value, otherValue) == true
            else { return false }
        }
        return true
    }
}

/// Observable box carrying the environment a list/grid resolved at its last
/// render. Host cells read `values` inside their tracked render scope, so an
/// environment change re-renders visible cells without a row reconfigure.
@MainActor
@Observable
final class FineEnvironmentStorage {
    private(set) var values = FineEnvironmentValues()

    /// What `values` was last set to, compared against without going through
    /// the observed property. `update(_:)` runs inside the list's own tracked
    /// render, where reading `values` would register the list as an observer
    /// of the storage it publishes to, and every publish would re-render it.
    @ObservationIgnored private var published = FineEnvironmentValues()

    /// Publishes `values` only when they differ from the stored ones, so
    /// unrelated list renders don't re-render every observing cell.
    func update(_ values: FineEnvironmentValues) {
        guard !published.fineIsApproximatelyEqual(to: values) else { return }

        published = values
        self.values = values
    }
}

@MainActor
struct FineEnvironmentWriter: FinePrimitiveRenderable {
    let content: FineResolvedRenderable
    let mutate: @MainActor (inout FineEnvironmentValues) -> Void

    init(content: any Renderable, mutate: @escaping @MainActor (inout FineEnvironmentValues) -> Void) {
        self.content = FineResolvedRenderable(content)
        self.mutate = mutate
    }

    func _makeView() -> UIView {
        content.primitive._makeView()
    }

    func _canUpdate(_ view: UIView) -> Bool {
        content.primitive._canUpdate(view)
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        let childContext = context.withEnvironment { mutate(&$0) }
        content.primitive._update(view, context: childContext)
    }

    var _modifierSignature: String {
        content.primitive._modifierSignature
    }

    var _key: AnyHashable? {
        content.primitive._key
    }

    var _viewProvider: any FinePrimitiveRenderable {
        content.primitive._viewProvider
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

/// Carries the hosting view's traits. Declared as a computed property so the
/// default costs nothing until a tree without a host reads it.
private struct FineTraitCollectionKey: FineEnvironmentKey {
    static var defaultValue: UITraitCollection { UITraitCollection() }
}

public extension FineEnvironmentValues {
    /// Traits of the view hosting the tree: content size category, interface
    /// style, size classes, layout direction.
    ///
    /// The runtime keeps this current and re-renders the tree when one of the
    /// traits it observes changes, so a description can branch on it:
    ///
    /// ```swift
    /// FineEnvironmentReader { environment in
    ///     environment.traitCollection.horizontalSizeClass == .compact
    ///         ? FineStack.vertical { … }
    ///         : FineStack.horizontal { … }
    /// }
    /// ```
    var traitCollection: UITraitCollection {
        get { self[FineTraitCollectionKey.self] }
        set { self[FineTraitCollectionKey.self] = newValue }
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
