import Foundation

enum BuildInfo {
    static let builtAt = "2026-06-25 03:45:12 UTC"
    static let gitCommit = "2e76965"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
