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
        let id: String
        let title: String

        init(id: String = UUID().uuidString, title: String) {
            self.id = id
            self.title = title
        }
    }

    private func attachToWindow(_ listView: UITableView) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 400, height: 800))
        listView.frame = window.bounds
        window.addSubview(listView)
        window.isHidden = false
        return window
    }

    private func waitForRows(_ count: Int, in listView: UITableView) async {
        for _ in 0..<10 where listView.numberOfRows(inSection: 0) != count {
            await Task.yield()
        }
    }

    @Test func rendersRowsForElements() async throws {
        let items = [Item(title: "A"), Item(title: "B")]
        let view = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) })
        let listView = try #require(view as? UITableView)

        let window = attachToWindow(listView)

        await waitForRows(2, in: listView)
        #expect(listView.numberOfRows(inSection: 0) == 2)

        listView.layoutIfNeeded()
        let cell = try #require(listView.cellForRow(at: .init(row: 0, section: 0)))
        let label = try #require(cell.contentView.subviews.first as? UILabel)
        #expect(label.text == "A")
        _ = window
    }

    @Test func reusesTableViewAcrossUpdates() async throws {
        var items = [Item(title: "A")]
        let list = { (items: [Item]) in FineList(items) { FineLabel(text: $0.title) } }

        let first = FineRenderer.render(list(items))
        let listView = try #require(first as? UITableView)

        items.append(Item(title: "B"))
        let second = FineRenderer.render(list(items), reusing: first)

        #expect(second === first)

        await waitForRows(2, in: listView)
        #expect(listView.numberOfRows(inSection: 0) == 2)
    }

    @Test func selectionInvokesHandlerWithElement() async throws {
        let first = Item(id: "a", title: "A")
        let second = Item(id: "b", title: "B")
        var selected: Item?
        let view = FineRenderer.render(FineList([first, second]) { FineLabel(text: $0.title) }
            .onSelect { selected = $0 })
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)

        await waitForRows(2, in: listView)
        listView.delegate?.tableView?(listView, didSelectRowAt: .init(row: 1, section: 0))

        #expect(selected === second)
        _ = window
    }

    @Test func selectionStyleFollowsOnSelect() async throws {
        let items = [Item(id: "a", title: "A")]
        let selectable = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) }
            .onSelect { _ in })
        let selectableListView = try #require(selectable as? UITableView)
        let selectableWindow = attachToWindow(selectableListView)

        await waitForRows(1, in: selectableListView)
        selectableListView.layoutIfNeeded()
        let selectableCell = try #require(selectableListView.cellForRow(at: .init(row: 0, section: 0)))
        #expect(selectableCell.selectionStyle == .default)

        let plain = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) })
        let plainListView = try #require(plain as? UITableView)
        let plainWindow = attachToWindow(plainListView)

        await waitForRows(1, in: plainListView)
        plainListView.layoutIfNeeded()
        let plainCell = try #require(plainListView.cellForRow(at: .init(row: 0, section: 0)))
        #expect(plainCell.selectionStyle == .none)

        _ = selectableWindow
        _ = plainWindow
    }

    @Test func onDeleteEnablesEditingAndSwipeConfiguration() async throws {
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) }
            .onDelete { _ in })
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        let indexPath = IndexPath(row: 0, section: 0)

        await waitForRows(1, in: listView)
        #expect(listView.dataSource?.tableView?(listView, canEditRowAt: indexPath) == true)

        let configuration = try #require(listView.delegate?.tableView?(listView, trailingSwipeActionsConfigurationForRowAt: indexPath) ?? nil)
        #expect(configuration.actions.count == 1)
        #expect(configuration.actions.first?.style == .destructive)
        _ = window
    }

    @Test func withoutOnDeleteNoEditingNoConfiguration() async throws {
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) })
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        let indexPath = IndexPath(row: 0, section: 0)

        await waitForRows(1, in: listView)
        #expect(listView.dataSource?.tableView?(listView, canEditRowAt: indexPath) == false)
        #expect((listView.delegate?.tableView?(listView, trailingSwipeActionsConfigurationForRowAt: indexPath) ?? nil) == nil)
        _ = window
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

