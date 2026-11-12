import SwiftUI
import ReaderCore

/// One rendered page: verdict chip (when the page carries the fleet's
/// `verdict:` field), the HTML fragment, provenance, and the generic
/// metadata section — assembled by ReaderCore's theme shell.
struct PageReaderView: View {
    var title: String
    var fragmentHTML: String
    var theme: ReaderTheme
    var provenance: String?
    var metadata: [(key: String, value: String)]
    var verdict: String?
    var fileURL: (_ kbID: String, _ path: String) -> URL?
    var onRoute: (String) -> Void

    private var document: String {
        var body = ""
        if let verdict {
            body += "<div class=\"verdict\">\(Markdown.escape(verdict))</div>\n"
        }
        body += fragmentHTML
        return theme.htmlDocument(title: title, bodyHTML: body,
                                  provenance: provenance, metadata: metadata)
    }

    var body: some View {
        ReaderWebView(html: document, fileURL: fileURL, onRoute: onRoute)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
