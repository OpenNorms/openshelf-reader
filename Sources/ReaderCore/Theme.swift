import Foundation

/// A reader theme: a named set of design tokens.
///
/// Themes in the OpenShelf ecosystem already exist as packages
/// (`themes/<name>/theme.yaml` + templates + assets) for composed web
/// sites, where a theme is "the whole front-end". The reader cannot use
/// web templates; what it shares with a theme package is its *token
/// core* — colours and type choices. A theme.yaml may carry a `tokens:`
/// map; when it does, the reader honours it. The bundled themes below
/// are defined directly in tokens.
public struct ReaderTheme: Equatable {
    public var name: String
    public var isDark: Bool
    public var tokens: [String: String]

    public init(name: String, isDark: Bool, tokens: [String: String]) {
        self.name = name
        self.isDark = isDark
        self.tokens = ReaderTheme.defaults.merging(tokens) { _, new in new }
    }

    public func token(_ key: String) -> String {
        tokens[key] ?? ReaderTheme.defaults[key] ?? "#000000"
    }

    /// Token defaults — every theme resolves every key.
    public static let defaults: [String: String] = [
        "bg": "#0b0e13", "panel": "#12161d", "panel2": "#171c25",
        "ink": "#e8e2d5", "dim": "#9aa3ad", "faint": "#6b7280",
        "line": "#232a35", "amber": "#e8a33d", "teal": "#2dd4bf",
        "rust": "#e0654a", "gold": "#c9a227", "codebg": "#0e1218",
        "serif": "Georgia, 'Times New Roman', serif",
        "sans": "-apple-system, 'Helvetica Neue', Arial, sans-serif",
        "mono": "ui-monospace, Menlo, monospace",
    ]

    public static let ink = ReaderTheme(name: "Ink", isDark: true, tokens: [:])

    public static let paper = ReaderTheme(name: "Paper", isDark: false, tokens: [
        "bg": "#f7f3ea", "panel": "#fffdf6", "panel2": "#efe9db",
        "ink": "#1c1a16", "dim": "#5c564a", "faint": "#8a8378",
        "line": "#ddd5c2", "codebg": "#efe9db",
    ])

    /// The boat site's dark/orange nautical register.
    public static let chart = ReaderTheme(name: "Chart", isDark: true, tokens: [
        "bg": "#0d1117", "panel": "#131a22", "panel2": "#18222d",
        "ink": "#e6e1d8", "dim": "#93a1ad", "faint": "#63707c",
        "line": "#243140", "amber": "#f08c1e", "teal": "#35c4b5",
        "rust": "#e05f3c", "codebg": "#0a0e13",
    ])

    public static let mono = ReaderTheme(name: "Mono", isDark: true, tokens: [
        "bg": "#000000", "panel": "#0a0a0a", "panel2": "#111111",
        "ink": "#f2f2f2", "dim": "#b5b5b5", "faint": "#7a7a7a",
        "line": "#262626", "amber": "#f2f2f2", "teal": "#f2f2f2",
        "rust": "#f2f2f2", "gold": "#f2f2f2", "codebg": "#050505",
    ])

    public static let sepia = ReaderTheme(name: "Sepia", isDark: false, tokens: [
        "bg": "#f3e9d2", "panel": "#faf2dd", "panel2": "#eee1c4",
        "ink": "#3a2f22", "dim": "#6d5c44", "faint": "#97835f",
        "line": "#ddcda6", "amber": "#b06f1e", "teal": "#2e7d6b",
        "rust": "#b34a2e", "gold": "#96741a", "codebg": "#eee1c4",
    ])

    public static let bundled: [ReaderTheme] = [.ink, .paper, .chart, .mono, .sepia]

