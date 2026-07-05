//
//  FineList.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineList<Element: Identifiable>: Renderable where Element.ID: Sendable {
    private let elements: [Element]
    private let content: @MainActor (Element) -> any Renderable

    public init(_ elements: [Element], content: @escaping @MainActor (Element) -> any Renderable) {
        self.elements = elements
        self.content = content
    }

    public func _makeView() -> UIView {
        FineListView(frame: .zero, style: .plain)
    }

    public func _canUpdate(_ view: UIView) -> Bool {
        guard let listView = view as? FineListView else { return false }
        return listView.coordinator == nil || listView.coordinator is Coordinator
    }

    public func _update(_ view: UIView) {
        guard let listView = view as? FineListView else { return }

        let coordinator: Coordinator
        if let existing = listView.coordinator as? Coordinator {
            coordinator = existing
        } else {
            coordinator = .init(listView: listView)
            listView.coordinator = coordinator
        }

        coordinator.content = content
        coordinator.elementsByID = .init(elements.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

        let ids = elements.map(\.id)
        let previousIDs = Set(coordinator.dataSource.snapshot().itemIdentifiers)

        var snapshot = NSDiffableDataSourceSnapshot<Section, Element.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(ids)
        // Rows whose identity survived may still have changed content;
        // reconfigure re-runs the cell provider, which updates hosted views in place.
        snapshot.reconfigureItems(ids.filter(previousIDs.contains))

        coordinator.dataSource.apply(snapshot, animatingDifferences: listView.window != nil)
    }
}

extension FineList {
    enum Section {
        case main
    }

    @MainActor
    final class Coordinator {
        let dataSource: UITableViewDiffableDataSource<Section, Element.ID>

        var elementsByID: [Element.ID: Element] = [:]
        var content: (@MainActor (Element) -> any Renderable)?

        init(listView: FineListView) {
            listView.register(FineListHostCell.self, forCellReuseIdentifier: FineListHostCell.reuseIdentifier)

            // The provider reaches the coordinator through the table view
            // instead of capturing it, avoiding a retain cycle.
            dataSource = .init(tableView: listView) { tableView, indexPath, id in
                let cell = tableView.dequeueReusableCell(withIdentifier: FineListHostCell.reuseIdentifier, for: indexPath)

                guard let cell = cell as? FineListHostCell,
                      let coordinator = (tableView as? FineListView)?.coordinator as? Coordinator,
                      let element = coordinator.elementsByID[id],
                      let content = coordinator.content
                else { return cell }

                cell.render(content(element))

                return cell
            }
        }
    }
}

@MainActor
final class FineListView: UITableView {
    var coordinator: AnyObject?
}

@MainActor
final class FineListHostCell: UITableViewCell {
    static let reuseIdentifier = "FineListHostCell"

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
