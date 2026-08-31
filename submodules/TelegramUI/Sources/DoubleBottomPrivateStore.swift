import Foundation
import Security
import CryptoKit
import SwiftSignalKit

public struct DoubleBottomPrivateState: Codable, Equatable {
    public struct LocalFolder: Codable, Equatable {
        public var id: String
        public var title: String
        public var peerIds: Set<Int64>
    }

    public var ownerPeerId: Int64?
    public var decoyAllowedPeerIds: Set<Int64>
    public var decoySelectedFolderId: String?
    public var decoyFolders: [LocalFolder]
    public var decoyPinnedPeerIds: [Int64]
    public var decoyRecentPeerIds: [Int64]
    public var decoySortOrder: Int32
    public var requiresLocalUnlock: Bool

    public static var empty: DoubleBottomPrivateState {
        return DoubleBottomPrivateState(ownerPeerId: nil, decoyAllowedPeerIds: Set(), decoySelectedFolderId: nil, decoyFolders: [], decoyPinnedPeerIds: [], decoyRecentPeerIds: [], decoySortOrder: 0, requiresLocalUnlock: false)
    }

    public init(ownerPeerId: Int64? = nil, decoyAllowedPeerIds: Set<Int64>, decoySelectedFolderId: String? = nil, decoyFolders: [LocalFolder] = [], decoyPinnedPeerIds: [Int64] = [], decoyRecentPeerIds: [Int64] = [], decoySortOrder: Int32 = 0, requiresLocalUnlock: Bool = false) {
        self.ownerPeerId = ownerPeerId
        self.decoyAllowedPeerIds = decoyAllowedPeerIds
        self.decoySelectedFolderId = decoySelectedFolderId
        self.decoyFolders = decoyFolders
        self.decoyPinnedPeerIds = decoyPinnedPeerIds
        self.decoyRecentPeerIds = decoyRecentPeerIds
        self.decoySortOrder = decoySortOrder
        self.requiresLocalUnlock = requiresLocalUnlock
    }

    private enum CodingKeys: String, CodingKey {
        case ownerPeerId = "o"
        case decoyAllowedPeerIds = "a"
        case decoySelectedFolderId = "f"
        case decoyFolders = "fs"
        case decoyPinnedPeerIds = "p"
        case decoyRecentPeerIds = "r"
        case decoySortOrder = "s"
        case requiresLocalUnlock = "l"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ownerPeerId = try container.decodeIfPresent(Int64.self, forKey: .ownerPeerId)
        self.decoyAllowedPeerIds = try container.decodeIfPresent(Set<Int64>.self, forKey: .decoyAllowedPeerIds) ?? Set()
        self.decoySelectedFolderId = try container.decodeIfPresent(String.self, forKey: .decoySelectedFolderId)
        self.decoyFolders = try container.decodeIfPresent([LocalFolder].self, forKey: .decoyFolders) ?? []
        self.decoyPinnedPeerIds = try container.decodeIfPresent([Int64].self, forKey: .decoyPinnedPeerIds) ?? []
        self.decoyRecentPeerIds = try container.decodeIfPresent([Int64].self, forKey: .decoyRecentPeerIds) ?? []
        self.decoySortOrder = try container.decodeIfPresent(Int32.self, forKey: .decoySortOrder) ?? 0
        self.requiresLocalUnlock = try container.decodeIfPresent(Bool.self, forKey: .requiresLocalUnlock) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.ownerPeerId, forKey: .ownerPeerId)
        try container.encode(self.decoyAllowedPeerIds, forKey: .decoyAllowedPeerIds)
        try container.encodeIfPresent(self.decoySelectedFolderId, forKey: .decoySelectedFolderId)
        try container.encode(self.decoyFolders, forKey: .decoyFolders)
        try container.encode(self.decoyPinnedPeerIds, forKey: .decoyPinnedPeerIds)
        try container.encode(self.decoyRecentPeerIds, forKey: .decoyRecentPeerIds)
        try container.encode(self.decoySortOrder, forKey: .decoySortOrder)
        try container.encode(self.requiresLocalUnlock, forKey: .requiresLocalUnlock)
    }
}

public enum DoubleBottomPrivateStoreError: Error, Equatable {
    case corruptData
    case missingKey
    case encryptionFailed
    case io
    case keychain(OSStatus)
}

public final class DoubleBottomPrivateStore {
    private struct StoredState: Codable {
        let version: Int32
        let state: DoubleBottomPrivateState
    }

    private static let currentVersion: Int32 = 1
    private static let keyLength = 32
    private static let keychainService = "org.telegram.double-bottom.private-store"
    private static let keychainAccount = "encryption-key-v1"
    private static let authenticatedData = Data("org.telegram.double-bottom.private-store.v1".utf8)

    private let queue = Queue(name: "DoubleBottomPrivateStore", qos: .userInitiated)
    private let directoryUrl: URL
    private let fileUrl: URL
    private var revision: Int64 = 0
    private let revisionPromise = ValuePromise<Int64>(0, ignoreRepeated: true)

    var updates: Signal<Void, NoError> {
        return self.revisionPromise.get()
        |> map { _ in () }
    }

    var hasPersistedState: Bool {
        return FileManager.default.fileExists(atPath: self.fileUrl.path)
    }

    var requiresLocalUnlockOnLaunch: Bool {
        guard self.hasPersistedState else {
            return false
        }
        var requiresLocalUnlock = true
        self.queue.sync {
            if let state = try? self.loadState() {
                requiresLocalUnlock = state.requiresLocalUnlock
            }
        }
        return requiresLocalUnlock
    }

