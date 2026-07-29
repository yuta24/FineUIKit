import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
@Observable
final class ComponentState {
    var index: Int = 0
    var amount: Double = 1
    var progress: Float = 0
    var isLoading: Bool = false
    var date: Date = .init(timeIntervalSince1970: 0)
    var page: Int = 0
    var note: String = ""
    var isFocused: Bool = false
}

@MainActor
struct FineSegmentedControlTests {
    @Test func rendersTitlesAndSelectsTheBoundIndex() throws {
        let state = ComponentState()
        state.index = 1

        let view = FineRenderer.render(
            FineSegmentedControl(titles: ["A", "B"], selection: .init(state, \.index))
        )
        let control = try #require(view as? UISegmentedControl)

        #expect(control.numberOfSegments == 2)
        #expect(control.titleForSegment(at: 0) == "A")
        #expect(control.selectedSegmentIndex == 1)
    }

    @Test func segmentsReconcileInPlace() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FineSegmentedControl(titles: ["A", "B", "C"], selection: .init(state, \.index))
        )
        let control = try #require(first as? UISegmentedControl)

        let second = FineRenderer.render(
            FineSegmentedControl(titles: ["A2", "B"], selection: .init(state, \.index)),
            reusing: first
        )

        #expect(second === first)
        #expect(control.numberOfSegments == 2)
        #expect(control.titleForSegment(at: 0) == "A2")
        #expect(control.titleForSegment(at: 1) == "B")
    }

    @Test func imageSegmentReplacesATitleSegment() throws {
        let state = ComponentState()
        let image = UIImage(systemName: "star")!
        let first = FineRenderer.render(
            FineSegmentedControl(titles: ["A"], selection: .init(state, \.index))
        )
        let control = try #require(first as? UISegmentedControl)

        _ = FineRenderer.render(
            FineSegmentedControl(segments: [.image(image)], selection: .init(state, \.index)),
            reusing: first
        )

        #expect(control.titleForSegment(at: 0) == nil)
        #expect(control.imageForSegment(at: 0) === image)
    }

    @Test func anEqualImageDerivedPerRenderIsNotReapplied() throws {
        let state = ComponentState()
        let image = UIImage(systemName: "star")!.withRenderingMode(.alwaysTemplate)
        let first = FineRenderer.render(
            FineSegmentedControl(segments: [.image(image)], selection: .init(state, \.index))
        )
        let control = try #require(first as? UISegmentedControl)
        let applied = control.imageForSegment(at: 0)

        // A description that derives its image per render hands over a fresh
        // instance; an equal one must not re-enter `setImage`.
        _ = FineRenderer.render(
            FineSegmentedControl(
                segments: [.image(UIImage(systemName: "star")!.withRenderingMode(.alwaysTemplate))],
                selection: .init(state, \.index)
            ),
            reusing: first
        )

        #expect(control.imageForSegment(at: 0) === applied)
    }

    @Test func selectionOutsideTheSegmentsShowsNothingSelected() throws {
        let state = ComponentState()
        state.index = 5

        let view = FineRenderer.render(
            FineSegmentedControl(titles: ["A", "B"], selection: .init(state, \.index))
        )
        let control = try #require(view as? UISegmentedControl)

        #expect(control.selectedSegmentIndex == UISegmentedControl.noSegment)
    }

    @Test func userSelectionWritesBackToTheBinding() throws {
        let state = ComponentState()
        let view = FineRenderer.render(
            FineSegmentedControl(titles: ["A", "B"], selection: .init(state, \.index))
        )
        let control = try #require(view as? UISegmentedControl)

        control.selectedSegmentIndex = 1
        control.sendActions(for: .valueChanged)

        #expect(state.index == 1)
    }

    @Test func enabledResetsOnReuse() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FineSegmentedControl(titles: ["A"], selection: .init(state, \.index)).enabled(false)
        )
        let control = try #require(first as? UISegmentedControl)

        #expect(control.isEnabled == false)

        _ = FineRenderer.render(
            FineSegmentedControl(titles: ["A"], selection: .init(state, \.index)),
            reusing: first
        )

        #expect(control.isEnabled == true)
    }
}

