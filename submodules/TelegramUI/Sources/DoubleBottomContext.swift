import TelegramCore
import TelegramUIPreferences
import SwiftSignalKit

public enum DoubleBottomAccessState: Equatable {
    case unlocked
    case secureExited
}

public final class DoubleBottomContext {
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let currentProfilePromise = Promise<DoubleBottomProfile>()
    private let accessStatePromise = ValuePromise<DoubleBottomAccessState>(.secureExited, ignoreRepeated: true)

    public var currentProfile: Signal<DoubleBottomProfile, NoError> {
        return self.currentProfilePromise.get()
    }

    public var accessState: Signal<DoubleBottomAccessState, NoError> {
        return self.accessStatePromise.get()
    }

    public init(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.accountManager = accountManager
        self.currentProfilePromise.set(
            doubleBottomSettings(accountManager: accountManager)
            |> map(\.currentProfile)
            |> distinctUntilChanged
        )
    }

    public func setCurrentProfile(_ profile: DoubleBottomProfile) -> Signal<Void, NoError> {
        return updateDoubleBottomSettingsInteractively(accountManager: self.accountManager) { settings in
            var settings = settings
            settings.currentProfile = profile
            return settings
        }
    }

    public func secureExit() {
        assert(Queue.mainQueue().isCurrent())
        self.accessStatePromise.set(.secureExited)
    }

    func completeLocalUnlock() {
        assert(Queue.mainQueue().isCurrent())
        self.accessStatePromise.set(.unlocked)
    }
}
