//
//  FineList.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import Observation
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

struct FineSectionIdentifier: Hashable, @unchecked Sendable {
    let value: AnyHashable

    init(_ value: AnyHashable) {
        self.value = value
    }
}

@MainActor
public struct FineList<Element: Identifiable>: FinePrimitiveRenderable where Element.ID: Sendable {
    private let sections: [FineListSection<Element>]
    private let content: @MainActor (Element) -> any Renderable
    private var onSelect: (@MainActor (Element) -> Void)?
    private var onDelete: (@MainActor (Element) -> Void)?
    private var onRefresh: (@MainActor () async -> Void)?
    private var areElementsEqual: ((Element, Element) -> Bool)?
    private var deleteActionTitle: String = "Delete"
    private var keyboardDismissMode: UIScrollView.KeyboardDismissMode = .none

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

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

    public func keyboardDismissMode(_ mode: UIScrollView.KeyboardDismissMode) -> FineList {
        var copy = self
        copy.keyboardDismissMode = mode
        return copy
    }

    func _makeView() -> UIView {
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

    func _canUpdate(_ view: UIView) -> Bool {
        guard let listView = view as? FineListView else { return false }
        return listView.coordinator == nil || listView.coordinator is Coordinator
    }

    func _update(_ view: UIView, context: FineRenderContext) {
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
        coordinator.environmentStorage.update(context.environment)
        coordinator.dataSource.canEditRows = onDelete != nil
        coordinator.updateRefreshControl(on: listView)

        if listView.keyboardDismissMode != keyboardDismissMode {
            listView.keyboardDismissMode = keyboardDismissMode
        }

        // The cell provider sets selectionStyle only when a cell is
        // (re)configured; visible cells must follow onSelect changes even when
        // no snapshot difference reconfigures them. Gated so the sweep runs
        // only when the style actually flips, not on every render.
        let selectionStyle = coordinator.selectionStyle
        if coordinator.appliedSelectionStyle != selectionStyle {
            coordinator.appliedSelectionStyle = selectionStyle
            for cell in listView.visibleCells where cell.selectionStyle != selectionStyle {
                cell.selectionStyle = selectionStyle
            }
        }

        var snapshotSections: [FineListSection<Element>] = []
        var seenSectionIDs = Set<AnyHashable>()
        var seenIDs = Set<Element.ID>()
        var elementsByID: [Element.ID: Element] = [:]
        var itemIDsBySectionID: [FineSectionIdentifier: [Element.ID]] = [:]

        for section in sections {
            guard seenSectionIDs.insert(section.id).inserted else {
                assertionFailure("Duplicate FineList section id: \(section.id)")
                continue
            }

            snapshotSections.append(section)
            let sectionIdentifier = FineSectionIdentifier(section.id)

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
        let previousElementsByID = coordinator.elementsByID

        let previousIDs = Set(coordinator.dataSource.snapshot().itemIdentifiers)

        var snapshot = NSDiffableDataSourceSnapshot<FineSectionIdentifier, Element.ID>()
        let sectionIDs = snapshotSections.map { FineSectionIdentifier($0.id) }
        snapshot.appendSections(sectionIDs)
        for sectionID in sectionIDs {
            snapshot.appendItems(itemIDsBySectionID[sectionID] ?? [], toSection: sectionID)
        }
        // Rows whose identity survived may still have changed content;
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
        coordinator.dataSource.apply(
            snapshot,
            animatingDifferences: FineTransactionContext.allowsDiffAnimation(inWindow: listView.window != nil)
        )
    }
}

public extension FineList where Element: Equatable {
    /// Reconfigures only rows whose element compares unequal to the previous
    /// render, instead of every surviving row.
    ///
    /// Requires `==` to cover every property the row content displays.
    /// Intended for value-type elements: class elements mutated in place
    /// compare equal to themselves and will never reconfigure. Rows that read
    /// `@Observable` properties update through per-cell observation instead.
    func reconfiguringOnlyChangedRows() -> FineList {
        var copy = self
        copy.areElementsEqual = { $0 == $1 }
        return copy
    }
}

extension FineList {
    private static var refreshActionKey: String {
        "FineUIKit.FineList.refresh"
    }

    @MainActor
    final class DataSource: UITableViewDiffableDataSource<FineSectionIdentifier, Element.ID> {
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
        // Environment resolved at the list's last render. Cells observe it,
        // so `.environment(_:_:)` changes reach visible rows even when no
        // snapshot difference reconfigures them.
        let environmentStorage = FineEnvironmentStorage()
        var appliedSelectionStyle: UITableViewCell.SelectionStyle?

        var selectionStyle: UITableViewCell.SelectionStyle {
            onSelect == nil ? .none : .default
        }

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

                cell.selectionStyle = coordinator.selectionStyle
                cell.render(environment: coordinator.environmentStorage) { content(element) }

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
            view.render(node, environment: environmentStorage)
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

    private var isRowHeightInvalidationScheduled = false

    /// Coalesces self-sizing invalidation from concurrently re-rendered hosts
    /// into one height pass per main-actor turn, instead of one
    /// beginUpdates/endUpdates per changed cell.
    func fineScheduleRowHeightInvalidation() {
        guard !isRowHeightInvalidationScheduled else { return }
        isRowHeightInvalidationScheduled = true

        Task { @MainActor in
            self.isRowHeightInvalidationScheduled = false

            if case .animate(let animation) = FineTransactionContext.current {
                animation.animate {
                    self.beginUpdates()
                    self.endUpdates()
                    self.layoutIfNeeded()
                }
            } else {
                UIView.performWithoutAnimation {
                    self.beginUpdates()
                    self.endUpdates()
                }
            }
        }
    }
}

@MainActor
final class FineListHostCell: UITableViewCell {
    static let reuseIdentifier = "FineListHostCell"

    private var host: FineNodeHost?

    override func prepareForReuse() {
        super.prepareForReuse()
        host?.invalidate()
    }

    /// Renders row content under local observation tracking.
    ///
    /// This mirrors `FineUI`'s render tracking at cell scope: values read while
    /// building and rendering the row can invalidate only this cell. When an
    /// observed update changes the row's fitting height, the enclosing table
    /// view coalesces a row-height recalculation.
    func render(environment: FineEnvironmentStorage, _ makeNode: @escaping @MainActor () -> any Renderable) {
        ensureHost().render(environment: environment, makeNode)
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
            guard contentView.fineNeedsHeightRemeasure,
                  let listView = fineEnclosing(FineListView.self)
            else { return }

            listView.fineScheduleRowHeightInvalidation()
        }
        self.host = host
        return host
    }
}

@MainActor
final class FineListHostHeaderFooterView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "FineListHostHeaderFooterView"

    private var host: FineNodeHost?

    override func prepareForReuse() {
        super.prepareForReuse()
        host?.invalidate()
    }

    /// Renders supplementary content under local observation tracking, the
    /// same way cells do: `@Observable` values read while rendering update
    /// this view in place, and height changes coalesce a table re-measure.
    func render(_ node: any Renderable, environment: FineEnvironmentStorage) {
        ensureHost().render(environment: environment) { node }
    }

    private func ensureHost() -> FineNodeHost {
        if let host { return host }

        let host = FineNodeHost(owner: self) { [unowned self] view in
            contentView.addSubview(view)

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentView.topAnchor),
                view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }
        host.onObservedRerender = { [unowned self] in
            guard contentView.fineNeedsHeightRemeasure,
                  let listView = fineEnclosing(FineListView.self)
            else { return }

            listView.fineScheduleRowHeightInvalidation()
        }
        self.host = host
        return host
    }
}
