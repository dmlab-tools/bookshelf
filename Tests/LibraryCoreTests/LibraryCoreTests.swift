import Foundation
import Testing
@testable import LibraryCore

@Suite struct ZipTests {
    @Test func readsStoredAndDeflatedEntries() throws {
        var w = ZipWriter()
        var originals: [String: Data] = [:]
        for i in 0..<50 {
            let d = Data(String(repeating: "Строка книги \(i) ", count: 200 + i * 37).utf8)
            originals["\(i).fb2"] = d
            w.add(name: "\(i).fb2", data: d)
        }
        originals["tiny.fb2"] = Data("x".utf8)
        w.add(name: "tiny.fb2", data: originals["tiny.fb2"]!)
        originals["empty.fb2"] = Data()
        w.add(name: "empty.fb2", data: Data())
        let url = tempDir().appendingPathComponent("a.zip")
        try w.finish().write(to: url)

        let zip = try ZipArchive(url: url)
        #expect(zip.entries.count == 52)
        for (n, d) in originals { #expect(try zip.read(named: n) == d) }
        #expect(zip.entry(named: "missing.fb2") == nil)
        #expect(throws: ZipError.self) { try zip.read(named: "missing.fb2") }
    }

    /// Archives made by the system zip tool, as real libraries are.
    @Test func readsSystemZip() throws {
        let dir = tempDir()
        let text = Data(String(repeating: "Lorem ipsum dolor sit amet. ", count: 5000).utf8)
        try text.write(to: dir.appendingPathComponent("1.fb2"))
        try Data().write(to: dir.appendingPathComponent("2.fb2"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-q", "books.zip", "1.fb2", "2.fb2"]
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)

        let zip = try ZipArchive(url: dir.appendingPathComponent("books.zip"))
        #expect(zip.entries.map(\.name).sorted() == ["1.fb2", "2.fb2"])
        #expect(try zip.read(named: "1.fb2") == text)
        #expect(try zip.read(named: "2.fb2").isEmpty)
    }

    @Test func rejectsNonZip() throws {
        let url = tempDir().appendingPathComponent("x.zip")
        try Data(repeating: 7, count: 100).write(to: url)
        #expect(throws: ZipError.self) { try ZipArchive(url: url) }
    }
}

@Suite struct FB2Tests {
    @Test func extractsInfo() {
        let cover = Data([1, 2, 3, 4, 5]).base64EncodedString()
        let book = fb2("<p>x</p>", binary: "<binary id=\"c.jpg\" content-type=\"image/jpeg\">\(cover)</binary>")
        let info = FB2.info(from: Data(book.utf8))
        #expect(info.annotation == "Первый абзац & ещё.\nВторой")
        #expect(info.year == "2001")
        #expect(info.publisher == "Изд")
        #expect(info.cover == Data([1, 2, 3, 4, 5]))
    }

    @Test func decodesCP1251() {
        let info = FB2.info(from: fb2("<p>x</p>", encoding: "windows-1251").data(using: .windowsCP1251)!)
        #expect(info.annotation.hasPrefix("Первый абзац"))
    }
}

@Suite struct NamingTests {
    @Test func normalization() {
        #expect(Book.formatAuthors("Толкин,Джон,Рональд Руэл:Иванов,,:") == "Толкин Джон Рональд Руэл, Иванов")
        #expect(Book.normalizeLanguage("RU") == "ru")
        #expect(Book.normalizeLanguage("ru-RU") == "ru")
        #expect(Book.normalize("Ёжик в Тумане") == "ежик в тумане")
    }

    @Test func exportFileNames() throws {
        let lib = try Library(folder: try makeLibrary(
            index: ["a.zip": [inpLine(author: "Стругацкий,Аркадий,:Стругацкий,Борис,:", title: "Пикник на обочине",
                                      series: "Мир Полудня", serno: "3", file: "1"),
                              inpLine(author: "A,,:B,,:C,,:", title: "What/if: “why”?", file: "2")]],
            archives: ["a.zip": ["1.fb2": Data("x".utf8), "2.fb2": Data("y".utf8)]]))
        let b = try #require(lib.books.first { $0.fileName == "1.fb2" })
        #expect(ExportNaming.authorTitle.fileName(for: b) == "Стругацкий Аркадий, Стругацкий Борис - Пикник на обочине.fb2")
        #expect(ExportNaming.authorSeriesTitle.fileName(for: b)
                == "Стругацкий Аркадий, Стругацкий Борис - Мир Полудня 03 - Пикник на обочине.fb2")
        #expect(ExportNaming.title.fileName(for: b) == "Пикник на обочине.fb2")
        let odd = try #require(lib.books.first { $0.fileName == "2.fb2" })
        let name = ExportNaming.authorTitle.fileName(for: odd)
        #expect(name.hasSuffix(" - What_if_ “why”_.fb2"))
        #expect(!name.contains("/") && !name.contains(":"))
    }
}

@Suite struct LibraryTests {
    static let index = [
        "fb2-000001-000003.zip": [
            inpLine(author: "Толкин,Джон,:", title: "Хоббит", series: "Средиземье", serno: "1", file: "1"),
            inpLine(author: "Tolkien,John,:", title: "The Hobbit", file: "2", lang: "en"),
            inpLine(author: "Козлов,Сергей,:", title: "Ёжик в тумане", file: "3", del: "1"),
            "a broken line without the other fields",
            inpLine(author: "Nobody,,:", title: "Not in the archive", file: "4"),
        ],
        "fb2-000005-000006.zip": [
            inpLine(author: "Шевченко,Тарас,:", title: "Кобзар", file: "5", lang: "uk"),
            inpLine(author: "Толкин,Джон,:", title: "Сильмариллион", series: "Средиземье", serno: "2", file: "6"),
        ],
        "fb2-000007-000007.zip": [inpLine(author: "Missing,,:", title: "Archive not on disk", file: "7")],
    ]
    static let archives = [
        "fb2-000001-000003.zip": ["1.fb2": Data(fb2("<p>Хоббит</p>").utf8), "2.fb2": Data("2".utf8), "3.fb2": Data("3".utf8)],
        "fb2-000005-000006.zip": ["5.fb2": Data("5".utf8), "6.fb2": Data("6".utf8)],
    ]

