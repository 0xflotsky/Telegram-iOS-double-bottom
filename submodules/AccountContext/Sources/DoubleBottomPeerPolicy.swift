import Postbox
import SwiftSignalKit

public enum DoubleBottomPeerPolicyMode: Equatable {
    case ordinary
    case secureExited
    case primary
    case decoy
}

public protocol DoubleBottomPeerPolicy: AnyObject {
    var updates: Signal<Void, NoError> { get }

    func currentMode(accountPeerId: PeerId) -> DoubleBottomPeerPolicyMode
    func mode(accountPeerId: PeerId) -> Signal<DoubleBottomPeerPolicyMode, NoError>
    func isOwner(accountPeerId: PeerId) -> Bool
    func canAccess(accountPeerId: PeerId, peerId: PeerId) -> Bool
}
