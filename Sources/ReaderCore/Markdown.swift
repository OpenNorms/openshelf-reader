import Foundation

/// A markdown -> HTML fragment renderer for the OpenShelf corpus.
///
/// Covers the dialect the fleet actually writes: ATX headings,
/// paragraphs, bold/italic/strikethrough, inline code and fenced code
/// blocks, GFM tables, nested lists, blockquotes, horizontal rules,
/// images, and links. Links are passed through a resolver supplied by
/// the caller, which turns relative `.md` references and `kb://` URLs
/// into reader routes (and flags broken ones). Raw HTML in a page is
/// escaped, not passed through — KBs are agent-maintained markdown,
/// and the reader renders them as documents, not web pages.
public enum Markdown {

    public typealias LinkResolver = (_ rawHref: String) -> (href: String, broken: Bool)

    public static func render(_ body: String,
                              resolveLink: LinkResolver = { ($0, false) }) -> String {
        let lines = body.components(separatedBy: "\n")
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
                let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                out.append("<pre><code\(cls)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed) {
                out.append("<h\(heading.level)>\(inline(heading.text, resolveLink))</h\(heading.level)>")
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
                var html = "<table><thead><tr>"
                for cell in header {
                    html += "<th>\(inline(cell, resolveLink))</th>"
                }
                html += "</tr></thead><tbody>"
                for row in bodyRows {
                    html += "<tr>"
                    for cell in row {
                        html += "<td>\(inline(cell, resolveLink))</td>"
                    }
                    html += "</tr>"
                }
                html += "</tbody></table>"
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
                out.append("<blockquote><p>\(inline(quoted.joined(separator: " "), resolveLink))</p></blockquote>")
                continue
            }

            // List (possibly nested)
            if listItem(line) != nil {
                let (html, consumed) = renderList(Array(lines[i...]), resolveLink)
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
                out.append("<p>\(inline(para.joined(separator: " "), resolveLink))</p>")
            }
        }
        return out.joined(separator: "\n")
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
                                   _ resolveLink: LinkResolver) -> (html: String, consumed: Int) {
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
                let (nested, consumed) = renderList(Array(lines[i...]), resolveLink)
                if consumed == 0 { break }
                if !items.isEmpty {
                    items[items.count - 1] += nested
                }
                i += consumed
                continue
            }
            if item.ordered != ordered { break }
            items.append(inline(item.text, resolveLink))
            i += 1
        }
        let tag = ordered ? "ol" : "ul"
        let html = "<\(tag)>" + items.map { "<li>\($0)</li>" }.joined() + "</\(tag)>"
        return (html, i)
    }

    // MARK: - Inline

    private static func inline(_ text: String, _ resolveLink: LinkResolver) -> String {
        // Protect code spans first, restore them at the end.
        var spans: [String] = []
        var s = extractCodeSpans(text, &spans)
        s = escape(s)
        // Images: ![alt](src)
        s = replaceRegex(s, pattern: "!\\[([^\\]]*)\\]\\(([^)\\s]+)(?:\\s+\"[^\"]*\")?\\)") { groups in
            "<img alt=\"\(groups[1])\" src=\"\(groups[2])\">"
        }
        // Links: [text](href)
        s = replaceRegex(s, pattern: "\\[([^\\]]+)\\]\\(([^)\\s]+)(?:\\s+\"[^\"]*\")?\\)") { groups in
            let (href, broken) = resolveLink(unescape(groups[2]))
            let cls = broken ? " class=\"broken\"" : ""
            return "<a href=\"\(escape(href))\"\(cls)>\(groups[1])</a>"
        }
        // Bold, strikethrough, italic.
        s = replaceRegex(s, pattern: "\\*\\*([^*]+)\\*\\*") { "<strong>\($0[1])</strong>" }
        s = replaceRegex(s, pattern: "~~([^~]+)~~") { "<del>\($0[1])</del>" }
        s = replaceRegex(s, pattern: "(?<![\\w])\\*([^*\\n]+)\\*(?![\\w])") { "<em>\($0[1])</em>" }
        s = replaceRegex(s, pattern: "(?<![\\w])_([^_\\n]+)_(?![\\w])") { "<em>\($0[1])</em>" }
        // Restore code spans.
        for (n, span) in spans.enumerated() {
            s = s.replacingOccurrences(of: "\u{E000}\(n)\u{E001}",
                                       with: "<code>\(escape(span))</code>")
        }
        return s
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
