//
//  FineCollection.swift
//  FineUIKit
//
//  Created by nova on 2026/08/16.
//

import UIKit

/// A section of a collection: rows in a `FineList`, items in a `FineGrid`.
///
/// One type for both, because a section is the same idea in each — an
/// identity, an optional header and footer, and items. `FineListSection` and
/// `FineGridSection` are spellings of it.
@MainActor
public struct FineSection<Element: Identifiable> {
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

    /// The description for one end of the section.
    func supplementary(_ kind: FineSupplementaryKind) -> (any Renderable)? {
        switch kind {
        case .header: header
        case .footer: footer
        }
    }

    private static func textSupplementaryView(_ text: String) -> any Renderable {
        FineLabel(text: text)
            .font(.preferredFont(forTextStyle: .subheadline))
            .textColor(.secondaryLabel)
            .padding(.init(top: 8, leading: 16, bottom: 4, trailing: 16))
    }
}

public typealias FineListSection<Element: Identifiable> = FineSection<Element>
public typealias FineGridSection<Element: Identifiable> = FineSection<Element>

struct FineSectionIdentifier: Hashable, @unchecked Sendable {
    let value: AnyHashable

    init(_ value: AnyHashable) {
        self.value = value
    }
}

/// Which end of a section a supplementary view belongs to.
///
/// Tables say header and footer with a `Bool`, collection views with two kind
/// strings. Neither spelling travels, so the runtime uses this one and each
/// collection converts at its own boundary.
enum FineSupplementaryKind: Hashable {
    case header
    case footer

    var elementKind: String {
        switch self {
        case .header: UICollectionView.elementKindSectionHeader
        case .footer: UICollectionView.elementKindSectionFooter
        }
    }

    init?(elementKind: String) {
        switch elementKind {
        case UICollectionView.elementKindSectionHeader: self = .header
        case UICollectionView.elementKindSectionFooter: self = .footer
        default: return nil
        }
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
    let kind: FineSupplementaryKind
}

/// A view that hosts a section's header or footer description.
///
/// Tables and collection views reuse different classes for it, and the only
/// thing the shared coordinator needs from either is the ability to be pointed
/// at a description.
@MainActor
protocol FineSupplementaryHosting: AnyObject {
    func render(
        identity: AnyHashable?,
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    )
}

/// What one render of a collection asks of its data source.
///
/// Produced by `FineCollectionCoordinator.plan(...)`, which has already folded
/// the described sections into the coordinator's state; what is left here is
/// the part the caller has to act on, and the part it may need even when there
/// is nothing to apply.
@MainActor
struct FineCollectionPlan<Element: Identifiable> where Element.ID: Sendable {
    let sectionIDs: [FineSectionIdentifier]
    let itemIDsBySectionID: [FineSectionIdentifier: [Element.ID]]
    let elementsByID: [Element.ID: Element]
    let supplementarySignature: [FineSupplementarySignature]
    /// Identities that survived but whose content may be stale.
    let reconfiguredIDs: [Element.ID]
    /// Whether a section gained or lost a header or footer. Grids re-run their
    /// layout on this, which they have to do whether or not anything is
    /// applied.
    let supplementaryDidChange: Bool
    /// Whether the data source has anything to do at all. A render that moves
    /// nothing and changes nothing would otherwise make it diff the whole
    /// collection — and a root render caused by an unrelated part of the tree
    /// would pay for that on every keystroke.
    let needsApply: Bool

