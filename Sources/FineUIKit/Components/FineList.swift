//
//  FineList.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import UIKit

@MainActor
public struct FineListSection<Element: Identifiable> {
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

struct FineListSectionIdentifier: Hashable, @unchecked Sendable {
    let value: AnyHashable

    init(_ value: AnyHashable) {
        self.value = value
    }
}

@MainActor
public struct FineList<Element: Identifiable>: Renderable where Element.ID: Sendable {
    private let sections: [FineListSection<Element>]
    private let content: @MainActor (Element) -> any Renderable
    private var onSelect: (@MainActor (Element) -> Void)?
    private var onDelete: (@MainActor (Element) -> Void)?
    private var onRefresh: (@MainActor () async -> Void)?
    private var deleteActionTitle: String = "Delete"

    public init(_ elements: [Element], content: @escaping @MainActor (Element) -> any Renderable) {
        self.sections = [.init(id: "__FineList.main", items: elements)]
        self.content = content
    }

    public init(sections: [FineListSection<Element>], content: @escaping @MainActor (Element) -> any Renderable) {
        self.sections = sections
        self.content = content
    }

    public func onSelect(_ handler: @escaping @MainActor (Element) -> Void) -> FineList {
        var copy = self
        copy.onSelect = handler
        return copy
    }

    /// Enables swipe-to-delete. Pass a localized `title` for the action
    /// button; the default is the English "Delete".
    public func onDelete(title: String = "Delete", _ handler: @escaping @MainActor (Element) -> Void) -> FineList {
        var copy = self
        copy.onDelete = handler
        copy.deleteActionTitle = title
        return copy
    }

    public func onRefresh(_ handler: @escaping @MainActor () async -> Void) -> FineList {
        var copy = self
        copy.onRefresh = handler
        return copy
    }

    public func _makeView() -> UIView {
        let listView = FineListView(frame: .zero, style: .plain)
        listView.sectionHeaderHeight = UITableView.automaticDimension
        listView.estimatedSectionHeaderHeight = 36
        listView.sectionFooterHeight = UITableView.automaticDimension
        listView.estimatedSectionFooterHeight = 24
        if #available(iOS 15.0, *) {
            listView.sectionHeaderTopPadding = 0
        }
        return listView
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
        coordinator.onSelect = onSelect
        coordinator.onDelete = onDelete
        coordinator.onRefresh = onRefresh
        coordinator.deleteActionTitle = deleteActionTitle
        coordinator.dataSource.canEditRows = onDelete != nil
        coordinator.updateRefreshControl(on: listView)

        var snapshotSections: [FineListSection<Element>] = []
        var seenSectionIDs = Set<AnyHashable>()
        var seenIDs = Set<Element.ID>()
        var elementsByID: [Element.ID: Element] = [:]
        var itemIDsBySectionID: [FineListSectionIdentifier: [Element.ID]] = [:]

        for section in sections {
            guard seenSectionIDs.insert(section.id).inserted else {
                assertionFailure("Duplicate FineList section id: \(section.id)")
                continue
            }

            snapshotSections.append(section)
            let sectionIdentifier = FineListSectionIdentifier(section.id)

            var sectionItemIDs: [Element.ID] = []
            for element in section.items {
                guard seenIDs.insert(element.id).inserted else {
                    assertionFailure("Duplicate FineList item id: \(element.id)")
                    continue
                }

                elementsByID[element.id] = element
                sectionItemIDs.append(element.id)
            }
            itemIDsBySectionID[sectionIdentifier] = sectionItemIDs
        }

        coordinator.sections = snapshotSections
        coordinator.elementsByID = elementsByID

        let previousIDs = Set(coordinator.dataSource.snapshot().itemIdentifiers)

        var snapshot = NSDiffableDataSourceSnapshot<FineListSectionIdentifier, Element.ID>()
        let sectionIDs = snapshotSections.map { FineListSectionIdentifier($0.id) }
        snapshot.appendSections(sectionIDs)
        for sectionID in sectionIDs {
            snapshot.appendItems(itemIDsBySectionID[sectionID] ?? [], toSection: sectionID)
        }
        // Rows whose identity survived may still have changed content;
        // reconfigure re-runs the cell provider, which updates hosted views in place.
        snapshot.reconfigureItems(elementsByID.keys.filter(previousIDs.contains))

        coordinator.dataSource.apply(snapshot, animatingDifferences: listView.window != nil)
    }
}

