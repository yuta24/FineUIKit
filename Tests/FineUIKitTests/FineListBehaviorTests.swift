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

@Observable
private final class SupplementarySectionsState {
    var showsFirstSection = true
    var secondHeader = "B1"
}

@Observable
private final class SupplementaryHeightState {
    var title = "short"
}

@Observable
private final class SupplementaryReorderState {
    var reversed = false
    var suffix = "1"
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

        let ui = FineUI(state: state) { state in
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

        let ui = FineUI(state: state) { state in
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

    /// A section removed above a visible header shifts its index. The header
    /// must keep rendering its own section, not the one that took its place —
    /// and not blank out because the old index no longer resolves.
    @Test func headerSurvivesSectionRemovalAboveIt() async throws {
        let state = SupplementarySectionsState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 600))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state: state) { state in
            let showsFirst = state.showsFirstSection
            let secondHeader = state.secondHeader
            var sections: [FineListSection<Item>] = []
            if showsFirst {
                sections.append(.init(id: "a", header: FineLabel(text: "A"), items: [Item(id: "a1", title: "A1")]))
            }
            sections.append(.init(id: "b", header: FineLabel(text: secondHeader), items: [Item(id: "b1", title: "B1")]))
            return FineList(sections: sections) { item in
                FineLabel(text: item.title)
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()

        let listView = try #require(container.subviews.compactMap { $0 as? UITableView }.first)
        func headerText(_ section: Int) -> String? {
            listView.layoutIfNeeded()
            guard let header = listView.headerView(forSection: section) else { return nil }
            return firstLabel(in: header)?.text
        }

        for _ in 0..<200 where headerText(1) != "B1" {
            await Task.yield()
        }
        #expect(headerText(1) == "B1")

        state.showsFirstSection = false
        for _ in 0..<200 where listView.numberOfSections != 1 {
            await Task.yield()
        }
        listView.layoutIfNeeded()

        // The surviving header renders its own section at its new index, and a
        // later change to that section still reaches it.
        #expect(headerText(0) == "B1")

        state.secondHeader = "B2"
        for _ in 0..<200 where headerText(0) != "B2" {
            await Task.yield()
        }
        #expect(headerText(0) == "B2")
        _ = (window, ui)
    }

    /// Refreshing a visible header renders it directly, which bypasses the
    /// host's observation callback — the path that normally re-measures the
    /// table. Growing content must still get a taller header.
    @Test func headerHeightFollowsGrowingContent() async throws {
        let state = SupplementaryHeightState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 200, height: 600))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state: state) { state in
            let title = state.title
            return FineList(sections: [
                FineListSection(
                    id: "s",
                    header: FineLabel(text: title).numberOfLines(0),
                    items: [Item(id: "a", title: "A")]
                ),
            ]) { item in
                FineLabel(text: item.title)
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()

        let listView = try #require(container.subviews.compactMap { $0 as? UITableView }.first)
        for _ in 0..<200 where listView.headerView(forSection: 0) == nil {
            await Task.yield()
        }
        listView.layoutIfNeeded()
        let shortHeight = try #require(listView.headerView(forSection: 0)?.bounds.height)

        state.title = String(repeating: "long wrapping header text ", count: 6)
        for _ in 0..<200 where (listView.headerView(forSection: 0)?.bounds.height ?? 0) <= shortHeight {
            listView.layoutIfNeeded()
            await Task.yield()
        }

        let tallHeight = try #require(listView.headerView(forSection: 0)?.bounds.height)
        #expect(tallHeight > shortHeight)
        _ = (window, ui)
    }

    /// Reordering sections keeps every header with its own section: a view
    /// that stays on screen at a new index must not start rendering the
    /// description of whatever section moved into its old position.
    @Test func headersFollowTheirSectionThroughAReorder() async throws {
        let state = SupplementaryReorderState()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 600))
        let window = UIWindow(frame: container.frame)
        window.addSubview(container)
        window.isHidden = false

        let ui = FineUI(state: state) { state in
            let reversed = state.reversed
            let suffix = state.suffix
            let a = FineListSection(
                id: "a",
                header: FineLabel(text: "A\(suffix)"),
                items: [Item(id: "a1", title: "A1")]
            )
            let b = FineListSection(
                id: "b",
                header: FineLabel(text: "B\(suffix)"),
                items: [Item(id: "b1", title: "B1")]
            )
            return FineList(sections: reversed ? [b, a] : [a, b]) { item in
                FineLabel(text: item.title)
            }
        }
        ui.build(to: container)
        window.layoutIfNeeded()

        let listView = try #require(container.subviews.compactMap { $0 as? UITableView }.first)
        func headerText(_ section: Int) -> String? {
            listView.layoutIfNeeded()
            guard let header = listView.headerView(forSection: section) else { return nil }
            return firstLabel(in: header)?.text
        }

        for _ in 0..<200 where headerText(0) != "A1" {
            await Task.yield()
        }
        #expect(headerText(0) == "A1")
        #expect(headerText(1) == "B1")

        state.reversed = true
        for _ in 0..<200 where headerText(0) != "B1" {
            await Task.yield()
        }
        #expect(headerText(0) == "B1")
        #expect(headerText(1) == "A1")

        // A later change must reach each header through its own section.
        state.suffix = "2"
        for _ in 0..<200 where headerText(0) != "B2" {
            await Task.yield()
        }
        #expect(headerText(0) == "B2")
        #expect(headerText(1) == "A2")
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

    /// A section that gains or loses a header or footer changes nothing the
    /// diffable snapshot can express, so the list has to notice it on its own —
    /// otherwise the table is never asked for the supplementary view.
    @Test(arguments: [true, false])
    func supplementaryAppearsWhenSectionIsOtherwiseUnchanged(isHeader: Bool) async throws {
        let items = [Item(id: "a", title: "A")]
        let list = { (text: String?) in
            FineList(sections: [
                FineListSection(
                    id: "main",
                    header: isHeader ? text.map { FineLabel(text: $0) } : nil,
                    footer: isHeader ? nil : text.map { FineLabel(text: $0) },
                    items: items
                ),
            ]) { FineLabel(text: $0.title) }
        }

        let view = FineRenderer.render(list(nil))
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        await waitForRows(1, in: listView)

        func supplementary() -> UIView? {
            listView.layoutIfNeeded()
            return isHeader ? listView.headerView(forSection: 0) : listView.footerView(forSection: 0)
        }

        #expect(supplementary() == nil)

        _ = FineRenderer.render(list("S"), reusing: view)
        await waitUntil { supplementary() != nil }

        let installed = try #require(supplementary())
        #expect(firstLabel(in: installed)?.text == "S")
        _ = window
    }

    @Test(arguments: [true, false])
    func supplementaryDisappearsWhenSectionIsOtherwiseUnchanged(isHeader: Bool) async throws {
        let items = [Item(id: "a", title: "A")]
        let list = { (text: String?) in
            FineList(sections: [
                FineListSection(
                    id: "main",
                    header: isHeader ? text.map { FineLabel(text: $0) } : nil,
                    footer: isHeader ? nil : text.map { FineLabel(text: $0) },
                    items: items
                ),
            ]) { FineLabel(text: $0.title) }
        }

        let view = FineRenderer.render(list("S"))
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        await waitForRows(1, in: listView)

        func supplementary() -> UIView? {
            listView.layoutIfNeeded()
            return isHeader ? listView.headerView(forSection: 0) : listView.footerView(forSection: 0)
        }

        await waitUntil { supplementary() != nil }
        #expect(supplementary() != nil)

        _ = FineRenderer.render(list(nil), reusing: view)
        await waitUntil { supplementary() == nil }

        #expect(supplementary() == nil)
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

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
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

    /// The grid reaches the same outcome as the list through a different route
    /// — a compositional layout that has to be invalidated for the section to
    /// gain or lose its supplementary item — so it is covered separately.
    @Test(arguments: [true, false])
    func supplementaryAppearsWhenSectionIsOtherwiseUnchanged(isHeader: Bool) async throws {
        let kind = isHeader
            ? UICollectionView.elementKindSectionHeader
            : UICollectionView.elementKindSectionFooter
        let items = [Item(id: "a", title: "A")]
        let grid = { (text: String?) in
            FineGrid(sections: [
                FineGridSection(
                    id: "main",
                    header: isHeader ? text.map { FineLabel(text: $0) } : nil,
                    footer: isHeader ? nil : text.map { FineLabel(text: $0) },
                    items: items
                ),
            ]) { FineLabel(text: $0.title) }
        }

        let view = FineRenderer.render(grid(nil))
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)
        await waitForItems(1, in: collectionView)

        func supplementaries() -> [UICollectionReusableView] {
            collectionView.layoutIfNeeded()
            return collectionView.visibleSupplementaryViews(ofKind: kind)
        }

        #expect(supplementaries().isEmpty)

        _ = FineRenderer.render(grid("S"), reusing: view)
        await waitUntil { !supplementaries().isEmpty }

        let installed = try #require(supplementaries().first)
        #expect(firstLabel(in: installed)?.text == "S")
        _ = window
    }

    @Test(arguments: [true, false])
    func supplementaryDisappearsWhenSectionIsOtherwiseUnchanged(isHeader: Bool) async throws {
        let kind = isHeader
            ? UICollectionView.elementKindSectionHeader
            : UICollectionView.elementKindSectionFooter
        let items = [Item(id: "a", title: "A")]
        let grid = { (text: String?) in
            FineGrid(sections: [
                FineGridSection(
                    id: "main",
                    header: isHeader ? text.map { FineLabel(text: $0) } : nil,
                    footer: isHeader ? nil : text.map { FineLabel(text: $0) },
                    items: items
                ),
            ]) { FineLabel(text: $0.title) }
        }

        let view = FineRenderer.render(grid("S"))
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)
        await waitForItems(1, in: collectionView)

        func supplementaries() -> [UICollectionReusableView] {
            collectionView.layoutIfNeeded()
            return collectionView.visibleSupplementaryViews(ofKind: kind)
        }

        await waitUntil { !supplementaries().isEmpty }
        #expect(!supplementaries().isEmpty)

        _ = FineRenderer.render(grid(nil), reusing: view)
        await waitUntil { supplementaries().isEmpty }

        #expect(supplementaries().isEmpty)
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
