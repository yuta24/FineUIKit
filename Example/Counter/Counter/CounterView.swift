//
//  CounterView.swift
//  Counter
//
//  Created by nova on 2026/07/09.
//

import FineUIKit
import UIKit

// The UI is identical for both counter implementations; only how state is
// stored and mutated differs. Sharing the body here keeps the comparison
// between the TCA version and the plain @Observable version honest: same
// FineUIKit description, different state layer feeding it.
@MainActor
func counterBody(
    count: Int,
    step: FineBinding<String>,
    isLoading: Bool,
    fact: String?,
    onDecrement: @escaping () -> Void,
    onIncrement: @escaping () -> Void,
    onGetFact: @escaping () -> Void
) -> any Renderable {
    FineStack.vertical(spacing: 16) {
        FineLabel(text: "\(count)")
            .font(.preferredFont(forTextStyle: .largeTitle))
            .textAlignment(.center)

        FineStack.horizontal(spacing: 12) {
            FineButton(title: "−", action: onDecrement)
                .configuration(.bordered())
            FineButton(title: "+", action: onIncrement)
                .configuration(.bordered())
        }

        FineStack.horizontal(spacing: 8) {
            FineLabel(text: "Step")
            FineTextField(text: step, placeholder: "1")
                .keyboardType(.numberPad)
        }

        FineButton(title: isLoading ? "Loading…" : "Get fact", action: onGetFact)
            .configuration(.filled())

        if let fact {
            FineLabel(text: fact)
                .numberOfLines(0)
                .textAlignment(.center)
                .textColor(.secondaryLabel)
        }

        FineSpacer()
    }
    .padding(.init(top: 24, leading: 16, bottom: 0, trailing: 16))
}