@MainActor
struct FineStepperTests {
    @Test func appliesRangeStepAndValue() throws {
        let state = ComponentState()
        state.amount = 4

        let view = FineRenderer.render(
            FineStepper(value: .init(state, \.amount), in: 0...10, step: 2)
        )
        let stepper = try #require(view as? UIStepper)

        #expect(stepper.minimumValue == 0)
        #expect(stepper.maximumValue == 10)
        #expect(stepper.stepValue == 2)
        #expect(stepper.value == 4)
    }

    @Test func rangeMovingEntirelyUpwardsKeepsBothBounds() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FineStepper(value: .init(state, \.amount), in: 0...100)
        )
        let stepper = try #require(first as? UIStepper)

        state.amount = 250
        _ = FineRenderer.render(
            FineStepper(value: .init(state, \.amount), in: 200...300),
            reusing: first
        )

        #expect(stepper.minimumValue == 200)
        #expect(stepper.maximumValue == 300)
        #expect(stepper.value == 250)
    }

    @Test func steppingWritesBackToTheBinding() throws {
        let state = ComponentState()
        let view = FineRenderer.render(
            FineStepper(value: .init(state, \.amount), in: 0...10)
        )
        let stepper = try #require(view as? UIStepper)

        stepper.value = 3
        stepper.sendActions(for: .valueChanged)

        #expect(state.amount == 3)
    }

    @Test func enabledResetsOnReuse() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FineStepper(value: .init(state, \.amount)).enabled(false)
        )
        let stepper = try #require(first as? UIStepper)

        #expect(stepper.isEnabled == false)

        _ = FineRenderer.render(FineStepper(value: .init(state, \.amount)), reusing: first)

        #expect(stepper.isEnabled == true)
    }
}

@MainActor
struct FineProgressViewTests {
    @Test func reportsTheFractionOfTotal() throws {
        let view = FineRenderer.render(FineProgressView(value: 5, total: 10))
        let progressView = try #require(view as? UIProgressView)

        #expect(progressView.progress == 0.5)
    }

    @Test func clampsOutOfRangeValues() throws {
        let over = FineRenderer.render(FineProgressView(value: 3, total: 2))
        #expect((over as? UIProgressView)?.progress == 1)

        let under = FineRenderer.render(FineProgressView(value: -1))
        #expect((under as? UIProgressView)?.progress == 0)

        let zeroTotal = FineRenderer.render(FineProgressView(value: 1, total: 0))
        #expect((zeroTotal as? UIProgressView)?.progress == 0)
    }

    @Test func anUndefinedFractionShowsAnEmptyBarRatherThanAFullOne() throws {
        // UIProgressView clamps a NaN progress to 1.0, so an upstream 0/0 would
        // otherwise read as "complete".
        let view = FineRenderer.render(FineProgressView(value: .nan))
        #expect((view as? UIProgressView)?.progress == 0)
    }

    @Test func styleAndTintResetOnReuse() throws {
        let first = FineRenderer.render(
            FineProgressView(value: 0.5)
                .progressViewStyle(.bar)
                .progressTintColor(.systemRed)
        )
        let progressView = try #require(first as? UIProgressView)

        #expect(progressView.progressViewStyle == .bar)
        #expect(progressView.progressTintColor == .systemRed)

        let second = FineRenderer.render(FineProgressView(value: 0.25), reusing: first)

        #expect(second === first)
        #expect(progressView.progressViewStyle == .default)
        #expect(progressView.progressTintColor == nil)
        #expect(progressView.progress == 0.25)
    }

    @MainActor
    final class BodyCounter {
        var count = 0
    }

