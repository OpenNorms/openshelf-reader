import Foundation

/// A deliberately small, tolerant YAML subset parser.
///
/// OpenShelf `kb.yaml` manifests and page frontmatter use a narrow slice
/// of YAML: scalar mappings, nested mappings by indentation, block and
/// inline sequences, quoted scalars, and `>` / `|` block scalars. This
/// parser covers that slice and degrades gracefully — anything it does
/// not understand is preserved as a scalar string rather than failing.
/// It is NOT a general YAML implementation; the OpenShelf spec's
/// manifests are the target corpus (spec 1.4 through 1.7, including
/// `layout:` blocks and `x-*` extension blocks, which parse as ordinary
/// nested maps).
public enum YAMLValue: Equatable {
    case scalar(String)
    case list([YAMLValue])
    case map([YAMLPair])

    public var scalarValue: String? {
        if case .scalar(let s) = self { return s }
        return nil
    }

    public var listValue: [YAMLValue]? {
        if case .list(let l) = self { return l }
        return nil
    }

    /// Look up a key in a map value.
    public func value(forKey key: String) -> YAMLValue? {
        if case .map(let pairs) = self {
            return pairs.first(where: { $0.key == key })?.value
        }
        return nil
    }

    /// Convenience: scalar for a key, if present.
    public func string(forKey key: String) -> String? {
        value(forKey: key)?.scalarValue
    }

    /// Convenience: a list of scalars for a key (accepts a lone scalar too).
    public func stringList(forKey key: String) -> [String] {
        guard let v = value(forKey: key) else { return [] }
        switch v {
        case .scalar(let s): return s.isEmpty ? [] : [s]
        case .list(let items): return items.compactMap { $0.scalarValue }
        case .map: return []
        }
    }
}

public struct YAMLPair: Equatable {
    public let key: String
    public let value: YAMLValue
    public init(key: String, value: YAMLValue) {
        self.key = key
        self.value = value
    }
}

public enum YAMLSubset {

    /// Parse a YAML document (a top-level mapping in all OpenShelf uses)
    /// into ordered key/value pairs.
    public static func parse(_ text: String) -> [YAMLPair] {
        let lines = logicalLines(text)
        var idx = 0
        let value = parseBlock(lines, &idx, indent: 0)
        if case .map(let pairs) = value { return pairs }
        return []
    }

    /// Parse frontmatter-style text; same grammar as `parse`.
    public static func parseMap(_ text: String) -> [String: YAMLValue] {
        var out: [String: YAMLValue] = [:]
        for pair in parse(text) { out[pair.key] = pair.value }
        return out
    }

    // MARK: - Line preparation

    private struct Line {
        let indent: Int
        let text: String  // content after indent, right-trimmed
    }

