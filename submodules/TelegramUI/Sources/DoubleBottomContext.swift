import TelegramCore
import TelegramUIPreferences
import SwiftSignalKit

public final class DoubleBottomContext {
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let currentProfilePromise = Promise<DoubleBottomProfile>()

    public var currentProfile: Signal<DoubleBottomProfile, NoError> {
        return self.currentProfilePromise.get()
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
}
