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
struct FineButtonTests {
    private func testImage() -> UIImage {
        UIGraphicsImageRenderer(size: .init(width: 1, height: 1)).image { _ in }
    }

    @Test func imageAppliesAndResetsWithoutConfiguration() throws {
        let first = FineRenderer.render(FineButton(title: "Add", action: {}).image(testImage()))
        let button = try #require(first as? UIButton)

        #expect(button.configuration == nil)
        #expect(button.image(for: .normal) != nil)

        let second = FineRenderer.render(FineButton(title: "Add", action: {}), reusing: first)

        #expect(second === first)
        #expect(button.configuration == nil)
        #expect(button.image(for: .normal) == nil)
    }

    @Test func configurationReceivesDeclaredTitleAndImage() throws {
        let image = testImage()
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Ignored"
        configuration.image = testImage()

        let view = FineRenderer.render(
            FineButton(title: "Save", action: {})
                .image(image)
                .configuration(configuration)
        )
        let button = try #require(view as? UIButton)
        let appliedConfiguration = try #require(button.configuration)
        let appliedImage = try #require(appliedConfiguration.image)

        #expect(appliedConfiguration.title == "Save")
        #expect(appliedImage === image)
    }

    @Test func configurationPresenceControlsReuseButValueChangesInPlace() {
        let configured = FineRenderer.render(FineButton(title: "A", action: {}).configuration(.filled()))
        let plain = FineRenderer.render(FineButton(title: "A", action: {}), reusing: configured)

        #expect(plain !== configured)

        let filled = FineRenderer.render(FineButton(title: "A", action: {}).configuration(.filled()))
        let tinted = FineRenderer.render(FineButton(title: "B", action: {}).configuration(.tinted()), reusing: filled)

        #expect(tinted === filled)
        #expect((tinted as? UIButton)?.configuration?.title == "B")
    }

    @Test func configuredButtonActionDoesNotStackOnReuse() throws {
        var tapCount = 0
        let first = FineRenderer.render(
            FineButton(title: "Tap", action: { tapCount += 1 })
                .configuration(.filled())
        )
        let button = try #require(first as? UIButton)

        let second = FineRenderer.render(
            FineButton(title: "Tap", action: { tapCount += 1 })
                .configuration(.filled()),
            reusing: first
        )

        #expect(second === first)

        button.sendActions(for: .primaryActionTriggered)

        #expect(tapCount == 1)
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

    @Test func deleteActionUsesCustomTitle() async throws {
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) }
            .onDelete(title: "削除") { _ in })
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        let indexPath = IndexPath(row: 0, section: 0)

        await waitForRows(1, in: listView)
        let configuration = try #require(listView.delegate?.tableView?(listView, trailingSwipeActionsConfigurationForRowAt: indexPath) ?? nil)
        #expect(configuration.actions.first?.title == "削除")
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
struct FineGridTests {
    final class Item: Identifiable {
        let id: String
        var title: String

