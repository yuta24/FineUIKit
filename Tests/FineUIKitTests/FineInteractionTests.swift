import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
struct FineControlEnabledTests {
    @Observable
    final class FormState {
        var text: String = ""
        var isOn: Bool = false
        var volume: Float = 0.5
    }

    @Test func buttonEnabledAppliesAndResetsOnReuse() throws {
        let first = FineRenderer.render(FineButton(title: "A", action: {}).enabled(false))
        let button = try #require(first as? UIButton)

        #expect(button.isEnabled == false)

        let second = FineRenderer.render(FineButton(title: "A", action: {}), reusing: first)

        #expect(second === first)
        #expect(button.isEnabled == true)
    }

    @Test func textFieldEnabledAppliesAndResetsOnReuse() throws {
        let state = FormState()
        let first = FineRenderer.render(FineTextField(text: .init(state, \.text)).enabled(false))
        let textField = try #require(first as? UITextField)

        #expect(textField.isEnabled == false)

        let second = FineRenderer.render(FineTextField(text: .init(state, \.text)), reusing: first)

        #expect(second === first)
        #expect(textField.isEnabled == true)
    }

    @Test func toggleAndSliderEnabledApply() throws {
        let state = FormState()

        let toggle = FineRenderer.render(FineToggle(isOn: .init(state, \.isOn)).enabled(false))
        #expect((toggle as? UISwitch)?.isEnabled == false)

        let slider = FineRenderer.render(FineSlider(value: .init(state, \.volume)).enabled(false))
        #expect((slider as? UISlider)?.isEnabled == false)

        let reusedToggle = FineRenderer.render(FineToggle(isOn: .init(state, \.isOn)), reusing: toggle)
        #expect(reusedToggle === toggle)
        #expect((toggle as? UISwitch)?.isEnabled == true)
    }
}

@MainActor
struct FineTapGestureTests {
    @Test func onTapInstallsRecognizerAndEnablesInteraction() throws {
        var tapCount = 0
        let view = FineRenderer.render(FineLabel(text: "A").onTap { tapCount += 1 })

        #expect(view.isUserInteractionEnabled)
        #expect(view.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } == true)

        let box = try #require(view.fineTapHandlerBox)
        box.handler()
        #expect(tapCount == 1)
    }

    @Test func onTapReuseSwapsHandlerWithoutStackingRecognizers() throws {
        var firstCount = 0
        var secondCount = 0
        let first = FineRenderer.render(FineLabel(text: "A").onTap { firstCount += 1 })

        let second = FineRenderer.render(FineLabel(text: "B").onTap { secondCount += 1 }, reusing: first)

        #expect(second === first)
        #expect(first.gestureRecognizers?.count == 1)

        let box = try #require(first.fineTapHandlerBox)
        box.handler()

        #expect(firstCount == 0)
        #expect(secondCount == 1)
    }

    @Test func removingOnTapRebuildsView() {
        let first = FineRenderer.render(FineLabel(text: "A").onTap {})
        let second = FineRenderer.render(FineLabel(text: "B"), reusing: first)

        #expect(second !== first)
        #expect(second.fineTapHandlerBox == nil)
    }

    @Test func chainedOnTapRunsAllHandlersInOrder() throws {
        var order: [String] = []
        let view = FineRenderer.render(
            FineLabel(text: "A")
                .onTap { order.append("first") }
                .onTap { order.append("second") }
        )

        let box = try #require(view.fineTapHandlerBox)
        box.handler()

        #expect(order == ["first", "second"])
        #expect(view.gestureRecognizers?.count == 1)
    }

    @Test func nilActionKeepsViewAndRemovesHandler() throws {
        let first = FineRenderer.render(FineLabel(text: "A").onTap {})
        #expect(first.fineTapHandlerBox != nil)

        let second = FineRenderer.render(FineLabel(text: "B").onTap(nil), reusing: first)

        #expect(second === first)
        #expect(first.fineTapHandlerBox == nil)
        #expect(first.gestureRecognizers?.contains { $0 is UITapGestureRecognizer } != true)
    }

    @Test func recognizerDoesNotCancelControlTouches() throws {
        let view = FineRenderer.render(FineButton(title: "Tap", action: {}).onTap {})
        let recognizer = try #require(view.gestureRecognizers?.first { $0 is UITapGestureRecognizer })

        #expect(view is UIButton)
        #expect(recognizer.cancelsTouchesInView == false)
    }
}

@MainActor
struct FineTextFieldFocusTests {
    @Observable
    final class FocusModel {
        var text: String = ""
        var isFocused: Bool = false
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    @Test func userDrivenFocusChangesWriteBackToBinding() throws {
        let model = FocusModel()
        let view = FineRenderer.render(
            FineTextField(text: .init(model, \.text))
                .focused(.init(model, \.isFocused))
        )
        let textField = try #require(view as? UITextField)

        textField.sendActions(for: .editingDidBegin)
        #expect(model.isFocused == true)

        textField.sendActions(for: .editingDidEnd)
        #expect(model.isFocused == false)
    }

