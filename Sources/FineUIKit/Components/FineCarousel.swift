//
//  FineCarousel.swift
//  FineUIKit
//
//  Created by nova on 2026/08/16.
//

import UIKit

/// A full-width run of pages, one at a time.
///
/// `FinePageControl` has been here since the beginning with nothing to pair it
/// with: an app wanting paged content had to build the paging itself and drive
/// the dots by hand. `currentPage(_:)` takes the same `FineBinding<Int>` the
/// page control does, so the two describe one thing.
///
/// ```swift
/// FineStack.vertical {
///     FineCarousel(banners) { FineBannerView($0) }
///         .currentPage(FineBinding(self, \.page))
///         .height(220)
///     FinePageControl(numberOfPages: banners.count, currentPage: FineBinding(self, \.page))
/// }
/// ```
///
/// A carousel is a sequence, not a table: there are no sections, headers or
/// footers, and pages are as wide and as tall as the carousel itself.
@MainActor
public struct FineCarousel<Element: Identifiable>: FinePrimitiveRenderable where Element.ID: Sendable {
    private let elements: [Element]
    private let content: @MainActor (Element) -> any Renderable
    private var currentPage: FineBinding<Int>?
    private var onSelect: (@MainActor (Element) -> Void)?
    private var onPrefetch: (@MainActor ([Element]) -> Void)?
    private var onCancelPrefetch: (@MainActor ([Element]) -> Void)?
    private var reconfiguresAllPages = false

    public var body: any Renderable {
        fatalError("Primitive Renderable body should not be evaluated")
    }

    public init(_ elements: [Element], content: @escaping @MainActor (Element) -> any Renderable) {
        self.elements = elements
        self.content = content
    }

    /// Follows and drives which page is showing.
    ///
    /// Two-way: scrolling writes the page that settled, and writing the binding
    /// scrolls there. A write that names the page already showing does nothing,
    /// which is what keeps the two directions from chasing each other.
    ///
    /// The binding is read while this node updates, so a page change re-runs
    /// this node rather than the whole screen.
    public func currentPage(_ binding: FineBinding<Int>) -> FineCarousel {
        var copy = self
        copy.currentPage = binding
        return copy
    }

    public func onSelect(_ handler: @escaping @MainActor (Element) -> Void) -> FineCarousel {
        var copy = self
        copy.onSelect = handler
        return copy
    }

    /// Reports pages that are about to be needed. See `FineGrid.onPrefetch(_:)`.
    public func onPrefetch(_ handler: @escaping @MainActor ([Element]) -> Void) -> FineCarousel {
        var copy = self
        copy.onPrefetch = handler
        return copy
    }

    /// An opportunity to stop work started in `onPrefetch(_:)`.
    public func onCancelPrefetch(_ handler: @escaping @MainActor ([Element]) -> Void) -> FineCarousel {
        var copy = self
        copy.onCancelPrefetch = handler
        return copy
    }

    /// Re-runs page content for every surviving page on each render, instead of
    /// only for pages whose element changed.
    public func reconfiguringAllPages() -> FineCarousel {
        var copy = self
        copy.reconfiguresAllPages = true
        return copy
    }

    func _makeView() -> UIView {
        let carouselView = FineCarouselView(frame: .zero, collectionViewLayout: Self.makeLayout())
        carouselView.backgroundColor = .clear
        // Paging rather than a `.paging` orthogonal section: a page is exactly
        // the carousel's width with nothing between, so the scroll view's own
        // paging lands where the layout already puts things.
        carouselView.isPagingEnabled = true
        carouselView.showsHorizontalScrollIndicator = false
        carouselView.alwaysBounceHorizontal = true
        // A page is as tall as the carousel it was given, not as tall as
        // whatever is left after the screen's safe area. See `FineShelf`.
        carouselView.contentInsetAdjustmentBehavior = .never
        return carouselView
    }

    func _canUpdate(_ view: UIView) -> Bool {
        guard let carouselView = view as? FineCarouselView else { return false }
        return carouselView.coordinator == nil || carouselView.coordinator is Coordinator
    }

    func _update(_ view: UIView, context: FineRenderContext) {
        guard let carouselView = view as? FineCarouselView else { return }

        let coordinator: Coordinator
        if let existing = carouselView.coordinator as? Coordinator {
            coordinator = existing
        } else {
            coordinator = .init(collectionView: carouselView)
            carouselView.coordinator = coordinator
        }

        coordinator.content = content
        coordinator.onSelect = onSelect
        coordinator.onPrefetch = onPrefetch
        coordinator.onCancelPrefetch = onCancelPrefetch
        coordinator.environmentStorage.update(context.environment)
        coordinator.renderGate = context.renderGate
        coordinator.currentPage = currentPage
        fineUpdatePrefetching(on: carouselView, with: coordinator)

        coordinator.apply(
            elements,
            reconfiguresAll: reconfiguresAllPages,
            name: "FineCarousel",
            in: carouselView
        )

        // Read after the apply, so a binding pointing at a page that only this
        // render introduced has somewhere to go. Reading it here — rather than
        // when the description was built — is also what puts it in this node's
        // observation scope.
        if let currentPage {
            coordinator.scrollToPage(currentPage.value, in: carouselView)
        }
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        // A page is as tall as the carousel, even a full-bleed one running
        // behind the status bar. See `FineShelf`.
        section.contentInsetsReference = .none

        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal

        return UICollectionViewCompositionalLayout(section: section, configuration: configuration)
    }
}