    func makeSnapshot() -> NSDiffableDataSourceSnapshot<FineSectionIdentifier, Element.ID> {
        var snapshot = NSDiffableDataSourceSnapshot<FineSectionIdentifier, Element.ID>()
        snapshot.appendSections(sectionIDs)
        for sectionID in sectionIDs {
            snapshot.appendItems(itemIDsBySectionID[sectionID] ?? [], toSection: sectionID)
        }
        snapshot.reconfigureItems(reconfiguredIDs)
        return snapshot
    }
}

/// The bookkeeping a diffable collection needs, without the collection.
///
/// `FineList` and `FineGrid` drive different UIKit classes but reconcile
/// identically: fold sections into an id-keyed index, work out which surviving
/// items are stale, and decide whether the data source has anything to do. That
/// logic lived twice, and the two copies had already drifted in the order they
/// recorded things — this is the one copy.
///
/// A base class rather than a value the coordinators hold, so the members the
/// cell providers and delegates already reach for keep their names.
@MainActor
class FineCollectionCoordinator<Element: Identifiable>: NSObject, FineCollectionPrefetchReporting
    where Element.ID: Sendable
{
    var sections: [FineSection<Element>] = [] {
        didSet {
            sectionsByID = Dictionary(
                sections.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }
    /// `sections` by identity. Supplementary lookups run per section on every
    /// layout pass, and a linear scan there is work proportional to the section
    /// count for each one of them.
    private(set) var sectionsByID: [AnyHashable: FineSection<Element>] = [:]
    var elementsByID: [Element.ID: Element] = [:]
    /// The structure last handed to the data source.
    var appliedSectionIDs: [FineSectionIdentifier] = []
    var appliedItemIDsBySectionID: [FineSectionIdentifier: [Element.ID]] = [:]
    var appliedItemIDs: Set<Element.ID> = []
    var appliedSupplementarySignature: [FineSupplementarySignature] = []
    var content: (@MainActor (Element) -> any Renderable)?
    var onSelect: (@MainActor (Element) -> Void)?
    var onRefresh: (@MainActor () async -> Void)?
    var onPrefetch: (@MainActor ([Element]) -> Void)?
    var onCancelPrefetch: (@MainActor ([Element]) -> Void)?
    /// What has been reported as coming and not yet reported as cancelled, so
    /// a cancellation can be about what was really started. Pruned to what the
    /// collection still holds on every render.
    private var outstandingPrefetchIDs: Set<Element.ID> = []
    // Environment resolved at the collection's last render. Cells observe it,
    // so `.environment(_:_:)` changes reach visible cells even when no snapshot
    // difference reconfigures them.
    let environmentStorage = FineEnvironmentStorage()
    // Gate of the tree this collection belongs to, so cell-local re-renders
    // stop while the screen is off screen.
    var renderGate: FineRenderGate?

    /// The section identifier the data source currently shows at `index`.
    ///
    /// Overridden by each collection: the two diffable data sources share no
    /// superclass, so the base has nothing to ask. Asked through the data
    /// source rather than a cache of our own, so an index UIKit hands us during
    /// an animated apply still resolves against what is on screen.
    func sectionID(at index: Int) -> AnyHashable? {
        fatalError("FineCollectionCoordinator subclasses must override sectionID(at:)")
    }

    func section(at index: Int) -> FineSection<Element>? {
        guard let id = sectionID(at: index) else { return nil }
        return sectionsByID[id]
    }

    /// The current description for a section's header or footer, found by
    /// section identity.
    ///
    /// Supplementary views re-render outside the data source — on an
    /// environment change, say — so they read the description here rather than
    /// keeping the one they were handed, which the next root render has already
    /// replaced. Identity, not position: a view stays on screen while a section
    /// removed above it shifts every index below.
    func supplementaryNode(forSection id: AnyHashable, kind: FineSupplementaryKind) -> (any Renderable)? {
        sectionsByID[id]?.supplementary(kind)
    }

    /// Points `view` at the description for `id`, re-read on every host
    /// re-render. Falls back to the description installed here, so a lookup
    /// that misses leaves the last content in place instead of blanking it.
    func install(id: AnyHashable, kind: FineSupplementaryKind, in view: some FineSupplementaryHosting) {
        let installed = supplementaryNode(forSection: id, kind: kind)
        let identity = FineSupplementaryIdentity(section: id, kind: kind)
        view.render(
            identity: AnyHashable(identity),
            environment: environmentStorage,
            renderGate: renderGate
        ) { [weak self] in
            self?.supplementaryNode(forSection: id, kind: kind) ?? installed ?? FineSpacer()
        }
    }

    /// Reports a selection by identity.
    func selectElement(withID id: Element.ID) {
        guard let element = elementsByID[id] else { return }
        onSelect?(element)
    }

    /// Whether UIKit should be asked to report cells before they are needed.
    ///
    /// A prefetch data source costs the frameworks below bookkeeping on every
    /// scroll, so one that would drop every call is not claimed — and a tree
    /// with only a cancel handler is exactly that. Cancelling is about work
    /// that started, so with nothing reporting a start there is nothing that
    /// could honestly be cancelled.
    var wantsPrefetching: Bool {
        onPrefetch != nil
    }

    /// Reports elements whose cells are about to be needed.
    ///
    /// Elements, not index paths: an index means nothing once a diffable apply
    /// has moved things, and by the time an app acts on this it is working with
    /// its own data anyway.
    ///
    /// Repeats are passed on rather than folded together, because UIKit asks
    /// more than once for a row it keeps expecting and an app watching this is
    /// entitled to see what UIKit actually did.
    func prefetchElements(withIDs ids: [Element.ID]) {
        // Nothing is outstanding if nobody was told it started. Recording it
        // anyway would let a later cancellation report work the app never
        // heard about, which is the one thing `onCancelPrefetch` promises not
        // to do.
        guard let onPrefetch else { return }

        // UIKit can name a row from a snapshot the data source has already
        // moved past. Dropping what no longer resolves is the only honest
        // answer — reporting it as whatever now sits at that index would hand
        // the app the wrong element.
        let elements = ids.compactMap { elementsByID[$0] }
        guard !elements.isEmpty else { return }

        outstandingPrefetchIDs.formUnion(elements.map(\.id))
        onPrefetch(elements)
    }

    /// Reports elements whose cells turned out not to be needed after all.
    ///
    /// Only elements this coordinator actually reported as coming. A
    /// cancellation names an index, and an index means something different once
    /// the rows have moved — resolving one against the current snapshot can
    /// land on a row that was never prefetched, and telling an app to stop work
    /// it never started is worse than saying nothing, because it will stop some
    /// other request instead.
    func cancelPrefetchingElements(withIDs ids: [Element.ID]) {
        let elements = ids.compactMap { id in
            outstandingPrefetchIDs.contains(id) ? elementsByID[id] : nil
        }
        guard !elements.isEmpty else { return }

        outstandingPrefetchIDs.subtract(elements.map(\.id))
        onCancelPrefetch?(elements)
    }

    /// Installs or removes the pull-to-refresh control to match `onRefresh`.
    func updateRefreshControl(on scrollView: UIScrollView) {
        guard onRefresh != nil else {
            scrollView.refreshControl?.fineSetHandler(Self.refreshActionKey, for: .valueChanged, handler: nil)
            scrollView.refreshControl = nil
            return
        }

        let refreshControl = scrollView.refreshControl ?? UIRefreshControl()
        scrollView.refreshControl = refreshControl

        refreshControl.fineSetHandler(Self.refreshActionKey, for: .valueChanged) { [weak self, weak refreshControl] _ in
            guard let self, let refreshControl else { return }

            Task { @MainActor in
                if let onRefresh = self.onRefresh {
                    await onRefresh()
                }
                refreshControl.endRefreshing()
            }
        }
    }

    private static var refreshActionKey: String {
        "FineUIKit.FineCollection.refresh"
    }

    /// Folds `sections` into this coordinator and says what the data source has
    /// to be told.
    ///
    /// Everything that has to happen whether or not the data source is touched
    /// is done here — `sections` and `elementsByID` are current when this
    /// returns, because supplementary views and cell providers read them. What
    /// is recorded as *applied* is not: that waits for `commit(_:)`, so a
    /// render that bails out does not claim to have applied a structure it
    /// never sent.
    ///
    /// - Parameter reconfiguresAll: Re-run content for every surviving item,
    ///   rather than only for those whose element changed.
    /// - Parameter areElementsEqual: How to tell a changed element from an
    ///   unchanged one, when the caller has stated it.
    /// - Parameter name: The collection's name, for the duplicate-id assertions.
    func plan(
        sections described: [FineSection<Element>],
        reconfiguresAll: Bool,
        areElementsEqual: ((Element, Element) -> Bool)?,
        name: String
    ) -> FineCollectionPlan<Element> {
        var snapshotSections: [FineSection<Element>] = []
        var seenSectionIDs = Set<AnyHashable>()
        var seenIDs = Set<Element.ID>()
        var elementsByID: [Element.ID: Element] = [:]
        var itemIDsBySectionID: [FineSectionIdentifier: [Element.ID]] = [:]

        for section in described {
            guard seenSectionIDs.insert(section.id).inserted else {
                assertionFailure("Duplicate \(name) section id: \(section.id)")
                continue
            }

            snapshotSections.append(section)
            let sectionIdentifier = FineSectionIdentifier(section.id)

            var sectionItemIDs: [Element.ID] = []
            for element in section.items {
                guard seenIDs.insert(element.id).inserted else {
                    assertionFailure("Duplicate \(name) item id: \(element.id)")
                    continue
                }

                elementsByID[element.id] = element
                sectionItemIDs.append(element.id)
            }
            itemIDsBySectionID[sectionIdentifier] = sectionItemIDs
        }

        // Read before either is replaced below.
        let previousElementsByID = self.elementsByID
        // The identifiers the data source holds, tracked alongside every apply
        // instead of read back through `snapshot()`, which copies them all.
        let previousIDs = appliedItemIDs

        self.sections = snapshotSections

        let sectionIDs = snapshotSections.map { FineSectionIdentifier($0.id) }
        let supplementarySignature = snapshotSections.map {
            FineSupplementarySignature(
                id: FineSectionIdentifier($0.id),
                hasHeader: $0.header != nil,
                hasFooter: $0.footer != nil
            )
        }

        // Items whose identity survived may still have changed content;
        // reconfigure re-runs the cell provider, which updates hosted views in
        // place. Items whose element is unchanged are skipped: `@Observable`
        // reads inside content update their own cell through per-cell
        // observation, so re-running every surviving item is wasted work.
        let reconfiguredIDs = elementsByID.keys.filter { id in
            guard previousIDs.contains(id) else { return false }
            guard !reconfiguresAll,
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

        self.elementsByID = elementsByID
        // An element that left the collection will never be cancelled, because
        // an index UIKit still holds for it now names something else. Dropping
        // it here keeps the set from growing for the life of the screen. The
        // app is not told: with plain UIKit, removing a row does not report a
        // cancellation either, and the code that removed the element is the
        // code that knows its work is moot.
        outstandingPrefetchIDs.formIntersection(elementsByID.keys)

        // Headers and footers are compared too, because they are not part of
        // the snapshot: a section that gains or loses one looks identical to
        // the diff, and nothing would re-ask for the supplementary view.
        let supplementaryDidChange = appliedSupplementarySignature != supplementarySignature
        let structureIsUnchanged = appliedSectionIDs == sectionIDs
            && appliedItemIDsBySectionID == itemIDsBySectionID
            && !supplementaryDidChange

        return .init(
            sectionIDs: sectionIDs,
            itemIDsBySectionID: itemIDsBySectionID,
            elementsByID: elementsByID,
            supplementarySignature: supplementarySignature,
            reconfiguredIDs: Array(reconfiguredIDs),
            supplementaryDidChange: supplementaryDidChange,
            needsApply: !structureIsUnchanged || !reconfiguredIDs.isEmpty
        )
    }

    /// Records what is about to be handed to the data source. Called only on
    /// the path that actually applies, so the recorded structure is one the
    /// data source has really been given.
    func commit(_ plan: FineCollectionPlan<Element>) {
        appliedSectionIDs = plan.sectionIDs
        appliedItemIDsBySectionID = plan.itemIDsBySectionID
        appliedItemIDs = Set(plan.elementsByID.keys)
        appliedSupplementarySignature = plan.supplementarySignature
    }
}

/// The collection view a `FineGrid`, `FineCarousel` or `FineShelf` renders
/// into.
///
/// Holds the coordinator — the cell providers reach it through the view rather
/// than capturing it, which is what keeps them out of a retain cycle — and owns
/// the one piece of behaviour every collection needs: folding self-sizing
/// invalidation into a single layout pass.
@MainActor
class FineCollectionHostView: UICollectionView {
    var coordinator: AnyObject?

    private var isLayoutInvalidationScheduled = false

    /// Coalesces self-sizing invalidation from concurrently re-rendered hosts
    /// into one layout pass per main-actor turn, instead of a full
    /// invalidateLayout per changed item. Inside a transaction the pass runs in
    /// the animation block so item frames animate.
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

/// The cell every collection-view-backed component renders an element into.
@MainActor
final class FineCollectionHostCell: UICollectionViewCell {
    static let reuseIdentifier = "FineCollectionHostCell"

    /// Whether the layout's size is final.
    ///
    /// A grid item is as tall as its content, so its cell negotiates: it
    /// measures what it holds and asks the layout for that height. A carousel
    /// page and a shelf item are as tall as the thing they sit in, and a cell
    /// that measured its content there would shrink to fit a short label and
    /// leave a ragged run — so those say the size they were given is the size
    /// they are.
    var usesGivenSize = false

    private var host: FineNodeHost?

    override func prepareForReuse() {
        super.prepareForReuse()
        host?.invalidate()
        usesGivenSize = false
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        guard !usesGivenSize else { return layoutAttributes }
        return super.preferredLayoutAttributesFitting(layoutAttributes)
    }

    /// Renders item content under local observation tracking.
    ///
    /// This mirrors `FineUI`'s render tracking at cell scope: values read while
    /// building and rendering the item can invalidate only this cell. When an
    /// observed update changes the item's fitting size, the enclosing
    /// collection view coalesces a layout invalidation.
    func render(
        identity: AnyHashable?,
        environment: FineEnvironmentStorage,
        renderGate: FineRenderGate?,
        _ makeNode: @escaping @MainActor () -> any Renderable
    ) {
        ensureHost().render(identity: identity, environment: environment, renderGate: renderGate, makeNode)
    }

    /// Re-measures the collection when this cell's content no longer fits its
    /// current size.
    func invalidateEnclosingLayoutIfNeeded() {
        guard contentView.fineNeedsHeightRemeasure,
              let collectionView = fineEnclosing(FineCollectionHostView.self)
        else { return }

        collectionView.fineScheduleLayoutInvalidation()
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

/// The coordinator for a collection that is one flat run of elements.
///
/// A carousel and a shelf have no sections, no headers and no footers — they
/// are a sequence, and the only structure they need is the one the diffable
/// data source already provides. What is left after that is the cell provider
/// and two delegate methods, which is the same in both, so it is written here
/// and each component adds only what makes it that component.
@MainActor
class FineFlatCollectionCoordinator<Element: Identifiable>: FineCollectionCoordinator<Element>,
    UICollectionViewDelegate,
    UICollectionViewDataSourcePrefetching
    where Element.ID: Sendable
{
    /// The one section a flat collection has. Its identity never changes, so
    /// the diff is always about items.
    static var sectionID: FineSectionIdentifier {
        .init(AnyHashable("__FineFlatCollection.main"))
    }

    let dataSource: UICollectionViewDiffableDataSource<FineSectionIdentifier, Element.ID>

    init(collectionView: FineCollectionHostView) {
        collectionView.register(
            FineCollectionHostCell.self,
            forCellWithReuseIdentifier: FineCollectionHostCell.reuseIdentifier
        )

        // The provider reaches the coordinator through the collection view
        // instead of capturing it, avoiding a retain cycle.
        dataSource = .init(collectionView: collectionView) { collectionView, indexPath, id in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FineCollectionHostCell.reuseIdentifier,
                for: indexPath
            )

            guard let cell = cell as? FineCollectionHostCell,
                  let coordinator = (collectionView as? FineCollectionHostView)?
                      .coordinator as? FineFlatCollectionCoordinator<Element>,
                  let element = coordinator.elementsByID[id],
                  let content = coordinator.content
            else { return cell }

            // A flat collection sizes its cells itself — a page is the
            // carousel's width, a shelf item is the shelf's height — so the
            // cell does not measure its way to a different answer.
            cell.usesGivenSize = true
            cell.render(
                identity: AnyHashable(id),
                environment: coordinator.environmentStorage,
                renderGate: coordinator.renderGate
            ) { content(element) }

            return cell
        }

        super.init()

        collectionView.delegate = self
    }

    override func sectionID(at index: Int) -> AnyHashable? {
        dataSource.sectionIdentifier(for: index)?.value
    }

    /// Folds a flat run of elements into the one section and applies it.
    func apply(_ elements: [Element], reconfiguresAll: Bool, name: String, in collectionView: UICollectionView) {
        let plan = plan(
            sections: [.init(id: Self.sectionID.value, items: elements)],
            reconfiguresAll: reconfiguresAll,
            areElementsEqual: nil,
            name: name
        )

        guard plan.needsApply else { return }

        commit(plan)
        dataSource.apply(
            plan.makeSnapshot(),
            animatingDifferences: FineTransactionContext.allowsDiffAnimation(inWindow: collectionView.window != nil)
        )
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)

        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }

        selectElement(withID: id)
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        onSelect != nil
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        prefetchElements(withIDs: indexPaths.compactMap { dataSource.itemIdentifier(for: $0) })
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        cancelPrefetchingElements(withIDs: indexPaths.compactMap { dataSource.itemIdentifier(for: $0) })
    }

    /// Called as the scroll offset changes, for collections that care where
    /// they are. Empty here: a shelf has no notion of a current anything.
    ///
    /// Declared on this class rather than the subclass that uses it because
    /// this is the class that states the `UICollectionViewDelegate`
    /// conformance, and that is where UIKit looks for the methods answering
    /// it — a scroll callback added further down goes uncalled.
    func scrollOffsetDidChange(in scrollView: UIScrollView) {}

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        scrollOffsetDidChange(in: scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollOffsetDidChange(in: scrollView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollOffsetDidChange(in: scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollOffsetDidChange(in: scrollView)
    }
}

/// Installs or removes a prefetch data source to match what a coordinator can
/// report.
///
/// Gated on change: assigning it is a statement to UIKit about its own prefetch
/// bookkeeping, and a root render caused by an unrelated part of the tree has
/// nothing to say about it.
@MainActor
func fineUpdatePrefetching(
    on collectionView: UICollectionView,
    with coordinator: some UICollectionViewDataSourcePrefetching & FineCollectionPrefetchReporting
) {
    let wantsPrefetching = coordinator.wantsPrefetching
    if (collectionView.prefetchDataSource != nil) != wantsPrefetching {
        collectionView.prefetchDataSource = wantsPrefetching ? coordinator : nil
    }
}

/// What `fineUpdatePrefetching(on:with:)` needs to know, so it does not have to
/// be generic over the element type.
@MainActor
protocol FineCollectionPrefetchReporting: AnyObject {
    var wantsPrefetching: Bool { get }
}
