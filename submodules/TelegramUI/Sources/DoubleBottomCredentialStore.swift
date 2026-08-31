import Foundation
import Security
import MtProtoKit
import SwiftSignalKit
import TelegramUIPreferences

public enum DoubleBottomCredentialStoreError: Error, Equatable {
    case invalidPassword
    case passwordsMustDiffer
    case notConfigured
    case corruptData
    case keyDerivationFailed
    case keychain(OSStatus)
}

public enum DoubleBottomCredentialStoreStatus: Equatable {
    case notConfigured
    case configured
    case unavailable
}

public enum DoubleBottomCredentialVerificationResult: Equatable {
    case primary
    case decoy
    case invalid
    case notConfigured
    case unavailable
}

public final class DoubleBottomCredentialStore {
    private struct CredentialRecord: Codable {
        let salt: Data
        let verifier: Data
        let iterations: Int32
    }

    private struct CredentialState: Codable {
        let version: Int32
        var primary: CredentialRecord
        var decoy: CredentialRecord
    }

    private static let service = "org.telegram.double-bottom.credentials"
    private static let account = "profiles-v1"
    private static let currentVersion: Int32 = 1
    private static let saltLength = 32
    private static let verifierLength = 64
    private static let iterations: Int32 = 100_000

    private let queue = Queue(name: "DoubleBottomCredentialStore", qos: .userInitiated)

    public init() {
    }

    var hasPersistedCredentials: Bool {
        let status = SecItemCopyMatching(self.keychainQuery() as CFDictionary, nil)
        return status != errSecItemNotFound
    }

    public func status() -> Signal<DoubleBottomCredentialStoreStatus, NoError> {
        return Signal { subscriber in
            let status: DoubleBottomCredentialStoreStatus
            do {
                let _ = try self.loadState()
                status = .configured
            } catch DoubleBottomCredentialStoreError.notConfigured {
                status = .notConfigured
            } catch {
                status = .unavailable
            }
            subscriber.putNext(status)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(self.queue)
    }

    public func setCredentials(primaryPassword: String, decoyPassword: String) -> Signal<Void, DoubleBottomCredentialStoreError> {
        return Signal { subscriber in
            do {
                guard !primaryPassword.isEmpty, !decoyPassword.isEmpty else {
                    throw DoubleBottomCredentialStoreError.invalidPassword
                }

                let primary = try self.makeCredentialRecord(password: primaryPassword)
                let decoy = try self.makeCredentialRecord(password: decoyPassword)
                if try self.matches(password: primaryPassword, record: decoy) {
                    throw DoubleBottomCredentialStoreError.passwordsMustDiffer
                }

                try self.storeState(CredentialState(
                    version: Self.currentVersion,
                    primary: primary,
                    decoy: decoy
                ))
                subscriber.putNext(())
                subscriber.putCompletion()
            } catch let error as DoubleBottomCredentialStoreError {
                subscriber.putError(error)
            } catch {
                subscriber.putError(.corruptData)
            }
            return EmptyDisposable
        }
        |> runOn(self.queue)
    }

    public func setPassword(_ password: String, for profile: DoubleBottomProfile) -> Signal<Void, DoubleBottomCredentialStoreError> {
        return Signal { subscriber in
            do {
                guard !password.isEmpty else {
                    throw DoubleBottomCredentialStoreError.invalidPassword
                }

                var state = try self.loadState()
                let otherRecord: CredentialRecord
                switch profile {
                case .primary:
                    otherRecord = state.decoy
                case .decoy:
                    otherRecord = state.primary
                }
                if try self.matches(password: password, record: otherRecord) {
                    throw DoubleBottomCredentialStoreError.passwordsMustDiffer
                }

                let updatedRecord = try self.makeCredentialRecord(password: password)
                switch profile {
                case .primary:
                    state.primary = updatedRecord
                case .decoy:
                    state.decoy = updatedRecord
                }
                try self.storeState(state)
                subscriber.putNext(())
                subscriber.putCompletion()
            } catch let error as DoubleBottomCredentialStoreError {
                subscriber.putError(error)
            } catch {
                subscriber.putError(.corruptData)
            }
            return EmptyDisposable
        }
        |> runOn(self.queue)
    }

    public func verify(password: String) -> Signal<DoubleBottomCredentialVerificationResult, NoError> {
        return Signal { subscriber in
            let result: DoubleBottomCredentialVerificationResult
            do {
                let state = try self.loadState()
                let matchesPrimary = try self.matches(password: password, record: state.primary)
                let matchesDecoy = try self.matches(password: password, record: state.decoy)

                if matchesPrimary != matchesDecoy {
                    result = matchesPrimary ? .primary : .decoy
                } else if matchesPrimary {
                    result = .unavailable
                } else {
                    result = .invalid
                }
            } catch DoubleBottomCredentialStoreError.notConfigured {
                result = .notConfigured
            } catch {
                result = .unavailable
            }
            subscriber.putNext(result)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(self.queue)
    }

    private func makeCredentialRecord(password: String) throws -> CredentialRecord {
        let salt = try self.randomData(count: Self.saltLength)
        let verifier = try self.deriveVerifier(password: password, salt: salt, iterations: Self.iterations)
        return CredentialRecord(salt: salt, verifier: verifier, iterations: Self.iterations)
    }

    private func matches(password: String, record: CredentialRecord) throws -> Bool {
        let candidate = try self.deriveVerifier(password: password, salt: record.salt, iterations: record.iterations)
        return self.constantTimeEqual(candidate, record.verifier)
    }

    private func deriveVerifier(password: String, salt: Data, iterations: Int32) throws -> Data {
        guard let passwordData = password.data(using: .utf8), let verifier = MTPBKDF2(passwordData, salt, iterations) else {
            throw DoubleBottomCredentialStoreError.keyDerivationFailed
        }
        return verifier
    }

    private func randomData(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let baseAddress = bytes.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw DoubleBottomCredentialStoreError.keychain(status)
        }
        return data
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        var difference: UInt8 = 0
        for index in 0 ..< lhs.count {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    private func loadState() throws -> CredentialState {
        var query = self.keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            throw DoubleBottomCredentialStoreError.notConfigured
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DoubleBottomCredentialStoreError.keychain(status)
        }
        guard let state = try? JSONDecoder().decode(CredentialState.self, from: data), self.isValid(state: state) else {
            throw DoubleBottomCredentialStoreError.corruptData
        }
        return state
    }

    private func storeState(_ state: CredentialState) throws {
        guard self.isValid(state: state), let data = try? JSONEncoder().encode(state) else {
            throw DoubleBottomCredentialStoreError.corruptData
        }

        let query = self.keychainQuery()
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw DoubleBottomCredentialStoreError.keychain(updateStatus)
            }
        } else if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw DoubleBottomCredentialStoreError.keychain(addStatus)
            }
        } else {
            throw DoubleBottomCredentialStoreError.keychain(status)
        }
    }

    private func isValid(state: CredentialState) -> Bool {
        guard state.version == Self.currentVersion else {
            return false
        }
        for record in [state.primary, state.decoy] {
            guard record.salt.count == Self.saltLength, record.verifier.count == Self.verifierLength, record.iterations == Self.iterations else {
                return false
            }
        }
        return true
    }

    private func keychainQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