@MainActor
struct FineModifierTests {
    @Test func styleValueChangeReusesView() throws {
        let first = FineRenderer.render(FineLabel(text: "A").backgroundColor(.red))
        let second = FineRenderer.render(FineLabel(text: "B").backgroundColor(.blue), reusing: first)

        #expect(second === first)
        #expect(second.backgroundColor?.isEqual(UIColor.blue) == true)
        #expect((second as? UILabel)?.text == "B")
    }

    @Test func removedStyleRebuildsView() {
        let first = FineRenderer.render(FineLabel(text: "A").backgroundColor(.red))
        let second = FineRenderer.render(FineLabel(text: "B"), reusing: first)

        #expect(second !== first)
        // A fresh UILabel's default background isn't nil on recent SDKs;
        // what matters is that the styled color didn't leak into the rebuild.
        #expect(second.backgroundColor?.isEqual(UIColor.red) != true)
        #expect((second as? UILabel)?.text == "B")
    }

    @Test func paddingReusesContainerAndChildWhileUpdatingInsets() throws {
        let first = FineRenderer.render(FineLabel(text: "A").padding(.init(top: 1, leading: 2, bottom: 3, trailing: 4)))
        let paddingView = try #require(first as? FinePaddingView)
        let child = try #require(paddingView.hosted as? UILabel)

        let second = FineRenderer.render(FineLabel(text: "B").padding(.init(top: 5, leading: 6, bottom: 7, trailing: 8)), reusing: first)

        #expect(second === first)
        #expect(paddingView.hosted === child)
        #expect(child.text == "B")
        #expect(paddingView.topConstraint?.constant == 5)
        #expect(paddingView.leadingConstraint?.constant == 6)
        #expect(paddingView.bottomConstraint?.constant == 7)
        #expect(paddingView.trailingConstraint?.constant == 8)
    }

    @Test func modifierOrderControlsStyledView() throws {
        let styledChild = FineRenderer.render(FineLabel(text: "A").backgroundColor(.red).padding(4))
        let styledChildContainer = try #require(styledChild as? FinePaddingView)
        let styledChildLabel = try #require(styledChildContainer.hosted as? UILabel)

        #expect(styledChildContainer.backgroundColor == nil)
        #expect(styledChildLabel.backgroundColor?.isEqual(UIColor.red) == true)

        let styledContainer = FineRenderer.render(FineLabel(text: "A").padding(4).backgroundColor(.blue))
        let paddingView = try #require(styledContainer as? FinePaddingView)
        let label = try #require(paddingView.hosted as? UILabel)

        #expect(paddingView.backgroundColor?.isEqual(UIColor.blue) == true)
        #expect(label.backgroundColor?.isEqual(UIColor.blue) != true)
    }

    @Test func frameCreatesDimensionConstraints() throws {
        let view = FineRenderer.render(FineLabel(text: "A").frame(width: 120, height: 44))
        let frameView = try #require(view as? FineFrameView)
        let label = try #require(frameView.hosted as? UILabel)

        #expect(label.text == "A")
        #expect(frameView.widthConstraint?.constant == 120)
        #expect(frameView.heightConstraint?.constant == 44)
        #expect(frameView.widthConstraint?.isActive == true)
        #expect(frameView.heightConstraint?.isActive == true)
    }

    @Test func labelTypedModifiersApplyAndResetToDefaults() throws {
        let customFont = UIFont.boldSystemFont(ofSize: 22)
        let first = FineRenderer.render(
            FineLabel(text: "A")
                .font(customFont)
                .textColor(.red)
                .textAlignment(.center)
                .numberOfLines(3)
        )
        let label = try #require(first as? UILabel)

        #expect(label.font.isEqual(customFont))
        #expect(label.textColor.isEqual(UIColor.red))
        #expect(label.textAlignment == .center)
        #expect(label.numberOfLines == 3)

        let second = FineRenderer.render(FineLabel(text: "B"), reusing: first)

        #expect(second === first)
        #expect(label.text == "B")
        #expect(label.font.isEqual(UIFont.systemFont(ofSize: UIFont.labelFontSize)))
        #expect(label.textColor.isEqual(UIColor.label))
        #expect(label.textAlignment == .natural)
        #expect(label.numberOfLines == 1)
    }
}

@MainActor
struct FineKeyedReconciliationTests {
    final class Item: Identifiable {
        let id: String
        let title: String

