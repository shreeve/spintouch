import Foundation

enum BuildInfo {
    static let builtAt = "2026-06-25 03:03:00 UTC"
    static let gitCommit = "4e8d600"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