    @Test func valueIsReadInsideTheNodeSoTheBodyIsNotReevaluated() async throws {
        let state = ComponentState()
        let counter = BodyCounter()

        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let fineUI = FineUI(state) { state in
            counter.count += 1
            return FineProgressView(value: state.progress)
        }
        fineUI.build(to: container)

        let evaluationsAfterBuild = counter.count
        let progressView = try #require(container.subviews.first as? UIProgressView)

        state.progress = 0.75

        for _ in 0..<200 where progressView.progress != 0.75 {
            await Task.yield()
        }

        #expect(progressView.progress == 0.75)
        #expect(counter.count == evaluationsAfterBuild)
    }
}

@MainActor
struct FineActivityIndicatorTests {
    @Test func startsAndStopsWithTheDescription() throws {
        let state = ComponentState()
        state.isLoading = true

        let first = FineRenderer.render(FineActivityIndicator(isAnimating: state.isLoading))
        let indicator = try #require(first as? UIActivityIndicatorView)

        #expect(indicator.isAnimating)

        state.isLoading = false
        let second = FineRenderer.render(
            FineActivityIndicator(isAnimating: state.isLoading),
            reusing: first
        )

        #expect(second === first)
        #expect(indicator.isAnimating == false)
    }

    @Test func styleAndHidesWhenStoppedResetOnReuse() throws {
        let first = FineRenderer.render(
            FineActivityIndicator(isAnimating: false)
                .style(.large)
                .hidesWhenStopped(false)
        )
        let indicator = try #require(first as? UIActivityIndicatorView)

        #expect(indicator.style == .large)
        #expect(indicator.hidesWhenStopped == false)

        _ = FineRenderer.render(FineActivityIndicator(isAnimating: false), reusing: first)

        #expect(indicator.style == .medium)
        #expect(indicator.hidesWhenStopped == true)
    }

    @Test func droppingTheColorRebuildsTheView() throws {
        let first = FineRenderer.render(FineActivityIndicator().color(.systemPink))
        #expect((first as? UIActivityIndicatorView)?.color == .systemPink)

        let second = FineRenderer.render(FineActivityIndicator(), reusing: first)

        #expect(second !== first)
    }
}

@MainActor
struct FineDatePickerTests {
    @Test func appliesSelectionRangeAndMode() throws {
        let state = ComponentState()
        let lower = Date(timeIntervalSince1970: -1000)
        let upper = Date(timeIntervalSince1970: 1000)

        let view = FineRenderer.render(
            FineDatePicker(selection: .init(state, \.date), in: lower...upper)
                .datePickerMode(.date)
        )
        let picker = try #require(view as? UIDatePicker)

        #expect(picker.date == state.date)
        #expect(picker.minimumDate == lower)
        #expect(picker.maximumDate == upper)
        #expect(picker.datePickerMode == .date)
    }

    @Test func rangeAndModeResetOnReuse() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FineDatePicker(
                selection: .init(state, \.date),
                in: Date(timeIntervalSince1970: -1000)...Date(timeIntervalSince1970: 1000)
            )
            .datePickerMode(.date)
        )
        let picker = try #require(first as? UIDatePicker)

        let second = FineRenderer.render(
            FineDatePicker(selection: .init(state, \.date)),
            reusing: first
        )

        #expect(second === first)
        #expect(picker.minimumDate == nil)
        #expect(picker.maximumDate == nil)
        #expect(picker.datePickerMode == .dateAndTime)
    }

    @Test func userSelectionWritesBackToTheBinding() throws {
        let state = ComponentState()
        let view = FineRenderer.render(FineDatePicker(selection: .init(state, \.date)))
        let picker = try #require(view as? UIDatePicker)

        let picked = Date(timeIntervalSince1970: 86_400)
        picker.date = picked
        picker.sendActions(for: .valueChanged)

        #expect(state.date == picked)
    }
}

