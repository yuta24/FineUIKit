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

/// Which sections carry a header and a footer.
///
/// Supplementary views live outside the diffable snapshot, so a section that
/// gains or loses one produces no snapshot difference. Lists and grids compare
/// this alongside the snapshot structure, or a header appearing on an otherwise
/// unchanged section would never be asked for.
struct FineSupplementarySignature: Equatable {
    let id: FineSectionIdentifier
    let hasHeader: Bool
    let hasFooter: Bool
}

/// What a recycled supplementary host is showing, so it can tell that it has
/// been handed a different section's header rather than the same one again.
struct FineSupplementaryIdentity: Hashable {
    let section: AnyHashable
    let kind: String
}

@MainActor
public struct FineList<Element: Identifiable>: FinePrimitiveRenderable where Element.ID: Sendable {
    private let sections: [FineListSection<Element>]
    private let content: @MainActor (Element) -> any Renderable
    private var onSelect: (@MainActor (Element) -> Void)?
    private var onDelete: (@MainActor (Element) -> Void)?
    private var onRefresh: (@MainActor () async -> Void)?
    private var areElementsEqual: ((Element, Element) -> Bool)?
    private var reconfiguresAllRows = false
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

    /// Re-runs row content for every surviving row on each list render, instead
    /// of only for rows whose element changed.
    ///
    /// Needed when row content displays values that are neither part of the
    /// element nor `@Observable` — a plain captured flag, say — because nothing
    /// else signals that those rows are stale.
    public func reconfiguringAllRows() -> FineList {
        var copy = self
        copy.reconfiguresAllRows = true
        copy.areElementsEqual = nil
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
        coordinator.renderGate = context.renderGate
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

        // The identifiers the data source holds, tracked alongside every apply
        // instead of read back through `snapshot()`, which copies them all.
        let previousIDs = coordinator.appliedItemIDs
        let sectionIDs = snapshotSections.map { FineSectionIdentifier($0.id) }
        let supplementarySignature = snapshotSections.map {
            FineSupplementarySignature(
                id: FineSectionIdentifier($0.id),
                hasHeader: $0.header != nil,
                hasFooter: $0.footer != nil
            )
        }

        // Rows whose identity survived may still have changed content;
        // reconfigure re-runs the cell provider, which updates hosted views in
        // place. Rows whose element is unchanged are skipped: `@Observable`
        // reads inside row content update their own cell through per-cell
        // observation, so re-running every surviving row is wasted work.
        let reconfiguredIDs = elementsByID.keys.filter { id in
            guard previousIDs.contains(id) else { return false }
            guard !reconfiguresAllRows,
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
        coordinator.refreshVisibleSupplementaryViews(in: listView)

        // A render that neither moves a row nor changes one has nothing for the
        // data source to do, and applying anyway makes it diff the whole list.
        // Root renders are triggered by any observed read in `body`, so an
        // unrelated field elsewhere on the screen would otherwise pay for this.
        //
        // Headers and footers are compared too, because they are not part of
        // the snapshot: a section that gains or loses one looks identical here,
        // and the table only re-asks for supplementary views when something
        // makes it reload.
        let structureIsUnchanged = coordinator.appliedSectionIDs == sectionIDs
            && coordinator.appliedItemIDsBySectionID == itemIDsBySectionID
            && coordinator.appliedSupplementarySignature == supplementarySignature
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
        coordinator.appliedSupplementarySignature = supplementarySignature
        coordinator.dataSource.apply(
            snapshot,
            animatingDifferences: FineTransactionContext.allowsDiffAnimation(inWindow: listView.window != nil)
        )
    }
}

public extension FineList where Element: Equatable {
    /// States explicitly that surviving rows reconfigure only when their
    /// element compares unequal.
    ///
    /// This is also the default for `Equatable` elements, so calling it is
    /// optional; it documents the requirement that `==` covers every property
    /// the row content displays. Class elements mutated in place compare equal
    /// to themselves and never reconfigure — rows that read `@Observable`
    /// properties update through per-cell observation instead, and rows that
    /// display neither need `reconfiguringAllRows()`.
    func reconfiguringOnlyChangedRows() -> FineList {
        var copy = self
        copy.areElementsEqual = { $0 == $1 }
        copy.reconfiguresAllRows = false
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

        var sections: [FineListSection<Element>] = [] {
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
        private(set) var sectionsByID: [AnyHashable: FineListSection<Element>] = [:]
        var elementsByID: [Element.ID: Element] = [:]
        /// The structure last handed to the data source. A render that changes
        /// neither the structure nor any row's content skips `apply`, which
        /// otherwise diffs the whole list — a root render triggered by an
        /// unrelated part of the tree would pay for it on every keystroke.
        var appliedSectionIDs: [FineSectionIdentifier] = []
        var appliedItemIDsBySectionID: [FineSectionIdentifier: [Element.ID]] = [:]
        var appliedItemIDs: Set<Element.ID> = []
        var appliedSupplementarySignature: [FineSupplementarySignature] = []
        var content: (@MainActor (Element) -> any Renderable)?
        var onSelect: (@MainActor (Element) -> Void)?
        var onDelete: (@MainActor (Element) -> Void)?
        var onRefresh: (@MainActor () async -> Void)?
        var deleteActionTitle: String = "Delete"
        // Environment resolved at the list's last render. Cells observe it,
        // so `.environment(_:_:)` changes reach visible rows even when no
        // snapshot difference reconfigures them.
        let environmentStorage = FineEnvironmentStorage()
        // Gate of the tree this list belongs to, so cell-local re-renders stop
        // while the screen is off screen.
        var renderGate: FineRenderGate?
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
                cell.render(
                    identity: AnyHashable(id),
                    environment: coordinator.environmentStorage,
                    renderGate: coordinator.renderGate
                ) { content(element) }

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
            guard let id = sectionID(at: index) else { return nil }
            return sectionsByID[id]
        }

        /// The current description for a section's header or footer, found by
        /// section identity.
        ///
        /// Supplementary views re-render outside the table's data source — on
        /// an environment change, say — so they read the description here
        /// rather than keeping the one they were handed, which the next root
        /// render has already replaced. Identity, not position: a view stays on
        /// screen while a section removed above it shifts every index below.
        func supplementaryNode(forSection id: AnyHashable, isHeader: Bool) -> (any Renderable)? {
            guard let section = sectionsByID[id] else { return nil }
            return isHeader ? section.header : section.footer
        }

        /// The identifier the data source currently shows at `index`.
        ///
        /// Asked through the data source rather than a cache of our own, so an
        /// index UIKit hands us during an animated apply still resolves against
        /// the sections on screen. `sectionIdentifier(for:)` reads the applied
        /// snapshot directly; `snapshot()` would copy the whole thing, and this
        /// runs per section on every layout pass.
        private func sectionID(at index: Int) -> AnyHashable? {
            dataSource.sectionIdentifier(for: index)?.value
        }

        /// Re-renders on-screen headers and footers from the current sections.
        ///
        /// The data source reconfigures rows, but nothing asks the table for a
        /// supplementary view it already has, so a header built from changed
        /// state would keep showing the old description.
        func refreshVisibleSupplementaryViews(in tableView: UITableView) {
            for index in 0..<tableView.numberOfSections {
                render(tableView.headerView(forSection: index), at: index, isHeader: true)
                render(tableView.footerView(forSection: index), at: index, isHeader: false)
            }
        }

        private func render(_ view: UITableViewHeaderFooterView?, at index: Int, isHeader: Bool) {
            guard let view = view as? FineListHostHeaderFooterView,
                  let id = sectionID(at: index),
                  supplementaryNode(forSection: id, isHeader: isHeader) != nil
            else { return }

            install(id: id, isHeader: isHeader, in: view)
            // A direct render bypasses the host's observation callback, which is
            // what normally re-measures a header whose content changed height.
            view.invalidateEnclosingHeightIfNeeded()
        }

        /// Points `view` at the description for `id`, re-read on every host
        /// re-render. Falls back to the description installed here, so a lookup
        /// that misses leaves the last content in place instead of blanking it.
        private func install(id: AnyHashable, isHeader: Bool, in view: FineListHostHeaderFooterView) {
            let installed = supplementaryNode(forSection: id, isHeader: isHeader)
            let identity = FineSupplementaryIdentity(section: id, kind: isHeader ? "header" : "footer")
            view.render(
                identity: AnyHashable(identity),
                environment: environmentStorage,
                renderGate: renderGate
            ) { [weak self] in
                self?.supplementaryNode(forSection: id, isHeader: isHeader) ?? installed ?? FineSpacer()
            }
        }

        private func supplementaryView(
            in tableView: UITableView,
            at index: Int,
            isHeader: Bool
        ) -> UIView? {
            guard let id = sectionID(at: index),
                  supplementaryNode(forSection: id, isHeader: isHeader) != nil
            else { return nil }

            let view = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: FineListHostHeaderFooterView.reuseIdentifier
            )

            guard let view = view as? FineListHostHeaderFooterView,
                  let id = sectionID(at: index)
            else { return nil }

            install(id: id, isHeader: isHeader, in: view)
            return view
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            supplementaryView(in: tableView, at: section, isHeader: true)
        }

        func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
            supplementaryView(in: tableView, at: section, isHeader: false)
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
    func render(
        identity: AnyHashable?,
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    ) {
        ensureHost().render(identity: identity, environment: environment, renderGate: renderGate, makeNode)
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
    func render(
        identity: AnyHashable?,
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    ) {
        ensureHost().render(identity: identity, environment: environment, renderGate: renderGate, makeNode)
    }

    /// Re-measures the table when this view's content no longer fits its
    /// current height. Called for observation-driven re-renders by the host,
    /// and by the list after it refreshes a visible supplementary view.
    func invalidateEnclosingHeightIfNeeded() {
        guard contentView.fineNeedsHeightRemeasure,
              let listView = fineEnclosing(FineListView.self)
        else { return }

        listView.fineScheduleRowHeightInvalidation()
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
            invalidateEnclosingHeightIfNeeded()
        }
        self.host = host
        return host
    }
}
