import Observation
import Testing
import UIKit
@testable import FineUIKit

@Observable
@MainActor
private final class ReasonState {
    var title = "A"
    var bodyValue = 0
}

/// Why a node rendered, which is the question a diff-based runtime is worst at
/// answering from the code alone.
@MainActor
@Suite(.serialized)
struct FineUpdateReasonTests {
    private func waitTicks(_ count: Int = 40) async {
        for _ in 0..<count {
            await Task.yield()
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    private func label(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, !(view.superview is UIButton) {
            return label
        }

        for subview in view.subviews {
            if let label = label(in: subview) {
                return label
            }
        }

        return nil
    }

    @Test func aFirstRenderSaysSo() throws {
        let view = FineRenderer.render(FineLabel(text: "A"))

        #expect(view.fineNode.lastUpdateReason == .initial)
    }

    @Test func rerenderingFromAboveNamesTheParent() throws {
        let view = FineRenderer.render(FineLabel(text: "A"))
        _ = FineRenderer.render(FineLabel(text: "B"), reusing: view)

        #expect(view.fineNode.lastUpdateReason == .parent)
    }

    /// The valuable one: this node ran on its own because something it read
    /// changed, rather than because anything above it did.
    @Test func aNodeThatUpdatesOnItsOwnNamesTheObservation() async throws {
        let state = ReasonState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state: state) { state in
            FineStack.vertical {
                FineLabel(text: state.title)
            }
        }
        ui.build(to: container)
        container.layoutIfNeeded()
        await waitTicks()

        let label = try #require(label(in: container))
        #expect(label.fineNode.lastUpdateReason == .initial)

        state.title = "B"
        await waitUntil { label.text == "B" }

        #expect(label.fineNode.lastUpdateReason == .observation)
        // The stack above it did not re-run: nothing it read changed.
        #expect(container.subviews.first?.fineNode.lastUpdateReason == .initial)
    }

    /// A read in the root `body` re-runs the tree, and the node the change
    /// arrived at reports the observation while its children report the parent.
    @Test func aRootScopeChangeNamesTheObservationOnlyAtTheTop() async throws {
        let state = ReasonState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state: state) { state in
            let value = state.bodyValue
            return FineStack.vertical {
                FineLabel(text: "\(value)")
            }
        }
        ui.build(to: container)
        container.layoutIfNeeded()
        await waitTicks()

        let stack = try #require(container.subviews.first)
        let label = try #require(label(in: container))

        state.bodyValue += 1
        await waitUntil { label.text == "1" }

        #expect(stack.fineNode.lastUpdateReason == .observation)
        #expect(label.fineNode.lastUpdateReason == .parent)
    }

    @Test func everyRenderRecordsWhatItCost() throws {
        let view = FineRenderer.render(FineLabel(text: "A"))

        let duration = try #require(view.fineNode.lastUpdateDuration)
        #expect(duration > .zero)
    }

    @Test func theDebugDescriptionCarriesTheReason() throws {
        let view = FineRenderer.render(FineLabel(text: "A"))

        #expect(view.fineDebugDescription.contains("because it is new here"))

        _ = FineRenderer.render(FineLabel(text: "B"), reusing: view)

        #expect(view.fineDebugDescription.contains("because its parent re-rendered"))
    }
}

@MainActor
struct FineDurationFormattingTests {
    @Test func picksTheUnitThatKeepsTheNumberSmall() {
        #expect(fineFormatted(.nanoseconds(750)) == "750 ns")
        #expect(fineFormatted(.microseconds(180)) == "180.00 µs")
        #expect(fineFormatted(.milliseconds(3)) == "3.00 ms")
    }
}
