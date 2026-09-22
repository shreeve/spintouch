import Foundation

enum BuildInfo {
    static let builtAt = "2026-09-22 19:50:25 UTC"
    static let gitCommit = "b36e364"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
