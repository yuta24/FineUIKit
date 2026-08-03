// expect-error: 'controller' is inaccessible due to 'private' protection level
//
// `FineScreen` holds the controller weakly and never hands it over as a value.
// Being able to would reopen the cycle: the local could then be captured
// strongly by a handler the node keeps.

import FineUIKit
import Observation
import UIKit

@Observable
final class ScreenEscapeModel {
    var title = "title"
}

final class ScreenEscapeController: FineViewController<ScreenEscapeModel> {
    override class func body(_ state: ScreenEscapeModel, _ screen: FineScreen) -> any Renderable {
        let controller = screen.controller
        return FineButton(title: "Close") { controller?.dismiss(animated: true) }
    }
}
