import AccountContext
import Postbox
import SwiftSignalKit

public final class DoubleBottomProfileUIStateContextImpl: DoubleBottomProfileUIStateContext {
    private let privateStore: DoubleBottomPrivateStore
    private let stateValue = Atomic<DoubleBottomProfileUIState>(value: .empty)
    private let statePromise = ValuePromise<DoubleBottomProfileUIState>(.empty, ignoreRepeated: true)
    private var stateDisposable: Disposable?

    public var currentDecoyState: DoubleBottomProfileUIState {
        return self.stateValue.with { $0 }
    }

    public var updates: Signal<Void, NoError> {
        return self.statePromise.get()
        |> map { _ in () }
    }

    init(privateStore: DoubleBottomPrivateStore, policy: DoubleBottomPolicy) {
        self.privateStore = privateStore

        self.stateDisposable = (combineLatest(privateStore.updates, policy.activeMode)
        |> mapToSignal { _, mode -> Signal<DoubleBottomProfileUIState, NoError> in
            guard mode == .primary || mode == .decoy else {
                return .single(.empty)
            }
            return privateStore.load()
            |> map(Self.mapState)
            |> `catch` { _ in
                return .single(.empty)
            }
        }
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            guard let self else {
                return
            }
            let _ = self.stateValue.swap(state)
            self.statePromise.set(state)
        })
    }

    deinit {
        self.stateDisposable?.dispose()
    }

    public func addRecentPeerId(_ peerId: PeerId) -> Signal<Void, NoError> {
        return self.update { state in
            guard state.decoyAllowedPeerIds.contains(peerId.toInt64()) else {
                return
            }
            state.decoyRecentPeerIds.removeAll(where: { $0 == peerId.toInt64() })
            state.decoyRecentPeerIds.insert(peerId.toInt64(), at: 0)
            if state.decoyRecentPeerIds.count > 20 {
                state.decoyRecentPeerIds.removeLast(state.decoyRecentPeerIds.count - 20)
            }
        }
    }

    public func removeRecentPeerId(_ peerId: PeerId) -> Signal<Void, NoError> {
        return self.update { state in
            state.decoyRecentPeerIds.removeAll(where: { $0 == peerId.toInt64() })
        }
    }

    public func clearRecentPeerIds() -> Signal<Void, NoError> {
        return self.update { state in
            state.decoyRecentPeerIds.removeAll()
        }
    }

    public func setSelectedFolderId(_ id: String?) -> Signal<Void, NoError> {
        return self.update { state in
            if let id, state.decoyFolders.contains(where: { $0.id == id }) {
                state.decoySelectedFolderId = id
            } else {
                state.decoySelectedFolderId = nil
            }
        }
    }

    public func setFolders(_ folders: [DoubleBottomLocalChatFolder]) -> Signal<Void, NoError> {
        return self.update { state in
            var usedIds = Set<String>()
            state.decoyFolders = folders.compactMap { folder in
                let id = String(folder.id.prefix(64))
                guard !id.isEmpty, usedIds.insert(id).inserted else {
                    return nil
                }
                return DoubleBottomPrivateState.LocalFolder(
                    id: id,
                    title: String(folder.title.prefix(64)),
                    peerIds: Set(folder.peerIds.map { $0.toInt64() }).intersection(state.decoyAllowedPeerIds)
                )
            }
            if let selectedFolderId = state.decoySelectedFolderId, !state.decoyFolders.contains(where: { $0.id == selectedFolderId }) {
                state.decoySelectedFolderId = nil
            }
        }
    }

    public func setPinnedPeerIds(_ peerIds: [PeerId]) -> Signal<Void, NoError> {
        return self.update { state in
            var usedPeerIds = Set<Int64>()
            state.decoyPinnedPeerIds = peerIds.compactMap { peerId in
                let peerId = peerId.toInt64()
                guard state.decoyAllowedPeerIds.contains(peerId), usedPeerIds.insert(peerId).inserted else {
                    return nil
                }
                return peerId
            }
            if state.decoyPinnedPeerIds.count > 100 {
                state.decoyPinnedPeerIds.removeLast(state.decoyPinnedPeerIds.count - 100)
            }
        }
    }

    public func setSortOrder(_ sortOrder: DoubleBottomLocalChatSortOrder) -> Signal<Void, NoError> {
        return self.update { state in
            state.decoySortOrder = sortOrder.rawValue
        }
    }

    func clearSensitiveState() {
        let _ = self.stateValue.swap(.empty)
        self.statePromise.set(.empty)
    }

    private func update(_ f: @escaping (inout DoubleBottomPrivateState) -> Void) -> Signal<Void, NoError> {
        return self.privateStore.update(f)
        |> `catch` { _ in
            return .complete()
        }
    }

    private static func mapState(_ state: DoubleBottomPrivateState) -> DoubleBottomProfileUIState {
        return DoubleBottomProfileUIState(
            selectedFolderId: state.decoySelectedFolderId,
            folders: state.decoyFolders.map { folder in
                return DoubleBottomLocalChatFolder(
                    id: folder.id,
                    title: folder.title,
                    peerIds: Set(folder.peerIds.map(PeerId.init))
                )
            },
            pinnedPeerIds: state.decoyPinnedPeerIds.map(PeerId.init),
            recentPeerIds: state.decoyRecentPeerIds.map(PeerId.init),
            sortOrder: DoubleBottomLocalChatSortOrder(rawValue: state.decoySortOrder) ?? .activity
        )
    }
}
