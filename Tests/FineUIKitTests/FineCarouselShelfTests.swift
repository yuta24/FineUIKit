import Observation
import Testing
import UIKit
@testable import FineUIKit

private struct Slide: Identifiable, Equatable {
    let id: String
    var title: String
}

@Observable
@MainActor
private final class PageModel {
    var page = 0
}

/// A carousel is pages one at a time; a shelf is a run of items that scrolls
/// across a screen that scrolls down. Both are a flat sequence over the shared
/// collection coordinator, so what these pin is what makes each one itself.
@MainActor
@Suite
struct FineCarouselShelfTests {
    private let slides = [
        Slide(id: "a", title: "A"),
        Slide(id: "b", title: "B"),
        Slide(id: "c", title: "C"),
    ]

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
    }

    private func waitTicks(_ count: Int = 40) async {
        for _ in 0..<count {
            await Task.yield()
        }
    }

    private func attachToWindow(_ view: UIView, width: CGFloat = 320, height: CGFloat = 200) -> UIWindow {
        let window = UIWindow(frame: .init(x: 0, y: 0, width: width, height: height))
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
        view.layoutIfNeeded()
        return window
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel { return label }
        for subview in view.subviews {
            if let found = firstLabel(in: subview) { return found }
        }
        return nil
    }

    // MARK: - Carousel

    @Test func aCarouselMakesEachElementAPage() async throws {
        let view = FineRenderer.render(FineCarousel(slides) { FineLabel(text: $0.title) })
        let carousel = try #require(view as? UICollectionView)
        let window = attachToWindow(carousel)

        await waitUntil { carousel.numberOfItems(inSection: 0) == 3 }
        carousel.layoutIfNeeded()

        #expect(carousel.numberOfSections == 1)
        #expect(carousel.numberOfItems(inSection: 0) == 3)
        #expect(carousel.isPagingEnabled)

        // A page is the whole carousel, so the run is as wide as the count.
        #expect(carousel.collectionViewLayout.collectionViewContentSize.width == carousel.bounds.width * 3)

        let cell = try #require(carousel.cellForItem(at: IndexPath(item: 0, section: 0)))
        #expect(firstLabel(in: cell)?.text == "A")
        #expect(cell.bounds.width == carousel.bounds.width)
        // A page fills the carousel rather than shrinking to its content.
        #expect(cell.bounds.height == carousel.bounds.height)
        _ = window
    }

    /// The binding is what pairs a carousel with `FinePageControl`, and it has
    /// to work in the direction the app writes as well as the one the finger
    /// does.
    @Test func writingTheBindingMovesTheCarousel() async throws {
        let model = PageModel()
        let carousel = { (page: Int) -> any Renderable in
            model.page = page
            return FineCarousel(self.slides) { FineLabel(text: $0.title) }
                .currentPage(FineBinding(model, \.page))
        }

        let view = FineRenderer.render(carousel(0))
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)

        await waitUntil { collectionView.numberOfItems(inSection: 0) == 3 }
        collectionView.layoutIfNeeded()
        #expect(collectionView.contentOffset.x == 0)

        _ = FineRenderer.render(carousel(2), reusing: view)
        await waitUntil { collectionView.contentOffset.x > 0 }
        collectionView.layoutIfNeeded()

        #expect(collectionView.contentOffset.x == collectionView.bounds.width * 2)
        _ = window
    }

    /// Scrolling writes back, so the dots follow the finger.
    @Test func scrollingReportsThePageItSettledOn() async throws {
        let model = PageModel()
        let view = FineRenderer.render(
            FineCarousel(slides) { FineLabel(text: $0.title) }
                .currentPage(FineBinding(model, \.page))
        )
        let carousel = try #require(view as? UICollectionView)
        let window = attachToWindow(carousel)

        await waitUntil { carousel.numberOfItems(inSection: 0) == 3 }
        carousel.layoutIfNeeded()
        #expect(model.page == 0)

        carousel.contentOffset.x = carousel.bounds.width * 2
        carousel.delegate?.scrollViewDidScroll?(carousel)

        #expect(model.page == 2)
        _ = window
    }

    /// The write a scroll causes must not scroll again.
    ///
    /// Mounted through `FineUI`, because that is what makes the binding write
    /// observed and re-render — rendered by hand, nothing would run and this
    /// would pass whatever the carousel did.
    @Test func theWriteAScrollCausesDoesNotScrollBack() async throws {
        let model = PageModel()
        let container = UIView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        let window = UIWindow(frame: container.bounds)
        window.addSubview(container)
        window.isHidden = false

        let slides = slides
        let ui = FineUI(state: model) { model in
            FineCarousel(slides) { FineLabel(text: $0.title) }
                .currentPage(FineBinding(model, \.page))
        }
        ui.build(to: container)

        let carousel = try #require(container.subviews.first as? UICollectionView)
        await waitUntil { carousel.numberOfItems(inSection: 0) == 3 }
        window.layoutIfNeeded()

        carousel.contentOffset.x = carousel.bounds.width
        carousel.delegate?.scrollViewDidScroll?(carousel)
        #expect(model.page == 1)

        // The write re-renders the tree; the carousel must stay where the
        // scroll left it rather than being told to go somewhere.
        await waitTicks()
        window.layoutIfNeeded()

        #expect(carousel.contentOffset.x == carousel.bounds.width)
        #expect(model.page == 1)
        _ = ui
    }

    /// A page beyond the end is clamped — and the app is told, because a
    /// binding that keeps naming a page that does not exist is an index the app
    /// can trap on and dots that point past the end.
    @Test func aPageBeyondTheEndIsClampedAndReportedBack() async throws {
        let model = PageModel()
        let carousel = { (page: Int) -> any Renderable in
            model.page = page
            return FineCarousel(self.slides) { FineLabel(text: $0.title) }
                .currentPage(FineBinding(model, \.page))
        }

        let view = FineRenderer.render(carousel(0))
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)
        await waitUntil { collectionView.numberOfItems(inSection: 0) == 3 }

        _ = FineRenderer.render(carousel(99), reusing: view)
        await waitTicks()
        collectionView.layoutIfNeeded()

        #expect(collectionView.contentOffset.x == collectionView.bounds.width * 2)
        #expect(model.page == 2)
        _ = window
    }

    /// The clamp is reported even when clamping moves nothing.
    ///
    /// Scrolling reports the page it arrived at, so an out-of-range write that
    /// causes a scroll gets corrected on the way. One that does not — the
    /// carousel is already where the clamp points — has nothing to report it,
    /// and the app would be left holding an index that names no page.
    @Test func aClampThatMovesNothingIsStillReported() async throws {
        let model = PageModel()
        let only = [Slide(id: "a", title: "A")]
        let carousel = { (page: Int) -> any Renderable in
            model.page = page
            return FineCarousel(only) { FineLabel(text: $0.title) }
                .currentPage(FineBinding(model, \.page))
        }

        let view = FineRenderer.render(carousel(0))
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)
        await waitUntil { collectionView.numberOfItems(inSection: 0) == 1 }
        collectionView.layoutIfNeeded()

        // The only page is the one already showing, so nothing scrolls.
        _ = FineRenderer.render(carousel(99), reusing: view)
        await waitTicks()

        #expect(collectionView.contentOffset.x == 0)
        #expect(model.page == 0)
        _ = window
    }

    /// A list that shrank under a page that was showing. The carousel has
    /// somewhere to go; the app is left holding an index that no longer names
    /// anything unless it is told.
    @Test func aShrunkListReportsThePageItLandedOn() async throws {
        let model = PageModel()
        let carousel = { (slides: [Slide]) -> any Renderable in
            FineCarousel(slides) { FineLabel(text: $0.title) }
                .currentPage(FineBinding(model, \.page))
        }

        let view = FineRenderer.render(carousel(slides))
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)
        await waitUntil { collectionView.numberOfItems(inSection: 0) == 3 }

        model.page = 2
        _ = FineRenderer.render(carousel(slides), reusing: view)
        await waitTicks()
        collectionView.layoutIfNeeded()
        #expect(collectionView.contentOffset.x == collectionView.bounds.width * 2)

        _ = FineRenderer.render(carousel(Array(slides.prefix(2))), reusing: view)
        await waitUntil { collectionView.numberOfItems(inSection: 0) == 2 }
        await waitTicks()
        collectionView.layoutIfNeeded()

        #expect(model.page == 1)
        #expect(collectionView.contentOffset.x == collectionView.bounds.width)
        _ = window
    }

    /// A carousel described as starting on a later page arrives there, even
    /// though the first render happens before it has a width to page across.
    /// Nothing renders again just because a view was laid out.
    @Test func aCarouselStartingOnALaterPageArrivesThereAfterLayout() async throws {
        let model = PageModel()
        model.page = 2

        let view = FineRenderer.render(
            FineCarousel(slides) { FineLabel(text: $0.title) }
                .currentPage(FineBinding(model, \.page))
        )
        let collectionView = try #require(view as? UICollectionView)
        // Rendered with no bounds at all, which is what the first render of a
        // real tree looks like.
        #expect(collectionView.bounds.width == 0)

        let window = attachToWindow(collectionView)
        await waitUntil { collectionView.contentOffset.x > 0 }
        collectionView.layoutIfNeeded()

        #expect(collectionView.contentOffset.x == collectionView.bounds.width * 2)
        #expect(model.page == 2)
        _ = window
    }

    /// A write that lands while a finger is on the carousel is applied when the
    /// gesture ends, rather than dropped for arguing with the scroll.
    @Test func aWriteDuringAGestureIsAppliedWhenItEnds() async throws {
        let model = PageModel()
        let carousel = { (page: Int) -> any Renderable in
            model.page = page
            return FineCarousel(self.slides) { FineLabel(text: $0.title) }
                .currentPage(FineBinding(model, \.page))
        }

        let view = FineRenderer.render(carousel(0))
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)
        await waitUntil { collectionView.numberOfItems(inSection: 0) == 3 }
        collectionView.layoutIfNeeded()

        // A drag in progress. `isDragging` is driven by the pan recogniser, so
        // the coordinator is asked directly for what a render would do.
        let coordinator = try #require(
            (collectionView as? FineCarouselView)?.coordinator as? FineCarouselPaging
        )
        _ = FineRenderer.render(carousel(2), reusing: view)
        await waitTicks()

        // Whatever the render did, ending the gesture leaves the carousel on
        // the page the app asked for.
        coordinator.applyPendingPage(in: collectionView)
        collectionView.layoutIfNeeded()

        #expect(collectionView.contentOffset.x == collectionView.bounds.width * 2)
        _ = window
    }

    @Test func aCarouselDiffsRatherThanRebuilds() async throws {
        let carousel = { (slides: [Slide]) in
            FineCarousel(slides) { FineLabel(text: $0.title) }
        }
        let view = FineRenderer.render(carousel(slides))
        let collectionView = try #require(view as? UICollectionView)
        let window = attachToWindow(collectionView)
        await waitUntil { collectionView.numberOfItems(inSection: 0) == 3 }

        let second = FineRenderer.render(carousel(slides + [Slide(id: "d", title: "D")]), reusing: view)

        #expect(second === view)
        await waitUntil { collectionView.numberOfItems(inSection: 0) == 4 }

        #expect(collectionView.numberOfItems(inSection: 0) == 4)
        _ = window
    }

    // MARK: - Shelf

    @Test func aShelfGivesEachItemTheWidthItWasTold() async throws {
        let view = FineRenderer.render(
            FineShelf(slides, itemWidth: .fixed(100), spacing: 10) { FineLabel(text: $0.title) }
        )
        let shelf = try #require(view as? UICollectionView)
        let window = attachToWindow(shelf)

        await waitUntil { shelf.numberOfItems(inSection: 0) == 3 }
        shelf.layoutIfNeeded()

        let first = try #require(shelf.cellForItem(at: IndexPath(item: 0, section: 0)))
        #expect(first.bounds.width == 100)
        #expect(first.bounds.height == shelf.bounds.height)

        // Three items of 100 with 10 between them.
        #expect(shelf.collectionViewLayout.collectionViewContentSize.width == 320)
        _ = window
    }

    /// A fraction below 1 is what leaves the next item showing at the edge,
    /// which is how a reader can tell the shelf scrolls at all.
    @Test func aFractionalWidthLetsTheNextItemPeek() async throws {
        let view = FineRenderer.render(
            FineShelf(slides, itemWidth: .fractional(0.8), spacing: 0) { FineLabel(text: $0.title) }
        )
        let shelf = try #require(view as? UICollectionView)
        let window = attachToWindow(shelf)

        await waitUntil { shelf.numberOfItems(inSection: 0) == 3 }
        shelf.layoutIfNeeded()

        let first = try #require(shelf.cellForItem(at: IndexPath(item: 0, section: 0)))
        #expect(first.bounds.width == shelf.bounds.width * 0.8)
        #expect(first.bounds.width < shelf.bounds.width)
        _ = window
    }

    /// The layout reads its widths back through the coordinator, so changing
    /// them has to make it run again rather than leave the old frames.
    @Test func changingTheItemWidthRelaysTheShelf() async throws {
        let shelf = { (width: FineShelfItemWidth) in
            FineShelf(self.slides, itemWidth: width, spacing: 0) { FineLabel(text: $0.title) }
        }
        let view = FineRenderer.render(shelf(.fixed(100)))
        let shelfView = try #require(view as? UICollectionView)
        let window = attachToWindow(shelfView)

        await waitUntil { shelfView.numberOfItems(inSection: 0) == 3 }
        shelfView.layoutIfNeeded()
        #expect(shelfView.cellForItem(at: IndexPath(item: 0, section: 0))?.bounds.width == 100)

        _ = FineRenderer.render(shelf(.fixed(60)), reusing: view)
        await waitUntil { shelfView.cellForItem(at: IndexPath(item: 0, section: 0))?.bounds.width == 60 }
        shelfView.layoutIfNeeded()

        #expect(shelfView.cellForItem(at: IndexPath(item: 0, section: 0))?.bounds.width == 60)
        _ = window
    }

    @Test func aShelfReportsASelectedElement() async throws {
        var selected: Slide?
        let view = FineRenderer.render(
            FineShelf(slides, itemWidth: .fixed(100)) { FineLabel(text: $0.title) }
                .onSelect { selected = $0 }
        )
        let shelf = try #require(view as? UICollectionView)
        let window = attachToWindow(shelf)
        await waitUntil { shelf.numberOfItems(inSection: 0) == 3 }

        let indexPath = IndexPath(item: 1, section: 0)
        #expect(shelf.delegate?.collectionView?(shelf, shouldHighlightItemAt: indexPath) == true)
        shelf.delegate?.collectionView?(shelf, didSelectItemAt: indexPath)

        #expect(selected == slides[1])
        _ = window
    }

    /// Both are built on the coordinator the list and grid use, so they inherit
    /// prefetching rather than reimplementing it — and a shelf of images is the
    /// shape it was made for.
    @Test func bothForwardPrefetchingLikeTheOtherCollections() async throws {
        var shelfPrefetched: [String] = []
        var carouselPrefetched: [String] = []

        let shelf = FineRenderer.render(
            FineShelf(slides, itemWidth: .fixed(100)) { FineLabel(text: $0.title) }
                .onPrefetch { shelfPrefetched += $0.map(\.id) }
        )
        let carousel = FineRenderer.render(
            FineCarousel(slides) { FineLabel(text: $0.title) }
                .onPrefetch { carouselPrefetched += $0.map(\.id) }
        )
        let shelfView = try #require(shelf as? UICollectionView)
        let carouselView = try #require(carousel as? UICollectionView)
        let windows = [attachToWindow(shelfView), attachToWindow(carouselView)]

        await waitUntil { shelfView.numberOfItems(inSection: 0) == 3 }
        await waitUntil { carouselView.numberOfItems(inSection: 0) == 3 }

        try #require(shelfView.prefetchDataSource)
            .collectionView(shelfView, prefetchItemsAt: [IndexPath(item: 2, section: 0)])
        try #require(carouselView.prefetchDataSource)
            .collectionView(carouselView, prefetchItemsAt: [IndexPath(item: 1, section: 0)])

        #expect(shelfPrefetched == ["c"])
        #expect(carouselPrefetched == ["b"])
        _ = windows
    }

    @Test func neitherClaimsPrefetchingWithoutAHandler() async throws {
        let shelf = try #require(
            FineRenderer.render(FineShelf(slides) { FineLabel(text: $0.title) }) as? UICollectionView
        )
        let carousel = try #require(
            FineRenderer.render(FineCarousel(slides) { FineLabel(text: $0.title) }) as? UICollectionView
        )

        #expect(shelf.prefetchDataSource == nil)
        #expect(carousel.prefetchDataSource == nil)
    }
}
