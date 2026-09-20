//
//  Profile.swift
//  Emberdeck
//
//  The streak layer: XP, daily goal, streak freezes, levels and achievements.
//  Small and Codable, so it lives in UserDefaults rather than the SwiftData store.
//

import Foundation

struct DayStat: Codable, Equatable {
    var reviews: Int = 0
    var correct: Int = 0
    var xp: Int = 0
    var seconds: Double = 0
    /// New cards introduced today, keyed by deck UUID string, to honour the daily cap.
    var newByDeck: [String: Int] = [:]
}

struct Profile: Codable, Equatable {
    var xp: Int = 0
    var streak: Int = 0
    var bestStreak: Int = 0
    var freezes: Int = 0

    /// Day numbers (see `DayMath`).
    var lastGoalDay: Int?
    var lastSeenDay: Int?

    var totalReviews: Int = 0
    var totalCorrect: Int = 0
    var totalSeconds: Double = 0

    var history: [Int: DayStat] = [:]
    var badges: Set<String> = []

    var level: Int { Int(Double(xp / 60).squareRoot()) + 1 }
    func xpRequired(forLevel level: Int) -> Int { Int(pow(Double(level - 1), 2) * 60) }
    var xpToNextLevel: Int { max(0, xpRequired(forLevel: level + 1) - xp) }

    var retention: Double {
        totalReviews > 0 ? Double(totalCorrect) / Double(totalReviews) : 0
    }

    func stat(for day: Int) -> DayStat { history[day] ?? DayStat() }
    var todayStat: DayStat { stat(for: DayMath.today) }
}

struct Settings: Codable, Equatable {
    var dailyGoal: Int = 50
    var newCardsPerDay: Int = 20
    var maxReviewsPerDay: Int = 200
    var reminderHour: Int = 19
    var reminderMinute: Int = 0
    var remindersEnabled: Bool = true
    var appearance: Appearance = .system
    var hapticsEnabled: Bool = true

    /// Duolingo-style chimes on answers and milestones.
    var soundEffects: Bool = true
    /// Play a card's own audio (from `[sound:…]`) when it is shown or flipped.
    var autoPlayCardAudio: Bool = true
    /// Speak cards that have no audio, using the deck's language.
    var speakCards: Bool = true

    /// A card lapsed this many times is a leech: tagged and suspended, then
    /// again every half-threshold after that. 0 turns the rule off.
    var leechThreshold: Int = 8
    /// Show four options instead of a blank for a card's very first review.
    var multipleChoiceForNew: Bool = true

    enum Appearance: String, Codable, CaseIterable {
        case system, light, dark
        var title: String { rawValue.capitalized }
    }

    struct GoalChoice: Identifiable, Hashable {
        let label: String
        let xp: Int
        var id: Int { xp }
    }

    static let goalChoices: [GoalChoice] = [
        GoalChoice(label: "Casual", xp: 20),
        GoalChoice(label: "Regular", xp: 50),
        GoalChoice(label: "Serious", xp: 100),
        GoalChoice(label: "Intense", xp: 200),
    ]
}

// MARK: - Achievements

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let test: (Profile) -> Bool

    static let all: [Achievement] = [
        Achievement(id: "s3", title: "Three in a row", detail: "A 3-day streak") { $0.bestStreak >= 3 },
        Achievement(id: "s7", title: "Week on fire", detail: "A 7-day streak") { $0.bestStreak >= 7 },
        Achievement(id: "s30", title: "Month of embers", detail: "A 30-day streak") { $0.bestStreak >= 30 },
        Achievement(id: "s100", title: "Century", detail: "A 100-day streak") { $0.bestStreak >= 100 },
        Achievement(id: "r100", title: "Hundred cards", detail: "100 reviews answered") { $0.totalReviews >= 100 },
        Achievement(id: "r1000", title: "Thousand cards", detail: "1,000 reviews answered") { $0.totalReviews >= 1000 },
        Achievement(id: "xp1k", title: "1,000 XP", detail: "Earned 1,000 XP") { $0.xp >= 1000 },
        Achievement(id: "xp10k", title: "10,000 XP", detail: "Earned 10,000 XP") { $0.xp >= 10000 },
        Achievement(id: "acc", title: "Sharp recall", detail: "90% retention over 100+ reviews") {
            $0.totalReviews >= 100 && $0.retention >= 0.9
        },
        Achievement(id: "combo25", title: "Twenty-five straight", detail: "A 25-card combo in one session") { $0.badges.contains("combo25") },
    ]
}

// MARK: - XP rules

enum XPRules {
    static let correct = 3
    static let again = 1
    static let comboEvery = 5
    static let comboBonus = 5
    /// One freeze earned every seventh streak day, capped so it stays a safety
    /// net rather than a way to stop studying.
    static let freezeEveryDays = 7
    static let maxFreezes = 2
}
