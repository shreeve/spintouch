import Foundation

enum BuildInfo {
    static let builtAt = "2026-06-25 04:25:09 UTC"
    static let gitCommit = "56e2bdf"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
