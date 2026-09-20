//
//  MediaStore.swift
//  Emberdeck
//
//  Images pulled out of .apkg files live on disk under Application Support,
//  referenced from card text by their original Anki filename.
//

import Foundation

enum MediaStore {
    static let directoryName = "EmberdeckMedia"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Anki filenames can contain slashes and other characters that would escape
    /// the media folder, so they are flattened before use.
    static func safeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(safeName(name))
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    @discardableResult
    static func write(_ data: Data, name: String) -> Bool {
        (try? data.write(to: url(for: name), options: .atomic)) != nil
    }

    static func isImage(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"].contains(ext)
    }

    /// Formats AVAudioPlayer can decode. Anki decks also ship .ogg, which iOS
    /// cannot play natively; those files are skipped at import.
    static func isPlayableAudio(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"].contains(ext)
    }

    static func isWanted(_ name: String) -> Bool { isImage(name) || isPlayableAudio(name) }

    static func totalBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, f in
            sum + Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
