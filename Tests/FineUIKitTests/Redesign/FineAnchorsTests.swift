import Testing
import UIKit
@testable import FineUIKit

@MainActor
struct FineAnchorsTests {
    private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.5
    }

    @Test func pinToSuperviewActivatesFourEdgeConstraints() throws {
        let container = UIView(frame: .init(x: 0, y: 0, width: 200, height: 200))
        let child = UIView()
        container.addSubview(child)

        let constraints = child.fineAnchors { $0.pinToSuperview(insets: .init(top: 8, leading: 4, bottom: 12, trailing: 16)) }

        #expect(constraints.count == 4)
        #expect(constraints.allSatisfy { $0.isActive })
        #expect(child.translatesAutoresizingMaskIntoConstraints == false)

        container.layoutIfNeeded()
        // Auto Layout solves via floating-point arithmetic, so exact `==` on
        // resulting frames is not reliable even for integral inputs.
        #expect(approximatelyEqual(child.frame.minX, 4))
        #expect(approximatelyEqual(child.frame.minY, 8))
        #expect(approximatelyEqual(child.frame.width, 200 - 4 - 16))
        #expect(approximatelyEqual(child.frame.height, 200 - 8 - 12))
    }

    @Test func callingTwiceActivatesTwoIndependentBatches() throws {
        let container = UIView()
        let child = UIView()
        container.addSubview(child)

        // Different anchors (not the same one twice) so both stay
        // simultaneously satisfiable and the test isn't just papering over an
        // Auto Layout conflict warning.
        let first = child.fineAnchors { $0.pin(child.widthAnchor.constraint(equalToConstant: 10)) }
        let second = child.fineAnchors { $0.pin(child.heightAnchor.constraint(equalToConstant: 20)) }

        #expect(first.count == 1)
        #expect(second.count == 1)
        // No reconciliation: both constraints exist and are active, exactly as issued.
        #expect(first[0].isActive)
        #expect(second[0].isActive)
    }
}