    @Test func focusBindingDrivesFirstResponder() async throws {
        let model = FocusModel()
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 200))
        window.makeKeyAndVisible()
        let container = UIView(frame: window.bounds)
        window.addSubview(container)

        let fineUI = FineUI(model) { model in
            FineTextField(text: .init(model, \.text))
                .focused(.init(model, \.isFocused))
        }
        fineUI.build(to: container)
        window.layoutIfNeeded()

        let textField = try #require(container.subviews.first as? UITextField)
        #expect(textField.isFirstResponder == false)

        model.isFocused = true

        await waitUntil { textField.isFirstResponder }
        #expect(textField.isFirstResponder)

        model.isFocused = false

        await waitUntil { !textField.isFirstResponder }
        #expect(textField.isFirstResponder == false)
        window.isHidden = true
    }

    @Test func initialFocusAppliesAfterAttachingToWindow() async throws {
        let model = FocusModel()
        model.isFocused = true

        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 200))
        window.makeKeyAndVisible()
        let container = UIView(frame: window.bounds)
        window.addSubview(container)

        let fineUI = FineUI(model) { model in
            FineTextField(text: .init(model, \.text))
                .focused(.init(model, \.isFocused))
        }
        // build renders before the view joins the window; the deferred focus
        // attempt must land once it does.
        fineUI.build(to: container)
        window.layoutIfNeeded()

        let textField = try #require(container.subviews.first as? UITextField)

        await waitUntil { textField.isFirstResponder }
        #expect(textField.isFirstResponder)
        window.isHidden = true
    }

    @Test func focusAppliesWhenWindowAttachHappensLate() async throws {
        let model = FocusModel()
        model.isFocused = true

        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let fineUI = FineUI(model) { model in
            FineTextField(text: .init(model, \.text))
                .focused(.init(model, \.isFocused))
        }
        fineUI.build(to: container)

        // Stay detached across several main-actor turns; a one-shot retry
        // would have given up by now.
        for _ in 0..<10 {
            await Task.yield()
        }

        let textField = try #require(container.subviews.first as? UITextField)
        #expect(textField.isFirstResponder == false)

        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 200))
        window.makeKeyAndVisible()
        window.addSubview(container)

        await waitUntil { textField.isFirstResponder }
        #expect(textField.isFirstResponder)
        window.isHidden = true
    }

    @Test func clearedFocusRequestDoesNotFireOnLaterAttach() async throws {
        let model = FocusModel()
        model.isFocused = true

        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let fineUI = FineUI(model) { model in
            FineTextField(text: .init(model, \.text))
                .focused(.init(model, \.isFocused))
        }
        fineUI.build(to: container)

        model.isFocused = false
        for _ in 0..<20 {
            await Task.yield()
        }

        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 200))
        window.makeKeyAndVisible()
        window.addSubview(container)
        for _ in 0..<20 {
            await Task.yield()
        }

        let textField = try #require(container.subviews.first as? UITextField)
        #expect(textField.isFirstResponder == false)
        window.isHidden = true
    }
}

@MainActor
struct FineSpacerConstraintTests {
    @Test func minLengthConstraintsYieldToRequiredContainerConstraints() throws {
        let spacer = FineRenderer.render(FineSpacer(minLength: 20))
        let minWidth = try #require(spacer.fineInstalledConstraints["spacer.minW"])
        let minHeight = try #require(spacer.fineInstalledConstraints["spacer.minH"])

        #expect(minWidth.priority == .init(999))
        #expect(minHeight.priority == .init(999))
    }
}

struct FineGridLayoutMathTests {
    @Test func adaptiveColumnCountAccountsForSpacing() {
        // 3 columns of >= 100 don't fit in 310 once two 8pt gaps are paid.
        #expect(FineGridLayoutMath.adaptiveColumnCount(width: 310, minimum: 100, spacing: 8) == 2)
        // 390: (390 - 2*8) / 3 = 124.6 per column, fits.
        #expect(FineGridLayoutMath.adaptiveColumnCount(width: 390, minimum: 100, spacing: 8) == 3)
    }

    @Test func adaptiveColumnCountNeverDropsBelowOne() {
        #expect(FineGridLayoutMath.adaptiveColumnCount(width: 50, minimum: 100, spacing: 8) == 1)
        #expect(FineGridLayoutMath.adaptiveColumnCount(width: 0, minimum: 0, spacing: 0) == 1)
    }

    @Test func adaptiveColumnCountSurvivesNegativeSpacing() {
        // minimum + spacing == 0 used to divide by zero and trap in Int(_:).
        #expect(FineGridLayoutMath.adaptiveColumnCount(width: 390, minimum: 1, spacing: -1) >= 1)
        #expect(FineGridLayoutMath.adaptiveColumnCount(width: 390, minimum: 100, spacing: -200) >= 1)
    }
}

struct FineEnvironmentEqualityTests {
    @Test func approximateEqualityComparesEquatableValues() {
        var first = FineEnvironmentValues()
        var second = FineEnvironmentValues()

        #expect(first.fineIsApproximatelyEqual(to: second))

        first.testAccent = "x"
        #expect(!first.fineIsApproximatelyEqual(to: second))

        second.testAccent = "x"
        #expect(first.fineIsApproximatelyEqual(to: second))

        second.testAccent = "y"
        #expect(!first.fineIsApproximatelyEqual(to: second))
    }
}

