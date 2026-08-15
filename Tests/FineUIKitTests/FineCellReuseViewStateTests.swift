import Testing
import UIKit
@testable import FineUIKit

/// UIKit state that describes the row rather than the view.
///
/// A recycled cell keeps its views on purpose, so nothing about the keyboard it
/// is holding or how far it has been scrolled ends on its own — those have to be
/// wound down where the host learns it is showing something else.
@MainActor
struct FineCellReuseViewStateTests {
    private func makeCell(in window: UIWindow) -> FineListHostCell {
        let cell = FineListHostCell(style: .default, reuseIdentifier: FineListHostCell.reuseIdentifier)
        cell.frame = window.bounds
        window.addSubview(cell)
        return cell
    }

    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 320, height: 200))
        window.isHidden = false
        return window
    }

    private func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }

        for subview in view.subviews {
            if let match = find(type, in: subview) { return match }
        }

        return nil
    }

    // MARK: - keyboard

    @Test func handingACellADifferentRowGivesUpTheKeyboard() throws {
        let window = makeWindow()
        let cell = makeCell(in: window)
        let environment = FineEnvironmentStorage()
        let draft = FineStateStorage("")

        func row(_ id: Int) -> any Renderable {
            FineTextField(
                text: .init(get: { draft.value }, set: { draft.value = $0 }),
                placeholder: "row \(id)"
            )
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil) { row(1) }
        window.layoutIfNeeded()

        let field = try #require(find(FineTextFieldView.self, in: cell))
        #expect(field.becomeFirstResponder())
        #expect(field.isFirstResponder)

        cell.render(identity: AnyHashable(2), environment: environment, renderGate: nil) { row(2) }
        window.layoutIfNeeded()

        #expect(!field.isFirstResponder)
        _ = window
    }

    @Test func recyclingACellGivesUpTheKeyboard() throws {
        let window = makeWindow()
        let cell = makeCell(in: window)
        let environment = FineEnvironmentStorage()
        let draft = FineStateStorage("")

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil) {
            FineTextField(text: .init(get: { draft.value }, set: { draft.value = $0 }))
        }
        window.layoutIfNeeded()

        let field = try #require(find(FineTextFieldView.self, in: cell))
        #expect(field.becomeFirstResponder())

        cell.prepareForReuse()

        #expect(!field.isFirstResponder)
        _ = window
    }

    // MARK: - scroll position

    @Test func handingACellADifferentRowResetsTheScrollPosition() throws {
        let window = makeWindow()
        let cell = makeCell(in: window)
        let environment = FineEnvironmentStorage()

        func shelf(_ id: Int) -> any Renderable {
            FineScrollView(.horizontal) {
                FineStack.horizontal(spacing: 8) {
                    for index in 0..<20 {
                        FineLabel(text: "\(id)-\(index)")
                            .width(120)
                    }
                }
            }
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil) { shelf(1) }
        window.layoutIfNeeded()

        let scrollView = try #require(find(FineScrollHostView.self, in: cell))
        scrollView.setContentOffset(.init(x: 400, y: 0), animated: false)
        #expect(scrollView.contentOffset.x == 400)

        cell.render(identity: AnyHashable(2), environment: environment, renderGate: nil) { shelf(2) }
        window.layoutIfNeeded()

        #expect(scrollView.contentOffset == .zero)
        _ = window
    }

    /// A recycled cell usually gets its own row back, and losing the place then
    /// would be the bug rather than the fix.
    @Test func recyclingACellKeepsTheScrollPositionForTheSameRow() throws {
        let window = makeWindow()
        let cell = makeCell(in: window)
        let environment = FineEnvironmentStorage()

        func shelf() -> any Renderable {
            FineScrollView(.horizontal) {
                FineStack.horizontal(spacing: 8) {
                    for index in 0..<20 {
                        FineLabel(text: "\(index)")
                            .width(120)
                    }
                }
            }
        }

        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil, shelf)
        window.layoutIfNeeded()

        let scrollView = try #require(find(FineScrollHostView.self, in: cell))
        scrollView.setContentOffset(.init(x: 400, y: 0), animated: false)

        cell.prepareForReuse()
        cell.render(identity: AnyHashable(1), environment: environment, renderGate: nil, shelf)
        window.layoutIfNeeded()

        #expect(scrollView.contentOffset.x == 400)
        _ = window
    }
}
