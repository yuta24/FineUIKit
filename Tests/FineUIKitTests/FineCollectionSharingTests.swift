import Testing
import UIKit
@testable import FineUIKit

private struct SharedItem: Identifiable, Equatable {
    let id: String
    var title: String
}

/// What `FineList` and `FineGrid` hold in common.
///
/// They reconcile through one implementation, so the point of these is that
/// neither can quietly grow a version of its own: a section is one type, and a
/// header reaches the screen the same way in both.
@MainActor
@Suite
struct FineCollectionSharingTests {
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

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel { return label }
        for subview in view.subviews {
            if let found = firstLabel(in: subview) { return found }
        }
        return nil
    }

    /// One value, both collections. `FineListSection` and `FineGridSection` are
    /// spellings of `FineSection`, so a section built once describes either —
    /// and re-splitting them would stop this compiling.
    @Test func oneSectionValueDescribesEitherCollection() async throws {
        let section = FineSection(
            id: "main",
            header: FineLabel(text: "H"),
            items: [SharedItem(id: "a", title: "A")]
        )
        let listSection: FineListSection<SharedItem> = section
        let gridSection: FineGridSection<SharedItem> = section

        let listView = try #require(
            FineRenderer.render(FineList(sections: [listSection]) { FineLabel(text: $0.title) }) as? UITableView
        )
        let gridView = try #require(
            FineRenderer.render(FineGrid(sections: [gridSection]) { FineLabel(text: $0.title) }) as? UICollectionView
        )
        let listWindow = attachToWindow(listView)
        let gridWindow = attachToWindow(gridView)

        await waitUntil { listView.numberOfRows(inSection: 0) == 1 }
        await waitUntil { gridView.numberOfItems(inSection: 0) == 1 }

        #expect(listView.numberOfSections == 1)
        #expect(gridView.numberOfSections == 1)
        #expect(listView.numberOfRows(inSection: 0) == 1)
        #expect(gridView.numberOfItems(inSection: 0) == 1)

        listView.layoutIfNeeded()
        gridView.layoutIfNeeded()

        // The header is described once and reaches both.
        let listHeader = listView.headerView(forSection: 0)
        await waitUntil {
            gridView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader).isEmpty == false
        }
        let gridHeader = gridView
            .visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
            .first

        #expect(firstLabel(in: try #require(listHeader))?.text == "H")
        #expect(firstLabel(in: try #require(gridHeader))?.text == "H")

        _ = listWindow
        _ = gridWindow
    }

    /// Header and footer are told apart by kind, not by a bare `Bool` or a
    /// UIKit string, and the two ends must not collide as one identity.
    @Test func headerAndFooterAreDistinctSupplementaryIdentities() {
        let header = FineSupplementaryIdentity(section: AnyHashable("s"), kind: .header)
        let footer = FineSupplementaryIdentity(section: AnyHashable("s"), kind: .footer)

        #expect(header != footer)
        #expect(header == FineSupplementaryIdentity(section: AnyHashable("s"), kind: .header))
        #expect(header != FineSupplementaryIdentity(section: AnyHashable("t"), kind: .header))
    }

    /// The kind survives the trip through the collection view's string form,
    /// which is the only place it is spelled that way.
    @Test func supplementaryKindRoundTripsThroughItsElementKind() {
        #expect(FineSupplementaryKind(elementKind: FineSupplementaryKind.header.elementKind) == .header)
        #expect(FineSupplementaryKind(elementKind: FineSupplementaryKind.footer.elementKind) == .footer)
        #expect(FineSupplementaryKind(elementKind: "something else") == nil)
    }
}
