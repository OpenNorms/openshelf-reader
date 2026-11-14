import Foundation

/// System-wide colour mode: follow the device, or force light / dark.
public enum AppearanceMode: String, Codable, CaseIterable {
    case system, light, dark
}

/// System-wide display typeface. Serif is New York (`ui-serif`), sans is
/// the system font; mono is always the system monospace.
public enum Typeface: String, Codable, CaseIterable {
    case serif, sans
}

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
        "rust": "#e0654a", "gold": "#c9a227", "codebg": "#171c25",
        "serif": "ui-serif, 'New York', Georgia, serif",
        "sans": "-apple-system, 'Helvetica Neue', Arial, sans-serif",
        "mono": "ui-monospace, Menlo, monospace",
    ]

    public static let ink = ReaderTheme(name: "Ink", isDark: true, tokens: [:])

    public static let paper = ReaderTheme(name: "Paper", isDark: false, tokens: [
        "bg": "#f7f3ea", "panel": "#fffdf6", "panel2": "#efe9db",
        "ink": "#1c1a16", "dim": "#5c564a", "faint": "#8a8378",
        "line": "#ddd5c2", "codebg": "#ebe4d3",
        // Light-ground accents (the dark defaults are too pale on cream).
        "amber": "#a5600f", "teal": "#1d7566", "rust": "#b03f26", "gold": "#856a0e",
    ])

    /// The boat site's dark/orange nautical register.
    public static let chart = ReaderTheme(name: "Chart", isDark: true, tokens: [
        "bg": "#0d1117", "panel": "#131a22", "panel2": "#18222d",
        "ink": "#e6e1d8", "dim": "#93a1ad", "faint": "#63707c",
        "line": "#243140", "amber": "#f08c1e", "teal": "#35c4b5",
        "rust": "#e05f3c", "codebg": "#18222d",
    ])

    public static let mono = ReaderTheme(name: "Mono", isDark: true, tokens: [
        "bg": "#000000", "panel": "#0a0a0a", "panel2": "#111111",
        "ink": "#f2f2f2", "dim": "#b5b5b5", "faint": "#7a7a7a",
        "line": "#262626", "amber": "#f2f2f2", "teal": "#f2f2f2",
        "rust": "#f2f2f2", "gold": "#f2f2f2", "codebg": "#161616",
    ])

    public static let sepia = ReaderTheme(name: "Sepia", isDark: false, tokens: [
        "bg": "#f3e9d2", "panel": "#faf2dd", "panel2": "#eee1c4",
        "ink": "#3a2f22", "dim": "#6d5c44", "faint": "#97835f",
        "line": "#ddcda6", "amber": "#b06f1e", "teal": "#2e7d6b",
        "rust": "#b34a2e", "gold": "#96741a", "codebg": "#e9dab8",
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

    public static let minTextSize = 14
    public static let maxTextSize = 24
    public static let defaultTextSize = 17

    /// The full stylesheet for a rendered page. `typeface` picks the
    /// display + body family (code is always mono); `textSize` is the
    /// body size in px, clamped to 14...24, with headings scaled from it.
    public func pageCSS(typeface: Typeface = .serif,
                        textSize: Int = ReaderTheme.defaultTextSize) -> String {
        let size = min(max(textSize, Self.minTextSize), Self.maxTextSize)
        let face = typeface == .serif ? "var(--serif)" : "var(--sans)"
        return """
        \(cssVariables)
        :root{--face:\(face);--fs:\(size)px}
        *{box-sizing:border-box}
        html,body{max-width:100%;overflow-x:hidden}
        body{overflow-wrap:break-word}
        a{overflow-wrap:anywhere}
        body{margin:0;background:var(--bg);color:var(--ink);
          font-family:var(--face);font-size:var(--fs);line-height:1.55;
          padding:22px 22px 132px;-webkit-text-size-adjust:100%}
        h1,h2,h3,h4{font-family:var(--face);font-weight:500;line-height:1.2;
          margin:1.3em 0 .5em;scroll-margin-top:12px}
        h1{font-size:1.75em;margin-top:0}
        h2{font-size:1.35em} h3{font-size:1.12em}
        h4{font-size:1em}
        p{margin:.6em 0}
        a{color:var(--amber);text-decoration:none}
        a.broken{color:var(--rust);text-decoration:line-through}
        a[href^="http://"],a[href^="https://"]{text-decoration:underline dotted;
          text-underline-offset:3px;text-decoration-thickness:1px}
        a[href^="http://"]::after,a[href^="https://"]::after{content:"\\2197\\FE0E";
          font-size:.8em;margin-left:.15em;vertical-align:.15em;opacity:.75}
        ul,ol{padding-left:1.3em}
        li{margin:.3em 0}
        ul>li::marker{color:var(--amber)}
        code{font-family:var(--mono);font-size:.86em;background:var(--codebg);
          border:1px solid var(--line);padding:.08em .35em;border-radius:5px;
          overflow-wrap:anywhere}
        pre{position:relative;background:var(--codebg);border:1px solid var(--line);
          border-radius:10px;padding:12px 14px;overflow-x:auto;tab-size:4;
          font-size:13.5px;line-height:1.45}
        pre[data-lang]{padding-top:26px}
        pre[data-lang]::before{content:attr(data-lang);position:absolute;top:7px;right:12px;
          font-family:-apple-system,sans-serif;font-size:10px;letter-spacing:.08em;
          text-transform:uppercase;color:var(--faint)}
        pre code{background:none;border:none;padding:0;font-size:inherit;
          overflow-wrap:normal;white-space:pre}
        .hljs-keyword,.hljs-selector-tag,.hljs-meta .hljs-keyword{color:var(--amber)}
        .hljs-string,.hljs-regexp,.hljs-char,.hljs-addition{color:var(--teal)}
        .hljs-number,.hljs-literal,.hljs-symbol,.hljs-bullet,.hljs-deletion{color:var(--rust)}
        .hljs-type,.hljs-built_in,.hljs-title.class_,.hljs-selector-class{color:var(--gold)}
        .hljs-title,.hljs-title.function_,.hljs-section{font-weight:600}
        .hljs-comment,.hljs-quote{color:var(--faint);font-style:italic}
        .hljs-meta,.hljs-attr,.hljs-attribute,.hljs-variable,.hljs-params{color:var(--dim)}
        .hljs-emphasis{font-style:italic} .hljs-strong{font-weight:700}
        .mermaid{margin:1em 0;overflow-x:auto;text-align:center}
        .mermaid svg{max-width:100%;height:auto}
        blockquote{border-left:3px solid var(--amber);margin:.8em 0;
          padding:.2em 0 .2em 14px;color:var(--dim)}
        .table-wrap{overflow-x:auto;margin:1em 0}
        .table-wrap table{margin:0}
        table{border-collapse:collapse;width:100%;font-size:.82em;margin:1em 0}
        th,td{border-bottom:1px solid var(--line);padding:7px 8px;text-align:left;vertical-align:top}
        th{color:var(--dim);font-size:.78em;text-transform:uppercase;letter-spacing:.08em;
          font-family:-apple-system,sans-serif}
        img{max-width:100%}
        hr{border:none;border-top:1px solid var(--line);margin:1.4em 0}
        .chips{display:flex;flex-wrap:wrap;gap:8px;margin:4px 0 0}
        .chip{font-family:var(--mono);font-size:11px;letter-spacing:.08em;text-transform:uppercase;
          color:var(--dim);border:1px solid var(--line);border-radius:999px;padding:4px 10px}
        .chip.primary{color:var(--amber);border-color:var(--amber)}
        .title{font-family:var(--face);font-weight:500;font-size:calc(var(--fs)*2.35);
          line-height:1.04;letter-spacing:-.01em;margin:14px 0 0;overflow-wrap:anywhere}
        .lede{font-family:var(--face);font-size:calc(var(--fs)*1.18);line-height:1.42;margin:16px 0 0}
        .page-body{margin-top:22px}
        .page-body>:first-child{margin-top:0}
        .meta{border:1px solid var(--line);background:var(--panel);border-radius:16px;
          padding:4px 16px 0;margin-top:28px;overflow:hidden}
        .meta-grid{margin-bottom:-1px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));column-gap:16px}
        .meta-cell{padding:12px 0;border-bottom:1px solid var(--line);display:flex;
          flex-direction:column;gap:3px;min-width:0}
        .meta-cell.wide{grid-column:1/-1}
        .meta-k{font-family:-apple-system,sans-serif;font-size:11px;letter-spacing:.1em;
          text-transform:uppercase;color:var(--faint)}
        .meta-v{font-size:15px;line-height:1.4;overflow-wrap:anywhere}
        .meta-v.mono{font-family:var(--mono);font-size:13px}
        .verdict{display:inline-block;font-family:var(--mono);font-size:12px;
          border:1px solid var(--amber);color:var(--amber);border-radius:999px;
          padding:2px 10px;margin-bottom:10px}
        """
    }

    /// What the shell shows above the page body.
    public struct PageHeader {
        public var title: String
        public var summary: String?
        /// Chips under the top of the page; the first is drawn as primary.
        public var chips: [String]

        public init(title: String, summary: String? = nil, chips: [String] = []) {
            self.title = title
            self.summary = summary
            self.chips = chips
        }
    }

    /// Wrap a rendered fragment in the HTML document the web view loads:
    /// chips, title and lede (when `header` is given), the body, then a
    /// two-column metadata card whose last cell is the provenance.
    public func htmlDocument(title: String, bodyHTML: String,
                             provenance: String? = nil,
                             metadata: [(key: String, value: String)] = [],
                             header: PageHeader? = nil,
                             typeface: Typeface = .serif,
                             textSize: Int = ReaderTheme.defaultTextSize) -> String {
        var parts: [String] = []
        parts.append("<!doctype html><html><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no\">"
            + "<title>\(Markdown.escape(title))</title>"
            + "<style>\(pageCSS(typeface: typeface, textSize: textSize))</style></head><body>")
        if let header {
            if !header.chips.isEmpty {
                let chips = header.chips.enumerated().map { idx, chip in
                    "<span class=\"chip\(idx == 0 ? " primary" : "")\">\(Markdown.escape(chip))</span>"
                }.joined()
                parts.append("<div class=\"chips\">\(chips)</div>")
            }
            parts.append("<h1 class=\"title\">\(Markdown.escape(header.title))</h1>")
            if let summary = header.summary, !summary.isEmpty {
                parts.append("<p class=\"lede\">\(Markdown.escape(summary))</p>")
            }
            parts.append("<div class=\"page-body\">\n\(bodyHTML)\n</div>")
        } else {
            parts.append(bodyHTML)
        }
        var cells: [(key: String, value: String, mono: Bool)] =
            metadata.map { ($0.key, $0.value, false) }
        if let provenance { cells.append(("Source", provenance, true)) }
        if !cells.isEmpty {
            var meta = "<div class=\"meta\"><div class=\"meta-grid\">"
            let wide = cells.map { $0.value.count > 40 }
            for (idx, cell) in cells.enumerated() {
                var cls = "meta-cell"
                if wide[idx] { cls += " wide" }
                meta += "<div class=\"\(cls)\"><div class=\"meta-k\">\(Markdown.escape(cell.key))</div>"
                    + "<div class=\"meta-v\(cell.mono ? " mono" : "")\">\(Markdown.escape(cell.value))</div></div>"
            }
            meta += "</div></div>"
            parts.append(meta)
        }
        parts.append("</body></html>")
        return parts.joined(separator: "\n")
    }
}
