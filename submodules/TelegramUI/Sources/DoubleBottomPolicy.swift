import Postbox
import SwiftSignalKit
import TelegramUIPreferences

public enum DoubleBottomPolicyMode: Equatable {
    case secureExited
    case primary
    case decoy
}

public final class DoubleBottomPolicy {
    private struct Snapshot: Equatable {
        let profile: DoubleBottomProfile
        let accessState: DoubleBottomAccessState
        let decoyAllowedPeerIds: Set<Int64>
        let isPrivateStoreAvailable: Bool
    }

    private let privateStore: DoubleBottomPrivateStore
    private let snapshotValue = Atomic<Snapshot?>(value: nil)
    private let snapshotPromise = ValuePromise<Snapshot>(ignoreRepeated: true)
    private var snapshotDisposable: Disposable?

    public var mode: Signal<DoubleBottomPolicyMode, NoError> {
        return self.snapshotPromise.get()
        |> map { snapshot in
            if snapshot.accessState == .secureExited {
                return .secureExited
            }
            switch snapshot.profile {
            case .primary:
                return .primary
            case .decoy:
                return .decoy
            }
        }
        |> distinctUntilChanged
    }

    public var currentProfile: Signal<DoubleBottomProfile, NoError> {
        return self.snapshotPromise.get()
        |> map(\.profile)
        |> distinctUntilChanged
    }

    public var updates: Signal<Void, NoError> {
        return self.snapshotPromise.get()
        |> map { _ in () }
    }

    init(context: DoubleBottomContext, privateStore: DoubleBottomPrivateStore) {
        self.privateStore = privateStore

        let snapshot = combineLatest(
            context.currentProfile,
            context.accessState,
            privateStore.updates
        )
        |> mapToSignal { profile, accessState, _ -> Signal<Snapshot, NoError> in
            switch profile {
            case .primary:
                return .single(Snapshot(
                    profile: .primary,
                    accessState: accessState,
                    decoyAllowedPeerIds: Set(),
                    isPrivateStoreAvailable: true
                ))
            case .decoy:
                return privateStore.load()
                |> map { state in
                    return Snapshot(
                        profile: .decoy,
                        accessState: accessState,
                        decoyAllowedPeerIds: state.decoyAllowedPeerIds,
                        isPrivateStoreAvailable: true
                    )
                }
                |> `catch` { _ -> Signal<Snapshot, NoError> in
                    return .single(Snapshot(
                        profile: .decoy,
                        accessState: accessState,
                        decoyAllowedPeerIds: Set(),
                        isPrivateStoreAvailable: false
                    ))
                }
            }
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue

        self.snapshotDisposable = snapshot.startStrict(next: { [weak self] snapshot in
            guard let self else {
                return
            }
            let _ = self.snapshotValue.swap(snapshot)
            self.snapshotPromise.set(snapshot)
        })
    }

    deinit {
        self.snapshotDisposable?.dispose()
    }

    public func canAccess(peerId: PeerId) -> Bool {
        return self.snapshotValue.with { snapshot in
            guard let snapshot, snapshot.accessState == .unlocked else {
                return false
            }
            switch snapshot.profile {
            case .primary:
                return true
            case .decoy:
                return snapshot.decoyAllowedPeerIds.contains(peerId.toInt64())
            }
        }
    }

    public func filterPeers<T>(_ peers: [T], peerId: (T) -> PeerId) -> [T] {
        return peers.filter { self.canAccess(peerId: peerId($0)) }
    }

    public func setDecoyAllowedPeerIds(_ peerIds: Set<PeerId>) -> Signal<Void, DoubleBottomPrivateStoreError> {
        let rawPeerIds = Set(peerIds.map { $0.toInt64() })
        return self.privateStore.update { state in
            state.decoyAllowedPeerIds = rawPeerIds
        }
    }
}
