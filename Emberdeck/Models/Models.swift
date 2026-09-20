//
//  Models.swift
//  Emberdeck
//
//  SwiftData models. Decks and cards live here; the profile and settings are
//  small enough to keep in UserDefaults (see Store/Profile.swift).
//

import Foundation
import SwiftData

/// Where a card sits in the SM-2 lifecycle.
enum CardState: Int, Codable, CaseIterable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3

    var label: String {
        switch self {
        case .new: return "new"
        case .learning: return "learning"
        case .review: return "review"
        case .relearning: return "relearning"
        }
    }
}

@Model
final class Deck {
    var id: UUID = UUID()
    var name: String = ""
    var created: Date = Date()

    /// `nil` falls back to the global setting.
    var newLimitOverride: Int?
    var reviewLimitOverride: Int?

    /// Study each note in both directions, as Anki's "Basic (and reversed card)"
    /// note type does. Reverse cards keep their own scheduling.
    var studyBothDirections: Bool = false

    /// BCP-47 code for text-to-speech on cards that carry no audio, e.g. "de-DE".
    /// `nil` means don't speak.
    var speechLanguage: String?
    /// Which side is in the foreign language and should be spoken: 0 front, 1 back.
    var speechSideRaw: Int = 0

    var speechSide: CardSide {
        get { CardSide(rawValue: speechSideRaw) ?? .front }
        set { speechSideRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card] = []

    init(name: String, created: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.created = created
    }
}

@Model
final class Card {
    var id: UUID = UUID()

    var front: String = ""
    var back: String = ""
    /// Space-separated, the way Anki stores them.
    var tagString: String = ""

    /// Shared by a forward card and its reverse twin.
    var noteKey: UUID = UUID()
    /// A reverse card asks `back` and answers `front`.
    var isReverse: Bool = false

    /// Set aside from study — by the leech rule, or by hand.
    var isSuspended: Bool = false

    var stateRaw: Int = CardState.new.rawValue

    /// Ordering for new cards, and the position they were imported at.
    var position: Int = 0
    /// When a learning or relearning card comes back, to the minute.
    var dueAt: Date = Date()
    /// The day number a review card is due on. See `DayMath`.
    var dueDay: Int = 0

    /// Current interval in days (review cards only).
    var interval: Double = 0
    /// Ease factor in permille, so 2500 is Anki's starting 250%.
    var ease: Int = 2500
    var reps: Int = 0
    var lapses: Int = 0
    /// Index into the learning or relearning step ladder.
    var step: Int = 0
    var lastReviewed: Date?
    var created: Date = Date()

    var deck: Deck?

    var state: CardState {
        get { CardState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    var tags: [String] {
        tagString.split(separator: " ").map(String.init)
    }

    var isLeech: Bool { tags.contains("leech") }

    func addTag(_ tag: String) {
        guard !tags.contains(tag) else { return }
        tagString = (tagString + " " + tag).trimmingCharacters(in: .whitespaces)
    }

    /// A card is "mature" once it survives three weeks between reviews.
    var isMature: Bool { state == .review && interval >= 21 }

    /// What the learner is shown first.
    var promptHTML: String { isReverse ? back : front }
    /// What appears when the card is flipped.
    var answerHTML: String { isReverse ? front : back }

    /// The field in the deck's foreign language, if the deck says which side that is.
    func foreignHTML(for deck: Deck) -> String {
        deck.speechSide == .front ? front : back
    }
    func foreignSideIsPrompt(for deck: Deck) -> Bool {
        (deck.speechSide == .front) != isReverse
    }

    init(front: String, back: String, tags: String = "", position: Int = 0,
         deck: Deck? = nil, noteKey: UUID = UUID(), isReverse: Bool = false) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.tagString = tags
        self.position = position
        self.deck = deck
        self.noteKey = noteKey
        self.isReverse = isReverse
        self.created = Date()
        self.dueAt = Date()
        self.dueDay = 0
    }
}

enum CardSide: Int, Codable, CaseIterable {
    case front = 0
    case back = 1
    var label: String { self == .front ? "Front" : "Back" }
}

/// Languages offered for text-to-speech. iOS ships voices for all of these.
enum SpeechLanguage {
    static let choices: [(code: String, name: String)] = [
        ("de-DE", "German"), ("en-GB", "English (UK)"), ("en-US", "English (US)"),
        ("es-ES", "Spanish (Spain)"), ("es-MX", "Spanish (Mexico)"), ("fr-FR", "French"),
        ("it-IT", "Italian"), ("pt-BR", "Portuguese (Brazil)"), ("nl-NL", "Dutch"),
        ("ru-RU", "Russian"), ("pl-PL", "Polish"), ("tr-TR", "Turkish"), ("ar-SA", "Arabic"),
        ("hi-IN", "Hindi"), ("ja-JP", "Japanese"), ("ko-KR", "Korean"), ("zh-CN", "Chinese (Mandarin)"),
    ]
    static func name(for code: String) -> String {
        choices.first { $0.code == code }?.name ?? code
    }
}

// MARK: - Reverse cards

extension Deck {
    /// Creates the missing reverse twin for every forward card. Idempotent.
    @discardableResult
    func ensureReverseCards() -> Int {
        let existing = Set(cards.filter(\.isReverse).map(\.noteKey))
        var made = 0
        // Same position as the forward card, so both directions of a note are
        // introduced around the same time; the queue keeps them apart.
        for card in cards where !card.isReverse && !existing.contains(card.noteKey) {
            let twin = Card(front: card.front, back: card.back, tags: card.tagString,
                            position: card.position, deck: self, noteKey: card.noteKey, isReverse: true)
            cards.append(twin)
            made += 1
        }
        return made
    }

    /// Cards that take part in study right now: not suspended, and honouring
    /// the direction setting.
    var activeCards: [Card] {
        cards.filter { !$0.isSuspended && (studyBothDirections || !$0.isReverse) }
    }

    var suspendedCards: [Card] { cards.filter(\.isSuspended) }
}

// MARK: - Day arithmetic

/// Emberdeck's day starts at 4am local time, the same convention Anki uses, so a
/// 1am review session still counts toward the previous day's streak.
enum DayMath {
    static let rolloverHour = 4

    static func dayNumber(_ date: Date = Date()) -> Int {
        let shifted = date.addingTimeInterval(TimeInterval(-rolloverHour * 3600))
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: shifted)
        var utc = DateComponents()
        utc.year = comps.year
        utc.month = comps.month
        utc.day = comps.day
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = utcCal.date(from: utc) ?? Date(timeIntervalSince1970: 0)
        return Int(midnight.timeIntervalSince1970 / 86400)
    }

    static var today: Int { dayNumber() }

    static func date(forDay day: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day) * 86400)
    }

    static func shortLabel(forDay day: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date(forDay: day))
    }
}
