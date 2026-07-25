import Observation
import Testing
import UIKit
@testable import FineUIKit

@Observable
private final class SupplementaryHeaderState {
    var title = "H1"
}

@Observable
private final class SupplementaryFooterState {
    var caption = "F1"
}

private struct TestBadgeEnvironmentKey: FineEnvironmentKey {
    static let defaultValue = "default"
}

private extension FineEnvironmentValues {
    var testBadge: String {
        get { self[TestBadgeEnvironmentKey.self] }
        set { self[TestBadgeEnvironmentKey.self] = newValue }
    }
}

@MainActor
struct FineListBehaviorTests {
    struct Item: Identifiable, Equatable {
        let id: String
        var title: String
    }

    @Observable
    final class ObservableRow: Identifiable {
        let id: String
        var title: String

        init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    private func attachToWindow(_ view: UIView, width: CGFloat = 400, height: CGFloat = 800) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: width, height: height))
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
        return window
    }

    private func waitForRows(_ count: Int, in listView: UITableView) async {
        for _ in 0..<100 where listView.numberOfSections == 0 || listView.numberOfRows(inSection: 0) != count {
            await Task.yield()
        }
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel {
            return label
        }

        for subview in view.subviews {
            if let label = firstLabel(in: subview) {
                return label
            }
        }

        return nil
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    @Test func cellContentReceivesInjectedEnvironment() async throws {
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(
            FineList(items) { _ in
                FineEnvironmentReader { environment in
                    FineLabel(text: environment.testBadge)
                }
            }
            .environment(\.testBadge, "injected")
        )
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)

        await waitForRows(1, in: listView)
        listView.layoutIfNeeded()

        let cell = try #require(listView.cellForRow(at: .init(row: 0, section: 0)))
        #expect(firstLabel(in: cell)?.text == "injected")
        _ = window
    }

    @Test func headerAndFooterReceiveInjectedEnvironment() async throws {
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(
            FineList(sections: [
                FineListSection(
                    id: "main",
                    header: FineEnvironmentReader { environment in
                        FineLabel(text: "H-\(environment.testBadge)")
                    },
                    footer: FineEnvironmentReader { environment in
                        FineLabel(text: "F-\(environment.testBadge)")
                    },
                    items: items
                ),
            ]) { FineLabel(text: $0.title) }
            .environment(\.testBadge, "injected")
        )
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)

        await waitForRows(1, in: listView)

        let header = try #require(listView.delegate?.tableView?(listView, viewForHeaderInSection: 0) ?? nil)
        let footer = try #require(listView.delegate?.tableView?(listView, viewForFooterInSection: 0) ?? nil)

        #expect(firstLabel(in: header)?.text == "H-injected")
        #expect(firstLabel(in: footer)?.text == "F-injected")
        _ = window
    }

    /// A header built from state that changed must not keep showing the old
    /// description: nothing asks the table for a supplementary view it already
    /// has, so the list refreshes visible ones itself.
    @Test func headerFollowsStateChangeWithoutSectionChange() async throws {
        let state = SupplementaryHeaderState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 600))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state) { state in
            let title = state.title
            return FineList(sections: [
                FineListSection(id: "s", header: FineLabel(text: title), items: [Item(id: "a", title: "A")]),
            ]) { item in
                FineLabel(text: item.title)
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()

        let listView = try #require(container.subviews.compactMap { $0 as? UITableView }.first)
        func headerText() -> String? {
            listView.layoutIfNeeded()
            guard let header = listView.headerView(forSection: 0) else { return nil }
            return firstLabel(in: header)?.text
        }

        for _ in 0..<200 where headerText() != "H1" {
            await Task.yield()
        }
        #expect(headerText() == "H1")

        state.title = "H2"
        for _ in 0..<200 where headerText() != "H2" {
            await Task.yield()
        }

        #expect(headerText() == "H2")
        _ = (window, ui)
    }

    @Test func footerFollowsStateChangeWithoutSectionChange() async throws {
        let state = SupplementaryFooterState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 600))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state) { state in
            let caption = state.caption
            return FineList(sections: [
                FineListSection(id: "s", footer: FineLabel(text: caption), items: [Item(id: "a", title: "A")]),
            ]) { item in
                FineLabel(text: item.title)
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()

        let listView = try #require(container.subviews.compactMap { $0 as? UITableView }.first)
        func footerText() -> String? {
            listView.layoutIfNeeded()
            guard let footer = listView.footerView(forSection: 0) else { return nil }
            return firstLabel(in: footer)?.text
        }

        for _ in 0..<200 where footerText() != "F1" {
            await Task.yield()
        }
        #expect(footerText() == "F1")

        state.caption = "F2"
        for _ in 0..<200 where footerText() != "F2" {
            await Task.yield()
        }

        #expect(footerText() == "F2")
        _ = (window, ui)
    }

    @Test func headerObservableContentUpdatesInPlace() async throws {
        let model = ObservableRow(id: "h", title: "Before")
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(
            FineList(sections: [
                FineListSection(
                    id: "main",
                    header: FineLabel(text: model.title),
                    items: items
                ),
            ]) { FineLabel(text: $0.title) }
        )
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)

        await waitForRows(1, in: listView)

        let header = try #require(listView.delegate?.tableView?(listView, viewForHeaderInSection: 0) ?? nil)
        let label = try #require(firstLabel(in: header))
        #expect(label.text == "Before")

        model.title = "After"

        await waitUntil { label.text == "After" }
        #expect(label.text == "After")
        _ = window
    }

    @Test func onSelectChangeUpdatesVisibleCellSelectionStyle() async throws {
        let items = [Item(id: "a", title: "A")]
        let list = { (items: [Item]) in
            FineList(items) { FineLabel(text: $0.title) }
                .reconfiguringOnlyChangedRows()
        }
        let first = FineRenderer.render(list(items))
        let listView = try #require(first as? UITableView)
        let window = attachToWindow(listView)

        await waitForRows(1, in: listView)
        listView.layoutIfNeeded()

        let cell = try #require(listView.cellForRow(at: .init(row: 0, section: 0)))
        #expect(cell.selectionStyle == .none)

        // Elements compare equal, so no row reconfigures; visible cells must
        // still pick up the new onSelect.
        _ = FineRenderer.render(list(items).onSelect { _ in }, reusing: first)

        #expect(cell.selectionStyle == .default)
        _ = window
    }

    @Test func environmentChangeReachesVisibleCellsWithoutReconfigure() async throws {
        let items = [Item(id: "a", title: "A")]
        let list = { (badge: String) in
            FineList(items) { _ in
                FineEnvironmentReader { environment in
                    FineLabel(text: environment.testBadge)
                }
            }
            .reconfiguringOnlyChangedRows()
            .environment(\.testBadge, badge)
        }
        let first = FineRenderer.render(list("one"))
        let listView = try #require(first as? UITableView)
        let window = attachToWindow(listView)

        await waitForRows(1, in: listView)
        listView.layoutIfNeeded()

        let cell = try #require(listView.cellForRow(at: .init(row: 0, section: 0)))
        #expect(firstLabel(in: cell)?.text == "one")

        // Elements compare equal, so no row reconfigures; the change must
        // arrive through the cells' environment observation.
        _ = FineRenderer.render(list("two"), reusing: first)

        await waitUntil { firstLabel(in: cell)?.text == "two" }
        #expect(firstLabel(in: cell)?.text == "two")
        _ = window
    }

    @Test func observedHeaderGrowthUpdatesHeaderHeight() async throws {
        let model = ObservableRow(id: "h", title: "Short")
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(FineList(sections: [
            FineListSection(
                id: "main",
                header: FineLabel(text: model.title).numberOfLines(0),
                items: items
            ),
        ]) { FineLabel(text: $0.title) })
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView, width: 200)

        await waitForRows(1, in: listView)
        listView.layoutIfNeeded()

        let initialHeight = listView.rectForHeader(inSection: 0).height
        #expect(initialHeight > 0)

        model.title = String(repeating: "A long header line that must wrap. ", count: 10)

        await waitUntil {
            listView.layoutIfNeeded()
            return listView.rectForHeader(inSection: 0).height > initialHeight + 10
        }

        #expect(listView.rectForHeader(inSection: 0).height > initialHeight + 10)
        _ = window
    }

    @Test func observedRowGrowthUpdatesRowHeight() async throws {
        let row = ObservableRow(id: "a", title: "Short")
        let view = FineRenderer.render(FineList([row]) { row in
            FineLabel(text: row.title)
                .numberOfLines(0)
        })
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView, width: 200)

        await waitForRows(1, in: listView)
        listView.layoutIfNeeded()

        let initialHeight = listView.rectForRow(at: .init(row: 0, section: 0)).height
        #expect(initialHeight > 0)

        row.title = String(repeating: "A long line that must wrap. ", count: 12)

        await waitUntil {
            listView.layoutIfNeeded()
            return listView.rectForRow(at: .init(row: 0, section: 0)).height > initialHeight + 10
        }

        let updatedHeight = listView.rectForRow(at: .init(row: 0, section: 0)).height
        #expect(updatedHeight > initialHeight + 10)
        _ = window
    }
}

