import Foundation

/// A markdown -> HTML fragment renderer for the OpenShelf corpus.
///
/// Covers the dialect the fleet actually writes: ATX headings,
/// paragraphs, bold/italic/strikethrough, inline code and fenced code
/// blocks, GFM tables, nested lists, blockquotes, horizontal rules,
/// images, and links — Markdown `[text](href)` and wikilinks
/// `[[target|label]]` (spec §4.4). Links are passed through a resolver
/// supplied by the caller, which turns relative `.md` references,
/// wikilink targets and `kb://` URLs into reader routes (and flags
/// broken ones). Raw HTML in a page is
/// escaped, not passed through — KBs are agent-maintained markdown,
/// and the reader renders them as documents, not web pages.
public enum Markdown {

    /// Which link syntax a raw reference came from: Markdown hrefs are
    /// paths relative to the page; wikilink targets are page ids.
    public enum LinkKind { case markdown, wiki }

    public typealias LinkResolver = (_ rawHref: String, _ kind: LinkKind) -> (href: String, broken: Bool)
    /// Title of the page a wikilink target resolves to, used as the link
    /// text when the wikilink has no `|label`.
    public typealias WikiTitle = (_ rawTarget: String) -> String?

    public static func render(_ body: String,
                              resolveLink: @escaping LinkResolver = { raw, _ in (raw, false) },
                              wikiTitle: @escaping WikiTitle = { _ in nil }) -> String {
        let linker = Linker(resolve: resolveLink, title: wikiTitle)
        let lines = stripComments(body.components(separatedBy: "\n"))
        var slugger = HeadingSlugger()
        var out: [String] = []
        var i = 0

        func isBlank(_ s: String) -> Bool {
            s.trimmingCharacters(in: .whitespaces).isEmpty
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isBlank(line) { i += 1; continue }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count,
                      !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1  // closing fence
                // Info string's first word is the language ("```swift title=x").
                let language = lang.split(separator: " ").first.map(String.init) ?? ""
                let cls = language.isEmpty ? "" : " class=\"language-\(escape(language))\""
                let data = language.isEmpty ? "" : " data-lang=\"\(escape(language))\""
                out.append("<pre\(data)><code\(cls)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed) {
                let id = slugger.next(for: heading.text)
                out.append("<h\(heading.level) id=\"\(escape(id))\">\(inline(heading.text, linker))</h\(heading.level)>")
                i += 1
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                out.append("<hr>")
                i += 1
                continue
            }

            // Table: header row + separator row
            if trimmed.hasPrefix("|"), i + 1 < lines.count,
               isTableSeparator(lines[i + 1]) {
                var rows: [[String]] = []
                var j = i
                while j < lines.count,
                      lines[j].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(splitTableRow(lines[j]))
                    j += 1
                }
                let header = rows.first ?? []
                let bodyRows = Array(rows.dropFirst(2))
                var html = "<div class=\"table-wrap\"><table><thead><tr>"
                for cell in header {
                    html += "<th>\(inline(cell, linker))</th>"
                }
                html += "</tr></thead><tbody>"
                for row in bodyRows {
                    html += "<tr>"
                    for cell in row {
                        html += "<td>\(inline(cell, linker))</td>"
                    }
                    html += "</tr>"
                }
                html += "</tbody></table></div>"
                out.append(html)
                i = j
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quoted.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                out.append("<blockquote><p>\(inline(quoted.joined(separator: " "), linker))</p></blockquote>")
                continue
            }

            // List (possibly nested)
            if listItem(line) != nil {
                let (html, consumed) = renderList(Array(lines[i...]), linker)
                out.append(html)
                i += consumed
                continue
            }

            // Paragraph: gather until a blank line or a block starter.
            var para: [String] = []
            while i < lines.count, !isBlank(lines[i]) {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if !para.isEmpty, (t.hasPrefix("```") || parseHeading(t) != nil
                    || t.hasPrefix(">") || t.hasPrefix("|")
                    || listItem(lines[i]) != nil
                    || t == "---" || t == "***" || t == "___") {
                    break
                }
                para.append(t)
                i += 1
            }
            if !para.isEmpty {
                out.append("<p>\(inline(para.joined(separator: " "), linker))</p>")
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Outline

    /// One heading of a page, for the reader's "On this page" list.
    public struct OutlineItem: Equatable {
        public var level: Int
        public var text: String
        /// The element id the renderer gave the heading (GitHub-style slug).
        public var id: String
    }

    /// The headings `render` would emit for `body`, in order, with the
    /// same ids. Fenced code and HTML comments are skipped as in render.
    public static func outline(_ body: String) -> [OutlineItem] {
        let lines = stripComments(body.components(separatedBy: "\n"))
        var slugger = HeadingSlugger()
        var items: [OutlineItem] = []
        var inFence = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            if let h = parseHeading(t) {
                items.append(OutlineItem(level: h.level,
                                         text: plainText(h.text),
                                         id: slugger.next(for: h.text)))
            }
        }
        return items
    }

    /// Heading text with inline markup removed.
    static func plainText(_ markdown: String) -> String {
        var t = markdown
        // [[target|label]] / [[target]] and [text](href) / ![alt](src)
        t = t.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, with: "$1",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: #"[`*~]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(^|\s)_+|_+(\s|$)"#, with: "$1$2",
                                   options: .regularExpression)
        // A trailing closing-hash run ("## Title ##").
        t = t.replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// GitHub-style heading ids: lowercase, punctuation dropped, spaces
    /// to hyphens, repeats suffixed -1, -2, ...
    struct HeadingSlugger {
        private var seen: [String: Int] = [:]

        mutating func next(for markdown: String) -> String {
            var base = ""
            for ch in Markdown.plainText(markdown).lowercased() {
                if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { base.append(ch) }
                else if ch == " " { base.append("-") }
            }
            if base.isEmpty { base = "section" }
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return n == 0 ? base : "\(base)-\(n)"
        }
    }

    // MARK: - Blocks

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.hasPrefix(" ") else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return false }
        let cells = t.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        return cells.allSatisfy { "|-: ".contains($0) } && cells.contains("-")
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// (indent, ordered, text) for a list-item line, else nil.
    private static func listItem(_ line: String) -> (indent: Int, ordered: Bool, text: String)? {
        let indent = line.prefix(while: { $0 == " " }).count
        let t = String(line.dropFirst(indent))
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
            return (indent, false, String(t.dropFirst(2)))
        }
        // Ordered: digits + ". "
        var digits = 0
        for ch in t {
            if ch.isNumber { digits += 1 } else { break }
        }
        if digits > 0 {
            let rest = t.dropFirst(digits)
            if rest.hasPrefix(". ") {
                return (indent, true, String(rest.dropFirst(2)))
            }
        }
        return nil
    }

    private static func renderList(_ lines: [String],
                                   _ linker: Linker) -> (html: String, consumed: Int) {
        guard let first = listItem(lines[0]) else { return ("", 0) }
        let baseIndent = first.indent
        let ordered = first.ordered
        var items: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            guard let item = listItem(line) else { break }
            if item.indent < baseIndent { break }
            if item.indent > baseIndent {
                // Nested list belonging to the previous item.
                let (nested, consumed) = renderList(Array(lines[i...]), linker)
                if consumed == 0 { break }
                if !items.isEmpty {
                    items[items.count - 1] += nested
                }
                i += consumed
                continue
            }
            if item.ordered != ordered { break }
            items.append(inline(item.text, linker))
            i += 1
        }
        let tag = ordered ? "ol" : "ul"
        let html = "<\(tag)>" + items.map { "<li>\($0)</li>" }.joined() + "</\(tag)>"
        return (html, i)
    }

    // MARK: - Inline

    private static func inline(_ text: String, _ linker: Linker) -> String {
        // Protect code spans first, restore them at the end.
        var spans: [String] = []
        var s = extractCodeSpans(text, &spans)
        s = escape(s)
        // Autolinks: <https://…> and bare http(s) URLs in prose. They go
        // into placeholders so emphasis rules can't mangle them; URLs that
        // are already a Markdown link's target or label are left alone.
        var autolinks: [String] = []
        func autolink(_ escapedURL: String) -> String {
            let url = unescape(escapedURL)
            let (href, broken) = linker.resolve(url, .markdown)
            let cls = broken ? " class=\"broken\"" : ""
            autolinks.append("<a href=\"\(escape(href))\"\(cls)>\(escapedURL)</a>")
            return "\u{E002}\(autolinks.count - 1)\u{E003}"
        }
        s = replaceRegex(s, pattern: "&lt;(https?://[^\\s]+?)&gt;") { autolink($0[1]) }
        s = replaceRegex(s, pattern: "(?<![\\w=/\\[])(?<!\\]\\()https?://[^\\s<]+") { groups in
            let (url, trailing) = splitTrailing(groups[0])
            return url.count > "https://".count ? autolink(url) + trailing : groups[0]
        }
        // Images: ![alt](src)
        s = replaceRegex(s, pattern: "!\\[([^\\]]*)\\]\\(([^)\\s]+)(?:\\s+\"[^\"]*\")?\\)") { groups in
            "<img alt=\"\(groups[1])\" src=\"\(groups[2])\">"
        }
        // Wikilinks: [[target]] or [[target|label]]. The label defaults
        // to the target as written.
        s = replaceRegex(s, pattern: "\\[\\[([^\\]|\\n]+)(?:\\|([^\\]\\n]+))?\\]\\]") { groups in
            let (href, broken) = linker.resolve(unescape(groups[1]), .wiki)
            let cls = broken ? " class=\"broken\"" : ""
            let label = groups[2].isEmpty
                ? escape(linker.title(unescape(groups[1])) ?? wikiFallbackLabel(unescape(groups[1])))
                : groups[2].trimmingCharacters(in: .whitespaces)
            return "<a href=\"\(escape(href))\"\(cls)>\(label)</a>"
        }
        // Links: [text](href)
        s = replaceRegex(s, pattern: "\\[([^\\]]+)\\]\\(([^)\\s]+)(?:\\s+\"[^\"]*\")?\\)") { groups in
            let (href, broken) = linker.resolve(unescape(groups[2]), .markdown)
            let cls = broken ? " class=\"broken\"" : ""
            return "<a href=\"\(escape(href))\"\(cls)>\(groups[1])</a>"
        }
        // Bold, strikethrough, italic.
        s = replaceRegex(s, pattern: "\\*\\*([^*]+)\\*\\*") { "<strong>\($0[1])</strong>" }
        s = replaceRegex(s, pattern: "~~([^~]+)~~") { "<del>\($0[1])</del>" }
        s = replaceRegex(s, pattern: "(?<![\\w])\\*([^*\\n]+)\\*(?![\\w])") { "<em>\($0[1])</em>" }
        s = replaceRegex(s, pattern: "(?<![\\w])_([^_\\n]+)_(?![\\w])") { "<em>\($0[1])</em>" }
        for (n, link) in autolinks.enumerated() {
            s = s.replacingOccurrences(of: "\u{E002}\(n)\u{E003}", with: link)
        }
        // Restore code spans.
        for (n, span) in spans.enumerated() {
            s = s.replacingOccurrences(of: "\u{E000}\(n)\u{E001}",
                                       with: "<code>\(escape(span))</code>")
        }
        return s
    }

    /// Remove HTML comments (`<!-- … -->`, possibly spanning lines) —
    /// they are notes for tools and agents, not reader content. Comments
    /// inside fenced code blocks or inline code spans are kept as text.
    /// A line that held only a comment becomes blank, which (as in
    /// CommonMark, where a comment is its own block) separates blocks.
    static func stripComments(_ lines: [String]) -> [String] {
        var result: [String] = []
        var inFence = false
        var inComment = false
        for line in lines {
            if !inComment && line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                result.append(line)
                continue
            }
            if inFence { result.append(line); continue }
            guard inComment || line.contains("<!--") else { result.append(line); continue }

            var kept = ""
            var inCode = false
            var rest = Substring(line)
            while !rest.isEmpty {
                if inComment {
                    guard let end = rest.range(of: "-->") else { rest = ""; break }
                    rest = rest[end.upperBound...]
                    inComment = false
                } else if rest.first == "`" {
                    inCode.toggle()
                    kept.append("`")
                    rest = rest.dropFirst()
                } else if !inCode && rest.hasPrefix("<!--") {
                    inComment = true
                    rest = rest.dropFirst(4)
                } else {
                    kept.append(rest.first!)
                    rest = rest.dropFirst()
                }
            }
            result.append(kept.trimmingCharacters(in: .whitespaces).isEmpty ? "" : kept)
        }
        return result
    }

    private struct Linker {
        let resolve: LinkResolver
        let title: WikiTitle
    }

    /// Link text for an unlabelled wikilink whose page is unknown: the
    /// last segment of the target (`projects/evoteam#x` -> `evoteam`).
    private static func wikiFallbackLabel(_ target: String) -> String {
        let path = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
        let last = path.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? path
        let name = last.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? target : name
    }

    private static func extractCodeSpans(_ text: String, _ spans: inout [String]) -> String {
        guard let regex = try? NSRegularExpression(pattern: "`([^`]+)`") else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last,
                                                 length: match.range.location - last))
            spans.append(ns.substring(with: match.range(at: 1)))
            result += "\u{E000}\(spans.count - 1)\u{E001}"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// Apply a regex, replacing each match with the block's result built
    /// from capture groups (index 0 = whole match).
    private static func replaceRegex(_ s: String, pattern: String,
                                     _ build: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last,
                                                 length: match.range.location - last))
            var groups: [String] = []
            for g in 0..<match.numberOfRanges {
                let range = match.range(at: g)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            result += build(groups)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// Split a bare URL match (escaped text) into the URL and trailing
    /// characters that belong to the sentence: an escaped quote or angle
    /// bracket, final punctuation, and a `)` that closes prose rather than
    /// the URL (`(see https://x.org/a_(b))` keeps the URL's own paren).
    static func splitTrailing(_ match: String) -> (url: String, trailing: String) {
        var url = match
        for stop in ["&quot;", "&lt;", "&gt;"] {
            if let r = url.range(of: stop) { url = String(url[..<r.lowerBound]) }
        }
        while let last = url.last {
            if ".,;:!?*_~'".contains(last) {
                url.removeLast()
            } else if last == ")",
                      url.filter({ $0 == "(" }).count < url.filter({ $0 == ")" }).count {
                url.removeLast()
            } else {
                break
            }
        }
        return (url, String(match.dropFirst(url.count)))
    }

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
         .replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
