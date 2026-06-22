import Foundation
import Security

/// User-configurable settings. The Anthropic API key lives in the Keychain;
/// everything else is small, non-secret config in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    @Published var apiKey: String {
        didSet { Keychain.set(apiKey, for: Self.keyKeychain) }
    }

    @AppStorage_ var poolVolumeGallons: String
    @AppStorage_ var poolType: String
    @AppStorage_ var model: String
    @AppStorage_ var waterTempF: String

    static let keyKeychain = "anthropic_api_key"
    static let defaultModel = "claude-sonnet-4-5"

    init() {
        apiKey = Keychain.get(Self.keyKeychain) ?? ""
        _poolVolumeGallons = AppStorage_(key: "poolVolumeGallons", default: "")
        _poolType = AppStorage_(key: "poolType", default: "Chlorine pool")
        _model = AppStorage_(key: "anthropicModel", default: Self.defaultModel)
        _waterTempF = AppStorage_(key: "waterTempF", default: "")
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var poolVolumeValue: Int? {
        Int(poolVolumeGallons.filter(\.isNumber))
    }

    var waterTempValue: Double? {
        Double(waterTempF.filter { $0.isNumber || $0 == "." })
    }
}

/// Tiny UserDefaults-backed property wrapper usable inside an ObservableObject
/// (Swift's @AppStorage is a View property wrapper and can't be used here).
@propertyWrapper
struct AppStorage_ {
    let key: String
    let `default`: String

    init(key: String, default def: String) {
        self.key = key
        self.default = def
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(def, forKey: key)
        }
    }

    var wrappedValue: String {
        get { UserDefaults.standard.string(forKey: key) ?? `default` }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Minimal Keychain string storage.
enum Keychain {
    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if value.isEmpty { return true }
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