@MainActor
struct FinePageControlTests {
    @Test func appliesPageCountAndCurrentPage() throws {
        let state = ComponentState()
        state.page = 2

        let view = FineRenderer.render(
            FinePageControl(numberOfPages: 4, currentPage: .init(state, \.page))
        )
        let pageControl = try #require(view as? UIPageControl)

        #expect(pageControl.numberOfPages == 4)
        #expect(pageControl.currentPage == 2)
    }

    @Test func currentPageIsClampedToThePageCount() throws {
        let state = ComponentState()
        state.page = 9

        let view = FineRenderer.render(
            FinePageControl(numberOfPages: 3, currentPage: .init(state, \.page))
        )
        let pageControl = try #require(view as? UIPageControl)

        #expect(pageControl.currentPage == 2)
    }

    @Test func userSelectionWritesBackToTheBinding() throws {
        let state = ComponentState()
        let view = FineRenderer.render(
            FinePageControl(numberOfPages: 3, currentPage: .init(state, \.page))
        )
        let pageControl = try #require(view as? UIPageControl)

        pageControl.currentPage = 1
        pageControl.sendActions(for: .valueChanged)

        #expect(state.page == 1)
    }

    @Test func hidesForSinglePageResetsOnReuse() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FinePageControl(numberOfPages: 1, currentPage: .init(state, \.page))
                .hidesForSinglePage()
        )
        let pageControl = try #require(first as? UIPageControl)

        #expect(pageControl.hidesForSinglePage)

        _ = FineRenderer.render(
            FinePageControl(numberOfPages: 1, currentPage: .init(state, \.page)),
            reusing: first
        )

        #expect(pageControl.hidesForSinglePage == false)
    }
}

/// Controls whose UIKit counterpart clamps or rounds what it is given write the
/// applied value back, so the state never disagrees with what is on screen.
@MainActor
struct FineClampWriteBackTests {
    @Test func stepperCorrectsAValueOutsideItsRange() throws {
        let state = ComponentState()
        state.amount = 0

        let view = FineRenderer.render(FineStepper(value: .init(state, \.amount), in: 1...20))

        #expect((view as? UIStepper)?.value == 1)
        #expect(state.amount == 1)
    }

    @Test func datePickerCorrectsADateOutsideItsRange() throws {
        let state = ComponentState()
        let lower = Date(timeIntervalSince1970: 10_000)
        state.date = Date(timeIntervalSince1970: 0)

        let view = FineRenderer.render(
            FineDatePicker(
                selection: .init(state, \.date),
                in: lower...Date(timeIntervalSince1970: 20_000)
            )
        )
        let picker = try #require(view as? UIDatePicker)

        #expect(picker.date == lower)
        #expect(state.date == lower)
    }

    @Test func datePickerCorrectsADateTheMinuteIntervalRounds() throws {
        let state = ComponentState()
        state.date = Date(timeIntervalSince1970: 137)

        let view = FineRenderer.render(
            FineDatePicker(selection: .init(state, \.date)).minuteInterval(15)
        )
        let picker = try #require(view as? UIDatePicker)

        #expect(state.date == picker.date)

        // The write guard has to hold again afterwards: a value the picker can
        // never take would otherwise be rewritten on every render.
        let rounded = picker.date
        _ = FineRenderer.render(
            FineDatePicker(selection: .init(state, \.date)).minuteInterval(15),
            reusing: view
        )
        #expect(picker.date == rounded)
        #expect(state.date == rounded)
    }

    @Test func pageControlCorrectsAnIndexPastTheEnd() throws {
        let state = ComponentState()
        state.page = 9

        let view = FineRenderer.render(
            FinePageControl(numberOfPages: 3, currentPage: .init(state, \.page))
        )

        #expect((view as? UIPageControl)?.currentPage == 2)
        #expect(state.page == 2)
    }

