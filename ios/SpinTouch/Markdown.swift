import SwiftUI
import WebKit

/// Minimal, dependency-free Markdown → HTML conversion for the AI read.
/// Handles the subset Claude emits here: headings, bold/italic/code, links,
/// ordered/unordered lists, horizontal rules, and paragraphs.
enum Markdown {
    /// Build a full styled HTML document from the AI response. If the response
    /// already looks like HTML, sanitize and use it directly; otherwise treat it
    /// as Markdown and convert. Either way it's wrapped in our CSS document.
    static func html(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksHTML = trimmed.range(
            of: #"<(h[1-6]|p|ul|ol|li|table|strong|em|div|br)\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil
        let inner = looksHTML ? sanitize(trimmed) : body(from: trimmed)
        return document(body: inner)
    }

    /// Treat model HTML as untrusted: strip scripts, dangerous tags, inline
    /// event handlers, and unsafe URL schemes. Combined with a strict CSP and
    /// JavaScript disabled in the web view, this is defense-in-depth.
    private static func sanitize(_ html: String) -> String {
        var s = html
        // Remove dangerous tags entirely (with their content where it matters).
        s = s.replacing(/(?is)<\s*(script|style)\b[\s\S]*?<\s*\/\s*\1\s*>/) { _ in "" }
        s = s.replacing(/(?is)<\s*\/?\s*(script|style|iframe|object|embed|form|meta|link|base|svg|audio|video|source)\b[^>]*>/) { _ in "" }
        // Inline event handlers (onload=, onclick=, ...).
        s = s.replacing(/(?i)\son[a-z]+\s*=\s*"[^"]*"/) { _ in "" }
        s = s.replacing(/(?i)\son[a-z]+\s*=\s*'[^']*'/) { _ in "" }
        s = s.replacing(/(?i)\son[a-z]+\s*=\s*[^\s>]+/) { _ in "" }
        // Unsafe URL schemes in any href/src attribute.
        s = s.replacing(/(?i)\s(href|src)\s*=\s*"\s*(javascript|data|file|vbscript):[^"]*"/) { _ in "" }
        s = s.replacing(/(?i)\s(href|src)\s*=\s*'\s*(javascript|data|file|vbscript):[^']*'/) { _ in "" }
        return s
    }

    private static func body(from markdown: String) -> String {
        var html = ""
        var inUL = false
        var inOL = false

        func closeUL() { if inUL { html += "</ul>"; inUL = false } }
        func closeOL() { if inOL { html += "</ol>"; inOL = false } }
        func closeLists() { closeUL(); closeOL() }

        for raw in markdown.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.isEmpty { closeLists(); continue }

            if line.hasPrefix("### ") {
                closeLists(); html += "<h3>\(inlineFmt(esc(String(line.dropFirst(4)))))</h3>"; continue
            }
            if line.hasPrefix("## ") {
                closeLists(); html += "<h2>\(inlineFmt(esc(String(line.dropFirst(3)))))</h2>"; continue
            }
            if line.hasPrefix("# ") {
                closeLists(); html += "<h1>\(inlineFmt(esc(String(line.dropFirst(2)))))</h1>"; continue
            }
            if line == "---" || line == "***" || line == "___" {
                closeLists(); html += "<hr>"; continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                closeOL()
                if !inUL { html += "<ul>"; inUL = true }
                html += "<li>\(inlineFmt(esc(String(line.dropFirst(2)))))</li>"
                continue
            }

            if let m = line.firstMatch(of: /^\d+\.\s+(.*)$/) {
                closeUL()
                if !inOL { html += "<ol>"; inOL = true }
                html += "<li>\(inlineFmt(esc(String(m.output.1))))</li>"
                continue
            }

            closeLists()
            html += "<p>\(inlineFmt(esc(line)))</p>"
        }

        closeLists()
        return html
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func inlineFmt(_ input: String) -> String {
        var s = input
        s = s.replacing(/\[([^\]]+)\]\(([^)]+)\)/) { m in
            let url = String(m.output.2)
            guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return String(m.output.1) }
            return "<a href=\"\(url.replacingOccurrences(of: "\"", with: "&quot;"))\">\(m.output.1)</a>"
        }
        s = s.replacing(/`([^`]+)`/) { "<code>\($0.output.1)</code>" }
        s = s.replacing(/\*\*([^*]+)\*\*/) { "<strong>\($0.output.1)</strong>" }
        s = s.replacing(/_([^_]+)_/) { "<em>\($0.output.1)</em>" }
        return s
    }

    private static func document(body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; media-src 'none'; frame-src 'none'; connect-src 'none'; form-action 'none'; base-uri 'none'">
        <style>
          :root { color-scheme: light dark; }
          html, body { background: transparent; }
          body {
            font: -apple-system-body;
            font-family: -apple-system, system-ui, sans-serif;
            margin: 0; padding: 4px 4px 24px;
            line-height: 1.5;
            color: #1c1c1e;
            -webkit-text-size-adjust: 100%;
            word-wrap: break-word;
          }
          h1 { font-size: 1.35em; } h2 { font-size: 1.18em; } h3 { font-size: 1.05em; }
          h1, h2, h3 { line-height: 1.25; margin: 1.1em 0 0.4em; }
          p { margin: 0.5em 0; }
          ul, ol { padding-left: 1.35em; margin: 0.4em 0; }
          li { margin: 0.25em 0; }
          strong { font-weight: 600; }
          code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 0.92em;
            background: rgba(127,127,127,0.16);
            padding: 0.1em 0.34em; border-radius: 5px;
          }
          a { color: #0a84ff; text-decoration: none; }
          hr { border: none; border-top: 1px solid rgba(127,127,127,0.3); margin: 1em 0; }
          table { border-collapse: collapse; width: 100%; margin: 0.7em 0; font-size: 0.95em; }
          th, td { border: 1px solid rgba(127,127,127,0.3); padding: 6px 9px; text-align: left; vertical-align: top; }
          th { background: rgba(127,127,127,0.12); font-weight: 600; }
          @media (prefers-color-scheme: dark) {
            body { color: #f2f2f7; }
          }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

/// Renders an HTML string in a transparent, non-scrolling-chrome WKWebView that
/// blends into the surrounding SwiftUI sheet.
struct HTMLView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow the initial loadHTMLString; send any tapped links to Safari.
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