private struct TestAccentEnvironmentKey: FineEnvironmentKey {
    static let defaultValue = "default"
}

private extension FineEnvironmentValues {
    var testAccent: String {
        get { self[TestAccentEnvironmentKey.self] }
        set { self[TestAccentEnvironmentKey.self] = newValue }
    }
}

@MainActor
struct FineViewRepresentableTests {
    struct ProgressBar: FineViewRepresentable {
        let progress: Float

        func makeView() -> UIProgressView {
            UIProgressView(progressViewStyle: .default)
        }

        func updateView(_ view: UIProgressView, environment: FineEnvironmentValues) {
            if view.progress != progress {
                view.progress = progress
            }
        }
    }

    struct OtherProgressBar: FineViewRepresentable {
        func makeView() -> UIProgressView {
            UIProgressView(progressViewStyle: .default)
        }

        func updateView(_ view: UIProgressView, environment: FineEnvironmentValues) {}
    }

    final class AccentView: UIView {
        var accent: String = ""
    }

    struct AccentReader: FineViewRepresentable {
        func makeView() -> AccentView {
            AccentView(frame: .zero)
        }

        func updateView(_ view: AccentView, environment: FineEnvironmentValues) {
            view.accent = environment.testAccent
        }
    }

    struct ComposedRepresentable: FineViewRepresentable {
        func makeView() -> UIProgressView {
            UIProgressView(progressViewStyle: .default)
        }

        func updateView(_ view: UIProgressView, environment: FineEnvironmentValues) {}

        var body: any Renderable {
            FineLabel(text: "composed")
        }
    }

    @Test func customBodyOverrideWinsOverViewBridging() throws {
        let view = FineRenderer.render(ComposedRepresentable())
        let label = try #require(view as? UILabel)

        #expect(label.text == "composed")
    }

    @Test func rendersWrappedViewAndUpdatesInPlace() throws {
        let first = FineRenderer.render(ProgressBar(progress: 0.25))
        let progressView = try #require(first as? UIProgressView)

        #expect(progressView.progress == 0.25)

        let second = FineRenderer.render(ProgressBar(progress: 0.75), reusing: first)

        #expect(second === first)
        #expect(progressView.progress == 0.75)
    }

    @Test func differentRepresentableTypesDoNotShareViews() {
        let first = FineRenderer.render(ProgressBar(progress: 0.5))
        let second = FineRenderer.render(OtherProgressBar(), reusing: first)

        #expect(second !== first)
    }

    @Test func composesWithModifiers() throws {
        let view = FineRenderer.render(ProgressBar(progress: 0.5).padding(8))
        let paddingView = try #require(view as? FinePaddingView)

        #expect(paddingView.hosted is UIProgressView)
    }

    @Test func receivesInjectedEnvironment() throws {
        let view = FineRenderer.render(
            AccentReader().environment(\.testAccent, "pink")
        )
        let accentView = try #require(view as? AccentView)

        #expect(accentView.accent == "pink")
    }

    @Test func worksInsideStacksWithKeyedReuse() throws {
        let stack = FineRenderer.render(FineStack.vertical {
            ProgressBar(progress: 0.1).key("bar")
            FineLabel(text: "A")
        })
        let stackView = try #require(stack as? UIStackView)
        let original = stackView.arrangedSubviews[0]

        _ = FineRenderer.render(FineStack.vertical {
            FineLabel(text: "Header")
            ProgressBar(progress: 0.9).key("bar")
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 2)
        #expect(stackView.arrangedSubviews[1] === original)
        #expect((original as? UIProgressView)?.progress == 0.9)
    }

    @Observable
    final class ProgressModel {
        var progress: Float = 0.2
    }

    struct ObservingBar: FineViewRepresentable {
        let model: ProgressModel

        func makeView() -> UIProgressView {
            UIProgressView(progressViewStyle: .default)
        }

        func updateView(_ view: UIProgressView, environment: FineEnvironmentValues) {
            view.progress = model.progress
        }
    }

    @Test func observableReadsInUpdateViewRerenderNodeLocally() async throws {
        let model = ProgressModel()
        let container = UIView()
        var bodyEvaluationCount = 0

        let fineUI = FineUI(model) { model in
            bodyEvaluationCount += 1
            return FineStack.vertical {
                ObservingBar(model: model)
            }
        }
        fineUI.build(to: container)

        let stackView = try #require(container.subviews.first as? UIStackView)
        let progressView = try #require(stackView.arrangedSubviews.first as? UIProgressView)
        #expect(progressView.progress == 0.2)
        #expect(bodyEvaluationCount == 1)

        model.progress = 0.8

        for _ in 0..<100 where progressView.progress != 0.8 {
            await Task.yield()
        }

        #expect(progressView.progress == 0.8)
        #expect(bodyEvaluationCount == 1)
    }
}
