//
//  FineGrid.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import Observation
import UIKit

public enum FineGridColumns: Equatable {
    case count(Int)
    case adaptive(minimum: CGFloat)
}

enum FineGridLayoutMath {
    /// Column count for `.adaptive`, accounting for inter-item spacing so
    /// each resulting column is at least `minimum` wide.
    static func adaptiveColumnCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        let minimum = max(minimum, 1)
        // Clamp the per-column stride so a negative spacing can never zero
        // the denominator (Int(CGFloat.infinity) traps).
        let stride = max(minimum + spacing, 1)
        return max(1, Int((width + spacing) / stride))
    }
}

@MainActor
public struct FineGrid<Element: Identifiable>: FinePrimitiveRenderable where Element.ID: Sendable {
    private let sections: [FineGridSection<Element>]
    private let columns: FineGridColumns
    private let spacing: CGFloat
    private let content: @MainActor (Element) -> any Renderable
    private var onSelect: (@MainActor (Element) -> Void)?
    private var onRefresh: (@MainActor () async -> Void)?
    private var onPrefetch: (@MainActor ([Element]) -> Void)?
    private var onCancelPrefetch: (@MainActor ([Element]) -> Void)?
    private var areElementsEqual: ((Element, Element) -> Bool)?
    private var reconfiguresAllItems = false
    private var keyboardDismissMode: UIScrollView.KeyboardDismissMode = .none

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(
        _ elements: [Element],
        columns: FineGridColumns = .count(2),
        spacing: CGFloat = 8,
        content: @escaping @MainActor (Element) -> any Renderable
    ) {
        self.sections = [.init(id: "__FineGrid.main", items: elements)]
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }

    public init(
        sections: [FineGridSection<Element>],
        columns: FineGridColumns = .count(2),
        spacing: CGFloat = 8,
        content: @escaping @MainActor (Element) -> any Renderable
    ) {
        self.sections = sections
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }

    public func onSelect(_ handler: @escaping @MainActor (Element) -> Void) -> FineGrid {
        var copy = self
        copy.onSelect = handler
        return copy
    }

    public func onRefresh(_ handler: @escaping @MainActor () async -> Void) -> FineGrid {
        var copy = self
        copy.onRefresh = handler
        return copy
    }

    public func keyboardDismissMode(_ mode: UIScrollView.KeyboardDismissMode) -> FineGrid {
        var copy = self
        copy.keyboardDismissMode = mode
        return copy
    }

    /// Reports items that are about to be needed, before they are asked for.
    ///
    /// Item content is built when the cell is configured, which is the moment
    /// it becomes visible — so anything slow inside it (a remote image, a
    /// decoded asset) starts too late and the item pops in. This is where that
    /// work starts instead. The runtime does none of it: it only forwards
    /// UIKit's warning, as elements rather than index paths.
    ///
    /// A grid is where this matters most: a row of a list is one cell, a row of
    /// a grid is as many as there are columns.
    ///
    /// Called on the main actor while scrolling, so hand the work off rather
    /// than doing it here. UIKit decides how far ahead to ask, and may ask for
    /// the same item more than once.
    public func onPrefetch(_ handler: @escaping @MainActor ([Element]) -> Void) -> FineGrid {
        var copy = self
        copy.onPrefetch = handler
        return copy
    }

    /// An opportunity to stop work started in `onPrefetch(_:)`, for items that
    /// turned out not to be needed.
    ///
    /// **Not a balancing count, and not a guarantee.** An item that scrolls
    /// into view is simply used and never reported here; an item whose element
    /// leaves the collection is not reported either, because the code that
    /// removed it is the code that knows its work is moot. Only items this grid
    /// really reported as coming are reported here, so a handler will not be
    /// asked to stop work it never started — but it should be safe to call
    /// about work that has already finished.
    public func onCancelPrefetch(_ handler: @escaping @MainActor ([Element]) -> Void) -> FineGrid {
        var copy = self
        copy.onCancelPrefetch = handler
        return copy
    }

    /// Re-runs item content for every surviving item on each grid render,
    /// instead of only for items whose element changed.
    ///
    /// Needed when item content displays values that are neither part of the
    /// element nor `@Observable` — a plain captured flag, say — because nothing
    /// else signals that those items are stale.
    public func reconfiguringAllItems() -> FineGrid {
        var copy = self
        copy.reconfiguresAllItems = true
        copy.areElementsEqual = nil
        return copy
    }

