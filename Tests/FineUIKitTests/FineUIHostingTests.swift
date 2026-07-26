import Observation
import Testing
import UIKit
@testable import FineUIKit

@Observable
@MainActor
private final class HostingModel {
    var title = "first"
}

/// Covers the contract of `FineUI.build(to:)`: which container the tree ends
/// up in, and that it keeps working after it moves.
@MainActor
@Suite(.serialized)
struct FineUIHostingTests {
    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 480))
        window.makeKeyAndVisible()
        return window
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    @Test func buildingToAnotherContainerMovesTheTree() async throws {
        let model = HostingModel()
        let window = makeWindow()
        let first = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let second = UIView(frame: .init(x: 0, y: 200, width: 200, height: 280))
        window.addSubview(first)
        window.addSubview(second)

        let fineUI = FineUI(model) { model in
            FineLabel(text: model.title)
        }
        fineUI.build(to: first)
        window.layoutIfNeeded()

        let label = try #require(first.subviews.first as? UILabel)
        #expect(label.text == "first")

        fineUI.build(to: second)
        window.layoutIfNeeded()

        // The root view is reusable, so the same instance must move rather than
        // stay behind in the container it was built into first.
        #expect(second.subviews.first === label)
        #expect(first.subviews.isEmpty)
        #expect(label.superview === second)
        #expect(label.text == "first")

        window.isHidden = true
    }

    @Test func movedTreeIsConstrainedToTheNewContainer() async throws {
        let model = HostingModel()
        let window = makeWindow()
        let first = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let second = UIView(frame: .init(x: 0, y: 200, width: 200, height: 280))
        window.addSubview(first)
        window.addSubview(second)

        let fineUI = FineUI(model) { _ in
            FineStack.vertical {
                FineSpacer()
            }
        }
        fineUI.build(to: first)
        window.layoutIfNeeded()

        let root = try #require(first.subviews.first)
        #expect(root.bounds.width == 320)

        fineUI.build(to: second)
        window.layoutIfNeeded()

        // Width follows the new container, which only holds if the constraints
        // were rebuilt against it.
        #expect(root.bounds.width == 200)
        // Constraints pinning the root to the old container must not survive.
        // Emptiness is the wrong bar: touching `keyboardLayoutGuide` makes
        // UIKit install constraints of its own on the container.
        let staleConstraints = first.constraints.filter { constraint in
            constraint.firstItem === root || constraint.secondItem === root
        }
        #expect(staleConstraints.isEmpty)

        window.isHidden = true
    }

    @Test func movedTreeKeepsRespondingToStateChanges() async throws {
        let model = HostingModel()
        let window = makeWindow()
        let first = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let second = UIView(frame: .init(x: 0, y: 200, width: 320, height: 280))
        window.addSubview(first)
        window.addSubview(second)

        let fineUI = FineUI(model) { model in
            FineLabel(text: model.title)
        }
        fineUI.build(to: first)
        window.layoutIfNeeded()

        fineUI.build(to: second)
        window.layoutIfNeeded()

        let label = try #require(second.subviews.first as? UILabel)
        model.title = "second"

        await waitUntil { label.text == "second" }
        #expect(label.text == "second")
        #expect(label.superview === second)

        window.isHidden = true
    }

    @Test func buildingTwiceToTheSameContainerKeepsOneRootView() async throws {
        let model = HostingModel()
        let window = makeWindow()
        let container = UIView(frame: window.bounds)
        window.addSubview(container)

        let fineUI = FineUI(model) { model in
            FineLabel(text: model.title)
        }
        fineUI.build(to: container)
        window.layoutIfNeeded()

        let label = try #require(container.subviews.first as? UILabel)
        let constraintCount = container.constraints.count

        fineUI.build(to: container)
        window.layoutIfNeeded()

        #expect(container.subviews.count == 1)
        #expect(container.subviews.first === label)
        // Re-rendering into the same container must not stack up another set of
        // pinning constraints.
        #expect(container.constraints.count == constraintCount)

        window.isHidden = true
    }

    @Test func traitChangesFollowTheNewContainer() async throws {
        let model = HostingModel()
        let window = makeWindow()
        let first = UIView(frame: window.bounds)
        let second = UIView(frame: window.bounds)
        window.addSubview(first)
        window.addSubview(second)

        let fineUI = FineUI(model) { model in
            FineEnvironmentReader { environment in
                FineLabel(text: "\(model.title)-\(environment.traitCollection.preferredContentSizeCategory.rawValue)")
            }
        }
        fineUI.build(to: first)
        window.layoutIfNeeded()

        fineUI.build(to: second)
        window.layoutIfNeeded()

        second.traitOverrides.preferredContentSizeCategory = .accessibilityLarge

        await waitUntil {
            (second.subviews.first?.subviews.first as? UILabel)?
                .text?.contains("AccessibilityL") == true
        }

        let label = try #require(second.subviews.first?.subviews.first as? UILabel)
        #expect(label.text?.contains("AccessibilityL") == true)

        window.isHidden = true
    }
}
