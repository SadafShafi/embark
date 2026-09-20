//
//  Importers.swift
//  Emberdeck
//
//  Reads Anki .apkg / .colpkg archives and plain delimited exports into a
//  neutral shape the app can insert as decks and cards.
//

import Foundation
import SwiftData

struct ParsedNote {
    var front: String
    var back: String
    var tags: String
}

struct ParsedDeck {
    var name: String
    var notes: [ParsedNote]
}

struct ImportResult {
    var decks: [ParsedDeck]
    var mediaImported: Int
    var totalNotes: Int { decks.reduce(0) { $0 + $1.notes.count } }
}

enum ImportError: LocalizedError {
    case noCollection
    case zstdUnsupported
    case emptyFile
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .noCollection:
            return "There's no Anki collection inside that file."
        case .zstdUnsupported:
            return """
                That deck uses Anki's newer compressed format. Export it again from Anki with \
                "Support older Anki versions" ticked, and it will import fine.
                """
        case .emptyFile:
            return "That file has no cards in it."
        case .unreadable(let why):
            return why
        }
    }
}

// MARK: - .apkg

enum ApkgImporter {

    /// Blocking. Call it off the main actor.
    static func parse(url: URL, mediaBudget: Int = 150_000_000) throws -> ImportResult {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let archive = try ZipArchive(url: url)

        // Newest first: anki21b is zstd-compressed and we cannot read it.
        if archive.contains("collection.anki21b") && !archive.contains("collection.anki21") && !archive.contains("collection.anki2") {
            throw ImportError.zstdUnsupported
        }
        let dbName = ["collection.anki21", "collection.anki2"].first { archive.contains($0) }
        guard let dbName else { throw ImportError.noCollection }

        let dbData = try archive.extract(dbName)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("emberdeck-\(UUID().uuidString).anki2")
        try dbData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let db = try SQLiteDatabase(path: tmp.path)

        let deckNames = readDeckNames(db)
        let noteDeck = readNoteDeckMap(db)

        let noteRows = try db.query("SELECT id, flds, tags FROM notes")
        guard !noteRows.isEmpty else { throw ImportError.emptyFile }

        let fallbackName = url.deletingPathExtension().lastPathComponent
        var grouped: [String: [ParsedNote]] = [:]
        var order: [String] = []

        for row in noteRows where row.count >= 3 {
            guard let noteID = row[0].intValue,
                  let fields = row[1].stringValue else { continue }

            // Anki separates a note's fields with 0x1f.
            let parts = fields.components(separatedBy: "\u{1f}")
            let front = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !front.isEmpty else { continue }

            let back = parts.dropFirst()
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "<br>")

            var deckName = fallbackName
            if let did = noteDeck[noteID], let named = deckNames[did], named != "Default", !named.isEmpty {
                deckName = named
            }

            let tags = (row[2].stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if grouped[deckName] == nil { order.append(deckName) }
            grouped[deckName, default: []].append(ParsedNote(front: front, back: back, tags: tags))
        }

        let mediaCount = importMedia(archive: archive, budget: mediaBudget)

        let decks = order.compactMap { name -> ParsedDeck? in
            guard let notes = grouped[name], !notes.isEmpty else { return nil }
            return ParsedDeck(name: name, notes: notes)
        }
        guard !decks.isEmpty else { throw ImportError.emptyFile }
        return ImportResult(decks: decks, mediaImported: mediaCount)
    }

    // MARK: Deck names across schema versions

    private static func readDeckNames(_ db: SQLiteDatabase) -> [Int64: String] {
        var names: [Int64: String] = [:]

        // Anki schema 18 and later keep decks in their own table, nesting
        // separated by 0x1f instead of "::".
        for row in db.optionalQuery("SELECT id, name FROM decks") where row.count >= 2 {
            if let id = row[0].intValue, let name = row[1].stringValue {
                names[id] = name.replacingOccurrences(of: "\u{1f}", with: "::")
            }
        }
        if !names.isEmpty { return names }

        // Older collections keep a JSON blob on the single `col` row.
        for row in db.optionalQuery("SELECT decks FROM col") where !row.isEmpty {
            guard let json = row[0].stringValue,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (key, value) in object {
                if let id = Int64(key), let dict = value as? [String: Any], let name = dict["name"] as? String {
                    names[id] = name
                }
            }
        }
        return names
    }

