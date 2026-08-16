import Observation
import Testing
import UIKit
@testable import FineUIKit

@Observable
@MainActor
private final class AnimationState {
    var isFocused = false
    var isVisible = true
}

/// `.animation(_:)` says at the description that arriving at it is worth
/// watching, so nothing at the mutation has to know.
@MainActor
@Suite(.serialized)
struct FineDeclarativeAnimationTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    private func waitTicks(_ count: Int = 40) async {
        for _ in 0..<count {
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

    private func attachToWindow(_ view: UIView) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 480))
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
        return window
    }

    // MARK: - transforms

    @Test func scaleAndOffsetComposeIntoOneTransform() throws {
        let view = FineRenderer.render(
            FineLabel(text: "A")
                .scale(2)
                .offset(x: 10, y: 0)
        )

        // Offset before scale, so moving by 10 moves by 10 whatever the scale.
        #expect(view.transform.a == 2)
        #expect(view.transform.tx == 10)
    }

    /// Two transform modifiers are two asks about the same view however far
    /// apart they are written. Another modifier between them is not a reason
    /// for the outer one to forget the inner.
    @Test func transformsComposeThroughAModifierBetweenThem() throws {
        let view = FineRenderer.render(
            FineLabel(text: "A")
                .scale(2)
                .backgroundColor(.red)
                .offset(x: 10, y: 0)
        )

        #expect(view.transform.a == 2)
        #expect(view.transform.tx == 10)
    }

    @Test func aChangedTransformIsWrittenWithoutRebuildingTheView() throws {
        let view = FineRenderer.render(FineLabel(text: "A").scale(1))
        #expect(view.transform.a == 1)

        let again = FineRenderer.render(FineLabel(text: "A").scale(1.5), reusing: view)

        // A value change must not change the modifier signature, or every frame
        // of an animation would rebuild the view it is animating.
        #expect(again === view)
        #expect(view.transform.a == 1.5)
    }

    @Test func addingATransformRebuildsSoTheOldOneCannotLinger() throws {
        let view = FineRenderer.render(FineLabel(text: "A").scale(2))
        let again = FineRenderer.render(FineLabel(text: "A"), reusing: view)

        #expect(again !== view)
        #expect(again.transform == .identity)
    }

    // MARK: - animation

    /// The mutation says nothing about animating; the description does.
    @Test func aDescribedAnimationHoldsAChangeTheMutationSaysNothingAbout() async throws {
        let state = AnimationState()
        let container = UIView()
        let ui = FineUI(state: state) { state in
            FineLabel(text: "A")
                .scale(state.isFocused ? 1.4 : 1)
                .animation(.linear(duration: 2))
        }
        let window = attachToWindow(container)
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let label = try #require(container.subviews.first)
        label.layer.removeAllAnimations()

        // No `withFineAnimation` here — the description already asked for it.
        state.isFocused = true

        await waitUntil { (label.layer.animationKeys() ?? []).contains("transform") }

        #expect((label.layer.animationKeys() ?? []).contains("transform"))
        _ = window
    }

    /// There is nothing to come from on the way in, so a first render arrives
    /// as described rather than growing into it.
    @Test func theFirstRenderIsNotAnimated() async throws {
        let state = AnimationState()
        let container = UIView()
        let ui = FineUI(state: state) { _ in
            FineLabel(text: "A")
                .scale(1.4)
                .animation(.linear(duration: 2))
        }
        let window = attachToWindow(container)
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let label = try #require(container.subviews.first)

        #expect((label.layer.animationKeys() ?? []).isEmpty)
        #expect(label.transform.a == 1.4)
        _ = window
    }

    /// A container carrying the ask animates the children that change, not just
    /// itself. Its own update hands them to the scheduler and returns, so a
    /// block opened around it would be shut before they were written to.
    @Test func anAnimationOnAContainerReachesTheChildThatChanges() async throws {
        let state = AnimationState()
        let container = UIView()
        let ui = FineUI(state: state) { state in
            FineStack.vertical {
                FineLabel(text: "A")
                    .scale(state.isFocused ? 1.4 : 1)
            }
            .animation(.linear(duration: 2))
        }
        let window = attachToWindow(container)
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let stack = try #require(container.subviews.first as? UIStackView)
        let label = try #require(stack.arrangedSubviews.first)
        label.layer.removeAllAnimations()

        state.isFocused = true
        await waitUntil { (label.layer.animationKeys() ?? []).contains("transform") }

        #expect((label.layer.animationKeys() ?? []).contains("transform"))
        _ = window
    }

    /// A description asking to animate does not overrule a caller who said not
    /// to. `withFineAnimation(nil)` means not now, whatever the tree wants.
    @Test func anExplicitlyDisabledMutationOverrulesTheDescription() async throws {
        let state = AnimationState()
        let container = UIView()
        let ui = FineUI(state: state) { state in
            FineLabel(text: "A")
                .scale(state.isFocused ? 1.4 : 1)
                .animation(.linear(duration: 2))
        }
        let window = attachToWindow(container)
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let label = try #require(container.subviews.first)
        label.layer.removeAllAnimations()

        withFineAnimation(nil) {
            state.isFocused = true
        }
        await waitTicks()

        #expect((label.layer.animationKeys() ?? []).isEmpty)
        #expect(label.transform.a == 1.4)
        _ = window
    }

    /// The catch-up after `resume()` is the same answer for the same reason:
    /// changes that happened off screen were never seen to leave, so they must
    /// not be seen to arrive.
    @Test func theCatchUpAfterResumeOverrulesTheDescription() async throws {
        let state = AnimationState()
        let container = UIView()
        let ui = FineUI(state: state) { state in
            FineLabel(text: "A")
                .scale(state.isFocused ? 1.4 : 1)
                .animation(.linear(duration: 2))
        }
        let window = attachToWindow(container)
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let label = try #require(container.subviews.first)
        label.layer.removeAllAnimations()

        ui.suspend()
        state.isFocused = true
        await waitTicks()

        ui.resume()
        await waitUntil { label.transform.a == 1.4 }

        #expect((label.layer.animationKeys() ?? []).isEmpty)
        _ = window
    }

    /// A cell handed a different row is showing that row for the first time,
    /// whatever the view it is reusing has been through.
    @Test func aRowArrivingInAReusedCellIsNotAnimatedIntoPlace() throws {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 120))
        window.isHidden = false
        let cell = FineListHostCell(style: .default, reuseIdentifier: FineListHostCell.reuseIdentifier)
        cell.frame = window.bounds
        window.addSubview(cell)
        let environment = FineEnvironmentStorage()

        func row(_ scale: CGFloat) -> any Renderable {
            FineLabel(text: "row")
                .scale(scale)
                .animation(.linear(duration: 2))
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil) { row(1.4) }
        window.layoutIfNeeded()

        let label = try #require(firstLabel(in: cell))
        label.layer.removeAllAnimations()

        cell.render(identity: AnyHashable(2), environment: environment, renderGate: nil) { row(1) }
        window.layoutIfNeeded()

        #expect((label.layer.animationKeys() ?? []).isEmpty)
        #expect(label.transform.a == 1)
        _ = window
    }

    /// A description asking for a slow animation gets one, even when the
    /// mutation that triggered it was wrapped in something faster. UIKit hands
    /// a nested animation the outer timing by default, which is right for a
    /// block written by hand and wrong for a description that named its own.
    @Test func aDescribedDurationSurvivesAFasterEnclosingOne() async throws {
        let state = AnimationState()
        let container = UIView()
        let ui = FineUI(state: state) { state in
            FineLabel(text: "A")
                .scale(state.isFocused ? 2 : 1)
                .animation(.linear(duration: 4))
        }
        let window = attachToWindow(container)
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let label = try #require(container.subviews.first)
        label.layer.removeAllAnimations()

        withFineAnimation(.linear(duration: 0.05)) {
            state.isFocused = true
        }
        await waitUntil { !(label.layer.animationKeys() ?? []).isEmpty }

        let animation = try #require(label.layer.animation(forKey: "transform"))
        #expect(animation.duration == 4)
        _ = window
    }

    /// `nil` holds a subtree still while the mutation around it animates.
    @Test func aNilAnimationOptsASubtreeOutOfAnAnimatedMutation() async throws {
        let state = AnimationState()
        let container = UIView()
        let ui = FineUI(state: state) { state in
            FineStack.vertical {
                FineLabel(text: "held")
                    .scale(state.isFocused ? 1.4 : 1)
                    .animation(nil)
            }
        }
        let window = attachToWindow(container)
        ui.build(to: container)
        window.layoutIfNeeded()
        await waitTicks()

        let stack = try #require(container.subviews.first as? UIStackView)
        let label = try #require(stack.arrangedSubviews.first)
        label.layer.removeAllAnimations()

        withFineAnimation(.linear(duration: 2)) {
            state.isFocused = true
        }
        await waitTicks()

        #expect((label.layer.animationKeys() ?? []).isEmpty)
        #expect(label.transform.a == 1.4)
        _ = window
    }
}
