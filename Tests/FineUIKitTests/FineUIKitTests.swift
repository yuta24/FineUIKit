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
