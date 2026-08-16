//
//  FineList.swift
//  FineUIKit
//
//  Created by nova on 2026/07/05.
//

import Observation
import UIKit

@MainActor
public struct FineList<Element: Identifiable>: FinePrimitiveRenderable where Element.ID: Sendable {
    private let sections: [FineListSection<Element>]
    private let content: @MainActor (Element) -> any Renderable
    private var onSelect: (@MainActor (Element) -> Void)?
    private var onDelete: (@MainActor (Element) -> Void)?
    private var onRefresh: (@MainActor () async -> Void)?
    private var onPrefetch: (@MainActor ([Element]) -> Void)?
    private var onCancelPrefetch: (@MainActor ([Element]) -> Void)?
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

    /// Reports rows that are about to be needed, before they are asked for.
    ///
    /// Row content is built when the cell is configured, which is the moment it
    /// becomes visible — so anything slow inside it (a remote image, a decoded
    /// asset) starts too late and the row pops in. This is where that work
    /// starts instead. The runtime does none of it: it only forwards UIKit's
    /// warning, as elements rather than index paths.
    ///
    /// Called on the main actor while scrolling, so hand the work off rather
    /// than doing it here. UIKit decides how far ahead to ask, and may ask for
    /// the same row more than once.
    public func onPrefetch(_ handler: @escaping @MainActor ([Element]) -> Void) -> FineList {
        var copy = self
        copy.onPrefetch = handler
        return copy
    }

    /// An opportunity to stop work started in `onPrefetch(_:)`, for rows that
    /// turned out not to be needed.
    ///
    /// Has no effect on its own: cancelling is about work that started, so
    /// without `onPrefetch(_:)` nothing is predicted and nothing is cancelled.
    ///
    /// **Not a balancing count, and not a guarantee.** A row that scrolls into
    /// view is simply used and never reported here; a row whose element leaves
    /// the collection is not reported either, because the code that removed it
    /// is the code that knows its work is moot. Only rows this list really
    /// reported as coming are reported here, so a handler will not be asked to
    /// stop work it never started — but it should be safe to call about work
    /// that has already finished.
    public func onCancelPrefetch(_ handler: @escaping @MainActor ([Element]) -> Void) -> FineList {
        var copy = self
        copy.onCancelPrefetch = handler
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
        coordinator.onPrefetch = onPrefetch
        coordinator.onCancelPrefetch = onCancelPrefetch
        coordinator.dataSource.canEditRows = onDelete != nil
        coordinator.updateRefreshControl(on: listView)

        // Gated on change: assigning this is a statement to UIKit about its own
        // prefetch bookkeeping, and a root render caused by an unrelated part
        // of the tree has nothing to say about it. Held weakly by the table,
        // and the coordinator outlives it through `listView.coordinator`.
        let wantsPrefetching = coordinator.wantsPrefetching
        if (listView.prefetchDataSource != nil) != wantsPrefetching {
            listView.prefetchDataSource = wantsPrefetching ? coordinator : nil
        }

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

        let plan = coordinator.plan(
            sections: sections,
            reconfiguresAll: reconfiguresAllRows,
            areElementsEqual: areElementsEqual,
            name: "FineList"
        )

        coordinator.refreshVisibleSupplementaryViews(in: listView)

        guard plan.needsApply else { return }

        coordinator.commit(plan)
        coordinator.dataSource.apply(
            plan.makeSnapshot(),
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
    @MainActor
    final class DataSource: UITableViewDiffableDataSource<FineSectionIdentifier, Element.ID> {
        var canEditRows = false

        override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            canEditRows
        }
    }

    @MainActor
    final class Coordinator: FineCollectionCoordinator<Element>, UITableViewDelegate, UITableViewDataSourcePrefetching {
        let dataSource: DataSource

        var onDelete: (@MainActor (Element) -> Void)?
        var deleteActionTitle: String = "Delete"
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

        override func sectionID(at index: Int) -> AnyHashable? {
            dataSource.sectionIdentifier(for: index)?.value
        }

        /// Re-renders on-screen headers and footers from the current sections.
        ///
        /// The data source reconfigures rows, but nothing asks the table for a
        /// supplementary view it already has, so a header built from changed
        /// state would keep showing the old description.
        func refreshVisibleSupplementaryViews(in tableView: UITableView) {
            for index in 0..<tableView.numberOfSections {
                render(tableView.headerView(forSection: index), at: index, kind: .header)
                render(tableView.footerView(forSection: index), at: index, kind: .footer)
            }
        }

        private func render(_ view: UITableViewHeaderFooterView?, at index: Int, kind: FineSupplementaryKind) {
            guard let view = view as? FineListHostHeaderFooterView,
                  let id = sectionID(at: index),
                  supplementaryNode(forSection: id, kind: kind) != nil
            else { return }

            install(id: id, kind: kind, in: view)
            // A direct render bypasses the host's observation callback, which is
            // what normally re-measures a header whose content changed height.
            view.invalidateEnclosingHeightIfNeeded()
        }

        private func supplementaryView(
            in tableView: UITableView,
            at index: Int,
            kind: FineSupplementaryKind
        ) -> UIView? {
            guard let id = sectionID(at: index),
                  supplementaryNode(forSection: id, kind: kind) != nil
            else { return nil }

            let view = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: FineListHostHeaderFooterView.reuseIdentifier
            )

            guard let view = view as? FineListHostHeaderFooterView else { return nil }

            install(id: id, kind: kind, in: view)
            return view
        }

        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            supplementaryView(in: tableView, at: section, kind: .header)
        }

        func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
            supplementaryView(in: tableView, at: section, kind: .footer)
        }

        func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
            self.section(at: section)?.header == nil ? .leastNonzeroMagnitude : UITableView.automaticDimension
        }


        func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
            self.section(at: section)?.footer == nil ? .leastNonzeroMagnitude : UITableView.automaticDimension
        }

        func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
            prefetchElements(withIDs: indexPaths.compactMap { dataSource.itemIdentifier(for: $0) })
        }

        func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
            cancelPrefetchingElements(withIDs: indexPaths.compactMap { dataSource.itemIdentifier(for: $0) })
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)

            guard let id = dataSource.itemIdentifier(for: indexPath) else { return }

            selectElement(withID: id)
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
final class FineListHostHeaderFooterView: UITableViewHeaderFooterView, FineSupplementaryHosting {
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
