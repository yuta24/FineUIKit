//
//  FineGrid.swift
//  FineUIKit
//
//  Created by nova on 2026/07/06.
//

import UIKit

public enum FineGridColumns: Equatable {
    case count(Int)
    case adaptive(minimum: CGFloat)
}

@MainActor
public struct FineGrid<Element: Identifiable>: Renderable where Element.ID: Sendable {
    private let elements: [Element]
    private let columns: FineGridColumns
    private let spacing: CGFloat
    private let content: @MainActor (Element) -> any Renderable
    private var onSelect: (@MainActor (Element) -> Void)?

    public init(
        _ elements: [Element],
        columns: FineGridColumns = .count(2),
        spacing: CGFloat = 8,
        content: @escaping @MainActor (Element) -> any Renderable
    ) {
        self.elements = elements
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }

    public func onSelect(_ handler: @escaping @MainActor (Element) -> Void) -> FineGrid {
        var copy = self
        copy.onSelect = handler
        return copy
    }

    public func _makeView() -> UIView {
        let gridView = FineGridView(frame: .zero, collectionViewLayout: Self.makeLayout())
        let layout = Self.makeLayout { [weak gridView] in
            (gridView?.coordinator as? Coordinator).map { ($0.columns, $0.spacing) }
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
        coordinator.elementsByID = .init(elements.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        coordinator.onSelect = onSelect

        if coordinator.columns != columns || coordinator.spacing != spacing {
            coordinator.columns = columns
            coordinator.spacing = spacing
            gridView.collectionViewLayout.invalidateLayout()
        }

        let ids = elements.map(\.id)
        let previousIDs = Set(coordinator.dataSource.snapshot().itemIdentifiers)

        var snapshot = NSDiffableDataSourceSnapshot<Section, Element.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(ids)
        snapshot.reconfigureItems(ids.filter(previousIDs.contains))

        coordinator.dataSource.apply(snapshot, animatingDifferences: gridView.window != nil)
    }

    private static func makeLayout(
        configuration: (@MainActor () -> (FineGridColumns, CGFloat)?)? = nil
    ) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let (columns, spacing) = configuration?() ?? (.count(2), 8)
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
            return section
        }
    }
}

extension FineGrid {
    enum Section {
        case main
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
        let dataSource: UICollectionViewDiffableDataSource<Section, Element.ID>

        var elementsByID: [Element.ID: Element] = [:]
        var content: (@MainActor (Element) -> any Renderable)?
        var onSelect: (@MainActor (Element) -> Void)?
        var columns: FineGridColumns
        var spacing: CGFloat

        init(gridView: FineGridView, columns: FineGridColumns, spacing: CGFloat) {
            self.columns = columns
            self.spacing = spacing

            gridView.register(FineGridHostCell.self, forCellWithReuseIdentifier: FineGridHostCell.reuseIdentifier)

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

                cell.render(content(element))

                return cell
            }

            super.init()

            gridView.delegate = self
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

    func render(_ node: any Renderable) {
        let view = FineRenderer.render(node, reusing: hostedView)
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