@MainActor
struct FineGridBehaviorTests {
    struct Item: Identifiable, Equatable {
        let id: String
        var title: String
    }

    private func attachToWindow(_ view: UIView, width: CGFloat = 400, height: CGFloat = 800) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: width, height: height))
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
        return window
    }

    private func waitForItems(_ count: Int, in collectionView: UICollectionView) async {
        for _ in 0..<100 where collectionView.numberOfSections == 0 || collectionView.numberOfItems(inSection: 0) != count {
            await Task.yield()
        }
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel {
            return label
        }

        for subview in view.subviews {
            if let label = firstLabel(in: subview) {
                return label
            }
        }

        return nil
    }

    @Test func cellContentReceivesInjectedEnvironment() async throws {
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(
            FineGrid(items) { _ in
                FineEnvironmentReader { environment in
                    FineLabel(text: environment.testBadge)
                }
            }
            .environment(\.testBadge, "injected")
        )
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)

        await waitForItems(1, in: collectionView)
        collectionView.layoutIfNeeded()

        let cell = try #require(collectionView.cellForItem(at: .init(item: 0, section: 0)))
        #expect(firstLabel(in: cell)?.text == "injected")
        _ = window
    }

    @Test func headerReceivesInjectedEnvironment() async throws {
        let items = [Item(id: "a", title: "A")]
        let view = FineRenderer.render(
            FineGrid(sections: [
                FineGridSection(
                    id: "main",
                    header: FineEnvironmentReader { environment in
                        FineLabel(text: "H-\(environment.testBadge)")
                    },
                    items: items
                ),
            ]) { FineLabel(text: $0.title) }
            .environment(\.testBadge, "injected")
        )
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)

        await waitForItems(1, in: collectionView)

        let header = try #require(collectionView.dataSource?.collectionView?(
            collectionView,
            viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader,
            at: .init(item: 0, section: 0)
        ))

        #expect(firstLabel(in: header)?.text == "H-injected")
        _ = window
    }

    @Test func supplementaryPrepareForReuseClearsHostedContent() {
        let view = FineGridHostSupplementaryView(frame: .init(x: 0, y: 0, width: 100, height: 40))
        view.render(environment: FineEnvironmentStorage(), renderGate: nil) { FineLabel(text: "X") }

        #expect(!view.subviews.isEmpty)

        // A recycled view returned by the provider's bail-out path (section
        // resolution failure) must be blank, not show the previous section.
        view.prepareForReuse()

        #expect(view.subviews.isEmpty)
    }
}
