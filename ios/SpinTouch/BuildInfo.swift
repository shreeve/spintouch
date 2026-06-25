import Foundation

enum BuildInfo {
    static let builtAt = "2026-06-25 05:28:35 UTC"
    static let gitCommit = "4d2b810"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
