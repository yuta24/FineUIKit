//
//  PlainCounterViewController.swift
//  Counter
//
//  Created by nova on 2026/07/09.
//

import FineUIKit
import Foundation
import Observation
import UIKit

// The plain counter. State lives in a bare `@Observable` model with methods
// that mutate it directly — no reducer, no actions, no store. FineUIKit reads
// the model's properties in `body(_:)`, so mutating them (including from the
// async `getFact()` task) re-renders the same way the TCA version does.
@Observable
final class PlainCounterViewModel {
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
}

final class PlainCounterViewController: FineViewController<PlainCounterViewModel> {
    init() {
        super.init(state: .init())
    }

    override func navigation(_ viewModel: PlainCounterViewModel) -> FineNavigation? {
        FineNavigation(title: "Plain")
    }

    override func body(_ viewModel: PlainCounterViewModel) -> any Renderable {
        counterBody(
            count: viewModel.count,
            step: .init(viewModel, \.stepText),
            isLoading: viewModel.isLoading,
            fact: viewModel.fact,
            onDecrement: { viewModel.decrement() },
            onIncrement: { viewModel.increment() },
            onGetFact: {
                Task { await viewModel.getFact() }
            }
        )
    }
}
