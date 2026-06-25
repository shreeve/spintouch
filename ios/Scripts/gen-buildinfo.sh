#!/bin/sh
# Regenerates SpinTouch/BuildInfo.swift on every build with the current git
# commit and UTC build timestamp. Invoked from the "Generate BuildInfo" run
# script build phase. SRCROOT points at the `ios` directory.
set -eu

repo_root="${SRCROOT}/.."
out="${SRCROOT}/SpinTouch/BuildInfo.swift"

commit="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
built_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

cat > "$out" <<SWIFT
import Foundation

enum BuildInfo {
    static let builtAt = "${built_at}"
    static let gitCommit = "${commit}"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
SWIFT
