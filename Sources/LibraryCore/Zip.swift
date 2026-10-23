import Foundation
import Compression

public enum ZipError: Error, CustomStringConvertible {
    case notZip(String)
    case corrupt(String)
    case unsupported(String)
    case io(String)

    public var description: String {
        switch self {
        case .notZip(let s): return "not a zip archive: \(s)"
        case .corrupt(let s): return "corrupt archive: \(s)"
        case .unsupported(let s): return "unsupported: \(s)"
        case .io(let s): return "I/O error: \(s)"
        }
    }
}

// MARK: - Little-endian helpers

@inline(__always) func rd16(_ d: Data, _ o: Int) -> UInt16 {
    d.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt16.self)) }
}
@inline(__always) func rd32(_ d: Data, _ o: Int) -> UInt32 {
    d.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt32.self)) }
}
@inline(__always) func rd64(_ d: Data, _ o: Int) -> UInt64 {
    d.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: o, as: UInt64.self)) }
}

private let sigLocal: UInt32 = 0x04034b50
private let sigCentral: UInt32 = 0x02014b50
private let sigEnd: UInt32 = 0x06054b50
private let sigEnd64: UInt32 = 0x06064b50
private let sigEnd64Locator: UInt32 = 0x07064b50

// MARK: - Reader

public struct ZipEntry: Sendable {
    public let name: String
    public let method: UInt16
    public let flags: UInt16
    public let crc32: UInt32
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let localHeaderOffset: UInt64
    /// MS-DOS modification date and time as stored in the archive.
    public var dosDate: UInt16 = 0
    public var dosTime: UInt16 = 0
}

/// Read-only zip archive backed by a memory-mapped file. Supports ZIP64, stored and deflated entries.
public final class ZipArchive: @unchecked Sendable {
    public let url: URL
    public let entries: [ZipEntry]
    /// Entry position by file name. Built eagerly so the archive can be read from several threads.
    public let index: [String: Int]
    let data: Data

    public init(url: URL) throws {
        self.url = url
        do {
            data = try Data(contentsOf: url, options: .alwaysMapped)
        } catch {
            throw ZipError.io("\(url.path): \(error.localizedDescription)")
        }
        let size = data.count
        guard size >= 22 else { throw ZipError.notZip(url.lastPathComponent) }

        var eocd = -1
        var p = size - 22
        let lowest = max(0, size - 22 - 65_535)
        while p >= lowest {
            if rd32(data, p) == sigEnd { eocd = p; break }
            p -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip(url.lastPathComponent) }

        var count = UInt64(rd16(data, eocd + 10))
        var cdSize = UInt64(rd32(data, eocd + 12))
        var cdOffset = UInt64(rd32(data, eocd + 16))
        if eocd >= 20, rd32(data, eocd - 20) == sigEnd64Locator {
            let z = Int(rd64(data, eocd - 20 + 8))
            guard z + 56 <= size, rd32(data, z) == sigEnd64 else { throw ZipError.corrupt("ZIP64 EOCD") }
            count = rd64(data, z + 32)
            cdSize = rd64(data, z + 40)
            cdOffset = rd64(data, z + 48)
        }
        guard cdOffset + cdSize <= UInt64(size) else { throw ZipError.corrupt("central directory outside the file") }

        var list: [ZipEntry] = []
        list.reserveCapacity(Int(count))
        var q = Int(cdOffset)
        let cdEnd = Int(cdOffset + cdSize)
        while q + 46 <= cdEnd, rd32(data, q) == sigCentral {
            let flags = rd16(data, q + 8)
            let method = rd16(data, q + 10)
            let crc = rd32(data, q + 16)
            var csize = UInt64(rd32(data, q + 20))
            var usize = UInt64(rd32(data, q + 24))
            let nlen = Int(rd16(data, q + 28))
            let elen = Int(rd16(data, q + 30))
            let clen = Int(rd16(data, q + 32))
            var offset = UInt64(rd32(data, q + 42))
            let recLen = 46 + nlen + elen + clen
            guard q + recLen <= cdEnd else { throw ZipError.corrupt("central directory record") }
            let nameData = data.subdata(in: (q + 46)..<(q + 46 + nlen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)

            if usize == 0xFFFF_FFFF || csize == 0xFFFF_FFFF || offset == 0xFFFF_FFFF {
                var e = q + 46 + nlen
                let eEnd = e + elen
                while e + 4 <= eEnd {
                    let id = rd16(data, e), len = Int(rd16(data, e + 2))
                    if id == 0x0001 {
                        var f = e + 4
                        if usize == 0xFFFF_FFFF { usize = rd64(data, f); f += 8 }
                        if csize == 0xFFFF_FFFF { csize = rd64(data, f); f += 8 }
                        if offset == 0xFFFF_FFFF { offset = rd64(data, f); f += 8 }
                        break
                    }
                    e += 4 + len
                }
            }
            var entry = ZipEntry(name: name, method: method, flags: flags, crc32: crc,
                                 compressedSize: csize, uncompressedSize: usize,
                                 localHeaderOffset: offset)
            entry.dosTime = rd16(data, q + 12)
            entry.dosDate = rd16(data, q + 14)
            list.append(entry)
            q += recLen
        }
        guard list.count == Int(count) else {
            throw ZipError.corrupt("expected \(count) files, found \(list.count)")
        }

        entries = list
        var d = [String: Int](minimumCapacity: list.count)
        for (i, e) in list.enumerated() { d[e.name] = i }
        index = d
    }

    public func entry(named name: String) -> ZipEntry? {
        index[name].map { entries[$0] }
    }

    static func dataStart(of e: ZipEntry, in buf: Data, at o: Int) throws -> Int {
        guard o >= 0, o + 30 <= buf.count, rd32(buf, o) == sigLocal else {
            throw ZipError.corrupt("local header of \(e.name)")
        }
        return o + 30 + Int(rd16(buf, o + 26)) + Int(rd16(buf, o + 28))
    }

    /// Decompressed contents of an entry.
    public func read(_ e: ZipEntry) throws -> Data {
        try Self.decode(e, in: data, at: Int(e.localHeaderOffset))
    }

    static func decode(_ e: ZipEntry, in buf: Data, at headerOffset: Int) throws -> Data {
        let start = try dataStart(of: e, in: buf, at: headerOffset)
        let csize = Int(e.compressedSize), usize = Int(e.uncompressedSize)
        guard start + csize <= buf.count else { throw ZipError.corrupt("data of \(e.name)") }
        if e.flags & 1 != 0 { throw ZipError.unsupported("encrypted file \(e.name)") }
        switch e.method {
        case 0:
            return buf.subdata(in: start..<(start + csize))
        case 8:
            if usize == 0 { return Data() }
            var out = Data(count: usize)
            let n = out.withUnsafeMutableBytes { dst in
                buf.withUnsafeBytes { src in
                    compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, usize,
                                              src.bindMemory(to: UInt8.self).baseAddress! + start, csize,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            guard n == usize else { throw ZipError.corrupt("inflating \(e.name): \(n) of \(usize) bytes") }
            return out
        default:
            throw ZipError.unsupported("compression method \(e.method) of \(e.name)")
        }
    }

    public func read(named name: String) throws -> Data {
        guard let e = entry(named: name) else { throw ZipError.corrupt("no \(name) in \(url.lastPathComponent)") }
        return try read(e)
    }
}
