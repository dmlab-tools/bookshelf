import Foundation

/// INPX index: a zip with one `.inp` file per book archive plus `collection.info`, `version.info`, `structure.info`.
/// Each `.inp` line is a book record with fields separated by 0x04.
public final class Inpx: @unchecked Sendable {
    public static let defaultStructure = ["AUTHOR", "GENRE", "TITLE", "SERIES", "SERNO", "FILE", "SIZE",
                                          "LIBID", "DEL", "EXT", "DATE", "LANG", "LIBRATE", "KEYWORDS"]

    public let url: URL
    public let names: [String]
    private let contents: [String: Data]
    public let fields: [String]
    private let columns: [String: Int]
    /// Positions of the standard fields, resolved once.
    public let col: Columns

    public struct Columns: Sendable {
        public let author, genre, title, series, serno, file, size, libid, del, ext, date, lang, librate: Int?
    }

    public init(url: URL) throws {
        self.url = url
        let zip = try ZipArchive(url: url)
        var names: [String] = []
        var contents: [String: Data] = [:]
        for e in zip.entries {
            names.append(e.name)
            contents[e.name] = try zip.read(e)
        }
        self.names = names
        self.contents = contents

        if let s = contents["structure.info"].flatMap({ Inpx.decode($0) }) {
            let f = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
            fields = f.isEmpty ? Inpx.defaultStructure : f
        } else {
            fields = Inpx.defaultStructure
        }
        var cols: [String: Int] = [:]
        for (i, f) in fields.enumerated() { cols[f] = i }
        columns = cols
        col = Columns(author: cols["AUTHOR"], genre: cols["GENRE"], title: cols["TITLE"], series: cols["SERIES"],
                      serno: cols["SERNO"], file: cols["FILE"], size: cols["SIZE"], libid: cols["LIBID"],
                      del: cols["DEL"], ext: cols["EXT"], date: cols["DATE"], lang: cols["LANG"], librate: cols["LIBRATE"])
    }

    /// Finds the first `.inpx` file in a library folder.
    public static func find(in folder: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension.lowercased() == "inpx" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    public var collectionName: String {
        contents["collection.info"].flatMap { Inpx.decode($0) }?
            .split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: "\u{FEFF}", with: "") } ?? url.deletingPathExtension().lastPathComponent
    }

    public var inpNames: [String] { names.filter { $0.lowercased().hasSuffix(".inp") } }

    public static func archiveName(forInp inp: String) -> String { String(inp.dropLast(4)) + ".zip" }
    public static func inpName(forArchive zip: String) -> String { String(zip.dropLast(4)) + ".inp" }

    public func column(_ name: String) -> Int? { columns[name] }

    public func lines(of inp: String) -> [String] {
        guard let d = contents[inp], let s = Inpx.decode(d) else { return [] }
        // Split on bytes: much faster than Character-based splitting, and "\r\n" is one Character anyway.
        return s.utf8.split(separator: 0x0A).compactMap { l in
            let t = l.last == 0x0D ? l.dropLast() : l
            return t.isEmpty ? nil : String(Substring(t))
        }
    }

    static func decode(_ d: Data) -> String? {
        String(data: d, encoding: .utf8) ?? String(data: d, encoding: .windowsCP1251)
    }
}

/// A parsed `.inp` line.
public struct InpRecord: @unchecked Sendable {
    public let line: String
    let parts: [Substring]
    let inpx: Inpx

    public init(line: String, inpx: Inpx) {
        self.line = line
        self.inpx = inpx
        parts = line.utf8.split(separator: 0x04, omittingEmptySubsequences: false).map { Substring($0) }
    }

    /// Broken lines (e.g. a stray newline inside a title) don't have the FILE column.
    public var isValid: Bool {
        guard let f = inpx.col.file else { return false }
        return parts.count > f && !parts[f].isEmpty
    }

    public func field(_ i: Int?) -> Substring {
        guard let i, i < parts.count else { return "" }
        return parts[i]
    }

    public subscript(_ field: String) -> String {
        guard let i = inpx.column(field), i < parts.count else { return "" }
        return String(parts[i])
    }

    public var fileName: String {
        let ext = field(inpx.col.ext)
        return field(inpx.col.file) + "." + (ext.isEmpty ? "fb2" : ext)
    }

    public var language: String { Book.normalizeLanguage(field(inpx.col.lang)) }

    public var authorsDisplay: String { Book.formatAuthors(field(inpx.col.author)) }
}

public struct Book: Identifiable, Hashable, Sendable {
    public let id: Int
    public let authors: String
    public let title: String
    public let series: String
    public let seriesNo: Int
    public let genres: [String]
    public let lang: String
    public let size: Int64
    public let date: String
    public let deleted: Bool
    public let rating: Int
    public let libId: Int
    public let archive: String
    public let fileName: String
    /// Normalized "authors \u{1} title \u{1} series" for fast substring search.
    public let searchKey: String
    public let authorKeyLength: Int
    public let titleKeyEnd: Int

    public init(id: Int, record r: InpRecord, archive: String) {
        let c = r.inpx.col
        self.id = id
        authors = Book.formatAuthors(r.field(c.author))
        let t = Book.trimmed(r.field(c.title))
        title = t
        series = Book.trimmed(r.field(c.series))
        seriesNo = Int(r.field(c.serno)) ?? 0
        genres = r.field(c.genre).split(separator: ":").map(String.init)
        lang = Book.normalizeLanguage(r.field(c.lang))
        size = Int64(r.field(c.size)) ?? 0
        date = String(r.field(c.date))
        deleted = r.field(c.del) == "1"
        rating = Int(r.field(c.librate)) ?? 0
        libId = Int(r.field(c.libid)) ?? 0
        self.archive = archive
        fileName = r.fileName
        let a = Book.normalize(authors), ti = Book.normalize(t)
        searchKey = a + "\u{1}" + ti + "\u{1}" + Book.normalize(series)
        authorKeyLength = a.utf8.count
        titleKeyEnd = authorKeyLength + 1 + ti.utf8.count
    }

    public static func == (a: Book, b: Book) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    public var genreNames: String { genres.map { Genres.name(for: $0) }.joined(separator: ", ") }
    public var seriesDisplay: String { series.isEmpty ? "" : (seriesNo > 0 ? "\(series) #\(seriesNo)" : series) }

    /// "Last,First,Middle:Last2,First2,:" → "Last First Middle, Last2 First2"
    public static func formatAuthors(_ raw: Substring) -> String {
        raw.split(separator: ":").map { a in
            a.split(separator: ",", omittingEmptySubsequences: true)
                .map { trimmed($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Trims spaces only when there are any; most fields have none and Foundation trimming is slow.
    static func trimmed(_ s: Substring) -> String {
        guard let f = s.utf8.first, let l = s.utf8.last else { return "" }
        if f > 0x20 && l > 0x20 { return String(s) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    public static func normalizeLanguage<S: StringProtocol>(_ raw: S) -> String {
        let l = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let cut = l.firstIndex(where: { $0 == "-" || $0 == "_" }) { return String(l[..<cut]) }
        return l
    }

    /// Lowercase with "ё" folded into "е", for search keys.
    public static func normalize(_ s: String) -> String {
        var bytes = Array(s.lowercased().utf8)
        var i = 0
        while i + 1 < bytes.count {
            if bytes[i] == 0xD1 && bytes[i + 1] == 0x91 { bytes[i] = 0xD0; bytes[i + 1] = 0xB5 }  // ё → е
            i += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
