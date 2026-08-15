//
//  FineIdentityScopedView.swift
//  FineUIKit
//
//  Created by nova on 2026/08/15.
//

import UIKit

/// A view holding something on behalf of what it is showing rather than of
/// itself, and which therefore has to let go when it is handed something else.
///
/// `FineNode.localState` covers the state the runtime owns. This covers the
/// state a view owns for the description — a running task, the keyboard it is
/// holding, how far it has been scrolled — which only the view can wind down.
///
/// The two methods separate the two things a host can tell a subtree, because
/// they are not the same for every view:
///
/// - **Parked**: the cell has been recycled and does not yet know what it will
///   show next. Whatever must not still be happening has to stop, but the same
///   row coming back is the ordinary case and its place is worth keeping.
/// - **Handed something else**: the row is genuinely gone, so anything
///   describing it goes with it.
///
/// A conformer implements whichever applies; the default for being handed
/// something else is to do what being parked does, since anything that has to
/// stop then has to stop now too.
@MainActor
protocol FineIdentityScopedView: UIView {
    /// Stops what the view is doing for the description it is showing.
    func fineStopIdentityWork()

    /// Also gives up state that describes what was being shown.
    func fineDiscardIdentityState()
}

extension FineIdentityScopedView {
    func fineStopIdentityWork() {}

    func fineDiscardIdentityState() {
        fineStopIdentityWork()
    }
}
