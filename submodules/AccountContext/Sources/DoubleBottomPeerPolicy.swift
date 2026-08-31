import Postbox
import SwiftSignalKit

public enum DoubleBottomPeerPolicyMode: Equatable {
    case secureExited
    case primary
    case decoy
}

public protocol DoubleBottomPeerPolicy: AnyObject {
    var currentMode: DoubleBottomPeerPolicyMode { get }
    var mode: Signal<DoubleBottomPeerPolicyMode, NoError> { get }
    var updates: Signal<Void, NoError> { get }

    func canAccess(peerId: PeerId) -> Bool
}
