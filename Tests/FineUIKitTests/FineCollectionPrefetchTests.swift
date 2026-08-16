import Testing
import UIKit
@testable import FineUIKit

private struct PrefetchItem: Identifiable, Equatable {
    let id: String
    var title: String
}

/// Telling the app what is about to be needed.
///
/// The expensive part of a row — a remote image, a decoded asset — lives in the
/// app's content closure, not in the runtime, so all the runtime can do is
/// forward UIKit's warning. It forwards it as elements: index paths do not
/// survive a diffable apply, and everything else here is identity-based too.
@MainActor
@Suite
struct FineCollectionPrefetchTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    private func attachToWindow(_ view: UIView) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: 400, height: 800))
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
        view.layoutIfNeeded()
        return window
    }

    private func firstRowText(in listView: UITableView) -> String? {
        listView.layoutIfNeeded()
        guard let cell = listView.cellForRow(at: IndexPath(row: 0, section: 0)) else { return nil }
        return firstLabel(in: cell)?.text
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel { return label }
        for subview in view.subviews {
            if let found = firstLabel(in: subview) { return found }
        }
        return nil
    }

    private let items = [
        PrefetchItem(id: "a", title: "A"),
        PrefetchItem(id: "b", title: "B"),
        PrefetchItem(id: "c", title: "C"),
    ]

    // MARK: - List

    @Test func listReportsRowsAboutToBeNeeded() async throws {
        var prefetched: [[String]] = []
        var cancelled: [[String]] = []

        let view = FineRenderer.render(
            FineList(items) { FineLabel(text: $0.title) }
                .onPrefetch { prefetched.append($0.map(\.id)) }
                .onCancelPrefetch { cancelled.append($0.map(\.id)) }
        )
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        await waitUntil { listView.numberOfRows(inSection: 0) == 3 }

        let source = try #require(listView.prefetchDataSource)
        source.tableView(
            listView,
            prefetchRowsAt: [IndexPath(row: 0, section: 0), IndexPath(row: 2, section: 0)]
        )

        #expect(prefetched == [["a", "c"]])
        #expect(cancelled.isEmpty)

        source.tableView?(listView, cancelPrefetchingForRowsAt: [IndexPath(row: 2, section: 0)])

        #expect(cancelled == [["c"]])
        _ = window
    }

    /// Nothing to forward means nothing to ask for: UIKit does bookkeeping for
    /// a prefetch data source, and claiming one that drops every call is a lie
    /// told to the frameworks below.
    @Test func listAsksForPrefetchingOnlyWhenSomethingHandlesIt() async throws {
        let plain = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) })
        let plainList = try #require(plain as? UITableView)

        #expect(plainList.prefetchDataSource == nil)

        let handled = FineRenderer.render(
            FineList(items) { FineLabel(text: $0.title) }.onPrefetch { _ in },
            reusing: plain
        )

        #expect(try #require(handled as? UITableView).prefetchDataSource != nil)

        let removed = FineRenderer.render(FineList(items) { FineLabel(text: $0.title) }, reusing: handled)

        #expect(try #require(removed as? UITableView).prefetchDataSource == nil)
    }

    /// Cancelling is about work that started, so a list that reports no
    /// starting has nothing to cancel.
    ///
    /// A cancel handler on its own is a strange thing to write, but it is legal
    /// to write it, and what it must not do is hear about rows the app was
    /// never told were coming — the one promise `onCancelPrefetch` makes.
    @Test func aCancelHandlerAloneIsNeverToldToStopWorkThatNeverStarted() async throws {
        var cancelled: [[String]] = []

        let view = FineRenderer.render(
            FineList(items) { FineLabel(text: $0.title) }
                .onCancelPrefetch { cancelled.append($0.map(\.id)) }
        )
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        await waitUntil { listView.numberOfRows(inSection: 0) == 3 }

        // Nothing here reports work starting, so UIKit is not asked to predict
        // anything: a prefetch data source that could only ever drop the call
        // is bookkeeping asked of the frameworks below for nothing.
        #expect(listView.prefetchDataSource == nil)

        // And were it asked anyway, a cancellation still says nothing.
        let coordinator = try #require(
            (listView as? FineListView)?.coordinator as? FineList<PrefetchItem>.Coordinator
        )
        coordinator.prefetchElements(withIDs: ["a", "b"])
        coordinator.cancelPrefetchingElements(withIDs: ["a", "b"])

        #expect(cancelled.isEmpty)
        _ = window
    }

    // MARK: - Grid

    @Test func gridReportsItemsAboutToBeNeeded() async throws {
        var prefetched: [[String]] = []
        var cancelled: [[String]] = []

        let view = FineRenderer.render(
            FineGrid(items) { FineLabel(text: $0.title) }
                .onPrefetch { prefetched.append($0.map(\.id)) }
                .onCancelPrefetch { cancelled.append($0.map(\.id)) }
        )
        let gridView = try #require(view as? UICollectionView)
        let window = attachToWindow(gridView)
        await waitUntil { gridView.numberOfItems(inSection: 0) == 3 }

        let source = try #require(gridView.prefetchDataSource)
        source.collectionView(
            gridView,
            prefetchItemsAt: [IndexPath(item: 0, section: 0), IndexPath(item: 2, section: 0)]
        )

        #expect(prefetched == [["a", "c"]])
        #expect(cancelled.isEmpty)

        source.collectionView?(gridView, cancelPrefetchingForItemsAt: [IndexPath(item: 2, section: 0)])

        #expect(cancelled == [["c"]])
        _ = window
    }

    @Test func gridAsksForPrefetchingOnlyWhenSomethingHandlesIt() async throws {
        let plain = FineRenderer.render(FineGrid(items) { FineLabel(text: $0.title) })
        let plainGrid = try #require(plain as? UICollectionView)

        #expect(plainGrid.prefetchDataSource == nil)

        let handled = FineRenderer.render(
            FineGrid(items) { FineLabel(text: $0.title) }.onPrefetch { _ in },
            reusing: plain
        )

        #expect(try #require(handled as? UICollectionView).prefetchDataSource != nil)

        let removed = FineRenderer.render(FineGrid(items) { FineLabel(text: $0.title) }, reusing: handled)

        #expect(try #require(removed as? UICollectionView).prefetchDataSource == nil)
    }

    // MARK: - Shared

    /// A row is reported by identity, not by where it sat when the description
    /// was written. After a reorder, the index UIKit names has to resolve to
    /// the element that is there now.
    @Test func aReorderedRowIsReportedAsWhatIsThereNow() async throws {
        var prefetched: [[String]] = []
        let list = { (items: [PrefetchItem]) in
            FineList(items) { FineLabel(text: $0.title) }
                .onPrefetch { prefetched.append($0.map(\.id)) }
        }

        let view = FineRenderer.render(list(items))
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        await waitUntil { listView.numberOfRows(inSection: 0) == 3 }

        _ = FineRenderer.render(list(items.reversed()), reusing: view)
        // Waiting on the reorder itself: the row this asks about has to be the
        // reordered one, and `prefetchDataSource` was already set.
        await waitUntil { firstRowText(in: listView) == "C" }

        let source = try #require(listView.prefetchDataSource)
        source.tableView(listView, prefetchRowsAt: [IndexPath(row: 0, section: 0)])

        #expect(prefetched == [["c"]])
        _ = window
    }

    /// An element that leaves the collection is dropped rather than remembered
    /// for the life of the screen — and the app is not told, because the code
    /// that removed it already knows.
    @Test func anElementThatLeavesIsForgottenRatherThanCancelled() async throws {
        var cancelled: [[String]] = []
        let list = { (items: [PrefetchItem]) in
            FineList(items) { FineLabel(text: $0.title) }
                .onPrefetch { _ in }
                .onCancelPrefetch { cancelled.append($0.map(\.id)) }
        }

        let view = FineRenderer.render(list(items))
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        await waitUntil { listView.numberOfRows(inSection: 0) == 3 }

        let source = try #require(listView.prefetchDataSource)
        source.tableView(listView, prefetchRowsAt: [IndexPath(row: 2, section: 0)])

        _ = FineRenderer.render(list(Array(items.prefix(2))), reusing: view)
        await waitUntil { listView.numberOfRows(inSection: 0) == 2 }

        // "c" is gone, so a cancellation naming its old index says nothing.
        source.tableView?(listView, cancelPrefetchingForRowsAt: [IndexPath(row: 1, section: 0)])

        #expect(cancelled.isEmpty)
        _ = window
    }

    /// A cancellation names an index, and an index means something different
    /// once the rows have moved. Cancelling has to be about what was actually
    /// reported as coming — telling an app to stop work it never started is
    /// worse than saying nothing, because it will stop the wrong request.
    @Test func aCancelAfterAReorderDoesNotNameAnUnrelatedRow() async throws {
        var prefetched: [[String]] = []
        var cancelled: [[String]] = []
        let list = { (items: [PrefetchItem]) in
            FineList(items) { FineLabel(text: $0.title) }
                .onPrefetch { prefetched.append($0.map(\.id)) }
                .onCancelPrefetch { cancelled.append($0.map(\.id)) }
        }

        let view = FineRenderer.render(list(items))
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        await waitUntil { listView.numberOfRows(inSection: 0) == 3 }

        let source = try #require(listView.prefetchDataSource)
        source.tableView(listView, prefetchRowsAt: [IndexPath(row: 2, section: 0)])
        #expect(prefetched == [["c"]])

        // Row 2 now holds "a".
        _ = FineRenderer.render(list(items.reversed()), reusing: view)
        await waitUntil { listView.numberOfRows(inSection: 0) == 3 }

        source.tableView?(listView, cancelPrefetchingForRowsAt: [IndexPath(row: 2, section: 0)])

        // "a" was never reported as coming, so nothing is cancelled for it.
        #expect(cancelled.isEmpty)
        _ = window
    }

    /// An index that no longer resolves is dropped rather than reported as
    /// something else. UIKit can name a row from a snapshot the data source has
    /// already moved past.
    @Test func anIndexThatNoLongerResolvesIsNotReported() async throws {
        var prefetched: [[String]] = []

        let view = FineRenderer.render(
            FineList(items) { FineLabel(text: $0.title) }
                .onPrefetch { prefetched.append($0.map(\.id)) }
        )
        let listView = try #require(view as? UITableView)
        let window = attachToWindow(listView)
        await waitUntil { listView.numberOfRows(inSection: 0) == 3 }

        let source = try #require(listView.prefetchDataSource)
        source.tableView(listView, prefetchRowsAt: [IndexPath(row: 99, section: 0)])

        // Nothing resolved, so nothing is reported — not an empty call.
        #expect(prefetched.isEmpty)
        _ = window
    }
}