    @Test func loadsOnlyBooksPresentOnDisk() throws {
        let lib = try Library(folder: try makeLibrary(index: Self.index, archives: Self.archives))
        #expect(lib.name == "Test library")
        #expect(lib.books.map(\.fileName).sorted() == ["1.fb2", "2.fb2", "3.fb2", "5.fb2", "6.fb2"])
        #expect(lib.languages.first?.code == "ru" && lib.languages.first?.count == 3)
        #expect(Set(lib.languages.map(\.code)) == ["ru", "en", "uk"])

        let hobbit = try #require(lib.books.first { $0.fileName == "1.fb2" })
        #expect(hobbit.authors == "Толкин Джон")
        #expect(hobbit.seriesDisplay == "Средиземье #1")
        #expect(FB2.info(from: try lib.data(for: hobbit)).publisher == "Изд")
        #expect(lib.books.first { $0.fileName == "3.fb2" }?.deleted == true)
    }

    @Test func search() throws {
        let books = try Library(folder: try makeLibrary(index: Self.index, archives: Self.archives)).books
        func files(_ q: String, _ scope: SearchScope = .all, lang: String = "") -> [String] {
            BookSearch.search(books, query: q, scope: scope, lang: lang).0.map(\.fileName)
        }
        #expect(files("хоббит толкин") == ["1.fb2"])
        #expect(files("ТОЛКИН ХОББИТ") == ["1.fb2"])
        #expect(files("толкин") == ["1.fb2", "6.fb2"])  // sorted by series number
        #expect(files("хоббит", .author).isEmpty)
        #expect(files("средиземье", .series) == ["1.fb2", "6.fb2"])
        #expect(files("средиземье", .title).isEmpty)
        #expect(files("ежик") == ["3.fb2"])
        #expect(files("ЁЖИК") == ["3.fb2"])
        #expect(files("hobbit", lang: "en") == ["2.fb2"])
        #expect(files("", lang: "uk") == ["5.fb2"])
        #expect(files("").isEmpty)
    }

    @Test func customFieldOrder() throws {
        let line = ["2", "Название", "Автор,,:", "be"].joined(separator: "\u{4}")
        let lib = try Library(folder: try makeLibrary(index: ["a.zip": [line]], archives: ["a.zip": ["2.fb2": Data()]],
                                                      structure: "FILE;TITLE;AUTHOR;LANG"))
        let b = try #require(lib.books.first)
        #expect((b.fileName, b.title, b.authors, b.lang) == ("2.fb2", "Название", "Автор", "be"))
    }

    @Test func failsWithoutIndexOrArchives() throws {
        #expect(throws: LibraryError.self) { try Library(folder: tempDir()) }
        let empty = try makeLibrary(index: ["a.zip": [inpLine(author: "A", title: "B", file: "1")]], archives: [:])
        #expect(throws: LibraryError.self) { try Library(folder: empty) }
    }
}

/// Read-only checks against a real library. Run with `BOOKSHELF_TEST_LIBRARY=/path/to/library swift test`.
@Suite struct RealLibraryTests {
    static let folder = ProcessInfo.processInfo.environment["BOOKSHELF_TEST_LIBRARY"].map { URL(fileURLWithPath: $0) }
    static var available: Bool { folder.flatMap { Inpx.find(in: $0) } != nil }

    @Test(.enabled(if: available)) func loadSearchRead() throws {
        let start = Date()
        let lib = try Library(folder: Self.folder!)
        print("loaded \(lib.books.count) books in \(Date().timeIntervalSince(start))s, languages: \(lib.languages.prefix(5))")
        let b = try #require(lib.books.first { $0.title.count > 3 && !$0.authors.isEmpty })

        let author = String(b.authors.split(separator: " ")[0])
        let t = Date()
        let (found, _) = BookSearch.search(lib.books, query: "\(author) \(b.title)", scope: .all, lang: "")
        print("search: \(found.count) in \(Date().timeIntervalSince(t))s")
        #expect(found.contains(b))
        let (byAuthor, _) = BookSearch.search(lib.books, query: author, scope: .author, lang: "")
        #expect(byAuthor.allSatisfy { Book.normalize($0.authors).contains(Book.normalize(author)) })

        let data = try lib.data(for: b)
        #expect(data.count == Int(b.size))
    }

    @Test(.enabled(if: available)) func someBookHasCoverAndAnnotation() throws {
        let lib = try Library(folder: Self.folder!)
        let step = max(1, lib.books.count / 300)
        let infos = stride(from: 0, to: lib.books.count, by: step).compactMap { try? FB2.info(from: lib.data(for: lib.books[$0])) }
        #expect(infos.contains { !$0.annotation.isEmpty && ($0.cover?.count ?? 0) > 1000 })
    }
}
