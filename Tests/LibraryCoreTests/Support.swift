import Compression
import Foundation
@testable import LibraryCore

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("lc-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func fb2(_ body: String, encoding: String = "UTF-8", binary: String = "") -> String {
    """
    <?xml version="1.0" encoding="\(encoding)"?>
    <FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><book-title>Книга</book-title>
    <annotation><p>Первый абзац &amp; ещё.</p><p>Второй</p></annotation><coverpage><image l:href="#c.jpg"/></coverpage>
    </title-info><publish-info><publisher>Изд</publisher><year>2001</year></publish-info></description>
    <body><section>\(body)</section></body>\(binary)</FictionBook>
    """
}

/// One `.inp` line in the default field order.
func inpLine(author: String, title: String, series: String = "", serno: String = "", file: String,
             size: Int = 1000, lang: String = "ru", genre: String = "sf", del: String = "0") -> String {
    [author, genre, title, series, serno, file, String(size), file, del, "fb2", "2020-01-01", lang, "0", ""]
        .joined(separator: "\u{4}")
}

/// A library folder: an `.inpx` listing `index` (archive name → `.inp` lines) and the zip archives in `archives`
/// (archive name → file name → contents). Archives left out of `archives` are listed but missing on disk.
func makeLibrary(index: [String: [String]], archives: [String: [String: Data]], structure: String? = nil) throws -> URL {
    let dir = tempDir()
    var inpx = ZipWriter()
    inpx.add(name: "collection.info", data: Data("Test library\r\n".utf8))
    if let structure { inpx.add(name: "structure.info", data: Data(structure.utf8)) }
    for (archive, lines) in index.sorted(by: { $0.key < $1.key }) {
        inpx.add(name: Inpx.inpName(forArchive: archive), data: Data(lines.map { $0 + "\r\n" }.joined().utf8))
    }
    try inpx.finish().write(to: dir.appendingPathComponent("test.inpx"))
    for (archive, files) in archives {
        var zip = ZipWriter()
        for (name, data) in files.sorted(by: { $0.key < $1.key }) { zip.add(name: name, data: data) }
        try zip.finish().write(to: dir.appendingPathComponent(archive))
    }
    return dir
}

// MARK: - A minimal zip writer for test fixtures

extension Data {
    mutating func put16(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func put32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
}

struct ZipWriter {
    private var body = Data()
    private var central = Data()
    private var count = 0

    /// Adds a file, deflated unless that doesn't make it smaller.
    mutating func add(name: String, data: Data) {
        let nameData = Data(name.utf8)
        let crc = crc32(data)
        var method: UInt16 = 8
        var payload = deflate(data)
        if payload == nil || payload!.count >= data.count { method = 0; payload = data }
        let offset = UInt32(body.count)
        let (dosTime, dosDate): (UInt16, UInt16) = (0, 0x5021)

        var h = Data()
        h.put32(0x04034b50); h.put16(20); h.put16(0x0800); h.put16(method)
        h.put16(dosTime); h.put16(dosDate); h.put32(crc)
        h.put32(UInt32(payload!.count)); h.put32(UInt32(data.count))
        h.put16(UInt16(nameData.count)); h.put16(0)
        body.append(h); body.append(nameData); body.append(payload!)

        var c = Data()
        c.put32(0x02014b50); c.put16(20); c.put16(20); c.put16(0x0800); c.put16(method)
        c.put16(dosTime); c.put16(dosDate); c.put32(crc)
        c.put32(UInt32(payload!.count)); c.put32(UInt32(data.count))
        c.put16(UInt16(nameData.count)); c.put16(0); c.put16(0); c.put16(0); c.put16(0)
        c.put32(0); c.put32(offset)
        central.append(c); central.append(nameData)
        count += 1
    }

    func finish() -> Data {
        var out = body
        out.append(central)
        out.put32(0x06054b50); out.put16(0); out.put16(0)
        out.put16(UInt16(count)); out.put16(UInt16(count))
        out.put32(UInt32(central.count)); out.put32(UInt32(body.count)); out.put16(0)
        return out
    }

    private func deflate(_ data: Data) -> Data? {
        if data.isEmpty { return Data() }
        let cap = data.count + data.count / 10 + 1024
        var out = Data(count: cap)
        let n = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        out.count = n
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = Self.crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}
