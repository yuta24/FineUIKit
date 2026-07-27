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
public struct FineGridSection<Element: Identifiable> {
    public let id: AnyHashable
    public let header: (any Renderable)?
    public let footer: (any Renderable)?
    public let items: [Element]

    public init(id: some Hashable, items: [Element]) {
        self.id = AnyHashable(id)
        self.header = nil
        self.footer = nil
        self.items = items
    }

    public init(
        id: some Hashable,
        header: (any Renderable)? = nil,
        footer: (any Renderable)? = nil,
        items: [Element]
    ) {
        self.id = AnyHashable(id)
        self.header = header
        self.footer = footer
        self.items = items
    }

    public init(id: some Hashable, header: String? = nil, footer: String? = nil, items: [Element]) {
        self.init(
            id: id,
            header: header.map(Self.textSupplementaryView),
            footer: footer.map(Self.textSupplementaryView),
            items: items
        )
    }

    private static func textSupplementaryView(_ text: String) -> any Renderable {
        FineLabel(text: text)
            .font(.preferredFont(forTextStyle: .subheadline))
            .textColor(.secondaryLabel)
            .padding(.init(top: 8, leading: 16, bottom: 4, trailing: 16))
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
        coordinator.updateRefreshControl(on: gridView)

        if gridView.keyboardDismissMode != keyboardDismissMode {
            gridView.keyboardDismissMode = keyboardDismissMode
        }

        var snapshotSections: [FineGridSection<Element>] = []
        var seenSectionIDs = Set<AnyHashable>()
        var seenIDs = Set<Element.ID>()
        var elementsByID: [Element.ID: Element] = [:]
        var itemIDsBySectionID: [FineSectionIdentifier: [Element.ID]] = [:]

        for section in sections {
            guard seenSectionIDs.insert(section.id).inserted else {
                assertionFailure("Duplicate FineGrid section id: \(section.id)")
                continue
            }

            snapshotSections.append(section)
            let sectionIdentifier = FineSectionIdentifier(section.id)

            var sectionItemIDs: [Element.ID] = []
            for element in section.items {
                guard seenIDs.insert(element.id).inserted else {
                    assertionFailure("Duplicate FineGrid item id: \(element.id)")
                    continue
                }

                elementsByID[element.id] = element
                sectionItemIDs.append(element.id)
            }
            itemIDsBySectionID[sectionIdentifier] = sectionItemIDs
        }

        let supplementarySignature = snapshotSections.map {
            FineSupplementarySignature(
                id: FineSectionIdentifier($0.id),
                hasHeader: $0.header != nil,
                hasFooter: $0.footer != nil
            )
        }
        coordinator.sections = snapshotSections

        // Held for the apply decision below: headers and footers are not part
        // of the snapshot, so a section that gains or loses one produces no
        // snapshot difference and would otherwise never be asked for.
        let supplementaryDidChange = coordinator.supplementarySignature != supplementarySignature

        if coordinator.columns != columns
            || coordinator.spacing != spacing
            || supplementaryDidChange
        {
            coordinator.columns = columns
            coordinator.spacing = spacing
            coordinator.supplementarySignature = supplementarySignature
            gridView.collectionViewLayout.invalidateLayout()
        }

        let previousElementsByID = coordinator.elementsByID
        // The identifiers the data source holds, tracked alongside every apply
        // instead of read back through `snapshot()`, which copies them all.
        let previousIDs = coordinator.appliedItemIDs
        let sectionIDs = snapshotSections.map { FineSectionIdentifier($0.id) }

        // Items whose identity survived may still have changed content;
        // reconfigure re-runs the cell provider, which updates hosted views in
        // place. Items whose element is unchanged are skipped: `@Observable`
        // reads inside item content update their own cell through per-cell
        // observation, so re-running every surviving item is wasted work.
        let reconfiguredIDs = elementsByID.keys.filter { id in
            guard previousIDs.contains(id) else { return false }
            guard !reconfiguresAllItems,
                  let previousElement = previousElementsByID[id],
                  let currentElement = elementsByID[id]
            else { return true }

            if let areElementsEqual {
                return !areElementsEqual(previousElement, currentElement)
            }
            // Reference elements mutated in place are the same instance on both
            // sides, so no `==` can see the change: only an explicit comparator
            // opts them into skipping.
            guard !fineIsReference(currentElement) else { return true }
            // Elements that cannot be compared are conservatively reconfigured.
            return fineDynamicEquals(previousElement, currentElement) != true
        }

        coordinator.elementsByID = elementsByID
        coordinator.refreshVisibleSupplementaryViews(in: gridView)

        // A render that neither moves an item nor changes one has nothing for
        // the data source to do, and applying anyway makes it diff the whole
        // grid. Root renders are triggered by any observed read in `body`, so
        // an unrelated field elsewhere on the screen would otherwise pay for
        // this.
        let structureIsUnchanged = coordinator.appliedSectionIDs == sectionIDs
            && coordinator.appliedItemIDsBySectionID == itemIDsBySectionID
            && !supplementaryDidChange
        guard !structureIsUnchanged || !reconfiguredIDs.isEmpty else { return }

        var snapshot = NSDiffableDataSourceSnapshot<FineSectionIdentifier, Element.ID>()
        snapshot.appendSections(sectionIDs)
        for sectionID in sectionIDs {
            snapshot.appendItems(itemIDsBySectionID[sectionID] ?? [], toSection: sectionID)
        }
        snapshot.reconfigureItems(reconfiguredIDs)

        coordinator.appliedSectionIDs = sectionIDs
        coordinator.appliedItemIDsBySectionID = itemIDsBySectionID
        coordinator.appliedItemIDs = Set(elementsByID.keys)
        coordinator.dataSource.apply(
            snapshot,
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
    private static var refreshActionKey: String {
        "FineUIKit.FineGrid.refresh"
    }

    struct LayoutConfiguration {
        var columns: FineGridColumns = .count(2)
        var spacing: CGFloat = 8
        var hasHeader = false
        var hasFooter = false
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
        let dataSource: UICollectionViewDiffableDataSource<FineSectionIdentifier, Element.ID>

        var sections: [FineGridSection<Element>] = [] {
            didSet {
                sectionsByID = Dictionary(
                    sections.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        }
        /// `sections` by identity. Supplementary lookups run per section on
        /// every layout pass, and a linear scan there is work proportional to
        /// the section count for each one of them.
        private(set) var sectionsByID: [AnyHashable: FineGridSection<Element>] = [:]
        var elementsByID: [Element.ID: Element] = [:]
        /// The structure last handed to the data source. A render that changes
        /// neither the structure nor any item's content skips `apply`, which
        /// otherwise diffs the whole grid — a root render triggered by an
        /// unrelated part of the tree would pay for it on every keystroke.
        var appliedSectionIDs: [FineSectionIdentifier] = []
        var appliedItemIDsBySectionID: [FineSectionIdentifier: [Element.ID]] = [:]
        var appliedItemIDs: Set<Element.ID> = []
        var content: (@MainActor (Element) -> any Renderable)?
        var onSelect: (@MainActor (Element) -> Void)?
        var onRefresh: (@MainActor () async -> Void)?
        var columns: FineGridColumns
        var spacing: CGFloat
        var supplementarySignature: [FineSupplementarySignature] = []
        // Environment resolved at the grid's last render. Cells observe it,
        // so `.environment(_:_:)` changes reach visible items even when no
        // snapshot difference reconfigures them.
        let environmentStorage = FineEnvironmentStorage()
        // Gate of the tree this grid belongs to, so cell-local re-renders stop
        // while the screen is off screen.
        var renderGate: FineRenderGate?

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
                      let id = coordinator.sectionID(at: indexPath.section),
                      coordinator.supplementaryNode(forSection: id, kind: kind) != nil
                else { return view }

                coordinator.install(id: id, kind: kind, in: view)
                return view
            }

            gridView.delegate = self
        }

        func updateRefreshControl(on gridView: FineGridView) {
            guard onRefresh != nil else {
                gridView.refreshControl?.fineSetHandler(FineGrid<Element>.refreshActionKey, for: .valueChanged, handler: nil)
                gridView.refreshControl = nil
                return
            }

            let refreshControl = gridView.refreshControl ?? UIRefreshControl()
            gridView.refreshControl = refreshControl

            refreshControl.fineSetHandler(FineGrid<Element>.refreshActionKey, for: .valueChanged) { [weak self, weak refreshControl] _ in
                guard let self, let refreshControl else { return }

                Task { @MainActor in
                    if let onRefresh = self.onRefresh {
                        await onRefresh()
                    }
                    refreshControl.endRefreshing()
                }
            }
        }

        /// The current description for a section's header or footer, found by
        /// section identity.
        ///
        /// Supplementary views re-render outside the data source — on an
        /// environment change, say — so they read the description here rather
        /// than keeping the one they were handed, which the next root render
        /// has already replaced. Identity, not position: a view stays on screen
        /// while a section removed above it shifts every index below.
        func supplementaryNode(forSection id: AnyHashable, kind: String) -> (any Renderable)? {
            guard let section = sectionsByID[id] else { return nil }

            switch kind {
            case UICollectionView.elementKindSectionHeader:
                return section.header
            case UICollectionView.elementKindSectionFooter:
                return section.footer
            default:
                return nil
            }
        }

        /// The identifier the data source currently shows at `index`.
        ///
        /// Asked through the data source rather than a cache of our own, so an
        /// index UIKit hands us during an animated apply still resolves against
        /// the sections on screen. `sectionIdentifier(for:)` reads the applied
        /// snapshot directly; `snapshot()` would copy the whole thing, and this
        /// runs per visible supplementary view.
        func sectionID(at index: Int) -> AnyHashable? {
            dataSource.sectionIdentifier(for: index)?.value
        }

        /// Points `view` at the description for `id`, re-read on every host
        /// re-render. Falls back to the description installed here, so a lookup
        /// that misses leaves the last content in place instead of blanking it.
        func install(id: AnyHashable, kind: String, in view: FineGridHostSupplementaryView) {
            let installed = supplementaryNode(forSection: id, kind: kind)
            view.render(environment: environmentStorage, renderGate: renderGate) { [weak self] in
                self?.supplementaryNode(forSection: id, kind: kind) ?? installed ?? FineSpacer()
            }
        }

        /// Re-renders on-screen headers and footers from the current sections.
        ///
        /// The data source reconfigures items, but nothing asks the collection
        /// view for a supplementary view it already has, so a header built from
        /// changed state would keep showing the old description.
        func refreshVisibleSupplementaryViews(in gridView: UICollectionView) {
            for kind in [UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter] {
                for indexPath in gridView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
                    guard let view = gridView.supplementaryView(forElementKind: kind, at: indexPath)
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

        private func section(at index: Int) -> FineGridSection<Element>? {
            guard let id = sectionID(at: index) else { return nil }
            return sectionsByID[id]
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: true)

            guard let id = dataSource.itemIdentifier(for: indexPath),
                  let element = elementsByID[id]
            else { return }

            onSelect?(element)
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
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    ) {
        ensureHost().render(environment: environment, renderGate: renderGate, makeNode)
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
final class FineGridHostSupplementaryView: UICollectionReusableView {
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
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    ) {
        ensureHost().render(environment: environment, renderGate: renderGate, makeNode)
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