    func _makeView() -> UIView {
        let gridView = FineGridView(frame: .zero, collectionViewLayout: Self.makeLayout())
        let layout = Self.makeLayout { [weak gridView] in
            (gridView?.coordinator as? Coordinator)?.layoutConfiguration(for: $0)
        }
        gridView.setCollectionViewLayout(layout, animated: false)
        gridView.backgroundColor = .clear
        return gridView
    }

    func _canUpdate(_ view: UIView) -> Bool {
        guard let gridView = view as? FineGridView else { return false }
        return gridView.coordinator == nil || gridView.coordinator is Coordinator
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let gridView = view as? FineGridView else { return }

        let coordinator: Coordinator
        if let existing = gridView.coordinator as? Coordinator {
            coordinator = existing
        } else {
            coordinator = .init(gridView: gridView, columns: columns, spacing: spacing)
            gridView.coordinator = coordinator
        }

        coordinator.content = content
        coordinator.onSelect = onSelect
        coordinator.onRefresh = onRefresh
        coordinator.environmentStorage.update(context.environment)
        coordinator.renderGate = context.renderGate
        coordinator.onPrefetch = onPrefetch
        coordinator.onCancelPrefetch = onCancelPrefetch
        coordinator.updateRefreshControl(on: gridView)

        // Gated on change: assigning this is a statement to UIKit about its own
        // prefetch bookkeeping, and a root render caused by an unrelated part
        // of the tree has nothing to say about it. Held weakly by the
        // collection view, and the coordinator outlives it through
        // `gridView.coordinator`.
        let wantsPrefetching = coordinator.wantsPrefetching
        if (gridView.prefetchDataSource != nil) != wantsPrefetching {
            gridView.prefetchDataSource = wantsPrefetching ? coordinator : nil
        }

        if gridView.keyboardDismissMode != keyboardDismissMode {
            gridView.keyboardDismissMode = keyboardDismissMode
        }

        let plan = coordinator.plan(
            sections: sections,
            reconfiguresAll: reconfiguresAllItems,
            areElementsEqual: areElementsEqual,
            name: "FineGrid"
        )

        // The layout reads the column count and whether a section has a header
        // from the coordinator, so any of those changing has to invalidate it —
        // including when nothing about the snapshot changed and the apply below
        // is skipped.
        if coordinator.columns != columns
            || coordinator.spacing != spacing
            || plan.supplementaryDidChange
        {
            coordinator.columns = columns
            coordinator.spacing = spacing
            gridView.collectionViewLayout.invalidateLayout()
        }

        coordinator.refreshVisibleSupplementaryViews(in: gridView)

        guard plan.needsApply else { return }

        coordinator.commit(plan)
        coordinator.dataSource.apply(
            plan.makeSnapshot(),
            animatingDifferences: FineTransactionContext.allowsDiffAnimation(inWindow: gridView.window != nil)
        )
    }

    private static func makeLayout(
        configuration: (@MainActor (Int) -> LayoutConfiguration?)? = nil
    ) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { sectionIndex, environment in
            let configuration = configuration?(sectionIndex) ?? .init()
            let columns = configuration.columns
            let spacing = configuration.spacing
            let columnCount: Int
            switch columns {
            case .count(let count):
                columnCount = max(1, count)
            case .adaptive(let minimum):
                columnCount = FineGridLayoutMath.adaptiveColumnCount(
                    width: environment.container.effectiveContentSize.width,
                    minimum: minimum,
                    spacing: spacing
                )
            }

            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columnCount)),
                heightDimension: .estimated(60)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: columnCount
            )
            group.interItemSpacing = .fixed(spacing)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.boundarySupplementaryItems = Self.boundarySupplementaryItems(
                hasHeader: configuration.hasHeader,
                hasFooter: configuration.hasFooter
            )
            return section
        }
    }

    private static func boundarySupplementaryItems(
        hasHeader: Bool,
        hasFooter: Bool
    ) -> [NSCollectionLayoutBoundarySupplementaryItem] {
        var items: [NSCollectionLayoutBoundarySupplementaryItem] = []

        if hasHeader {
            let size = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(36)
            )
            items.append(.init(layoutSize: size, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top))
        }

        if hasFooter {
            let size = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(24)
            )
            items.append(.init(layoutSize: size, elementKind: UICollectionView.elementKindSectionFooter, alignment: .bottom))
        }

        return items
    }
}

