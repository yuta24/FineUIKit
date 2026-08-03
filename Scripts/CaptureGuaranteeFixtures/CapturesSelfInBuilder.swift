// expect-error: instance member 'taps' cannot be used on type
//
// The shape that used to leak: a handler inside a builder reaching the
// controller. `body` is a type method, so there is no instance to reach.

import FineUIKit
import Observation
import UIKit

@Observable
final class BuilderCaptureModel {
    var title = "title"
}

final class BuilderCaptureController: FineViewController<BuilderCaptureModel> {
    var taps = 0

    override class func body(_ state: BuilderCaptureModel, _ screen: FineScreen) -> any Renderable {
        FineStack.vertical {
            FineLabel(text: state.title)
            FineButton(title: "Tap") { self.taps += 1 }
        }
    }
}
