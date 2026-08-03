//
//  TCACounterScreen.swift
//  Counter
//
//  Created by nova on 2026/07/09.
//

import ComposableArchitecture
import FineUIKit

// The TCA-backed counter. The screen holds a store rather than its own state;
// nothing about FineUIKit is TCA-specific. The render loop tracks whatever
// observable values `body()` reads, and here those reads go through the
// store's `@ObservableState`.
final class TCACounterScreen: FineScreen {
    let store: StoreOf<CounterFeature>

    init() {
        store = Store(initialState: CounterFeature.State()) {
            CounterFeature()
        }
    }

    func navigation() -> FineNavigation? {
        FineNavigation(title: "TCA")
    }

    func body() -> any Renderable {
        counterBody(
            count: store.count,
            // Two-way binding into TCA state. The setter writes through the
            // store's bindable dynamic-member subscript, which sends
            // `.binding(.set(\.stepText, _))` for BindingReducer to apply.
            step: .init(get: { self.store.stepText }, set: { self.store.stepText = $0 }),
            isLoading: store.isLoading,
            fact: store.fact,
            onDecrement: { self.store.send(.decrementTapped) },
            onIncrement: { self.store.send(.incrementTapped) },
            onGetFact: { self.store.send(.factButtonTapped) }
        )
    }
}
