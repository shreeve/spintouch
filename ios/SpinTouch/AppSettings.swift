import Foundation
import Security

/// User-configurable settings. The Anthropic API key lives in the Keychain;
/// everything else is small, non-secret config in UserDefaults. All properties
/// are @Published so SwiftUI re-renders (e.g. the LSI gauge) react to edits.
@MainActor
final class AppSettings: ObservableObject {
    @Published var apiKey: String { didSet { guard loaded else { return }; Keychain.set(apiKey, for: Self.keyKeychain) } }
    @Published var poolVolumeGallons: String { didSet { persist(poolVolumeGallons, "poolVolumeGallons") } }
    @Published var poolType: String { didSet { persist(poolType, "poolType") } }
    @Published var poolNotes: String { didSet { persist(poolNotes, "poolNotes") } }
    @Published var model: String { didSet { persist(model, "anthropicModel") } }
    @Published var waterTempF: String { didSet { persist(waterTempF, "waterTempF") } }
    @Published var aiDisclosureAccepted: Bool { didSet { guard loaded else { return }; UserDefaults.standard.set(aiDisclosureAccepted, forKey: "aiDisclosureAccepted") } }

    private var loaded = false

    static let keyKeychain = "anthropic_api_key"
    static let defaultModel = "claude-sonnet-4-5"
    static let poolTypeOptions = ["Chlorine", "Saltwater", "Bromine", "Biguanide", "Other"]

    init() {
        let d = UserDefaults.standard
        apiKey = Keychain.get(Self.keyKeychain) ?? Keychain.getLegacy(Self.keyKeychain) ?? ""
        poolVolumeGallons = d.string(forKey: "poolVolumeGallons") ?? ""
        poolType = d.string(forKey: "poolType") ?? "Chlorine"
        poolNotes = d.string(forKey: "poolNotes") ?? ""
        model = d.string(forKey: "anthropicModel") ?? Self.defaultModel
        waterTempF = d.string(forKey: "waterTempF") ?? ""
        aiDisclosureAccepted = d.bool(forKey: "aiDisclosureAccepted")
        loaded = true

        // Migrate any earlier free-text pool type to a known option.
        if !Self.poolTypeOptions.contains(poolType) { poolType = "Chlorine" }
        // Re-save a legacy (serviceless) key under the new service-scoped item.
        if !apiKey.isEmpty { Keychain.set(apiKey, for: Self.keyKeychain) }
    }

    private func persist(_ value: String, _ key: String) {
        guard loaded else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var poolVolumeValue: Int? {
        Int(poolVolumeGallons) ?? Int(poolVolumeGallons.filter(\.isNumber))
    }

    var waterTempValue: Double? {
        let s = waterTempF.replacingOccurrences(of: ",", with: ".")
        return Double(s) ?? Double(s.filter { $0.isNumber || $0 == "." || $0 == "-" })
    }
}

/// Keychain string storage scoped by service + account.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "SpinTouch"

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if value.isEmpty {
            SecItemDelete(base as CFDictionary)
            return true
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    static func get(_ account: String) -> String? {
        read([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ])
    }

    /// Read a pre-existing item that was stored without a service attribute.
    static func getLegacy(_ account: String) -> String? {
        read([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ])
    }

    private static func read(_ query: [String: Any]) -> String? {
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
