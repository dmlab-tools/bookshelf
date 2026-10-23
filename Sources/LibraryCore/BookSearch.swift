import Foundation

public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all, author, title, series
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .author: return String(localized: "Author")
        case .title: return String(localized: "Title")
        case .series: return String(localized: "Series")
        }
    }
}

public enum BookSearch {
    public static let resultLimit = 5000

    /// Books whose fields contain every word of the query (any order, case and "ё" ignored).
    /// Returns at most `resultLimit` books sorted by author, series, number, title, and whether more were found.
    public static func search(_ books: [Book], query: String, scope: SearchScope, lang: String) -> ([Book], Bool) {
        let tokens = Book.normalize(query).split(whereSeparator: { $0.isWhitespace }).map { Array($0.utf8) }
        if tokens.isEmpty && lang.isEmpty { return ([], false) }

        let chunks = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let size = (books.count + chunks - 1) / chunks
        var partial = [[Book]](repeating: [], count: chunks)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: chunks) { c in
            var out: [Book] = []
            let lo = c * size, hi = min(books.count, lo + size)
            if lo < hi {
                for i in lo..<hi {
                    let b = books[i]
                    if !lang.isEmpty && b.lang != lang { continue }
                    if !tokens.isEmpty && !matches(b, tokens, scope) { continue }
                    out.append(b)
                    if out.count > resultLimit { break }
                }
            }
            lock.lock(); partial[c] = out; lock.unlock()
        }
        var all = partial.flatMap { $0 }
        let more = all.count > resultLimit
        if more { all = Array(all.prefix(resultLimit)) }
        all.sort(by: defaultOrder)
        return (all, more)
    }

    static func matches(_ b: Book, _ tokens: [[UInt8]], _ scope: SearchScope) -> Bool {
        b.searchKey.utf8.withContiguousStorageIfAvailable { key -> Bool in
            let (lo, hi): (Int, Int)
            switch scope {
            case .all: (lo, hi) = (0, key.count)
            case .author: (lo, hi) = (0, b.authorKeyLength)
            case .title: (lo, hi) = (b.authorKeyLength + 1, b.titleKeyEnd)
            case .series: (lo, hi) = (b.titleKeyEnd + 1, key.count)
            }
            guard lo <= hi, let base = key.baseAddress else { return false }
            for t in tokens {
                if t.count > hi - lo || memmem(base + lo, hi - lo, t, t.count) == nil { return false }
            }
            return true
        } ?? false
    }

    public static func defaultOrder(_ a: Book, _ b: Book) -> Bool {
        if a.authors != b.authors { return a.authors.localizedStandardCompare(b.authors) == .orderedAscending }
        if a.series != b.series { return a.series.localizedStandardCompare(b.series) == .orderedAscending }
        if a.seriesNo != b.seriesNo { return a.seriesNo < b.seriesNo }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