        init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    private func attachToWindow(_ collectionView: UICollectionView) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 400, height: 800))
        collectionView.frame = window.bounds
        window.addSubview(collectionView)
        window.isHidden = false
        return window
    }

    private func waitForItems(_ count: Int, in collectionView: UICollectionView) async {
        for _ in 0..<10 where collectionView.numberOfItems(inSection: 0) != count {
            await Task.yield()
        }
    }

    @Test func rendersCellsForElements() async throws {
        let items = [
            Item(id: "a", title: "A"),
            Item(id: "b", title: "B"),
            Item(id: "c", title: "C"),
        ]
        let view = FineRenderer.render(FineGrid(items, columns: .count(2)) { FineLabel(text: $0.title) })
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)

        await waitForItems(3, in: collectionView)
        #expect(collectionView.numberOfItems(inSection: 0) == 3)

        collectionView.layoutIfNeeded()
        let cell = try #require(collectionView.cellForItem(at: .init(item: 0, section: 0)))
        let label = try #require(cell.contentView.subviews.first as? UILabel)
        #expect(label.text == "A")
        _ = window
    }

    @Test func reusesCollectionViewAcrossUpdates() async throws {
        var items = [Item(id: "a", title: "A")]
        let grid = { (items: [Item]) in FineGrid(items) { FineLabel(text: $0.title) } }

        let first = FineRenderer.render(grid(items))
        let collectionView = try #require(first as? UICollectionView)
        let window = attachToWindow(collectionView)

        items.append(Item(id: "b", title: "B"))
        let second = FineRenderer.render(grid(items), reusing: first)

        #expect(second === first)
        await waitForItems(2, in: collectionView)
        #expect(collectionView.numberOfItems(inSection: 0) == 2)
        _ = window
    }

    @Test func reconfigureUpdatesCellContentInPlace() async throws {
        let item = Item(id: "a", title: "A")
        let grid = { FineGrid([item]) { FineLabel(text: $0.title) } }

        let first = FineRenderer.render(grid())
        let collectionView = try #require(first as? UICollectionView)
        let window = attachToWindow(collectionView)

        await waitForItems(1, in: collectionView)
        collectionView.layoutIfNeeded()

        item.title = "A2"
        let second = FineRenderer.render(grid(), reusing: first)

        #expect(second === first)
        for _ in 0..<10 {
            collectionView.layoutIfNeeded()
            let currentText = (collectionView.cellForItem(at: .init(item: 0, section: 0))?.contentView.subviews.first as? UILabel)?.text
            if currentText == "A2" { break }
            await Task.yield()
        }
        let cell = try #require(collectionView.cellForItem(at: .init(item: 0, section: 0)))
        let label = try #require(cell.contentView.subviews.first as? UILabel)
        #expect(label.text == "A2")
        _ = window
    }

    @Test func columnChangeReusesViewAndInvalidatesLayout() async throws {
        let items = [
            Item(id: "a", title: "A"),
            Item(id: "b", title: "B"),
        ]
        let first = FineRenderer.render(FineGrid(items, columns: .count(2)) { FineLabel(text: $0.title) })
        let collectionView = try #require(first as? UICollectionView)
        let window = attachToWindow(collectionView)

        await waitForItems(2, in: collectionView)
        let second = FineRenderer.render(FineGrid(items, columns: .count(3)) { FineLabel(text: $0.title) }, reusing: first)

        #expect(second === first)
        await waitForItems(2, in: collectionView)
        #expect(collectionView.numberOfItems(inSection: 0) == 2)
        _ = window
    }

    @Test func selectionInvokesHandlerWithElement() async throws {
        let first = Item(id: "a", title: "A")
        let second = Item(id: "b", title: "B")
        var selected: Item?
        let view = FineRenderer.render(FineGrid([first, second]) { FineLabel(text: $0.title) }
            .onSelect { selected = $0 })
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)
        let indexPath = IndexPath(item: 1, section: 0)

        await waitForItems(2, in: collectionView)
        #expect(collectionView.delegate?.collectionView?(collectionView, shouldHighlightItemAt: indexPath) == true)
        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)

        #expect(selected === second)

        let plain = FineRenderer.render(FineGrid([first, second]) { FineLabel(text: $0.title) })
        let plainCollectionView = try #require(plain as? UICollectionView)
        #expect(plainCollectionView.delegate?.collectionView?(plainCollectionView, shouldHighlightItemAt: indexPath) == false)
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

    @Test func textFieldInputTraitsApply() throws {
        let state = FormState()
        let view = FineRenderer.render(
            FineTextField(text: .init(state, \.text))
                .keyboardType(.emailAddress)
                .returnKeyType(.done)
                .secureTextEntry()
        )
        let textField = try #require(view as? UITextField)

        #expect(textField.keyboardType == .emailAddress)
        #expect(textField.returnKeyType == .done)
        #expect(textField.isSecureTextEntry == true)
    }

    @Test func textFieldInputTraitsResetToDefaultsOnReuse() throws {
        let state = FormState()
        let first = FineRenderer.render(
            FineTextField(text: .init(state, \.text))
                .keyboardType(.numberPad)
                .returnKeyType(.go)
                .secureTextEntry()
        )
        let textField = try #require(first as? UITextField)

        let second = FineRenderer.render(FineTextField(text: .init(state, \.text)), reusing: first)

        #expect(second === first)
        #expect(textField.keyboardType == .default)
        #expect(textField.returnKeyType == .default)
        #expect(textField.isSecureTextEntry == false)
    }

    @Test func textFieldOnSubmitRunsOnEditingDidEndOnExit() throws {
        let state = FormState()
        var submitCount = 0
        let view = FineRenderer.render(
            FineTextField(text: .init(state, \.text))
                .onSubmit { submitCount += 1 }
        )
        let textField = try #require(view as? UITextField)

        textField.sendActions(for: .editingDidEndOnExit)

        #expect(submitCount == 1)
    }

    @Test func textFieldOnSubmitIsRemovedOnReuse() throws {
        let state = FormState()
        var submitCount = 0
        let first = FineRenderer.render(
            FineTextField(text: .init(state, \.text))
                .onSubmit { submitCount += 1 }
        )
        let textField = try #require(first as? UITextField)

        _ = FineRenderer.render(FineTextField(text: .init(state, \.text)), reusing: first)
        textField.sendActions(for: .editingDidEndOnExit)

        #expect(submitCount == 0)
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
struct FineLayoutModifierTests {
    private func attachToWindow(_ view: UIView, width: CGFloat = 320, height: CGFloat = 200) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: width, height: height))
        view.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: window.topAnchor),
            view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
        window.isHidden = false
        return window
    }

    private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.5
    }

    @Test func widthHeightAndAspectConstraintsInstallAndUpdate() throws {
        let first = FineRenderer.render(
            FineLabel(text: "A")
                .width(.equal, 100)
                .height(.greaterThanOrEqual, 44, priority: .init(750))
                .aspectRatio(2)
        )
        let width = try #require(first.fineInstalledConstraints.values.first {
            $0.firstAttribute == .width && $0.secondItem == nil
        })
        let height = try #require(first.fineInstalledConstraints.values.first {
            $0.firstAttribute == .height && $0.relation == .greaterThanOrEqual
        })
        let aspect = try #require(first.fineInstalledConstraints.values.first {
            $0.firstAttribute == .width && $0.secondAttribute == .height
        })

        #expect(width.constant == 100)
        #expect(width.relation == .equal)
        #expect(width.priority == .init(999))
        #expect(height.constant == 44)
        #expect(height.priority == .init(750))
        #expect(aspect.multiplier == 2)

        let second = FineRenderer.render(
            FineLabel(text: "B")
                .width(.equal, 120)
                .height(.greaterThanOrEqual, 50, priority: .init(750))
                .aspectRatio(2),
            reusing: first
        )
        let updatedWidth = try #require(second.fineInstalledConstraints.values.first {
            $0.firstAttribute == .width && $0.secondItem == nil
        })
        let updatedHeight = try #require(second.fineInstalledConstraints.values.first {
            $0.firstAttribute == .height && $0.relation == .greaterThanOrEqual
        })

        #expect(second === first)
        #expect(updatedWidth === width)
        #expect(updatedHeight === height)
        #expect(updatedWidth.constant == 120)
        #expect(updatedHeight.constant == 50)

        let third = FineRenderer.render(FineLabel(text: "C").width(.lessThanOrEqual, 120), reusing: second)
        #expect(third !== second)
    }

    @Test func priorityModifiersApplyAndDoNotLeak() {
        let styled = FineRenderer.render(
            FineLabel(text: "A")
                .hugging(.required, axis: .horizontal)
                .compressionResistance(.required, axis: .vertical)
        )

        #expect(styled.contentHuggingPriority(for: .horizontal) == .required)
        #expect(styled.contentCompressionResistancePriority(for: .vertical) == .required)

        let plain = FineRenderer.render(FineLabel(text: "B"), reusing: styled)
        #expect(plain !== styled)
    }

    @Test func fillStackCanOverrideSelfWidthConstraint() {
        let stack = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "A").width(.equal, 120)]
        })
        let stackView = stack as! UIStackView
        let window = attachToWindow(stackView, width: 300, height: 80)

        window.layoutIfNeeded()

        #expect(approximatelyEqual(stackView.bounds.width, 300))
        #expect(approximatelyEqual(stackView.arrangedSubviews[0].bounds.width, stackView.bounds.width))
        _ = window
    }

    @Test func frameAlignmentCentersChildAndAlignmentChangeRebuilds() throws {
        let first = FineRenderer.render(FineLabel(text: "A").frame(width: 44, height: 44, alignment: .center))
        let frameView = try #require(first as? FineFrameView)
        let child = try #require(frameView.hosted)
        let window = attachToWindow(frameView, width: 44, height: 44)

        window.layoutIfNeeded()

        #expect(approximatelyEqual(child.center.x, frameView.bounds.midX))
        #expect(approximatelyEqual(child.center.y, frameView.bounds.midY))

        let second = FineRenderer.render(FineLabel(text: "A").frame(width: 44, height: 44, alignment: .leading), reusing: first)
        #expect(second !== first)
        _ = window
    }

    @Test func customConstraintsRecreateOnEveryRender() throws {
        var runCount = 0
        let node = {
            FineLabel(text: "A").constraints(id: "test") { view in
                runCount += 1
                return [view.widthAnchor.constraint(equalToConstant: CGFloat(10 * runCount))]
            }
        }

        let first = FineRenderer.render(node())
        let firstConstraint = try #require(first.fineCustomConstraints["custom:test"]?.first)

        #expect(runCount == 1)
        #expect(firstConstraint.isActive)

        let second = FineRenderer.render(node(), reusing: first)
        let secondConstraint = try #require(second.fineCustomConstraints["custom:test"]?.first)

        #expect(second === first)
        #expect(runCount == 2)
        #expect(firstConstraint !== secondConstraint)
        #expect(firstConstraint.isActive == false)
        #expect(secondConstraint.isActive)
    }

    @Test func spacerAbsorbsSlackAndMinLengthInstallsConstraints() throws {
        let stack = FineRenderer.render(FineStack.horizontal {
            [
                FineLabel(text: "A"),
                FineSpacer(),
                FineLabel(text: "B"),
            ]
        })
        let stackView = stack as! UIStackView
        let window = attachToWindow(stackView, width: 400, height: 80)

        window.layoutIfNeeded()

        #expect(approximatelyEqual(stackView.arrangedSubviews[0].frame.minX, 0))
        #expect(approximatelyEqual(stackView.arrangedSubviews[2].frame.maxX, 400))

        let spacer = FineRenderer.render(FineSpacer(minLength: 20))
        let minWidth = try #require(spacer.fineInstalledConstraints["spacer.minW"])
        let minHeight = try #require(spacer.fineInstalledConstraints["spacer.minH"])
        #expect(minWidth.relation == .greaterThanOrEqual)
        #expect(minWidth.constant == 20)
        #expect(minHeight.relation == .greaterThanOrEqual)
        #expect(minHeight.constant == 20)
        _ = window
    }

    @Test func scrollViewHostsTallContentAndReusesViews() throws {
        let makeContent = {
            FineStack.vertical(spacing: 4) {
                (0..<30).map { FineLabel(text: "\($0)") as any Renderable }
            }
        }
        let first = FineRenderer.render(FineScrollView(.vertical) { makeContent() })
        let scrollView = try #require(first as? FineScrollHostView)
        let hosted = try #require(scrollView.hosted)
        let window = attachToWindow(scrollView, width: 200, height: 100)

        window.layoutIfNeeded()

        #expect(scrollView.contentSize.height > scrollView.bounds.height)

        let second = FineRenderer.render(FineScrollView(.vertical) { makeContent() }, reusing: first)

        #expect(second === first)
        #expect(scrollView.hosted === hosted)
        _ = window
    }
}