public extension FineGrid where Element: Equatable {
    /// States explicitly that surviving items reconfigure only when their
    /// element compares unequal.
    ///
    /// This is also the default for `Equatable` elements, so calling it is
    /// optional; it documents the requirement that `==` covers every property
    /// the item content displays. Items that display values outside the element
    /// and outside `@Observable` state need `reconfiguringAllItems()`.
    func reconfiguringOnlyChangedItems() -> FineGrid {
        var copy = self
        copy.areElementsEqual = { $0 == $1 }
        copy.reconfiguresAllItems = false
        return copy
    }
}

extension FineGrid {
    struct LayoutConfiguration {
        var columns: FineGridColumns = .count(2)
        var spacing: CGFloat = 8
        var hasHeader = false
        var hasFooter = false
    }

    @MainActor
    final class Coordinator: FineCollectionCoordinator<Element>, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        let dataSource: UICollectionViewDiffableDataSource<FineSectionIdentifier, Element.ID>

        var columns: FineGridColumns
        var spacing: CGFloat

        init(gridView: FineGridView, columns: FineGridColumns, spacing: CGFloat) {
            self.columns = columns
            self.spacing = spacing

            gridView.register(FineGridHostCell.self, forCellWithReuseIdentifier: FineGridHostCell.reuseIdentifier)
            gridView.register(
                FineGridHostSupplementaryView.self,
                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                withReuseIdentifier: FineGridHostSupplementaryView.reuseIdentifier
            )
            gridView.register(
                FineGridHostSupplementaryView.self,
                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                withReuseIdentifier: FineGridHostSupplementaryView.reuseIdentifier
            )

            // The provider reaches the coordinator through the collection view
            // instead of capturing it, avoiding a retain cycle.
            dataSource = .init(collectionView: gridView) { collectionView, indexPath, id in
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: FineGridHostCell.reuseIdentifier,
                    for: indexPath
                )

                guard let cell = cell as? FineGridHostCell,
                      let coordinator = (collectionView as? FineGridView)?.coordinator as? Coordinator,
                      let element = coordinator.elementsByID[id],
                      let content = coordinator.content
                else { return cell }

                cell.render(
                    identity: AnyHashable(id),
                    environment: coordinator.environmentStorage,
                    renderGate: coordinator.renderGate
                ) { content(element) }

                return cell
            }

            super.init()

            dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
                let view = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: FineGridHostSupplementaryView.reuseIdentifier,
                    for: indexPath
                )

                guard let view = view as? FineGridHostSupplementaryView,
                      let coordinator = (collectionView as? FineGridView)?.coordinator as? Coordinator,
                      let kind = FineSupplementaryKind(elementKind: kind),
                      let id = coordinator.sectionID(at: indexPath.section),
                      coordinator.supplementaryNode(forSection: id, kind: kind) != nil
                else { return view }

                coordinator.install(id: id, kind: kind, in: view)
                return view
            }

            gridView.delegate = self
        }

        override func sectionID(at index: Int) -> AnyHashable? {
            dataSource.sectionIdentifier(for: index)?.value
        }

        /// Re-renders on-screen headers and footers from the current sections.
        ///
        /// The data source reconfigures items, but nothing asks the collection
        /// view for a supplementary view it already has, so a header built from
        /// changed state would keep showing the old description.
        func refreshVisibleSupplementaryViews(in gridView: UICollectionView) {
            for kind in [FineSupplementaryKind.header, .footer] {
                for indexPath in gridView.indexPathsForVisibleSupplementaryElements(ofKind: kind.elementKind) {
                    guard let view = gridView.supplementaryView(forElementKind: kind.elementKind, at: indexPath)
                            as? FineGridHostSupplementaryView,
                          let id = sectionID(at: indexPath.section),
                          supplementaryNode(forSection: id, kind: kind) != nil
                    else { continue }

                    install(id: id, kind: kind, in: view)
                    // A direct render bypasses the host's observation callback,
                    // which is what normally re-measures content that changed
                    // size.
                    view.invalidateEnclosingLayoutIfNeeded()
                }
            }
        }

        func layoutConfiguration(for sectionIndex: Int) -> LayoutConfiguration {
            guard sections.indices.contains(sectionIndex) else {
                return .init(columns: columns, spacing: spacing)
            }

            let section = sections[sectionIndex]
            return .init(
                columns: columns,
                spacing: spacing,
                hasHeader: section.header != nil,
                hasFooter: section.footer != nil
            )
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            prefetchElements(withIDs: indexPaths.compactMap { dataSource.itemIdentifier(for: $0) })
        }

        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            cancelPrefetchingElements(withIDs: indexPaths.compactMap { dataSource.itemIdentifier(for: $0) })
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: true)

            guard let id = dataSource.itemIdentifier(for: indexPath) else { return }

            selectElement(withID: id)
        }

        func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
            onSelect != nil
        }
    }
}

