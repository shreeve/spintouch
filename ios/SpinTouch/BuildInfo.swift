import Foundation

enum BuildInfo {
    static let builtAt = "2026-06-25 03:04:18 UTC"
    static let gitCommit = "bbe734d"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
