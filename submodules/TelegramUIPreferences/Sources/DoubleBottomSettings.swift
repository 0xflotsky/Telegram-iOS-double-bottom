import Foundation
import TelegramCore
import SwiftSignalKit

public enum DoubleBottomProfile: Int32, Codable {
    case primary = 0
    case decoy = 1

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer(), let rawValue = try? container.decode(Int32.self) else {
            self = .primary
            return
        }
        self = DoubleBottomProfile(rawValue: rawValue) ?? .primary
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

public struct DoubleBottomSettings: Codable, Equatable {
    public var currentProfile: DoubleBottomProfile

    public static var defaultSettings: DoubleBottomSettings {
        return DoubleBottomSettings(currentProfile: .primary)
    }

    public init(currentProfile: DoubleBottomProfile) {
        self.currentProfile = currentProfile
    }

    private enum CodingKeys: String, CodingKey {
        case currentProfile = "p"
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.currentProfile = .primary
            return
        }
        let rawValue = (try? container.decode(Int32.self, forKey: .currentProfile)) ?? DoubleBottomProfile.primary.rawValue
        self.currentProfile = DoubleBottomProfile(rawValue: rawValue) ?? .primary
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.currentProfile.rawValue, forKey: .currentProfile)
    }
}

public func doubleBottomSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<DoubleBottomSettings, NoError> {
    return accountManager.sharedData(keys: Set([ApplicationSpecificSharedDataKeys.doubleBottomSettings]))
    |> map { sharedData in
        return sharedData.entries[ApplicationSpecificSharedDataKeys.doubleBottomSettings]?.get(DoubleBottomSettings.self) ?? .defaultSettings
    }
}

public func updateDoubleBottomSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (DoubleBottomSettings) -> DoubleBottomSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.doubleBottomSettings, { entry in
            let currentSettings = entry?.get(DoubleBottomSettings.self) ?? .defaultSettings
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
