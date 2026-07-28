import Observation
import Testing
import UIKit
@testable import FineUIKit

@MainActor
struct FineSliderRangeTests {
    @MainActor
    @Observable
    final class SliderState {
        var volume: Float = 0.5
    }

    @Test func correctsAValueOutsideItsRange() throws {
        let state = SliderState()
        state.volume = 5

        let view = FineRenderer.render(FineSlider(value: .init(state, \.volume), in: 0...1))

        // The state follows what is shown: UIKit clamped the value, and leaving
        // the binding at 5 would keep state and UI disagreeing forever.
        #expect((view as? UISlider)?.value == 1)
        #expect(state.volume == 1)
    }

    @Test func aRangeMovingEntirelyUpwardsKeepsBothBounds() throws {
        let state = SliderState()
        let first = FineRenderer.render(FineSlider(value: .init(state, \.volume), in: 0...1))
        let slider = try #require(first as? UISlider)

        state.volume = 250
        _ = FineRenderer.render(
            FineSlider(value: .init(state, \.volume), in: 200...300),
            reusing: first
        )

        #expect(slider.minimumValue == 200)
        #expect(slider.maximumValue == 300)
        #expect(slider.value == 250)
    }
}
