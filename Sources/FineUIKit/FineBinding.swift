//
//  FineBinding.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import Foundation

/// A two-way connection between a component and a piece of state.
///
/// Reading `value` inside a render pass registers the underlying
/// `@Observable` property with observation tracking, so external changes
/// to the state re-render the component.
@MainActor
public struct FineBinding<Value> {
    private let get: @MainActor () -> Value
    private let set: @MainActor (Value) -> Void

    public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
        self.get = get
        self.set = set
    }

    /// Binds a mutable property of a reference-typed state object
    /// (e.g. an `@Observable` model): `.init(viewModel, \.draft)`.
    public init<Root: AnyObject>(_ root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>) {
        self.init(
            get: { root[keyPath: keyPath] },
            set: { root[keyPath: keyPath] = $0 }
        )
    }

    public var value: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }
}
