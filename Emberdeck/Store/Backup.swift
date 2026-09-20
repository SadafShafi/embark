//
//  Backup.swift
//  Emberdeck
//
//  A portable snapshot of everything: decks, cards with their scheduling, the
//  profile and the settings. Exported and restored as a plain JSON file, so it
//  can live in iCloud Drive or be mailed to yourself.
//

import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupCard: Codable {
    var front: String
    var back: String
    var tags: String
    var noteKey: UUID?
    var isReverse: Bool?
    var isSuspended: Bool?
    var state: Int
    var position: Int
    var dueAt: Date
    var dueDay: Int
    var interval: Double
    var ease: Int
    var reps: Int
    var lapses: Int
    var step: Int
    var lastReviewed: Date?
    var created: Date
}

struct BackupDeck: Codable {
    var name: String
    var created: Date
    var newLimitOverride: Int?
    var reviewLimitOverride: Int?
    var studyBothDirections: Bool?
    var speechLanguage: String?
    var speechSide: Int?
    var cards: [BackupCard]
}

struct BackupPayload: Codable {
    var version: Int = 1
    var exportedAt: Date = Date()
    var profile: Profile
    var settings: Settings
    var decks: [BackupDeck]

    var cardCount: Int { decks.reduce(0) { $0 + $1.cards.count } }
}

enum Backup {

    static func make(decks: [Deck], model: AppModel) -> BackupPayload {
        let snapshots = decks.map { deck in
            BackupDeck(
                name: deck.name,
                created: deck.created,
                newLimitOverride: deck.newLimitOverride,
                reviewLimitOverride: deck.reviewLimitOverride,
                studyBothDirections: deck.studyBothDirections,
                speechLanguage: deck.speechLanguage,
                speechSide: deck.speechSideRaw,
                cards: deck.cards.sorted { $0.position < $1.position }.map { card in
                    BackupCard(front: card.front, back: card.back, tags: card.tagString,
                               noteKey: card.noteKey, isReverse: card.isReverse, isSuspended: card.isSuspended,
                               state: card.stateRaw, position: card.position,
                               dueAt: card.dueAt, dueDay: card.dueDay,
                               interval: card.interval, ease: card.ease,
                               reps: card.reps, lapses: card.lapses, step: card.step,
                               lastReviewed: card.lastReviewed, created: card.created)
                }
            )
        }
        return BackupPayload(profile: model.profile, settings: model.settings, decks: snapshots)
    }

    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupPayload.self, from: data)
    }

    /// Wipes the store and writes the backup in its place.
    static func restore(_ payload: BackupPayload, context: ModelContext, model: AppModel) throws {
        let existing = try context.fetch(FetchDescriptor<Deck>())
        for deck in existing { context.delete(deck) }

        for snapshot in payload.decks {
            let deck = Deck(name: snapshot.name, created: snapshot.created)
            deck.newLimitOverride = snapshot.newLimitOverride
            deck.reviewLimitOverride = snapshot.reviewLimitOverride
            deck.studyBothDirections = snapshot.studyBothDirections ?? false
            deck.speechLanguage = snapshot.speechLanguage
            deck.speechSideRaw = snapshot.speechSide ?? 0
            context.insert(deck)

            for saved in snapshot.cards {
                let card = Card(front: saved.front, back: saved.back,
                                tags: saved.tags, position: saved.position, deck: deck,
                                noteKey: saved.noteKey ?? UUID(), isReverse: saved.isReverse ?? false)
                card.stateRaw = saved.state
                card.isSuspended = saved.isSuspended ?? false
                card.dueAt = saved.dueAt
                card.dueDay = saved.dueDay
                card.interval = saved.interval
                card.ease = saved.ease
                card.reps = saved.reps
                card.lapses = saved.lapses
                card.step = saved.step
                card.lastReviewed = saved.lastReviewed
                card.created = saved.created
                context.insert(card)
            }
        }
        try context.save()

        model.profile = payload.profile
        model.settings = payload.settings
    }

    static func suggestedFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "Emberdeck-\(formatter.string(from: Date())).json"
    }
}

/// Lets `.fileExporter` write the backup straight into Files or iCloud Drive.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