extension FineList {
    private static var refreshActionKey: String {
        "FineUIKit.FineList.refresh"
    }

    @MainActor
    final class DataSource: UITableViewDiffableDataSource<FineListSectionIdentifier, Element.ID> {
        var canEditRows = false

        override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            canEditRows
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITableViewDelegate {
        let dataSource: DataSource

        var sections: [FineListSection<Element>] = []
        var elementsByID: [Element.ID: Element] = [:]
        var content: (@MainActor (Element) -> any Renderable)?
        var onSelect: (@MainActor (Element) -> Void)?
        var onDelete: (@MainActor (Element) -> Void)?
        var onRefresh: (@MainActor () async -> Void)?
        var deleteActionTitle: String = "Delete"

        init(listView: FineListView) {
            listView.register(FineListHostCell.self, forCellReuseIdentifier: FineListHostCell.reuseIdentifier)
            listView.register(
                FineListHostHeaderFooterView.self,
                forHeaderFooterViewReuseIdentifier: FineListHostHeaderFooterView.reuseIdentifier
            )

            // The provider reaches the coordinator through the table view
            // instead of capturing it, avoiding a retain cycle.
            dataSource = .init(tableView: listView) { tableView, indexPath, id in
                let cell = tableView.dequeueReusableCell(withIdentifier: FineListHostCell.reuseIdentifier, for: indexPath)

                guard let cell = cell as? FineListHostCell,
                      let coordinator = (tableView as? FineListView)?.coordinator as? Coordinator,
                      let element = coordinator.elementsByID[id],
                      let content = coordinator.content
                else { return cell }

                cell.selectionStyle = coordinator.onSelect == nil ? .none : .default
                cell.render(content(element))

                return cell
            }

            super.init()

            listView.delegate = self
        }

        func updateRefreshControl(on listView: FineListView) {
            guard onRefresh != nil else {
                listView.refreshControl?.fineSetHandler(FineList<Element>.refreshActionKey, for: .valueChanged, handler: nil)
                listView.refreshControl = nil
                return
            }

            let refreshControl = listView.refreshControl ?? UIRefreshControl()
            listView.refreshControl = refreshControl

            refreshControl.fineSetHandler(FineList<Element>.refreshActionKey, for: .valueChanged) { [weak self, weak refreshControl] _ in
                guard let self, let refreshControl else { return }

                Task { @MainActor in
                    if let onRefresh = self.onRefresh {
                        await onRefresh()
                    }
                    refreshControl.endRefreshing()
                }
            }
        }

        private func section(at index: Int) -> FineListSection<Element>? {
            let identifiers = dataSource.snapshot().sectionIdentifiers
            guard identifiers.indices.contains(index) else { return nil }
            let id = identifiers[index]
            return sections.first { $0.id == id.value }
        }

        private func supplementaryView(
            in tableView: UITableView,
            for node: (any Renderable)?
        ) -> UIView? {
            guard let node else { return nil }

            let view = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: FineListHostHeaderFooterView.reuseIdentifier
            )

            guard let view = view as? FineListHostHeaderFooterView else { return nil }
            view.render(node)
            return view
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            supplementaryView(in: tableView, for: self.section(at: section)?.header)
        }

        func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
            supplementaryView(in: tableView, for: self.section(at: section)?.footer)
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            self.section(at: section)?.header == nil ? .leastNonzeroMagnitude : UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
            self.section(at: section)?.footer == nil ? .leastNonzeroMagnitude : UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)

            guard let id = dataSource.itemIdentifier(for: indexPath),
                  let element = elementsByID[id]
            else { return }

            onSelect?(element)
        }

        func tableView(
            _ tableView: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard let onDelete,
                  let id = dataSource.itemIdentifier(for: indexPath),
                  let element = elementsByID[id]
            else { return nil }

            let action = UIContextualAction(style: .destructive, title: deleteActionTitle) { _, _, completion in
                MainActor.assumeIsolated {
                    onDelete(element)
                    completion(true)
                }
            }
            return .init(actions: [action])
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

@MainActor
final class FineListHostHeaderFooterView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "FineListHostHeaderFooterView"

    private var hostedView: UIView?

    func render(_ node: any Renderable) {
        let view = FineRenderer.render(node, reusing: hostedView)
        guard view !== hostedView else { return }

        hostedView?.removeFromSuperview()
        hostedView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }
}
