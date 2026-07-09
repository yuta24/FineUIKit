//
//  CounterFeature.swift
//  Counter
//
//  Created by nova on 2026/07/09.
//

import ComposableArchitecture

// TCA sample. A small feature demonstrating how a `StoreOf<Feature>` drives a
// FineUIKit view: `@ObservableState` reads are tracked by the same
// `withObservationTracking` loop FineUIKit uses, so `store.send(...)` and the
// effects it triggers re-render the screen automatically on iOS 17+.
//
// This project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
// would otherwise make the reducer MainActor-isolated and clash with the
// nonisolated `Reducer` conformance the `@Reducer` macro synthesizes. Opt the
// reducer back out to nonisolated.
@Reducer
nonisolated struct CounterFeature {
    @ObservableState
    struct State: Equatable {
        var count = 0
        // Bound to a text field via FineBinding + BindingReducer.
        var stepText = "1"
        var fact: String?
        var isLoading = false

        var step: Int { Int(stepText) ?? 1 }
    }

    enum Action: BindableAction {
        case incrementTapped
        case decrementTapped
        case factButtonTapped
        case factResponse(String)
        case binding(BindingAction<State>)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .incrementTapped:
                state.count += state.step
                state.fact = nil
                return .none

            case .decrementTapped:
                state.count -= state.step
                state.fact = nil
                return .none

            case .factButtonTapped:
                state.isLoading = true
                state.fact = nil
                // An async effect. When it finishes and feeds an action back,
                // the resulting state change re-renders the FineUIKit tree.
                return .run { [count = state.count] send in
                    try await Task.sleep(for: .seconds(1))
                    await send(.factResponse("\(count) is a great number!"))
                }

            case let .factResponse(fact):
                state.isLoading = false
                state.fact = fact
                return .none

            case .binding:
                return .none
            }
        }
    }
}
