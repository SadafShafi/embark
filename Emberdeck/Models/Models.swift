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

    /// A card is "mature" once it survives three weeks between reviews.
    var isMature: Bool { state == .review && interval >= 21 }

    init(front: String, back: String, tags: String = "", position: Int = 0, deck: Deck? = nil) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.tagString = tags
        self.position = position
        self.deck = deck
        self.created = Date()
        self.dueAt = Date()
        self.dueDay = 0
    }
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
