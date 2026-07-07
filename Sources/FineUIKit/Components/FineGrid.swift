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
public struct FineGrid<Element: Identifiable>: Renderable where Element.ID: Sendable {
    private let sections: [FineGridSection<Element>]
    private let columns: FineGridColumns
    private let spacing: CGFloat
    private let content: @MainActor (Element) -> any Renderable
    private var onSelect: (@MainActor (Element) -> Void)?
    private var onRefresh: (@MainActor () async -> Void)?
    private var areElementsEqual: ((Element, Element) -> Bool)?
    private var keyboardDismissMode: UIScrollView.KeyboardDismissMode = .none

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

    public func _makeView() -> UIView {
        let gridView = FineGridView(frame: .zero, collectionViewLayout: Self.makeLayout())
        let layout = Self.makeLayout { [weak gridView] in
            (gridView?.coordinator as? Coordinator)?.layoutConfiguration(for: $0)
        }
        gridView.setCollectionViewLayout(layout, animated: false)
        gridView.backgroundColor = .clear
        return gridView
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        guard let gridView = view as? FineGridView else { return false }
        return gridView.coordinator == nil || gridView.coordinator is Coordinator
    }

    public func _update(_ view: UIView) {
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
            SectionSupplementarySignature(
                id: FineSectionIdentifier($0.id),
                hasHeader: $0.header != nil,
                hasFooter: $0.footer != nil
            )
        }
        coordinator.sections = snapshotSections

        if coordinator.columns != columns
            || coordinator.spacing != spacing
            || coordinator.supplementarySignature != supplementarySignature
        {
            coordinator.columns = columns
            coordinator.spacing = spacing
            coordinator.supplementarySignature = supplementarySignature
            gridView.collectionViewLayout.invalidateLayout()
        }

        let previousElementsByID = coordinator.elementsByID
        let previousIDs = Set(coordinator.dataSource.snapshot().itemIdentifiers)

        var snapshot = NSDiffableDataSourceSnapshot<FineSectionIdentifier, Element.ID>()
        let sectionIDs = snapshotSections.map { FineSectionIdentifier($0.id) }
        snapshot.appendSections(sectionIDs)
        for sectionID in sectionIDs {
            snapshot.appendItems(itemIDsBySectionID[sectionID] ?? [], toSection: sectionID)
        }
        // Items whose identity survived may still have changed content;
        // reconfigure re-runs the cell provider, which updates hosted views in place.
        let reconfiguredIDs = elementsByID.keys.filter { id in
            guard previousIDs.contains(id) else { return false }
            guard let areElementsEqual,
                  let previousElement = previousElementsByID[id],
                  let currentElement = elementsByID[id]
            else { return true }

            return !areElementsEqual(previousElement, currentElement)
        }
        snapshot.reconfigureItems(reconfiguredIDs)

        coordinator.elementsByID = elementsByID
        coordinator.dataSource.apply(snapshot, animatingDifferences: gridView.window != nil)
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
                columnCount = max(1, Int(environment.container.effectiveContentSize.width / max(minimum, 1)))
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
    /// Reconfigures only items whose element compares unequal to the previous
    /// render, instead of every surviving item.
    ///
    /// Requires `==` to cover every property the item content displays.
    /// Intended for value-type elements: class elements mutated in place
    /// compare equal to themselves and will never reconfigure. Items that read
    /// `@Observable` properties update through per-cell observation instead.
    func reconfiguringOnlyChangedItems() -> FineGrid {
        var copy = self
        copy.areElementsEqual = { $0 == $1 }
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

    struct SectionSupplementarySignature: Equatable {
        let id: FineSectionIdentifier
        let hasHeader: Bool
        let hasFooter: Bool
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
        let dataSource: UICollectionViewDiffableDataSource<FineSectionIdentifier, Element.ID>

        var sections: [FineGridSection<Element>] = []
        var elementsByID: [Element.ID: Element] = [:]
        var content: (@MainActor (Element) -> any Renderable)?
        var onSelect: (@MainActor (Element) -> Void)?
        var onRefresh: (@MainActor () async -> Void)?
        var columns: FineGridColumns
        var spacing: CGFloat
        var supplementarySignature: [SectionSupplementarySignature] = []

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

                cell.render { content(element) }

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
                      let section = coordinator.section(at: indexPath.section)
                else { return view }

                let node: (any Renderable)?
                switch kind {
                case UICollectionView.elementKindSectionHeader:
                    node = section.header
                case UICollectionView.elementKindSectionFooter:
                    node = section.footer
                default:
                    node = nil
                }

                if let node {
                    view.render(node)
                }
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
            let identifiers = dataSource.snapshot().sectionIdentifiers
            guard identifiers.indices.contains(index) else { return nil }
            let id = identifiers[index]
            return sections.first { $0.id == id.value }
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
}

@MainActor
final class FineGridHostCell: UICollectionViewCell {
    static let reuseIdentifier = "FineGridHostCell"

    private var hostedView: UIView?
    private var makeNode: (@MainActor () -> any Renderable)?
    private var generation = 0

    override func prepareForReuse() {
        super.prepareForReuse()
        makeNode = nil
        generation += 1
    }

    /// Renders item content under local observation tracking.
    ///
    /// This mirrors `FineUI`'s render tracking at cell scope: values read while
    /// building and rendering the item can invalidate only this cell. Height
    /// changes caused by observed updates do not ask `UICollectionView` to
    /// recalculate item height; this is intended for height-stable updates.
    func render(_ makeNode: @escaping @MainActor () -> any Renderable) {
        self.makeNode = makeNode
        renderTracked()
    }

    private func renderTracked() {
        generation += 1
        let expectedGeneration = generation
        guard let makeNode else { return }

        let view = withObservationTracking {
            FineRenderer.render(makeNode(), reusing: hostedView)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.generation == expectedGeneration,
                      self.makeNode != nil
                else { return }

                self.renderTracked()
            }
        }

        guard view !== hostedView else { return }

        hostedView?.removeFromSuperview()
        hostedView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)

        let guide = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: guide.topAnchor),
            view.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
    }
}

@MainActor
final class FineGridHostSupplementaryView: UICollectionReusableView {
    static let reuseIdentifier = "FineGridHostSupplementaryView"

    private var hostedView: UIView?

    override func prepareForReuse() {
        super.prepareForReuse()
        hostedView?.removeFromSuperview()
        hostedView = nil
    }

    func render(_ node: any Renderable) {
        let view = FineRenderer.render(node, reusing: hostedView)
        guard view !== hostedView else { return }

        hostedView?.removeFromSuperview()
        hostedView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