    @Test func pageControlKeepsTheIndexWhileThereAreNoPagesYet() throws {
        let state = ComponentState()
        state.page = 3

        // The shape of a list still loading: resetting the index here would
        // throw away a restored or deep-linked page.
        _ = FineRenderer.render(
            FinePageControl(numberOfPages: 0, currentPage: .init(state, \.page))
        )

        #expect(state.page == 3)
    }

    @Test func correctingTheStateSettlesInsteadOfRenderingForever() async throws {
        let state = ComponentState()
        state.page = 9
        let counter = FineProgressViewTests.BodyCounter()

        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let fineUI = FineUI(state) { state in
            counter.count += 1
            return FinePageControl(numberOfPages: 3, currentPage: .init(state, \.page))
        }
        fineUI.build(to: container)

        for _ in 0..<50 {
            await Task.yield()
        }

        #expect(state.page == 2)
        // One build plus at most one re-render triggered by the correction.
        #expect(counter.count <= 2)
    }
}

@MainActor
struct FineDividerTests {
    @Test func hairlineIsThinOnItsOwnAxisAndFreeOnTheOther() throws {
        let view = try #require(FineRenderer.render(FineDivider()) as? FineDividerView)

        #expect(view.intrinsicContentSize.width == UIView.noIntrinsicMetric)
        #expect(view.intrinsicContentSize.height > 0)
        #expect(view.intrinsicContentSize.height <= 1)
    }

    @Test func verticalDividerSwapsTheThinAxis() throws {
        let view = try #require(FineRenderer.render(FineDivider.vertical()) as? FineDividerView)

        #expect(view.intrinsicContentSize.height == UIView.noIntrinsicMetric)
        #expect(view.intrinsicContentSize.width > 0)
    }

    @Test func explicitThicknessAndColorApplyAndResetOnReuse() throws {
        let first = FineRenderer.render(FineDivider().thickness(4).color(.systemBlue))
        let divider = try #require(first as? FineDividerView)

        #expect(divider.intrinsicContentSize.height == 4)
        #expect(divider.backgroundColor == .systemBlue)

        let second = FineRenderer.render(FineDivider(), reusing: first)

        #expect(second === first)
        #expect(divider.intrinsicContentSize.height < 4)
        #expect(divider.backgroundColor == .separator)
    }

    @Test func zeroThicknessStaysARealSizeRatherThanNoIntrinsicMetric() throws {
        let view = try #require(FineRenderer.render(FineDivider().thickness(0)) as? FineDividerView)

        // `UIView.noIntrinsicMetric` is -1, so the guard that rejects a
        // negative thickness has to let a deliberate zero through — otherwise
        // hiding a line by collapsing it would instead free its axis entirely.
        #expect(view.intrinsicContentSize.height == 0)
        #expect(view.intrinsicContentSize.width == UIView.noIntrinsicMetric)
    }

    @Test func dividerDoesNotStretchInsideAFillStack() throws {
        let stack = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "A"), FineDivider(), FineLabel(text: "B")]
        })
        let stackView = try #require(stack as? UIStackView)
        let divider = try #require(stackView.arrangedSubviews[1] as? FineDividerView)

        stackView.frame = .init(x: 0, y: 0, width: 320, height: 300)
        stackView.layoutIfNeeded()

        // The stack's spare height goes to the labels, not to the line.
        #expect(divider.frame.height == divider.intrinsicContentSize.height)
    }

    @Test func anExplicitHeightOutranksTheHairlineIntrinsicSize() throws {
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let divider = FineRenderer.render(FineDivider().height(20))
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        container.layoutIfNeeded()

        // Hugging at 1000 would outrank the 999 the modifier uses, leaving a
        // hairline and silently dropping the modifier.
        #expect(divider.frame.height == 20)
    }
}

@MainActor
struct FineTextViewTests {
    @Test func rendersTextAndPlaceholder() throws {
        let state = ComponentState()
        state.note = "Hello"

        let view = FineRenderer.render(
            FineTextView(text: .init(state, \.note), placeholder: "Note")
        )
        let textView = try #require(view as? FineTextViewView)

        #expect(textView.text == "Hello")
        #expect(textView.placeholder == "Note")
        #expect(textView.placeholderLabel.isHidden)
    }

