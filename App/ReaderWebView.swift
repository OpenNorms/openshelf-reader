import SwiftUI
import WebKit

/// A WKWebView that displays one rendered page and routes its links.
///
/// Rendered HTML is loaded with base URL `openshelf://reader/`, so the
/// core's routes resolve against it: `page/<slug>` and
/// `kb/<kb-id>/<slug>` arrive as link taps on that scheme and are
/// handed to `onRoute`. `kbfile://<kb-id>/<path>` references (images
/// and attachments) are loaded from the member KB's cache directory.
/// Ordinary http(s) links open in the browser.
struct ReaderWebView: UIViewRepresentable {
    var html: String
    /// Resolve a kbfile path for a KB id to a file URL in its cache.
    var fileURL: (_ kbID: String, _ path: String) -> URL?
    var onRoute: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .clear
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            webView.loadHTMLString(html,
                                   baseURL: URL(string: "openshelf://reader/"))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ReaderWebView
        var loadedHTML: String?

        init(_ parent: ReaderWebView) { self.parent = parent }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            switch url.scheme {
            case "openshelf":
                // Path is "/page/<slug>" or "/kb/<id>/<slug>".
                let route = url.path.hasPrefix("/")
                    ? String(url.path.dropFirst()) : url.path
                parent.onRoute(route)
                decisionHandler(.cancel)
            case "kbfile":
                if let host = url.host,
                   let file = parent.fileURL(host, url.path) {
                    webView.loadFileURL(file, allowingReadAccessTo: file)
                }
                decisionHandler(.cancel)
            case "http", "https":
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }
    }
}