    /// Load a theme from a theme package's `theme.yaml` text. Reads the
    /// package name and, when present, its `tokens:` map (the portable
    /// core); template/asset entries are the web layer and are ignored.
    public static func fromThemeYAML(_ text: String) -> ReaderTheme? {
        let root = YAMLValue.map(YAMLSubset.parse(text))
        guard let name = root.string(forKey: "name") else { return nil }
        var tokens: [String: String] = [:]
        if let tokenMap = root.value(forKey: "tokens"), case .map(let pairs) = tokenMap {
            for pair in pairs {
                if let v = pair.value.scalarValue { tokens[pair.key] = v }
            }
        }
        let dark = (root.string(forKey: "dark") ?? "true") != "false"
        return ReaderTheme(name: name, isDark: dark, tokens: tokens)
    }

    // MARK: - CSS / HTML shell

    public var cssVariables: String {
        let keys = ["bg", "panel", "panel2", "ink", "dim", "faint", "line",
                    "amber", "teal", "rust", "gold", "codebg"]
        let body = keys.map { "--\($0):\(token($0));" }.joined()
        return ":root{\(body)--serif:\(token("serif"));--sans:\(token("sans"));--mono:\(token("mono"));}"
    }

    /// The full stylesheet for a rendered page (content styles shared
    /// with the web renderers' register: serif display type, amber
    /// accents, panel surfaces).
    public var pageCSS: String {
        """
        \(cssVariables)
        *{box-sizing:border-box}
        body{margin:0;background:var(--bg);color:var(--ink);
          font-family:var(--sans);font-size:17px;line-height:1.55;
          padding:20px 18px 48px;-webkit-text-size-adjust:100%}
        h1,h2,h3,h4{font-family:var(--serif);line-height:1.2;margin:1.2em 0 .5em}
        h1{font-size:30px;margin-top:0}
        h2{font-size:23px} h3{font-size:19px}
        p{margin:.6em 0}
        a{color:var(--amber);text-decoration:none}
        a.broken{color:var(--rust);text-decoration:line-through}
        code{font-family:var(--mono);font-size:.86em;background:var(--codebg);
          padding:.1em .35em;border-radius:5px}
        pre{background:var(--codebg);border:1px solid var(--line);
          border-radius:10px;padding:12px;overflow-x:auto}
        pre code{background:none;padding:0}
        blockquote{border-left:3px solid var(--amber);margin:.8em 0;
          padding:.2em 0 .2em 14px;color:var(--dim)}
        table{border-collapse:collapse;width:100%;font-size:14px;margin:1em 0}
        th,td{border-bottom:1px solid var(--line);padding:7px 8px;text-align:left;vertical-align:top}
        th{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.08em}
        img{max-width:100%}
        hr{border:none;border-top:1px solid var(--line);margin:1.4em 0}
        .provenance{font-family:var(--mono);font-size:11px;color:var(--faint);
          border:1px solid var(--line);border-radius:8px;padding:6px 9px;margin-bottom:16px}
        .meta{border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin-top:22px}
        .meta h3{margin-top:0;font-size:15px}
        .meta table{margin:0}
        .verdict{display:inline-block;font-family:var(--mono);font-size:12px;
          border:1px solid var(--amber);color:var(--amber);border-radius:999px;
          padding:2px 10px;margin-bottom:10px}
        """
    }

    /// Wrap a rendered fragment in the HTML document the web view loads.
    public func htmlDocument(title: String, bodyHTML: String,
                             provenance: String? = nil,
                             metadata: [(key: String, value: String)] = []) -> String {
        var parts: [String] = []
        parts.append("<!doctype html><html><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<style>\(pageCSS)</style></head><body>")
        if let provenance {
            parts.append("<div class=\"provenance\">\(Markdown.escape(provenance))</div>")
        }
        parts.append(bodyHTML)
        if !metadata.isEmpty {
            var meta = "<div class=\"meta\"><h3>Page metadata</h3><table>"
            for pair in metadata {
                meta += "<tr><td>\(Markdown.escape(pair.key))</td>"
                    + "<td>\(Markdown.escape(pair.value))</td></tr>"
            }
            meta += "</table></div>"
            parts.append(meta)
        }
        parts.append("</body></html>")
        return parts.joined(separator: "\n")
    }
}