@MainActor
final class FineGridView: UICollectionView {
    var coordinator: AnyObject?

    private var isLayoutInvalidationScheduled = false

    /// Coalesces self-sizing invalidation from concurrently re-rendered hosts
    /// into one layout pass per main-actor turn, instead of a full
    /// invalidateLayout per changed item. Inside a transaction the pass runs
    /// in the animation block so item frames animate.
    func fineScheduleLayoutInvalidation() {
        guard !isLayoutInvalidationScheduled else { return }
        isLayoutInvalidationScheduled = true

        Task { @MainActor in
            self.isLayoutInvalidationScheduled = false

            if case .animate(let animation) = FineTransactionContext.current {
                animation.animate {
                    self.collectionViewLayout.invalidateLayout()
                    self.layoutIfNeeded()
                }
            } else {
                UIView.performWithoutAnimation {
                    self.collectionViewLayout.invalidateLayout()
                    self.layoutIfNeeded()
                }
            }
        }
    }
}

@MainActor
final class FineGridHostCell: UICollectionViewCell {
    static let reuseIdentifier = "FineGridHostCell"

    private var host: FineNodeHost?

    override func prepareForReuse() {
        super.prepareForReuse()
        host?.invalidate()
    }

    /// Renders item content under local observation tracking.
    ///
    /// This mirrors `FineUI`'s render tracking at cell scope: values read while
    /// building and rendering the item can invalidate only this cell. When an
    /// observed update changes the item's fitting height, the enclosing
    /// collection view coalesces a layout invalidation.
    func render(
        identity: AnyHashable?,
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    ) {
        ensureHost().render(identity: identity, environment: environment, renderGate: renderGate, makeNode)
    }

    /// Re-measures the grid when this view's content no longer fits its
    /// current size.
    func invalidateEnclosingLayoutIfNeeded() {
        guard contentView.fineNeedsHeightRemeasure,
              let gridView = fineEnclosing(FineGridView.self)
        else { return }

        gridView.fineScheduleLayoutInvalidation()
    }

    private func ensureHost() -> FineNodeHost {
        if let host { return host }

        let host = FineNodeHost(owner: self) { [unowned self] view in
            contentView.addSubview(view)

            let guide = contentView.layoutMarginsGuide
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: guide.topAnchor),
                view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            ])
        }
        host.onObservedRerender = { [unowned self] in
            invalidateEnclosingLayoutIfNeeded()
        }
        self.host = host
        return host
    }
}

@MainActor
final class FineGridHostSupplementaryView: UICollectionReusableView, FineSupplementaryHosting {
    static let reuseIdentifier = "FineGridHostSupplementaryView"

    private var host: FineNodeHost?

    override func prepareForReuse() {
        super.prepareForReuse()
        // Tear the hosted view down so the provider's bail-out path (section
        // resolution failure during a snapshot transition) returns a blank
        // view instead of another section's stale content.
        host?.reset()
    }

    /// Renders supplementary content under local observation tracking, the
    /// same way cells do: `@Observable` values read while rendering update
    /// this view in place, and height changes coalesce a layout invalidation.
    func render(
        identity: AnyHashable?,
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    ) {
        ensureHost().render(identity: identity, environment: environment, renderGate: renderGate, makeNode)
    }

    /// Re-measures the grid when this view's content no longer fits its
    /// current size. Called for observation-driven re-renders by the host, and
    /// by the grid after it refreshes a visible supplementary view.
    func invalidateEnclosingLayoutIfNeeded() {
        guard fineNeedsHeightRemeasure,
              let gridView = fineEnclosing(FineGridView.self)
        else { return }

        gridView.fineScheduleLayoutInvalidation()
    }

    private func ensureHost() -> FineNodeHost {
        if let host { return host }

        let host = FineNodeHost(owner: self) { [unowned self] view in
            addSubview(view)

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        host.onObservedRerender = { [unowned self] in
            invalidateEnclosingLayoutIfNeeded()
        }
        self.host = host
        return host
    }
}
