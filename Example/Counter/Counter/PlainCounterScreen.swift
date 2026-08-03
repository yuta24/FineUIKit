//
//  PlainCounterScreen.swift
//  Counter
//
//  Created by nova on 2026/07/09.
//

import FineUIKit
import Foundation
import Observation
import UIKit

// The plain counter. The screen is the state: a bare `@Observable` class with
// methods that mutate it directly — no reducer, no actions, no store. FineUIKit
// reads its properties in `body()`, so mutating them (including from the async
// `getFact()` task) re-renders the same way the TCA version does.
@Observable
final class PlainCounterScreen: FineScreen {
    var count = 0
    var stepText = "1"
    var fact: String?
    var isLoading = false

    private var step: Int { Int(stepText) ?? 1 }

    func increment() {
        count += step
        fact = nil
    }

    func decrement() {
        count -= step
        fact = nil
    }

    func getFact() async {
        isLoading = true
        fact = nil
        let number = count
        try? await Task.sleep(for: .seconds(1))
        fact = "\(number) is a great number!"
        isLoading = false
    }

    func navigation() -> FineNavigation? {
        FineNavigation(title: "Plain")
    }

    func body() -> any Renderable {
        counterBody(
            count: count,
            step: .init(self, \.stepText),
            isLoading: isLoading,
            fact: fact,
            onDecrement: { self.decrement() },
            onIncrement: { self.increment() },
            onGetFact: {
                Task { await self.getFact() }
            }
        )
    }
}
