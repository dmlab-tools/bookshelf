import Foundation

public struct FB2Info: Sendable {
    public var annotation = ""
    public var cover: Data?
    public var year = ""
    public var publisher = ""
}

public enum FB2 {
    /// Pulls annotation, cover image and publication info out of an fb2 file.
    public static func info(from data: Data) -> FB2Info {
        var info = FB2Info()
        let head = data.prefix(upTo: find("</description>", in: data) ?? min(data.count, 256 * 1024))
        let text = decode(head)

        if let a = between(text, "<annotation", "</annotation>") {
            info.annotation = plainText(String(a.drop(while: { $0 != ">" }).dropFirst()))
        }
        if let pub = between(text, "<publish-info", "</publish-info>") {
            info.year = between(pub, "<year>", "</year>").map { plainText(String($0)) } ?? ""
            info.publisher = between(pub, "<publisher>", "</publisher>").map { plainText(String($0)) } ?? ""
        }
        if info.year.isEmpty, let ti = between(text, "<title-info", "</title-info>"),
           let d = between(ti, "<date", "</date>") {
            info.year = plainText(String(d.drop(while: { $0 != ">" }).dropFirst()))
        }

        // <coverpage><image l:href="#cover.jpg"/></coverpage> → <binary id="cover.jpg">base64</binary>
        if let cp = between(text, "<coverpage", "</coverpage>"),
           let hash = cp.range(of: "href=\"#") ?? cp.range(of: "href='#") {
            let rest = cp[hash.upperBound...]
            let id = String(rest.prefix { $0 != "\"" && $0 != "'" })
            info.cover = binary(id: id, in: data)
        }
        return info
    }

    static func binary(id: String, in data: Data) -> Data? {
        for quote in ["\"", "'"] {
            guard let idPos = find("id=\(quote)\(id)\(quote)", in: data) else { continue }
            guard let open = data[idPos...].firstIndex(of: UInt8(ascii: ">")),
                  let close = find("</binary>", in: data, from: open) else { return nil }
            return Data(base64Encoded: data[(open + 1)..<close], options: .ignoreUnknownCharacters)
        }
        return nil
    }

    /// Decodes fb2 text using the encoding from the XML declaration (UTF-8, windows-1251, koi8-r…).
    public static func decode(_ data: Data) -> String {
        let prolog = String(decoding: data.prefix(200), as: UTF8.self)
        if let r = prolog.range(of: "encoding=\"") ?? prolog.range(of: "encoding='") {
            let name = String(prolog[r.upperBound...].prefix { $0 != "\"" && $0 != "'" })
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let s = String(data: data, encoding: enc) { return s }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    static func find(_ s: String, in data: Data, from: Int? = nil) -> Int? {
        let needle = Array(s.utf8)
        return data.withUnsafeBytes { raw -> Int? in
            guard let base = raw.baseAddress else { return nil }
            let start = (from ?? data.startIndex) - data.startIndex
            guard start < raw.count,
                  let r = memmem(base + start, raw.count - start, needle, needle.count) else { return nil }
            return data.startIndex + base.distance(to: UnsafeRawPointer(r))
        }
    }

    static func between<S: StringProtocol>(_ s: S, _ a: String, _ b: String) -> S.SubSequence? {
        guard let r1 = s.range(of: a), let r2 = s.range(of: b, range: r1.upperBound..<s.endIndex) else { return nil }
        return s[r1.upperBound..<r2.lowerBound]
    }

    /// Converts fb2 markup to plain text with paragraph breaks.
    static func plainText(_ xml: String) -> String {
        var s = xml.replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "<empty-line/>", with: "\n")
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        let lines = s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }
}

public enum ExportNaming: String, CaseIterable, Identifiable {
    case authorTitle, authorSeriesTitle, title

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .authorTitle: return String(localized: "Author - Title")
        case .authorSeriesTitle: return String(localized: "Author - Series 01 - Title")
        case .title: return String(localized: "Title")
        }
    }

    public func fileName(for b: Book) -> String {
        let list = b.authors.components(separatedBy: ", ")
        let author = list.count > 2 ? list[0] + String(localized: " et al.") : list.joined(separator: ", ")
        var parts: [String] = []
        switch self {
        case .authorTitle:
            parts = [author, b.title]
        case .authorSeriesTitle:
            var series = b.series
            if !series.isEmpty, b.seriesNo > 0 { series += String(format: " %02d", b.seriesNo) }
            parts = [author, series, b.title]
        case .title:
            parts = [b.title]
        }
        var name = parts.filter { !$0.isEmpty }.joined(separator: " - ")
        if name.isEmpty { name = String(b.libId) }
        name = name.replacingOccurrences(of: "[/\\\\:*?\"<>|\\p{Cc}]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if name.count > 150 { name = String(name.prefix(150)).trimmingCharacters(in: .whitespaces) }
        let ext = (b.fileName as NSString).pathExtension
        return name + "." + (ext.isEmpty ? "fb2" : ext)
    }
}
