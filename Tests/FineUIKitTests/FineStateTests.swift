import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
struct FineStateTests {
    @Observable
    final class ParentState {
        var tick = 0
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel {
            return label
        }

        for subview in view.subviews {
            if let label = firstLabel(in: subview) {
                return label
            }
        }

        return nil
    }

    /// Collects content labels in tree order, skipping labels that belong to a
    /// `UIButton` (its internal `titleLabel`) so button titles don't interleave
    /// with the labels the tests care about.
    private func labels(in view: UIView) -> [UILabel] {
        var result: [UILabel] = []

        if let label = view as? UILabel {
            result.append(label)
        }

        for subview in view.subviews where !(subview is UIButton) {
            result.append(contentsOf: labels(in: subview))
        }

        return result
    }

    private func firstButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton {
            return button
        }

        for subview in view.subviews {
            if let button = firstButton(in: subview) {
                return button
            }
        }

        return nil
    }

    private func buttons(in view: UIView) -> [UIButton] {
        var result: [UIButton] = []

        if let button = view as? UIButton {
            result.append(button)
        }

        for subview in view.subviews {
            result.append(contentsOf: buttons(in: subview))
        }

        return result
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10 where !condition() {
            await Task.yield()
        }
    }

    @Test func rendersInitialValue() throws {
        let container = UIView()
        let fineUI = FineUI(()) { _ in
            FineState(0) { count in
                FineLabel(text: "\(count.value)")
            }
        }
        fineUI.build(to: container)

        let label = try #require(firstLabel(in: container))
        #expect(label.text == "0")
    }

    @Test func localUpdateRerendersWithoutExternalState() async throws {
        let container = UIView()
        let fineUI = FineUI(()) { _ in
            FineState(0) { count in
                FineStack.vertical {
                    [
                        FineLabel(text: "\(count.value)"),
                        FineButton(title: "+") { count.value += 1 },
                    ]
                }
            }
        }
        fineUI.build(to: container)

        let label = try #require(firstLabel(in: container))
        let button = try #require(firstButton(in: container))
        #expect(label.text == "0")

        button.sendActions(for: .primaryActionTriggered)

        await waitUntil { label.text == "1" }
        #expect(label.text == "1")
    }

    @Test func preservesLocalStateAcrossParentRerender() async throws {
        let state = ParentState()
        let container = UIView()
        let fineUI = FineUI(state) { state in
            let tick = state.tick
            return FineStack.vertical {
                [
                    FineLabel(text: "\(tick)"),
                    FineState(0) { count in
                        FineStack.vertical {
                            [
                                FineLabel(text: "\(count.value)"),
                                FineButton(title: "+") { count.value += 1 },
                            ]
                        }
                    },
                ]
            }
        }
        fineUI.build(to: container)

        let initialLabels = labels(in: container)
        let tickLabel = try #require(initialLabels.first)
        let countLabel = try #require(initialLabels.dropFirst().first)
        let button = try #require(firstButton(in: container))
        #expect(tickLabel.text == "0")
        #expect(countLabel.text == "0")

        button.sendActions(for: .primaryActionTriggered)
        await waitUntil { countLabel.text == "1" }
        #expect(countLabel.text == "1")

        state.tick += 1

        await waitUntil { tickLabel.text == "1" }
        #expect(tickLabel.text == "1")
        #expect(countLabel.text == "1")
    }

    @Test func siblingStatesAreIndependent() async throws {
        let container = UIView()
        let fineUI = FineUI(()) { _ in
            FineStack.vertical {
                [
                    FineState(0) { count in
                        FineStack.vertical {
                            [
                                FineLabel(text: "\(count.value)"),
                                FineButton(title: "+") { count.value += 1 },
                            ]
                        }
                    },
                    FineState(10) { count in
                        FineStack.vertical {
                            [
                                FineLabel(text: "\(count.value)"),
                                FineButton(title: "+") { count.value += 1 },
                            ]
                        }
                    },
                ]
            }
        }
        fineUI.build(to: container)

        let initialLabels = labels(in: container)
        let firstCountLabel = try #require(initialLabels.first)
        let secondCountLabel = try #require(initialLabels.dropFirst().first)
        let firstButton = try #require(buttons(in: container).first)
        #expect(firstCountLabel.text == "0")
        #expect(secondCountLabel.text == "10")

        firstButton.sendActions(for: .primaryActionTriggered)

        await waitUntil { firstCountLabel.text == "1" }
        #expect(firstCountLabel.text == "1")
        #expect(secondCountLabel.text == "10")
    }
}
