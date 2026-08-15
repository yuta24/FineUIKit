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

/// Equatable and unchanged, so a catch-up render does not reconfigure the row —
/// which is the case that leaves the cell to recover for itself.
private struct ReasonRow: Identifiable, Equatable {
    let id: Int
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

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, !(view.superview is UIButton) {
            return label
        }

        for subview in view.subviews {
            if let label = firstLabel(in: subview) {
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

        let labelView = try #require(firstLabel(in: container))
        #expect(labelView.fineNode.lastUpdateReason == .initial)

        state.title = "B"
        await waitUntil { labelView.text == "B" }

        #expect(labelView.fineNode.lastUpdateReason == .observation)
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
        let labelView = try #require(firstLabel(in: container))

        state.bodyValue += 1
        await waitUntil { labelView.text == "1" }

        #expect(stack.fineNode.lastUpdateReason == .observation)
        #expect(labelView.fineNode.lastUpdateReason == .parent)
    }

    /// A catch-up render answers for a change that happened while nobody was
    /// looking, and says so. Left to the default the root would claim its parent
    /// re-rendered, and there is nothing above the root.
    @Test func aCatchUpRenderNamesTheObservationItIsCatchingUpOn() async throws {
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

        ui.suspend()
        state.bodyValue += 1
        await waitTicks()

        ui.resume()
        await waitUntil { self.firstLabel(in: container)?.text == "1" }

        #expect(stack.fineNode.lastUpdateReason == .observation)
    }

    /// A cell that recovers for itself is answering for an observation too.
    ///
    /// Its scope is not on the catch-up render's walk — an unchanged row is not
    /// reconfigured — so it hands in its own recovery, which `resume()` runs
    /// after the catch-up. That is a second render, and it needs a reason of its
    /// own: the one the catch-up was given has already been claimed.
    @Test func aCellRecoveringForItselfNamesTheObservation() async throws {
        let model = ReasonState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state: model) { model in
            FineList([ReasonRow(id: 1)]) { _ in
                // Read while building the row, so the cell's own scope is what
                // goes stale — the node-local path recovers separately.
                let title = model.title
                return FineLabel(text: title)
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        ui.suspend()
        model.title = "B"
        await waitTicks()

        ui.resume()
        await waitUntil {
            window.layoutIfNeeded()
            return self.firstLabel(in: container)?.text == "B"
        }

        let labelView = try #require(firstLabel(in: container))
        #expect(labelView.fineNode.lastUpdateReason == .observation)
        _ = window
    }

    /// A node recovering for itself already knows why it is running, so the
    /// reason handed to the recovery is spare — and a spare reason is taken by
    /// the first child the node goes on to render, which is there because its
    /// parent ran and nothing else.
    @Test func aNodeRecoveringForItselfDoesNotPassItsReasonToItsChildren() async throws {
        let model = ReasonState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state: model) { model in
            FineList([ReasonRow(id: 1)]) { _ in
                FineStack.vertical {
                    // Read while the stack's builder runs, so the stack's own
                    // node is the scope that goes stale — not the cell host's.
                    let title = model.title
                    FineLabel(text: title)
                }
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        ui.suspend()
        model.title = "B"
        await waitTicks()

        ui.resume()
        await waitUntil {
            window.layoutIfNeeded()
            return self.firstLabel(in: container)?.text == "B"
        }

        let labelView = try #require(firstLabel(in: container))
        let stack = try #require(labelView.superview)

        #expect(stack.fineNode.lastUpdateReason == .observation)
        #expect(labelView.fineNode.lastUpdateReason == .parent)
        _ = window
    }

    /// A reason nobody claims must not be left lying around for the next render
    /// to pick up. A tree whose container has gone returns before it reaches a
    /// node, which is the case that leaves one behind.
    @Test func aReasonNoNodeClaimsDoesNotLeakIntoTheNextRender() async throws {
        let state = ReasonState()
        var container: UIView? = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let ui = FineUI(state: state) { state in
            // Read in the root body rather than through a component's
            // autoclosure: this has to be the root scope that re-renders, since
            // a node-local update never goes near the reason being tested.
            let value = state.bodyValue
            return FineLabel(text: "\(value)")
        }
        ui.build(to: container!)
        container?.layoutIfNeeded()
        await waitTicks()

        // The container goes, so the next render returns without touching a
        // node — and whatever reason it was given goes nowhere.
        container = nil
        state.bodyValue += 1
        await waitTicks()

        // An unrelated render must still describe itself truthfully.
        let fresh = FineRenderer.render(FineLabel(text: "fresh"))

        #expect(fresh.fineNode.lastUpdateReason == .initial)
    }

    /// That a cost was recorded at all, which is the claim. Asking for a
    /// positive one would be asking the clock to tick during a `UILabel`
    /// update, and a render fast enough to fit inside its resolution is a
    /// render working correctly.
    @Test func everyRenderRecordsWhatItCost() throws {
        let view = FineRenderer.render(FineLabel(text: "A"))

        let duration = try #require(view.fineNode.lastUpdateDuration)
        #expect(duration >= .zero)
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
