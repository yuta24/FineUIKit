// expect-error: 'controller' is inaccessible due to 'private' protection level
//
// `FineHost` holds the controller weakly and never hands it over as a value.
// Being able to would reopen the cycle: the local could then be captured
// strongly by a handler the node keeps.

import FineUIKit
import Observation
import UIKit

@Observable
final class HostEscapeModel {
    var title = "title"
}

final class HostEscapeController: FineViewController<HostEscapeModel> {
    override class func body(_ state: HostEscapeModel, _ host: FineHost) -> any Renderable {
        let controller = host.controller
        return FineButton(title: "Close") { controller?.dismiss(animated: true) }
    }
}