@MainActor
struct FineAccessibilityTests {
    @Test func accessibilityPropertiesApply() {
        let view = FineRenderer.render(
            FineLabel(text: "Task")
                .accessibilityLabel("Task title")
                .accessibilityValue("Done")
                .accessibilityHint("Double tap to open")
                .accessibilityTraits(.button)
                .accessibilityIdentifier("task-title")
        )

        #expect(view.accessibilityLabel == "Task title")
        #expect(view.accessibilityValue == "Done")
        #expect(view.accessibilityHint == "Double tap to open")
        #expect(view.accessibilityTraits == .button)
        #expect(view.accessibilityIdentifier == "task-title")
        #expect(view.isAccessibilityElement)
    }

    @Test func hiddenHidesFromAccessibility() {
        let view = FineRenderer.render(FineLabel(text: "Hidden").accessibilityHidden())

        #expect(view.accessibilityElementsHidden)
        #expect(view.isAccessibilityElement == false)
    }

    @Test func removalRebuildsView() {
        let first = FineRenderer.render(FineLabel(text: "A").accessibilityLabel("A"))
        let second = FineRenderer.render(FineLabel(text: "B"), reusing: first)

        #expect(second !== first)
        #expect((second as? UILabel)?.text == "B")
    }

    @Test func chainingFlattens() throws {
        let view = FineRenderer.render(
            FineButton(title: "Add") {}
                .accessibilityLabel("Add task")
                .accessibilityHint("Adds a task")
        )
        let button = try #require(view as? UIButton)

        #expect(button.accessibilityLabel == "Add task")
        #expect(button.accessibilityHint == "Adds a task")
    }
}

