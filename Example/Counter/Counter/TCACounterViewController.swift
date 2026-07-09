//
//  TCACounterViewController.swift
//  Counter
//
//  Created by nova on 2026/07/09.
//

import ComposableArchitecture
import FineUIKit
import UIKit

// The TCA-backed counter. `State` is a `StoreOf<Feature>`; nothing about
// FineUIKit is TCA-specific. The render loop tracks whatever observable values
// `body(_:)` reads, and here those reads go through the store's
// `@ObservableState`.
final class TCACounterViewController: FineViewController<StoreOf<CounterFeature>> {
    init() {
        super.init(state: Store(initialState: CounterFeature.State()) {
            CounterFeature()
        })
    }

    override func navigation(_ store: StoreOf<CounterFeature>) -> FineNavigation? {
        FineNavigation(title: "TCA")
    }

    override func body(_ store: StoreOf<CounterFeature>) -> any Renderable {
        counterBody(
            count: store.count,
            // Two-way binding into TCA state. The setter writes through the
            // store's bindable dynamic-member subscript, which sends
            // `.binding(.set(\.stepText, _))` for BindingReducer to apply.
            step: .init(get: { store.stepText }, set: { store.stepText = $0 }),
            isLoading: store.isLoading,
            fact: store.fact,
            onDecrement: { store.send(.decrementTapped) },
            onIncrement: { store.send(.incrementTapped) },
            onGetFact: { store.send(.factButtonTapped) }
        )
    }
}