        init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    @Test func headInsertionPreservesKeyedViews() throws {
        let a = Item(id: "a", title: "A")
        let b = Item(id: "b", title: "B")
        let c = Item(id: "c", title: "C")
        let stack = FineRenderer.render(FineStack.vertical {
            FineForEach([a, b]) { item in
                FineLabel(text: item.title)
            }
        })
        let stackView = try #require(stack as? UIStackView)
        let originalA = stackView.arrangedSubviews[0]
        let originalB = stackView.arrangedSubviews[1]

        _ = FineRenderer.render(FineStack.vertical {
            FineForEach([c, a, b]) { item in
                FineLabel(text: item.title)
            }
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 3)
        #expect(stackView.arrangedSubviews[0] !== originalA)
        #expect(stackView.arrangedSubviews[1] === originalA)
        #expect(stackView.arrangedSubviews[2] === originalB)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "C")
        #expect((stackView.arrangedSubviews[1] as? UILabel)?.text == "A")
        #expect((stackView.arrangedSubviews[2] as? UILabel)?.text == "B")
    }

    @Test func reorderMovesExistingViews() throws {
        let a = Item(id: "a", title: "A")
        let b = Item(id: "b", title: "B")
        let stack = FineRenderer.render(FineStack.vertical {
            FineForEach([a, b]) { item in
                FineLabel(text: item.title)
            }
        })
        let stackView = try #require(stack as? UIStackView)
        let originalA = stackView.arrangedSubviews[0]
        let originalB = stackView.arrangedSubviews[1]

        _ = FineRenderer.render(FineStack.vertical {
            FineForEach([b, a]) { item in
                FineLabel(text: item.title)
            }
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 2)
        #expect(stackView.arrangedSubviews[0] === originalB)
        #expect(stackView.arrangedSubviews[1] === originalA)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "B")
        #expect((stackView.arrangedSubviews[1] as? UILabel)?.text == "A")
    }

    @Test func removalDropsOnlyThatView() throws {
        let a = Item(id: "a", title: "A")
        let b = Item(id: "b", title: "B")
        let c = Item(id: "c", title: "C")
        let stack = FineRenderer.render(FineStack.vertical {
            FineForEach([a, b, c]) { item in
                FineLabel(text: item.title)
            }
        })
        let stackView = try #require(stack as? UIStackView)
        let originalA = stackView.arrangedSubviews[0]
        let originalC = stackView.arrangedSubviews[2]

        _ = FineRenderer.render(FineStack.vertical {
            FineForEach([a, c]) { item in
                FineLabel(text: item.title)
            }
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 2)
        #expect(stackView.arrangedSubviews[0] === originalA)
        #expect(stackView.arrangedSubviews[1] === originalC)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "A")
        #expect((stackView.arrangedSubviews[1] as? UILabel)?.text == "C")
    }

    @Test func mixedUnkeyedAndKeyedChildren() throws {
        let a = Item(id: "a", title: "A")
        let b = Item(id: "b", title: "B")
        let stack = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "header")] + FineForEach([a, b]) { item in
                FineLabel(text: item.title)
            }
        })
        let stackView = try #require(stack as? UIStackView)
        let header = stackView.arrangedSubviews[0]
        let originalA = stackView.arrangedSubviews[1]
        let originalB = stackView.arrangedSubviews[2]

        _ = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "header")] + FineForEach([b, a]) { item in
                FineLabel(text: item.title)
            }
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 3)
        #expect(stackView.arrangedSubviews[0] === header)
        #expect(stackView.arrangedSubviews[1] === originalB)
        #expect(stackView.arrangedSubviews[2] === originalA)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "header")
        #expect((stackView.arrangedSubviews[1] as? UILabel)?.text == "B")
        #expect((stackView.arrangedSubviews[2] as? UILabel)?.text == "A")
    }

    @Test func keyMismatchPreventsReuseInRenderer() {
        let first = FineRenderer.render(FineLabel(text: "A").key("x"))
        let differentKey = FineRenderer.render(FineLabel(text: "B").key("y"), reusing: first)
        let sameKey = FineRenderer.render(FineLabel(text: "C").key("x"), reusing: first)

        #expect(differentKey !== first)
        #expect((differentKey as? UILabel)?.text == "B")
        #expect(sameKey === first)
        #expect((sameKey as? UILabel)?.text == "C")
    }
}