extension FineCarousel {
    @MainActor
    final class Coordinator: FineFlatCollectionCoordinator<Element> {
        var currentPage: FineBinding<Int>?
        /// A page asked for that could not be shown yet — because the carousel
        /// has no width to page across, or because a finger is on it.
        ///
        /// Deliberately not a record of "the page we are on": one of those
        /// drifts from the truth the moment a scroll, a relayout or a changed
        /// element list disagrees with it, and everything below reads the page
        /// off the scroll view instead.
        private var pendingPage: Int?

        /// Shows `page`, now or as soon as that means anything.
        func scrollToPage(_ page: Int, in collectionView: UICollectionView) {
            let count = collectionView.numberOfItems(inSection: 0)
            guard count > 0 else {
                // Nothing to show a page of. A pending request from before the
                // collection emptied is not worth keeping: whatever refills it
                // is a render, and that render asks again.
                pendingPage = nil
                return
            }

            let target = min(max(page, 0), count - 1)
            // The binding named a page that does not exist — after a list that
            // shrank, say. Saying so is the whole point of a two-way binding:
            // left alone, the app holds an index it can trap on, and the dots
            // point past the end.
            if target != page {
                currentPage?.value = target
            }

            // A finger is on it, and the binding is probably being written *by*
            // that gesture. Arguing with it would fight the scroll; dropping
            // the request would lose a write the app made for its own reasons.
            guard !collectionView.isDragging, !collectionView.isDecelerating else {
                pendingPage = target
                return
            }

            show(target, in: collectionView)
        }

        /// Applies a page that was asked for while it could not be shown.
        ///
        /// Called when the carousel is laid out and when a gesture ends, which
        /// are the two moments something that was impossible becomes possible.
        func applyPendingPage(in collectionView: UICollectionView) {
            guard let pendingPage,
                  !collectionView.isDragging,
                  !collectionView.isDecelerating
            else { return }

            let count = collectionView.numberOfItems(inSection: 0)
            guard count > 0 else {
                self.pendingPage = nil
                return
            }

            show(min(max(pendingPage, 0), count - 1), in: collectionView)
        }

        private func show(_ target: Int, in collectionView: UICollectionView) {
            // Without a width there is no paging to do, and `scrollToItem`
            // would land nowhere. Keeping it pending is what makes a carousel
            // that starts on page 2 arrive there once it has been laid out.
            guard collectionView.bounds.width > 0 else {
                pendingPage = target
                return
            }

            pendingPage = nil
            guard page(in: collectionView) != target else { return }

            collectionView.scrollToItem(
                at: IndexPath(item: target, section: 0),
                at: .centeredHorizontally,
                // Never animated: this is the tree catching up with state, and
                // a page that changed while the carousel was off screen has no
                // motion to show.
                animated: false
            )
        }

        /// The page under the current scroll offset — read, never remembered.
        private func page(in scrollView: UIScrollView) -> Int? {
            let width = scrollView.bounds.width
            guard width > 0 else { return nil }

            let page = Int((scrollView.contentOffset.x / width).rounded())
            guard let collectionView = scrollView as? UICollectionView else { return page }

            let count = collectionView.numberOfItems(inSection: 0)
            guard count > 0 else { return nil }

            return min(max(page, 0), count - 1)
        }

        /// Reports the page under the offset, as it changes.
        ///
        /// Every offset change, not only where scrolling stops: a page control
        /// that only moved once deceleration finished would lag behind the page
        /// the reader is already looking at. Comparing against the binding's own
        /// value — rather than a remembered one — is what keeps this from
        /// writing on every frame, and cannot go stale.
        private func reportPageIfChanged(in scrollView: UIScrollView) {
            guard let currentPage,
                  let page = page(in: scrollView),
                  currentPage.value != page
            else { return }

            currentPage.value = page
        }

        override func scrollOffsetDidChange(in scrollView: UIScrollView) {
            reportPageIfChanged(in: scrollView)
        }

        override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            super.scrollViewDidEndDecelerating(scrollView)

            if let collectionView = scrollView as? UICollectionView {
                applyPendingPage(in: collectionView)
            }
        }

        override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            super.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)

            guard !decelerate, let collectionView = scrollView as? UICollectionView else { return }

            applyPendingPage(in: collectionView)
        }
    }
}

@MainActor
final class FineCarouselView: FineCollectionHostView {
    /// Applies a page that was asked for before there was a width to page
    /// across.
    ///
    /// A carousel is described with `currentPage` already set — the app is
    /// restoring where the reader was — but the first render happens before
    /// layout, when `scrollToItem` has nothing to aim at. Nothing else would
    /// ask again: a render only happens when something changes, and arriving at
    /// a width is not a change the tree hears about.
    override func layoutSubviews() {
        super.layoutSubviews()

        guard let coordinator = coordinator as? (any FineCarouselPaging) else { return }

        coordinator.applyPendingPage(in: self)
    }
}

/// What `FineCarouselView` needs from its coordinator without knowing the
/// element type it is generic over.
@MainActor
protocol FineCarouselPaging: AnyObject {
    func applyPendingPage(in collectionView: UICollectionView)
}

extension FineCarousel.Coordinator: FineCarouselPaging {}
