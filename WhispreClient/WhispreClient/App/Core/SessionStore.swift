import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var accessToken: String?
    @Published var refreshToken: String?
    @Published var userID: String?
    @Published var ownerUserID: String?
    @Published var username: String?
    @Published var deviceID: String?
    @Published var accountDeviceMap: [String: String]
    @Published var hasRegistered: Bool

    private enum Keys {
        static let legacyAccessToken = "session.accessToken"
        static let legacyRefreshToken = "session.refreshToken"
        static let keychainAccessToken = "accessToken"
        static let keychainRefreshToken = "refreshToken"
        static let userID = "session.userId"
        static let ownerUserID = "session.ownerUserId"
        static let username = "session.username"
        static let deviceID = "session.deviceId"
        static let accountDeviceMap = "session.accountDeviceMap"
        static let hasRegistered = "session.hasRegistered"
    }

    private let keychain = KeychainStore(service: "com.whispre.client.session")

    init() {
        let defaults = UserDefaults.standard
        accessToken = Self.loadToken(
            account: Keys.keychainAccessToken,
            legacyKey: Keys.legacyAccessToken,
            keychain: keychain,
            defaults: defaults
        )
        refreshToken = Self.loadToken(
            account: Keys.keychainRefreshToken,
            legacyKey: Keys.legacyRefreshToken,
            keychain: keychain,
            defaults: defaults
        )
        userID = defaults.string(forKey: Keys.userID)
        ownerUserID = defaults.string(forKey: Keys.ownerUserID)
        username = defaults.string(forKey: Keys.username)
        deviceID = defaults.string(forKey: Keys.deviceID)
        if let rawMap = defaults.dictionary(forKey: Keys.accountDeviceMap) as? [String: String] {
            accountDeviceMap = rawMap
        } else {
            accountDeviceMap = [:]
        }
        hasRegistered = defaults.bool(forKey: Keys.hasRegistered)

        if deviceID == nil {
            let newID = UUID().uuidString.lowercased()
            deviceID = newID
            defaults.set(newID, forKey: Keys.deviceID)
        }
    }

    func saveTokens(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        keychain.setString(access, account: Keys.keychainAccessToken)
        keychain.setString(refresh, account: Keys.keychainRefreshToken)
        UserDefaults.standard.removeObject(forKey: Keys.legacyAccessToken)
        UserDefaults.standard.removeObject(forKey: Keys.legacyRefreshToken)
    }

    func saveUser(id: String, username: String) {
        userID = id
        self.username = username
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: Keys.userID)
        defaults.set(username, forKey: Keys.username)
    }

    func bindOwnerIfNeeded(_ userID: String) {
        if ownerUserID == nil {
            ownerUserID = userID
            UserDefaults.standard.set(userID, forKey: Keys.ownerUserID)
        }
    }

    func markRegistered() {
        hasRegistered = true
        UserDefaults.standard.set(true, forKey: Keys.hasRegistered)
    }

    func activateDevice(for userID: String) {
        if let existing = accountDeviceMap[userID] {
            deviceID = existing
        } else {
            let newID = UUID().uuidString.lowercased()
            accountDeviceMap[userID] = newID
            deviceID = newID
            UserDefaults.standard.set(accountDeviceMap, forKey: Keys.accountDeviceMap)
        }
        if let active = deviceID {
            UserDefaults.standard.set(active, forKey: Keys.deviceID)
        }
    }

    func setActiveDevice(_ deviceID: String, for userID: String) {
        accountDeviceMap[userID] = deviceID
        self.deviceID = deviceID
        let defaults = UserDefaults.standard
        defaults.set(accountDeviceMap, forKey: Keys.accountDeviceMap)
        defaults.set(deviceID, forKey: Keys.deviceID)
    }

    func clearSession() {
        accessToken = nil
        refreshToken = nil
        userID = nil
        username = nil

        let defaults = UserDefaults.standard
        keychain.remove(account: Keys.keychainAccessToken)
        keychain.remove(account: Keys.keychainRefreshToken)
        defaults.removeObject(forKey: Keys.legacyAccessToken)
        defaults.removeObject(forKey: Keys.legacyRefreshToken)
        defaults.removeObject(forKey: Keys.userID)
        defaults.removeObject(forKey: Keys.username)
    }

    func resetAllLocalData() {
        accessToken = nil
        refreshToken = nil
        userID = nil
        ownerUserID = nil
        username = nil
        accountDeviceMap = [:]
        hasRegistered = false

        let defaults = UserDefaults.standard
        keychain.remove(account: Keys.keychainAccessToken)
        keychain.remove(account: Keys.keychainRefreshToken)
        defaults.removeObject(forKey: Keys.legacyAccessToken)
        defaults.removeObject(forKey: Keys.legacyRefreshToken)
        defaults.removeObject(forKey: Keys.userID)
        defaults.removeObject(forKey: Keys.ownerUserID)
        defaults.removeObject(forKey: Keys.username)
        defaults.removeObject(forKey: Keys.accountDeviceMap)
        defaults.removeObject(forKey: Keys.hasRegistered)

        let newDeviceID = UUID().uuidString.lowercased()
        deviceID = newDeviceID
        defaults.set(newDeviceID, forKey: Keys.deviceID)
    }

    private static func loadToken(
        account: String,
        legacyKey: String,
        keychain: KeychainStore,
        defaults: UserDefaults
    ) -> String? {
        if let value = keychain.getString(account: account) {
            defaults.removeObject(forKey: legacyKey)
            return value
        }

        guard let legacyValue = defaults.string(forKey: legacyKey) else {
            return nil
        }
        keychain.setString(legacyValue, account: account)
        defaults.removeObject(forKey: legacyKey)
        return legacyValue
    }
}