    public init(basePath: String) {
        let directoryUrl = URL(fileURLWithPath: basePath, isDirectory: true).appendingPathComponent("double-bottom", isDirectory: true)
        self.directoryUrl = directoryUrl
        self.fileUrl = directoryUrl.appendingPathComponent("private-state-v1.bin", isDirectory: false)
    }

    public func load() -> Signal<DoubleBottomPrivateState, DoubleBottomPrivateStoreError> {
        return Signal { subscriber in
            do {
                subscriber.putNext(try self.loadState())
                subscriber.putCompletion()
            } catch let error as DoubleBottomPrivateStoreError {
                subscriber.putError(error)
            } catch {
                subscriber.putError(.corruptData)
            }
            return EmptyDisposable
        }
        |> runOn(self.queue)
    }

    public func update(_ f: @escaping (inout DoubleBottomPrivateState) -> Void) -> Signal<Void, DoubleBottomPrivateStoreError> {
        return Signal { subscriber in
            do {
                var state = try self.loadState()
                f(&state)
                try self.storeState(state)
                self.revision += 1
                self.revisionPromise.set(self.revision)
                subscriber.putNext(())
                subscriber.putCompletion()
            } catch let error as DoubleBottomPrivateStoreError {
                subscriber.putError(error)
            } catch {
                subscriber.putError(.corruptData)
            }
            return EmptyDisposable
        }
        |> runOn(self.queue)
    }

    func setRequiresLocalUnlockSynchronously(_ value: Bool) -> Bool {
        var succeeded = false
        self.queue.sync {
            do {
                var state = try self.loadState()
                state.requiresLocalUnlock = value
                try self.storeState(state)
                self.revision += 1
                self.revisionPromise.set(self.revision)
                succeeded = true
            } catch {
            }
        }
        return succeeded
    }

    public func claimOwner(peerId: Int64) -> Signal<Bool, DoubleBottomPrivateStoreError> {
        return Signal { subscriber in
            do {
                var state = try self.loadState()
                if let ownerPeerId = state.ownerPeerId {
                    subscriber.putNext(ownerPeerId == peerId)
                    subscriber.putCompletion()
                    return EmptyDisposable
                }

                state.ownerPeerId = peerId
                try self.storeState(state)
                self.revision += 1
                self.revisionPromise.set(self.revision)
                subscriber.putNext(true)
                subscriber.putCompletion()
            } catch let error as DoubleBottomPrivateStoreError {
                subscriber.putError(error)
            } catch {
                subscriber.putError(.corruptData)
            }
            return EmptyDisposable
        }
        |> runOn(self.queue)
    }

    public func clearDecryptedState() {
        // State is intentionally not cached by this store. Each operation decrypts
        // into operation-scoped values that are released when the signal completes.
    }

    private func loadState() throws -> DoubleBottomPrivateState {
        guard FileManager.default.fileExists(atPath: self.fileUrl.path) else {
            return .empty
        }

        let keyData = try self.loadKey()
        guard let encryptedData = try? Data(contentsOf: self.fileUrl),
              let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData) else {
            throw DoubleBottomPrivateStoreError.corruptData
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(
                sealedBox,
                using: SymmetricKey(data: keyData),
                authenticating: Self.authenticatedData
            )
        } catch {
            throw DoubleBottomPrivateStoreError.corruptData
        }

        guard let storedState = try? JSONDecoder().decode(StoredState.self, from: plaintext), storedState.version == Self.currentVersion else {
            throw DoubleBottomPrivateStoreError.corruptData
        }
        return storedState.state
    }

    private func storeState(_ state: DoubleBottomPrivateState) throws {
        let storedState = StoredState(version: Self.currentVersion, state: state)
        guard let plaintext = try? JSONEncoder().encode(storedState) else {
            throw DoubleBottomPrivateStoreError.corruptData
        }

        let keyData = try self.loadOrCreateKey()
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(
                plaintext,
                using: SymmetricKey(data: keyData),
                authenticating: Self.authenticatedData
            )
        } catch {
            throw DoubleBottomPrivateStoreError.encryptionFailed
        }
        guard let combined = sealedBox.combined else {
            throw DoubleBottomPrivateStoreError.encryptionFailed
        }

        do {
            try FileManager.default.createDirectory(
                at: self.directoryUrl,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var directoryUrl = self.directoryUrl
            try directoryUrl.setResourceValues(resourceValues)

            try combined.write(to: self.fileUrl, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: self.fileUrl.path
            )
        } catch {
            throw DoubleBottomPrivateStoreError.io
        }
    }

    private func loadOrCreateKey() throws -> Data {
        do {
            return try self.loadKey()
        } catch DoubleBottomPrivateStoreError.missingKey {
            if FileManager.default.fileExists(atPath: self.fileUrl.path) {
                throw DoubleBottomPrivateStoreError.missingKey
            }

            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            try self.storeKey(keyData)
            return keyData
        }
    }

    private func loadKey() throws -> Data {
        var query = self.keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            throw DoubleBottomPrivateStoreError.missingKey
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DoubleBottomPrivateStoreError.keychain(status)
        }
        guard data.count == Self.keyLength else {
            throw DoubleBottomPrivateStoreError.missingKey
        }
        return data
    }

    private func storeKey(_ data: Data) throws {
        guard data.count == Self.keyLength else {
            throw DoubleBottomPrivateStoreError.encryptionFailed
        }

        var query = self.keychainQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw DoubleBottomPrivateStoreError.keychain(status)
        }
    }

    private func keychainQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
    }
}
