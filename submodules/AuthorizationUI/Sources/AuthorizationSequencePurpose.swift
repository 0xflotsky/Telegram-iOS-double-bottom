import SwiftSignalKit
import TelegramCore

public enum AuthorizationSequenceDoubleBottomPasswordResult {
    case primary
    case decoy
    case invalid
    case unavailable
}

public final class AuthorizationSequenceDoubleBottomReentryContext {
    public let protectedOwnerPeerId: PeerId
    public let preservedOwnerAccountId: AccountRecordId
    public let preservedOwnerPhoneNumber: String
    public let verifyPassword: (String) -> Signal<AuthorizationSequenceDoubleBottomPasswordResult, NoError>

    public init(
        protectedOwnerPeerId: PeerId,
        preservedOwnerAccountId: AccountRecordId,
        preservedOwnerPhoneNumber: String,
        verifyPassword: @escaping (String) -> Signal<AuthorizationSequenceDoubleBottomPasswordResult, NoError>
    ) {
        self.protectedOwnerPeerId = protectedOwnerPeerId
        self.preservedOwnerAccountId = preservedOwnerAccountId
        self.preservedOwnerPhoneNumber = preservedOwnerPhoneNumber
        self.verifyPassword = verifyPassword
    }
}

public enum AuthorizationSequencePurpose {
    case normal
    case doubleBottomReentry(AuthorizationSequenceDoubleBottomReentryContext)
}
