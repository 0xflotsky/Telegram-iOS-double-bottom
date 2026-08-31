import AccountContext
import Postbox
import SwiftSignalKit
import TelegramUIPreferences

public final class DoubleBottomPolicy: DoubleBottomPeerPolicy {
    private struct Snapshot: Equatable {
        let profile: DoubleBottomProfile
        let accessState: DoubleBottomAccessState
        let ownerPeerId: Int64?
        let decoyAllowedPeerIds: Set<Int64>
        let isPrivateStoreAvailable: Bool
        let hasPersistedCredentialState: Bool
    }

    private let privateStore: DoubleBottomPrivateStore
    private let snapshotValue = Atomic<Snapshot?>(value: nil)
    private let snapshotPromise = ValuePromise<Snapshot>(ignoreRepeated: true)
    private let activeAccountPeerIdValue = Atomic<PeerId?>(value: nil)
    private let activeAccountPeerIdPromise = ValuePromise<PeerId?>(nil, ignoreRepeated: true)
    private var snapshotDisposable: Disposable?

    var activeMode: Signal<DoubleBottomPeerPolicyMode, NoError> {
        return combineLatest(self.snapshotPromise.get(), self.activeAccountPeerIdPromise.get())
        |> map { snapshot, accountPeerId in
            guard let accountPeerId else {
                return .ordinary
            }
            return Self.mode(snapshot: snapshot, accountPeerId: accountPeerId)
        }
        |> distinctUntilChanged
    }

    var canUnlockActiveOwner: Bool {
        let activeAccountPeerId = self.activeAccountPeerIdValue.with { $0 }
        return self.snapshotValue.with { snapshot in
            guard let snapshot, snapshot.isPrivateStoreAvailable, let ownerPeerId = snapshot.ownerPeerId, let activeAccountPeerId else {
                return false
            }
            return ownerPeerId == activeAccountPeerId.toInt64()
        }
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

    init(context: DoubleBottomContext, credentialStore: DoubleBottomCredentialStore, privateStore: DoubleBottomPrivateStore) {
        self.privateStore = privateStore
        let hasPersistedCredentialState = credentialStore.hasPersistedCredentials

        let snapshot = combineLatest(
            context.currentProfile,
            context.accessState,
            privateStore.updates
        )
        |> mapToSignal { profile, accessState, _ -> Signal<Snapshot, NoError> in
            return privateStore.load()
            |> map { state in
                return Snapshot(
                    profile: profile,
                    accessState: accessState,
                    ownerPeerId: state.ownerPeerId,
                    decoyAllowedPeerIds: state.decoyAllowedPeerIds,
                    isPrivateStoreAvailable: true,
                    hasPersistedCredentialState: hasPersistedCredentialState
                )
            }
            |> `catch` { _ -> Signal<Snapshot, NoError> in
                return .single(Snapshot(
                    profile: profile,
                    accessState: accessState,
                    ownerPeerId: nil,
                    decoyAllowedPeerIds: Set(),
                    isPrivateStoreAvailable: false,
                    hasPersistedCredentialState: hasPersistedCredentialState
                ))
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

    public func currentMode(accountPeerId: PeerId) -> DoubleBottomPeerPolicyMode {
        return self.snapshotValue.with { snapshot in
            guard let snapshot else {
                return .secureExited
            }
            return Self.mode(snapshot: snapshot, accountPeerId: accountPeerId)
        }
    }

    public func mode(accountPeerId: PeerId) -> Signal<DoubleBottomPeerPolicyMode, NoError> {
        return self.snapshotPromise.get()
        |> map { snapshot in
            return Self.mode(snapshot: snapshot, accountPeerId: accountPeerId)
        }
        |> distinctUntilChanged
    }

    public func isOwner(accountPeerId: PeerId) -> Bool {
        return self.snapshotValue.with { snapshot in
            guard let snapshot, snapshot.isPrivateStoreAvailable, let ownerPeerId = snapshot.ownerPeerId else {
                return false
            }
            return ownerPeerId == accountPeerId.toInt64()
        }
    }

    public func shouldDisplaySettings(accountPeerId: PeerId) -> Bool {
        return self.snapshotValue.with { snapshot in
            guard let snapshot, snapshot.isPrivateStoreAvailable else {
                return false
            }
            guard let ownerPeerId = snapshot.ownerPeerId else {
                return !snapshot.hasPersistedCredentialState
            }
            return ownerPeerId == accountPeerId.toInt64() && snapshot.accessState == .unlocked && snapshot.profile == .primary
        }
    }

    public func canAccess(accountPeerId: PeerId, peerId: PeerId) -> Bool {
        return self.snapshotValue.with { snapshot in
            guard let snapshot else {
                return false
            }
            switch Self.mode(snapshot: snapshot, accountPeerId: accountPeerId) {
            case .ordinary, .primary:
                return true
            case .secureExited:
                return false
            case .decoy:
                return peerId == accountPeerId || snapshot.decoyAllowedPeerIds.contains(peerId.toInt64())
            }
        }
    }

    func setActiveAccountPeerId(_ peerId: PeerId?) {
        let previous = self.activeAccountPeerIdValue.swap(peerId)
        if previous != peerId {
            self.activeAccountPeerIdPromise.set(peerId)
        }
    }

    private static func mode(snapshot: Snapshot, accountPeerId: PeerId) -> DoubleBottomPeerPolicyMode {
        guard snapshot.isPrivateStoreAvailable else {
            return .secureExited
        }
        if snapshot.ownerPeerId == nil && snapshot.hasPersistedCredentialState {
            return .secureExited
        }
        guard let ownerPeerId = snapshot.ownerPeerId else {
            return .ordinary
        }
        guard ownerPeerId == accountPeerId.toInt64() else {
            return .ordinary
        }
        guard snapshot.accessState == .unlocked else {
            return .secureExited
        }
        switch snapshot.profile {
        case .primary:
            return .primary
        case .decoy:
            return .decoy
        }
    }

    public func filterPeers<T>(_ peers: [T], accountPeerId: PeerId, peerId: (T) -> PeerId) -> [T] {
        return peers.filter { self.canAccess(accountPeerId: accountPeerId, peerId: peerId($0)) }
    }

    public func claimOwner(accountPeerId: PeerId) -> Signal<Bool, DoubleBottomPrivateStoreError> {
        return self.privateStore.claimOwner(peerId: accountPeerId.toInt64())
    }

    public func setDecoyAllowedPeerIds(_ peerIds: Set<PeerId>, accountPeerId: PeerId) -> Signal<Void, DoubleBottomPrivateStoreError> {
        guard self.isOwner(accountPeerId: accountPeerId) else {
            return .complete()
        }
        let rawPeerIds = Set(peerIds.map { $0.toInt64() })
        return self.privateStore.update { state in
            guard state.ownerPeerId == accountPeerId.toInt64() else {
                return
            }
            state.decoyAllowedPeerIds = rawPeerIds
            state.decoyPinnedPeerIds.removeAll(where: { !rawPeerIds.contains($0) })
            state.decoyRecentPeerIds.removeAll(where: { !rawPeerIds.contains($0) })
            for index in state.decoyFolders.indices {
                state.decoyFolders[index].peerIds = state.decoyFolders[index].peerIds.intersection(rawPeerIds)
            }
        }
    }
}