    private static func logicalLines(_ text: String) -> [Line] {
        var out: [Line] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed == "---" || trimmed == "..." { continue }
            let indent = line.prefix(while: { $0 == " " }).count
            out.append(Line(indent: indent, text: trimmed))
        }
        return out
    }

    // MARK: - Block parsing

    private static func parseBlock(_ lines: [Line], _ idx: inout Int, indent: Int) -> YAMLValue {
        guard idx < lines.count else { return .scalar("") }
        if lines[idx].text.hasPrefix("- ") || lines[idx].text == "-" {
            return parseList(lines, &idx, indent: indent)
        }
        return parseMapBlock(lines, &idx, indent: indent)
    }

    private static func parseList(_ lines: [Line], _ idx: inout Int, indent: Int) -> YAMLValue {
        var items: [YAMLValue] = []
        while idx < lines.count {
            let line = lines[idx]
            guard line.indent == indent, line.text.hasPrefix("-") else { break }
            let rest = line.text == "-" ? "" : String(line.text.dropFirst(2))
            if rest.isEmpty {
                idx += 1
                if idx < lines.count, lines[idx].indent > indent {
                    items.append(parseBlock(lines, &idx, indent: lines[idx].indent))
                } else {
                    items.append(.scalar(""))
                }
            } else if isKeyValue(rest) {
                // "- key: value" opens a map whose remaining keys sit at
                // indent + 2. Rewrite the current line as a map line and
                // parse a map block starting there.
                let savedIndent = line.indent
                var virtual = lines
                virtual[idx] = Line(indent: savedIndent + 2, text: rest)
                var j = idx
                let map = parseMapBlock(virtual, &j, indent: savedIndent + 2,
                                        stopIndent: indent)
                items.append(map)
                idx = j
            } else {
                items.append(.scalar(unquote(rest)))
                idx += 1
            }
        }
        return .list(items)
    }

    private static func parseMapBlock(_ lines: [Line], _ idx: inout Int,
                                      indent: Int, stopIndent: Int = -1) -> YAMLValue {
        var pairs: [YAMLPair] = []
        while idx < lines.count {
            let line = lines[idx]
            if line.indent < indent || line.indent <= stopIndent { break }
            if line.indent > indent { break }  // stray deeper line; stop
            guard let (key, rest) = splitKeyValue(line.text) else { break }
            idx += 1
            if rest == ">" || rest == "|" || rest == ">-" || rest == "|-" {
                // Block scalar: gather deeper lines.
                var parts: [String] = []
                let baseIndent = idx < lines.count ? lines[idx].indent : indent + 1
                while idx < lines.count, lines[idx].indent >= baseIndent {
                    parts.append(lines[idx].text)
                    idx += 1
                }
                let joined = rest.hasPrefix(">")
                    ? parts.joined(separator: " ")
                    : parts.joined(separator: "\n")
                pairs.append(YAMLPair(key: key, value: .scalar(joined)))
            } else if rest.isEmpty {
                if idx < lines.count, lines[idx].indent > indent {
                    let nested = parseBlock(lines, &idx, indent: lines[idx].indent)
                    pairs.append(YAMLPair(key: key, value: nested))
                } else if idx < lines.count, lines[idx].indent == indent,
                          lines[idx].text.hasPrefix("-") {
                    // A block sequence at the SAME indent as its key is
                    // legal YAML ("key:\n- a\n- b").
                    let nested = parseList(lines, &idx, indent: indent)
                    pairs.append(YAMLPair(key: key, value: nested))
                } else {
                    pairs.append(YAMLPair(key: key, value: .scalar("")))
                }
            } else if rest.hasPrefix("[") {
                pairs.append(YAMLPair(key: key, value: .list(parseInlineList(rest))))
            } else {
                pairs.append(YAMLPair(key: key, value: .scalar(unquote(rest))))
            }
        }
        return .map(pairs)
    }

    // MARK: - Scalars

    private static func isKeyValue(_ s: String) -> Bool {
        splitKeyValue(s) != nil
    }

    /// Split "key: value" / "key:" — the colon must be followed by a
    /// space or end-of-line (so URLs and times are not split).
    private static func splitKeyValue(_ s: String) -> (String, String)? {
        var searchStart = s.startIndex
        // Skip a quoted key.
        if s.hasPrefix("\"") || s.hasPrefix("'") {
            let quote = s.first!
            var i = s.index(after: s.startIndex)
            while i < s.endIndex, s[i] != quote { i = s.index(after: i) }
            guard i < s.endIndex else { return nil }
            searchStart = s.index(after: i)
        }
        var i = searchStart
        while i < s.endIndex {
            if s[i] == ":" {
                let after = s.index(after: i)
                if after == s.endIndex || s[after] == " " {
                    let key = unquote(String(s[s.startIndex..<i])
                        .trimmingCharacters(in: .whitespaces))
                    let rest = after == s.endIndex
                        ? ""
                        : String(s[s.index(after: after)...])
                            .trimmingCharacters(in: .whitespaces)
                    return key.isEmpty ? nil : (key, rest)
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func parseInlineList(_ s: String) -> [YAMLValue] {
        var inner = s.trimmingCharacters(in: .whitespaces)
        if inner.hasPrefix("[") { inner.removeFirst() }
        if inner.hasSuffix("]") { inner.removeLast() }
        inner = inner.trimmingCharacters(in: .whitespaces)
        if inner.isEmpty { return [] }
        // Split on commas outside quotes.
        var parts: [String] = []
        var current = ""
        var quote: Character? = nil
        for ch in inner {
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                current.append(ch)
            } else if ch == "," {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespaces))
        }
        return parts.map { .scalar(unquote($0)) }
    }

    private static func unquote(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, v.hasPrefix("\""), v.hasSuffix("\"") {
            v = String(v.dropFirst().dropLast())
            return v.replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if v.count >= 2, v.hasPrefix("'"), v.hasSuffix("'") {
            v = String(v.dropFirst().dropLast())
            return v.replacingOccurrences(of: "''", with: "'")
        }
        // Strip a trailing " # comment" from bare scalars.
        if let range = v.range(of: " #") {
            v = String(v[v.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        }
        return v
    }
}
