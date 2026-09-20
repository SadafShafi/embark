//
//  ZipArchive.swift
//  Emberdeck
//
//  A read-only ZIP reader, just enough for .apkg files. No dependencies: stored
//  entries are copied out and deflated ones go through Apple's Compression
//  framework, whose COMPRESSION_ZLIB is raw DEFLATE — exactly what ZIP stores.
//

import Foundation
import Compression

struct ZipEntry {
    let name: String
    let compressionMethod: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

enum ZipError: LocalizedError {
    case notAZip
    case zip64Unsupported
    case unsupportedCompression(UInt16)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .notAZip:
            return "That file isn't a valid archive."
        case .zip64Unsupported:
            return "That archive uses ZIP64. Export it again in smaller pieces."
        case .unsupportedCompression(let m):
            return "The archive uses compression method \(m), which Emberdeck can't read."
        case .corrupt(let what):
            return "The archive looks damaged (\(what))."
        }
    }
}

struct ZipArchive {
    private let data: Data
    let entries: [String: ZipEntry]

    init(data: Data) throws {
        self.data = data
        self.entries = try ZipArchive.readCentralDirectory(data)
    }

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// Pulls one entry out, decompressing if needed.
    func extract(_ name: String) throws -> Data {
        guard let entry = entries[name] else {
            throw ZipError.corrupt("missing entry \(name)")
        }
        return try extract(entry)
    }

    func extract(_ entry: ZipEntry) throws -> Data {
        // The local header repeats the name and extra-field lengths, and they can
        // differ from the central directory's, so read them again here.
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count,
              read32(at: base) == 0x0403_4b50 else {
            throw ZipError.corrupt("bad local header for \(entry.name)")
        }
        let nameLen = Int(read16(at: base + 26))
        let extraLen = Int(read16(at: base + 28))
        let start = base + 30 + nameLen + extraLen
        let end = start + entry.compressedSize
        guard end <= data.count else { throw ZipError.corrupt("entry \(entry.name) runs past the end") }

        let payload = data.subdata(in: start..<end)

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return try ZipArchive.inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }
    }

    // MARK: - Raw DEFLATE

    static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard !input.isEmpty else { return Data() }
        // Trust the declared size, but keep a floor for entries that declare zero.
        let capacity = max(expectedSize, input.count * 4, 1024)
        var output = Data(count: capacity)

        let written: Int = output.withUnsafeMutableBytes { dst -> Int in
            guard let dstPtr = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return input.withUnsafeBytes { src -> Int in
                guard let srcPtr = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstPtr, capacity, srcPtr, input.count, nil, COMPRESSION_ZLIB)
            }
        }

        guard written > 0 else { throw ZipError.corrupt("could not inflate an entry") }
        output.removeSubrange(written..<output.count)
        return output
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ data: Data) throws -> [String: ZipEntry] {
        guard data.count > 22 else { throw ZipError.notAZip }

        // The end-of-central-directory record sits in the last 64KB or so,
        // after a variable-length comment.
        let searchSpan = min(data.count, 65_557)
        var eocd = -1
        var i = data.count - 22
        let floor = data.count - searchSpan
        while i >= floor {
            if read32(data, at: i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZip }

        let entryCount = Int(read16(data, at: eocd + 10))
        let directoryOffset = Int(read32(data, at: eocd + 16))
        let directorySize = Int(read32(data, at: eocd + 12))

        if directoryOffset == 0xFFFF_FFFF || entryCount == 0xFFFF {
            throw ZipError.zip64Unsupported
        }
        guard directoryOffset + directorySize <= data.count else {
            throw ZipError.corrupt("central directory out of bounds")
        }

        var result: [String: ZipEntry] = [:]
        var p = directoryOffset

        for _ in 0..<entryCount {
            guard p + 46 <= data.count, read32(data, at: p) == 0x0201_4b50 else { break }

            let method = read16(data, at: p + 10)
            let compressed = Int(read32(data, at: p + 20))
            let uncompressed = Int(read32(data, at: p + 24))
            let nameLen = Int(read16(data, at: p + 28))
            let extraLen = Int(read16(data, at: p + 30))
            let commentLen = Int(read16(data, at: p + 32))
            let localOffset = Int(read32(data, at: p + 42))

            guard p + 46 + nameLen <= data.count else { break }
            let nameData = data.subdata(in: (p + 46)..<(p + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)

            if !name.hasSuffix("/") {
                result[name] = ZipEntry(name: name,
                                        compressionMethod: method,
                                        compressedSize: compressed,
                                        uncompressedSize: uncompressed,
                                        localHeaderOffset: localOffset)
            }
            p += 46 + nameLen + extraLen + commentLen
        }

        guard !result.isEmpty else { throw ZipError.corrupt("no files inside") }
        return result
    }

    // MARK: - Little-endian reads

    private func read16(at offset: Int) -> UInt16 { ZipArchive.read16(data, at: offset) }
    private func read32(at offset: Int) -> UInt32 { ZipArchive.read32(data, at: offset) }

    private static func read16(_ d: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= d.count, offset >= 0 else { return 0 }
        return UInt16(d[d.startIndex + offset]) | (UInt16(d[d.startIndex + offset + 1]) << 8)
    }

    private static func read32(_ d: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= d.count, offset >= 0 else { return 0 }
        let b = d.startIndex + offset
        return UInt32(d[b]) | (UInt32(d[b + 1]) << 8) | (UInt32(d[b + 2]) << 16) | (UInt32(d[b + 3]) << 24)
    }
}
