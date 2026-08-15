import Testing
import UIKit
@testable import FineUIKit

/// A cell reuses its views for whatever row lands in it next — that is what
/// makes a cell cheap — but state scoped to the row it used to show must not
/// come along.
@MainActor
struct FineCellReuseTests {
    private final class Box<Value> {
        var value: Value?
    }

    @Test func recycledCellDoesNotCarryLocalStateToTheNextRow() throws {
        let cell = FineListHostCell(style: .default, reuseIdentifier: FineListHostCell.reuseIdentifier)
        let environment = FineEnvironmentStorage()
        let binding = Box<FineBinding<Int>>()

        func row() -> any Renderable {
            FineState(0) { value in
                binding.value = value
                return FineLabel(text: "\(value.value)")
            }
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil, row)
        try #require(binding.value).value = 7
        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil, row)
        #expect(label(in: cell)?.text == "7")

        cell.prepareForReuse()
        cell.render(identity: AnyHashable(2), environment: environment, renderGate: nil, row)

        #expect(label(in: cell)?.text == "0")
    }

    /// The same row rendering again is not a recycle, so its state stays.
    @Test func rerenderingTheSameRowKeepsItsLocalState() throws {
        let cell = FineListHostCell(style: .default, reuseIdentifier: FineListHostCell.reuseIdentifier)
        let environment = FineEnvironmentStorage()
        let binding = Box<FineBinding<Int>>()

        func row() -> any Renderable {
            FineState(0) { value in
                binding.value = value
                return FineLabel(text: "\(value.value)")
            }
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil, row)
        try #require(binding.value).value = 7

        cell.prepareForReuse()
        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil, row)

        #expect(label(in: cell)?.text == "7")
    }

    private func label(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, !(view.superview is UIButton) {
            return label
        }

        for subview in view.subviews {
            if let label = label(in: subview) {
                return label
            }
        }

        return nil
    }
}
