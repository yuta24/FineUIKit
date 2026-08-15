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