    /// A note can own several cards across several decks; the first one wins.
    private static func readNoteDeckMap(_ db: SQLiteDatabase) -> [Int64: Int64] {
        var map: [Int64: Int64] = [:]
        for row in db.optionalQuery("SELECT nid, did FROM cards ORDER BY ord") where row.count >= 2 {
            if let nid = row[0].intValue, let did = row[1].intValue, map[nid] == nil {
                map[nid] = did
            }
        }
        return map
    }

    // MARK: Media

    /// Classic .apkg files carry a JSON map of numbered entries to filenames.
    /// The newer protobuf map is skipped; the text still imports.
    private static func importMedia(archive: ZipArchive, budget: Int) -> Int {
        guard archive.contains("media"),
              let mapData = try? archive.extract("media"),
              let object = try? JSONSerialization.jsonObject(with: mapData) as? [String: String] else {
            return 0
        }

        var written = 0
        var used = 0
        for (entryName, fileName) in object {
            guard MediaStore.isWanted(fileName), archive.contains(entryName) else { continue }
            guard let blob = try? archive.extract(entryName) else { continue }
            guard used + blob.count <= budget else { break }
            if MediaStore.write(blob, name: fileName) {
                used += blob.count
                written += 1
            }
        }
        return written
    }
}

// MARK: - CSV / TSV / Anki text export

enum DelimitedImporter {

    static func parse(text: String, fallbackName: String) throws -> ImportResult {
        var separator: Character?
        var htmlMode = false
        var deckName = fallbackName
        var tagsColumn: Int?
        var bodyLines: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Anki's text exports start with "#key:value" directives.
            if line.hasPrefix("#") {
                let stripped = String(line.dropFirst())
                let pieces = stripped.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2 else { continue }
                let key = pieces[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = pieces[1].trimmingCharacters(in: .whitespaces)

                switch key {
                case "separator":
                    switch value.lowercased() {
                    case "tab": separator = "\t"
                    case "comma": separator = ","
                    case "semicolon": separator = ";"
                    case "pipe": separator = "|"
                    default: separator = value.first
                    }
                case "html":
                    htmlMode = value.lowercased() == "true"
                case "deck":
                    deckName = value.components(separatedBy: "::").last ?? value
                case "tags column":
                    if let n = Int(value) { tagsColumn = n - 1 }
                default:
                    break
                }
                continue
            }
            bodyLines.append(rawLine)
        }

        guard !bodyLines.isEmpty else { throw ImportError.emptyFile }
        let sep = separator ?? sniffSeparator(bodyLines)

        var notes: [ParsedNote] = []
        for line in bodyLines {
            let columns = splitRow(line, separator: sep)
            guard let first = columns.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !first.isEmpty else { continue }

            var tags = ""
            var rest: [String] = []
            for (index, column) in columns.enumerated() where index > 0 {
                let value = column.trimmingCharacters(in: .whitespacesAndNewlines)
                if index == tagsColumn {
                    tags = value
                } else if !value.isEmpty {
                    rest.append(htmlMode ? value : escape(value))
                }
            }
            notes.append(ParsedNote(front: htmlMode ? first : escape(first),
                                    back: rest.joined(separator: "<br>"),
                                    tags: tags))
        }

        guard !notes.isEmpty else { throw ImportError.emptyFile }
        return ImportResult(decks: [ParsedDeck(name: deckName, notes: notes)], mediaImported: 0)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
    }

    private static func sniffSeparator(_ lines: [String]) -> Character {
        let sample = lines.prefix(30).joined(separator: "\n")
        let tabs = sample.filter { $0 == "\t" }.count
        let semis = sample.filter { $0 == ";" }.count
        let commas = sample.filter { $0 == "," }.count
        if tabs >= lines.prefix(30).count { return "\t" }
        return semis > commas ? ";" : ","
    }

    /// Handles quoted fields with doubled quotes, the way Anki and Excel write them.
    static func splitRow(_ line: String, separator: Character) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        var pending: Character?

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { current.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == separator {
                out.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        out.append(current)
        return out
    }
}