@MainActor
struct FineBuilderTests {
    final class Item: Identifiable {
        let id: String
        let title: String

        init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    @Test func sequentialStatementsBecomeArrangedSubviewsInOrder() throws {
        let stack = FineRenderer.render(FineStack.vertical {
            FineLabel(text: "A")
            FineButton(title: "B") {}
            FineLabel(text: "C")
        })
        let stackView = try #require(stack as? UIStackView)

        #expect(stackView.arrangedSubviews.count == 3)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "A")
        #expect((stackView.arrangedSubviews[1] as? UIButton)?.title(for: .normal) == "B")
        #expect((stackView.arrangedSubviews[2] as? UILabel)?.text == "C")
    }

    @Test func optionalIfAddsAndRemovesChildrenAcrossRenders() throws {
        var showsDetail = true
        let stack = FineRenderer.render(FineStack.vertical {
            FineLabel(text: "Header")
            if showsDetail {
                FineLabel(text: "Detail")
            }
        })
        let stackView = try #require(stack as? UIStackView)
        let header = stackView.arrangedSubviews[0]

        #expect(stackView.arrangedSubviews.count == 2)

        showsDetail = false
        _ = FineRenderer.render(FineStack.vertical {
            FineLabel(text: "Header")
            if showsDetail {
                FineLabel(text: "Detail")
            }
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 1)
        #expect(stackView.arrangedSubviews[0] === header)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "Header")
    }

    @Test func eitherBranchesUseExistingDiffRules() throws {
        var usesButton = false
        let differentType = FineRenderer.render(FineStack.vertical {
            if usesButton {
                FineButton(title: "Action") {}
            } else {
                FineLabel(text: "Label")
            }
        })
        let differentTypeStack = try #require(differentType as? UIStackView)
        let originalLabel = differentTypeStack.arrangedSubviews[0]

        usesButton = true
        _ = FineRenderer.render(FineStack.vertical {
            if usesButton {
                FineButton(title: "Action") {}
            } else {
                FineLabel(text: "Label")
            }
        }, reusing: differentType)

        #expect(differentTypeStack.arrangedSubviews[0] !== originalLabel)
        #expect(differentTypeStack.arrangedSubviews[0] is UIButton)

        var usesAlternateText = false
        let sameType = FineRenderer.render(FineStack.vertical {
            if usesAlternateText {
                FineLabel(text: "B")
            } else {
                FineLabel(text: "A")
            }
        })
        let sameTypeStack = try #require(sameType as? UIStackView)
        let originalSameTypeLabel = sameTypeStack.arrangedSubviews[0]

        usesAlternateText = true
        _ = FineRenderer.render(FineStack.vertical {
            if usesAlternateText {
                FineLabel(text: "B")
            } else {
                FineLabel(text: "A")
            }
        }, reusing: sameType)

        #expect(sameTypeStack.arrangedSubviews[0] === originalSameTypeLabel)
        #expect((sameTypeStack.arrangedSubviews[0] as? UILabel)?.text == "B")
    }

    @Test func forInIsFlattened() throws {
        let items = ["A", "B", "C"]
        let stack = FineRenderer.render(FineStack.vertical {
            FineLabel(text: "Header")
            for item in items {
                FineLabel(text: item)
            }
        })
        let stackView = try #require(stack as? UIStackView)

        #expect(stackView.arrangedSubviews.count == 4)
        #expect((stackView.arrangedSubviews[0] as? UILabel)?.text == "Header")
        #expect((stackView.arrangedSubviews[1] as? UILabel)?.text == "A")
        #expect((stackView.arrangedSubviews[2] as? UILabel)?.text == "B")
        #expect((stackView.arrangedSubviews[3] as? UILabel)?.text == "C")
    }

    @Test func fineForEachKeepsKeyedViewsInsideBuilder() throws {
        let a = Item(id: "a", title: "A")
        let b = Item(id: "b", title: "B")
        let c = Item(id: "c", title: "C")
        let stack = FineRenderer.render(FineStack.vertical {
            FineLabel(text: "Header")
            FineForEach([a, b]) { item in
                FineLabel(text: item.title)
            }
        })
        let stackView = try #require(stack as? UIStackView)
        let header = stackView.arrangedSubviews[0]
        let originalA = stackView.arrangedSubviews[1]
        let originalB = stackView.arrangedSubviews[2]

        _ = FineRenderer.render(FineStack.vertical {
            FineLabel(text: "Header")
            FineForEach([c, a, b]) { item in
                FineLabel(text: item.title)
            }
        }, reusing: stack)

        #expect(stackView.arrangedSubviews.count == 4)
        #expect(stackView.arrangedSubviews[0] === header)
        #expect(stackView.arrangedSubviews[1] !== originalA)
        #expect(stackView.arrangedSubviews[2] === originalA)
        #expect(stackView.arrangedSubviews[3] === originalB)
        #expect((stackView.arrangedSubviews[1] as? UILabel)?.text == "C")
        #expect((stackView.arrangedSubviews[2] as? UILabel)?.text == "A")
        #expect((stackView.arrangedSubviews[3] as? UILabel)?.text == "B")
    }

    @Test func arrayLiteralAndExplicitReturnClosuresRemainCompatible() throws {
        let arrayLiteral = FineRenderer.render(FineStack.vertical {
            [FineLabel(text: "A"), FineLabel(text: "B")]
        })
        let arrayLiteralStack = try #require(arrayLiteral as? UIStackView)

        #expect(arrayLiteralStack.arrangedSubviews.count == 2)
        #expect((arrayLiteralStack.arrangedSubviews[0] as? UILabel)?.text == "A")
        #expect((arrayLiteralStack.arrangedSubviews[1] as? UILabel)?.text == "B")

        let explicitReturn = FineRenderer.render(FineStack.vertical {
            let first: any Renderable = FineLabel(text: "C")
            return [first, FineLabel(text: "D")]
        })
        let explicitReturnStack = try #require(explicitReturn as? UIStackView)

        #expect(explicitReturnStack.arrangedSubviews.count == 2)
        #expect((explicitReturnStack.arrangedSubviews[0] as? UILabel)?.text == "C")
        #expect((explicitReturnStack.arrangedSubviews[1] as? UILabel)?.text == "D")
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