    @Test func placeholderShowsOnlyWhileTheTextIsEmpty() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FineTextView(text: .init(state, \.note), placeholder: "Note")
        )
        let textView = try #require(first as? FineTextViewView)

        #expect(textView.placeholderLabel.isHidden == false)

        state.note = "Typed"
        _ = FineRenderer.render(
            FineTextView(text: .init(state, \.note), placeholder: "Note"),
            reusing: first
        )

        #expect(textView.placeholderLabel.isHidden)
    }

    @Test func aWrappingPlaceholderIsNotClipped() throws {
        let state = ComponentState()
        let view = FineRenderer.render(
            FineTextView(
                text: .init(state, \.note),
                placeholder: "Write a longer note here so the hint has to wrap onto several lines"
            )
        )
        let textView = try #require(view as? FineTextViewView)

        textView.frame = .init(x: 0, y: 0, width: 240, height: textView.intrinsicContentSize.height)
        textView.layoutIfNeeded()
        textView.frame.size.height = textView.intrinsicContentSize.height
        textView.layoutIfNeeded()

        #expect(textView.placeholderLabel.frame.height > 0)
        #expect(textView.placeholderLabel.frame.maxY <= textView.bounds.height)
    }

    @Test func typingWritesBackToTheBinding() throws {
        let state = ComponentState()
        let view = FineRenderer.render(FineTextView(text: .init(state, \.note)))
        let textView = try #require(view as? FineTextViewView)

        textView.text = "Typed"
        textView.textViewDidChange(textView)

        #expect(state.note == "Typed")
        #expect(textView.placeholderLabel.isHidden)
    }

    @Test func scrollingIsOffByDefaultAndResetsOnReuse() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FineTextView(text: .init(state, \.note)).scrollEnabled()
        )
        let textView = try #require(first as? FineTextViewView)

        #expect(textView.isScrollEnabled)

        let second = FineRenderer.render(FineTextView(text: .init(state, \.note)), reusing: first)

        #expect(second === first)
        #expect(textView.isScrollEnabled == false)
    }

    @Test func editableResetsOnReuse() throws {
        let state = ComponentState()
        let first = FineRenderer.render(
            FineTextView(text: .init(state, \.note)).editable(false)
        )
        let textView = try #require(first as? FineTextViewView)

        #expect(textView.isEditable == false)

        _ = FineRenderer.render(FineTextView(text: .init(state, \.note)), reusing: first)

        #expect(textView.isEditable)
    }

    @Test func userDrivenFocusChangesWriteBackToBinding() throws {
        let state = ComponentState()
        let view = FineRenderer.render(
            FineTextView(text: .init(state, \.note))
                .focused(.init(state, \.isFocused))
        )
        let textView = try #require(view as? FineTextViewView)

        textView.textViewDidBeginEditing(textView)
        #expect(state.isFocused)

        textView.textViewDidEndEditing(textView)
        #expect(state.isFocused == false)
    }

    @Test func focusBindingDrivesFirstResponder() async throws {
        let state = ComponentState()
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 200))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let container = UIView(frame: window.bounds)
        window.addSubview(container)

        let fineUI = FineUI(state) { state in
            FineTextView(text: .init(state, \.note))
                .focused(.init(state, \.isFocused))
        }
        fineUI.build(to: container)
        window.layoutIfNeeded()

        let textView = try #require(container.subviews.first as? FineTextViewView)
        #expect(textView.isFirstResponder == false)

        state.isFocused = true

        for _ in 0..<200 where !textView.isFirstResponder {
            await Task.yield()
        }
        #expect(textView.isFirstResponder)

        state.isFocused = false

        for _ in 0..<200 where textView.isFirstResponder {
            await Task.yield()
        }
        #expect(textView.isFirstResponder == false)
    }
}
