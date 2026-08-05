import Observation
import Testing
import UIKit
@testable import FineUIKit

/// Where a composite's `body` is evaluated decides which observation scope its
/// reads belong to. A read deferred into `_update` by an `@autoclosure` is
/// always tracked, so these read in `body` itself and branch on the result.
@Observable
@MainActor
private final class BranchingModel {
    var isOn = false
}

@MainActor
private struct BranchingComposite: Renderable {
    let model: BranchingModel

    var body: any Renderable {
        if self.model.isOn {
            FineLabel(text: "on")
        } else {
            FineImage(image: UIImage())
        }
    }
}

@MainActor
private final class RootComposite: FineContent {
    let model: BranchingModel

    init(model: BranchingModel) {
        self.model = model
    }

    func body() -> any Renderable {
        BranchingComposite(model: model)
    }
}

@MainActor
private final class NestedComposite: FineContent {
    let model: BranchingModel

    init(model: BranchingModel) {
        self.model = model
    }

    func body() -> any Renderable {
        FineStack.vertical {
            BranchingComposite(model: self.model)
        }
    }
}

@MainActor
@Suite(.serialized)
struct FineCompositeObservationTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    private func hasLabel(in view: UIView) -> Bool {
        if view is UILabel { return true }
        return view.subviews.contains { hasLabel(in: $0) }
    }

    /// The root case is the one that needed fixing: resolution happens in
    /// `FineUI.render()`, and it has to sit inside the tracking or the read
    /// belongs to no scope and the tree never updates again.
    @Test func aReadInACompositeAtTheRootIsTracked() async throws {
        let model = BranchingModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let fineUI = FineUI(RootComposite(model: model))
        fineUI.build(to: container)

        #expect(hasLabel(in: container) == false)

        model.isOn = true
        await waitUntil { self.hasLabel(in: container) }

        #expect(hasLabel(in: container) == true)
    }

    /// Deeper in the tree the walk already happens inside a node's `_update`,
    /// which the scheduler tracks.
    @Test func aReadInACompositeInsideAContainerIsTracked() async throws {
        let model = BranchingModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 480))
        let fineUI = FineUI(NestedComposite(model: model))
        fineUI.build(to: container)

        #expect(hasLabel(in: container) == false)

        model.isOn = true
        await waitUntil { self.hasLabel(in: container) }

        #expect(hasLabel(in: container) == true)
    }
}
