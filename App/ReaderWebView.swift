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
/// Scroll progress, observed only by the progress hairline so that
/// scrolling never re-renders the page screen.
final class ScrollProgress: ObservableObject {
    @Published var fraction: Double = 0
}

/// Commands to, and scroll state from, a ReaderWebView.
final class ReaderWebController {
    let progress = ScrollProgress()
    fileprivate weak var webView: WKWebView?

    /// Scroll the heading with this element id to the top of the page.
    func scrollToHeading(id: String) {
        guard let data = try? JSONEncoder().encode(id),
              let literal = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript(
            "var e=document.getElementById(\(literal)); if(e){e.scrollIntoView({behavior:'smooth',block:'start'})}; void 0")
    }
}

struct ReaderWebView: UIViewRepresentable {
    var html: String
    /// Resolve a kbfile path for a KB id to a file URL in its cache.
    var fileURL: (_ kbID: String, _ path: String) -> URL?
    var onRoute: (String) -> Void
    /// Horizontal page swipe (see App/swipe.js).
    var onSwipe: (SwipeDirection) -> Void = { _ in }
    /// Whether a forward page exists; the swipe script rubber-bands if not.
    var canGoForward = false
    /// Lets the SwiftUI side scroll the page and read its scroll progress.
    var controller: ReaderWebController?
    /// Identifies the page; reloading the same page (appearance change)
    /// keeps its scroll position, a different page starts at the top.
    var pageID = ""

    enum SwipeDirection { case back, forward }

    /// highlight.js (App/Vendor) plus a runner that colours only fenced
    /// blocks with a language the bundle knows; untagged blocks stay plain
    /// rather than being guessed at. Loaded once, shared by all pages.
    private static let highlightScript: WKUserScript? = {
        guard let url = Bundle.main.url(forResource: "highlight.min", withExtension: "js"),
              let lib = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let run = """
        document.querySelectorAll('pre code[class*="language-"]').forEach(function (el) {
          var lang = (el.className.match(/language-(\\S+)/) || [])[1];
          if (lang && hljs.getLanguage(lang)) { hljs.highlightElement(el); }
        });
        """
        return WKUserScript(source: lib + "\n" + run,
                            injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }()

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if let script = Self.highlightScript {
            config.userContentController.addUserScript(script)
        }
        if let swipe = Coordinator.bundledText("swipe") {
            config.userContentController.addUserScript(
                WKUserScript(source: swipe, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            config.userContentController.add(context.coordinator, name: "swipe")
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .clear
        webView.isOpaque = false
        // Pages are as wide as the screen (CSS); never pan sideways.
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        controller?.webView = webView
        context.coordinator.observeScroll(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.publishCanForward(webView)
        controller?.webView = webView
        if context.coordinator.loadedHTML != html {
            if context.coordinator.loadedHTML != nil, context.coordinator.pageID == pageID {
                context.coordinator.restoreOffset = webView.scrollView.contentOffset.y
            } else {
                context.coordinator.restoreOffset = nil
                controller?.progress.fraction = 0
            }
            context.coordinator.pageID = pageID
            context.coordinator.loadedHTML = html
            webView.loadHTMLString(html,
                                   baseURL: URL(string: "openshelf://reader/"))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // The content controller retains its message handlers.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "swipe")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ReaderWebView
        var loadedHTML: String?
        var pageID = ""
        var restoreOffset: CGFloat?
        private var scrollObservation: NSKeyValueObservation?

        init(_ parent: ReaderWebView) { self.parent = parent }

        func observeScroll(_ webView: WKWebView) {
            scrollObservation = webView.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                let range = scroll.contentSize.height - scroll.bounds.height
                let fraction = range > 1 ? min(max(scroll.contentOffset.y / range, 0), 1) : 0
                DispatchQueue.main.async { self?.parent.controller?.progress.fraction = Double(fraction) }
            }
        }

        // Pages are documents, not zoomable canvases: the viewport meta
        // already disallows scaling; this also stops the pinch gesture.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.pinchGestureRecognizer?.isEnabled = false
            if let y = restoreOffset {
                restoreOffset = nil
                webView.scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            }
            publishCanForward(webView)
            renderMermaidIfNeeded(webView)
        }

        /// mermaid.js is ~2.5 MB, so it is evaluated only on pages that
        /// actually contain a ```mermaid block, after the page has loaded.
        private func renderMermaidIfNeeded(_ webView: WKWebView) {
            guard let library = Self.mermaidLibrary, let runner = Self.mermaidRunner else { return }
            webView.evaluateJavaScript("document.querySelector('pre > code.language-mermaid') !== null") { has, _ in
                guard (has as? Bool) == true else { return }
                webView.evaluateJavaScript(library + "\n;void 0") { _, _ in
                    webView.evaluateJavaScript(runner + "\n;void 0")
                }
            }
        }

        func publishCanForward(_ webView: WKWebView) {
            webView.evaluateJavaScript("window.__openshelfCanForward = \(parent.canGoForward); void 0")
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.body as? String {
            case "back": parent.onSwipe(.back)
            case "forward": parent.onSwipe(.forward)
            default: break
            }
        }

        static func bundledText(_ name: String) -> String? {
            Bundle.main.url(forResource: name, withExtension: "js")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        private static let mermaidLibrary = bundledText("mermaid.min")
        private static let mermaidRunner = bundledText("mermaid-run")

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
