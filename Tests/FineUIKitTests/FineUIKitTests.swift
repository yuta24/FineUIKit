import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
struct FineRendererTests {
    @Test func labelIsReusedAndUpdatedInPlace() {
        let first = FineRenderer.render(FineLabel(text: "Hello"))
        let second = FineRenderer.render(FineLabel(text: "World"), reusing: first)

        #expect(second === first)
        #expect((second as? UILabel)?.text == "World")
    }

    @Test func incompatibleViewIsReplaced() {
        let label = FineRenderer.render(FineLabel(text: "Hello"))
        let button = FineRenderer.render(FineButton(title: "Tap", action: {}), reusing: label)

        #expect(button !== label)
        #expect(button is UIButton)
    }

    @Test func stackReconcilesChildrenPositionally() {
        let stack = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "A"), FineLabel(text: "B")]
        })
        let stackView = try! #require(stack as? UIStackView)
        let originalChildren = stackView.arrangedSubviews

        _ = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "A2"), FineLabel(text: "B2"), FineLabel(text: "C")]
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 3)
        #expect(stackView.arrangedSubviews[0] === originalChildren[0])
        #expect(stackView.arrangedSubviews[1] === originalChildren[1])
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "A2")
        #expect((stackView.arrangedSubviews[2] as? UILabel)?.text == "C")
    }

    @Test func stackRemovesExtraChildren() {
        let stack = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "A"), FineLabel(text: "B")]
        })
        let stackView = try! #require(stack as? UIStackView)

        _ = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "A")]
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 1)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "A")
    }
}

@MainActor
struct FineListTests {
    final class Item: Identifiable {
        let title: String

        init(title: String) {
            self.title = title
        }
    }

    @Test func rendersRowsForElements() async throws {
        let items = [Item(title: "A"), Item(title: "B")]
        let view = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) })
        let listView = try #require(view as? UITableView)

        let window = UIWindow(frame: .init(x: 0, y: 0, width: 400, height: 800))
        listView.frame = window.bounds
        window.addSubview(listView)
        window.isHidden = false

        for _ in 0..<10 where listView.numberOfRows(inSection: 0) != 2 {
            await Task.yield()
        }
        #expect(listView.numberOfRows(inSection: 0) == 2)

        listView.layoutIfNeeded()
        let cell = try #require(listView.cellForRow(at: .init(row: 0, section: 0)))
        let label = try #require(cell.contentView.subviews.first as? UILabel)
        #expect(label.text == "A")
    }

    @Test func reusesTableViewAcrossUpdates() async throws {
        var items = [Item(title: "A")]
        let list = { (items: [Item]) in FineList(items) { FineLabel(text: $0.title) } }

        let first = FineRenderer.render(list(items))
        let listView = try #require(first as? UITableView)

        items.append(Item(title: "B"))
        let second = FineRenderer.render(list(items), reusing: first)

        #expect(second === first)

        for _ in 0..<10 where listView.numberOfRows(inSection: 0) != 2 {
            await Task.yield()
        }
        #expect(listView.numberOfRows(inSection: 0) == 2)
    }
}

@MainActor
struct FineBindingTests {
    @Observable
    final class FormState {
        var text: String = ""
        var isOn: Bool = false
        var volume: Float = 0.5
    }

    @Test func textFieldWritesBackToState() throws {
        let state = FormState()
        let view = FineRenderer.render(FineTextField(text: .init(state, \.text)))
        let textField = try #require(view as? UITextField)

        textField.text = "hello"
        textField.sendActions(for: .editingChanged)

        #expect(state.text == "hello")
    }

    @Test func textFieldUpdatesFromState() async throws {
        let state = FormState()
        let container = UIView()

        let fineUI = FineUI(state) { state in
            FineTextField(text: .init(state, \.text))
        }
        fineUI.build(to: container)

        let textField = try #require(container.subviews.first as? UITextField)
        #expect(textField.text == "")

        state.text = "abc"

        for _ in 0..<10 where textField.text != "abc" {
            await Task.yield()
        }

        #expect(textField.text == "abc")
    }

    @Test func toggleRoundTrips() async throws {
        let state = FormState()
        let container = UIView()

        let fineUI = FineUI(state) { state in
            FineToggle(isOn: .init(state, \.isOn))
        }
        fineUI.build(to: container)

        let uiSwitch = try #require(container.subviews.first as? UISwitch)
        #expect(uiSwitch.isOn == false)

        // UI -> state
        uiSwitch.isOn = true
        uiSwitch.sendActions(for: .valueChanged)
        #expect(state.isOn == true)

        // state -> UI
        state.isOn = false
        for _ in 0..<10 where uiSwitch.isOn {
            await Task.yield()
        }
        #expect(uiSwitch.isOn == false)
    }

    @Test func sliderAppliesRangeAndWritesBack() throws {
        let state = FormState()
        let view = FineRenderer.render(FineSlider(value: .init(state, \.volume), in: 0...10))
        let slider = try #require(view as? UISlider)

        #expect(slider.minimumValue == 0)
        #expect(slider.maximumValue == 10)
        #expect(slider.value == 0.5)

        slider.value = 7
        slider.sendActions(for: .valueChanged)

        #expect(state.volume == 7)
    }
}

@MainActor
struct FineViewControllerTests {
    @Observable
    final class Counter {
        var count: Int = 0
    }

    final class CounterViewController: FineViewController<Counter> {
        override func body(_ state: Counter) -> any Renderable {
            FineLabel(text: "\(state.count)")
        }
    }

    @Test func buildsBodyAndRerendersOnStateChange() async throws {
        let counter = Counter()
        let viewController = CounterViewController(state: counter)
        viewController.loadViewIfNeeded()

        let label = try #require(viewController.view.subviews.first as? UILabel)
        #expect(label.text == "0")

        counter.count = 1

        for _ in 0..<10 where label.text != "1" {
            await Task.yield()
        }

        #expect(label.text == "1")
        #expect(viewController.view.subviews.first === label)
    }
}

@MainActor
struct FineUITests {
    @Observable
    final class Counter {
        var count: Int = 0
    }

    @Test func rerendersWhenObservableStateChanges() async throws {
        let counter = Counter()
        let container = UIView()

        let fineUI = FineUI(counter) { counter in
            FineLabel(text: "\(counter.count)")
        }
        fineUI.build(to: container)

        let label = try #require(container.subviews.first as? UILabel)
        #expect(label.text == "0")

        counter.count = 1

        // Re-rendering hops through a MainActor task; give it a beat.
        for _ in 0..<10 where label.text != "1" {
            await Task.yield()
        }

        #expect(label.text == "1")
        #expect(container.subviews.first === label)
    }

    // Regression test: state reads inside a container's content closure happen
    // lazily during _update, and must still be picked up by observation tracking.
    @Test func rerendersWhenStateIsReadInsideStackContent() async throws {
        let counter = Counter()
        let container = UIView()

        let fineUI = FineUI(counter) { counter in
            FineStack.vertical {
                [FineLabel(text: "\(counter.count)")]
            }
        }
        fineUI.build(to: container)

        let stackView = try #require(container.subviews.first as? UIStackView)
        let label = try #require(stackView.arrangedSubviews.first as? UILabel)
        #expect(label.text == "0")

        counter.count = 1

        for _ in 0..<10 where label.text != "1" {
            await Task.yield()
        }

        #expect(label.text == "1")
        #expect(stackView.arrangedSubviews.first === label)
    }
}
