import Foundation

/// A library folder opened for browsing: the books listed in the .inpx that are actually present in the archives.
public final class Library: @unchecked Sendable {
    public let folder: URL
    public let name: String
    public let books: [Book]
    /// Languages with their book counts, most common first.
    public let languages: [(code: String, count: Int)]
    let archives: Set<String>

    public init(folder: URL, progress: ((String) -> Void)? = nil) throws {
        self.folder = folder
        guard let inpxURL = Inpx.find(in: folder) else {
            throw LibraryError(String(localized: "The folder has no .inpx file (the library catalog)."))
        }
        let inpx = try Inpx(url: inpxURL)
        let inps = inpx.inpNames.filter {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(Inpx.archiveName(forInp: $0)).path)
        }
        if inps.isEmpty { throw LibraryError(String(localized: "There are no book archives next to \(inpxURL.lastPathComponent).")) }
        progress?(String(localized: "Reading \(inps.count) archives…"))

        let lock = NSLock()
        var archives = Set<String>()
        var parts = [[Book]](repeating: [], count: inps.count)
        var errors: [String] = []
        DispatchQueue.concurrentPerform(iterations: inps.count) { i in
            let name = Inpx.archiveName(forInp: inps[i])
            do {
                let zip = try ZipArchive(url: folder.appendingPathComponent(name))
                var list: [Book] = []
                for (n, line) in inpx.lines(of: inps[i]).enumerated() {
                    let r = InpRecord(line: line, inpx: inpx)
                    guard r.isValid, zip.index[r.fileName] != nil else { continue }
                    list.append(Book(id: i << 20 | n, record: r, archive: name))
                }
                lock.lock(); archives.insert(name); parts[i] = list; lock.unlock()
            } catch {
                lock.lock(); errors.append("\(name): \(error)"); lock.unlock()
            }
        }
        if archives.isEmpty { throw LibraryError(errors.joined(separator: "\n")) }
        books = parts.flatMap { $0 }
        var counts: [String: Int] = [:]
        for b in books { counts[b.lang, default: 0] += 1 }
        languages = counts.map { (code: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
        name = inpx.collectionName
        self.archives = archives
    }

    /// The book's fb2 file contents. The archive is opened anew each time rather than kept open: another tool
    /// may have replaced it since, and an open old copy would hold its disk space until the app quits.
    public func data(for book: Book) throws -> Data {
        guard archives.contains(book.archive) else { throw LibraryError(String(localized: "Archive \(book.archive) not found")) }
        return try autoreleasepool { try ZipArchive(url: folder.appendingPathComponent(book.archive)).read(named: book.fileName) }
    }
}

/// An error shown to the user as is, in the app's language.
public struct LibraryError: Error, CustomStringConvertible {
    public let description: String
    init(_ message: String) { description = message }
}
