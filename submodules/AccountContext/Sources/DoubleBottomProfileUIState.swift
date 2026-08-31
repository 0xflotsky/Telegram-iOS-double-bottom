import Foundation
import Postbox
import SwiftSignalKit

public enum DoubleBottomLocalChatSortOrder: Int32, Equatable {
    case activity = 0
    case title = 1
}

public struct DoubleBottomLocalChatFolder: Equatable {
    public let id: String
    public let title: String
    public let peerIds: Set<PeerId>

    public init(id: String, title: String, peerIds: Set<PeerId>) {
        self.id = id
        self.title = title
        self.peerIds = peerIds
    }
}

public struct DoubleBottomProfileUIState: Equatable {
    public var selectedFolderId: String?
    public var folders: [DoubleBottomLocalChatFolder]
    public var pinnedPeerIds: [PeerId]
    public var recentPeerIds: [PeerId]
    public var sortOrder: DoubleBottomLocalChatSortOrder

    public static var empty: DoubleBottomProfileUIState {
        return DoubleBottomProfileUIState(
            selectedFolderId: nil,
            folders: [],
            pinnedPeerIds: [],
            recentPeerIds: [],
            sortOrder: .activity
        )
    }

    public init(selectedFolderId: String?, folders: [DoubleBottomLocalChatFolder], pinnedPeerIds: [PeerId], recentPeerIds: [PeerId], sortOrder: DoubleBottomLocalChatSortOrder) {
        self.selectedFolderId = selectedFolderId
        self.folders = folders
        self.pinnedPeerIds = pinnedPeerIds
        self.recentPeerIds = recentPeerIds
        self.sortOrder = sortOrder
    }
}

public protocol DoubleBottomProfileUIStateContext: AnyObject {
    var currentDecoyState: DoubleBottomProfileUIState { get }
    var updates: Signal<Void, NoError> { get }

    func addRecentPeerId(_ peerId: PeerId) -> Signal<Void, NoError>
    func removeRecentPeerId(_ peerId: PeerId) -> Signal<Void, NoError>
    func clearRecentPeerIds() -> Signal<Void, NoError>
    func setSelectedFolderId(_ id: String?) -> Signal<Void, NoError>
    func setFolders(_ folders: [DoubleBottomLocalChatFolder]) -> Signal<Void, NoError>
    func setPinnedPeerIds(_ peerIds: [PeerId]) -> Signal<Void, NoError>
    func setSortOrder(_ sortOrder: DoubleBottomLocalChatSortOrder) -> Signal<Void, NoError>
}
