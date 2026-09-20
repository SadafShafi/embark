//
//  AppModel.swift
//  Emberdeck
//
//  Owns the profile and settings, awards XP, keeps the streak honest, and builds
//  the study queue. Views observe this; SwiftData holds the cards themselves.
//

import Foundation
import Observation
import SwiftData
import UIKit

@Observable
final class AppModel {

    // MARK: Persisted state

    var profile: Profile {
        didSet { if profile != oldValue { persistProfile() } }
    }
    var settings: Settings {
        didSet {
            if settings != oldValue {
                persistSettings()
                Task { await NotificationManager.shared.reschedule(using: self) }
            }
        }
    }

    /// Set when a session just pushed the streak up, so the summary can celebrate.
    var streakJustAdvanced = false
    /// Achievements unlocked during the current session.
    var freshBadges: [Achievement] = []
    /// A message to surface once, e.g. "a streak freeze saved your streak".
    var pendingNotice: String?

    private let defaults = UserDefaults.standard
    private static let profileKey = "emberdeck.profile.v1"
    private static let settingsKey = "emberdeck.settings.v1"

    init() {
        profile = AppModel.load(Profile.self, key: AppModel.profileKey) ?? Profile()
        settings = AppModel.load(Settings.self, key: AppModel.settingsKey) ?? Settings()
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func persistProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }

    /// Forces both blobs out to disk, for scene-phase changes.
    func persistAll() {
        persistProfile()
        persistSettings()
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: - Streak bookkeeping

    /// Call on launch and whenever the app returns to the foreground. Decides
    /// whether the streak survived the gap since the last day the goal was met.
    func reconcileStreak() {
        let today = DayMath.today
        defer { profile.lastSeenDay = today }
        guard let last = profile.lastGoalDay else { return }

        let gap = today - last
        guard gap > 1, profile.streak > 0 else { return }

        let missed = gap - 1
        if profile.freezes >= missed {
            profile.freezes -= missed
            profile.lastGoalDay = today - 1
            pendingNotice = missed == 1
                ? "A streak freeze saved your streak."
                : "\(missed) streak freezes used to bridge the gap."
        } else {
            profile.streak = 0
            profile.lastGoalDay = nil
            pendingNotice = "Your streak reset. Start a new one today."
        }
    }

    var goalMetToday: Bool { profile.todayStat.xp >= settings.dailyGoal }
    var goalProgress: Double {
        min(1, Double(profile.todayStat.xp) / Double(max(1, settings.dailyGoal)))
    }

    // MARK: - Awarding

    func award(grade: Grade, seconds: Double, deckID: UUID, wasNew: Bool, combo: Int) -> Int {
        let today = DayMath.today
        var stat = profile.stat(for: today)

        var gained = grade.isCorrect ? XPRules.correct : XPRules.again
        if grade.isCorrect, combo > 0, combo % XPRules.comboEvery == 0 {
            gained += XPRules.comboBonus
        }

        stat.reviews += 1
        stat.xp += gained
        stat.seconds += seconds
        if grade.isCorrect { stat.correct += 1 }
        if wasNew { stat.newByDeck[deckID.uuidString, default: 0] += 1 }
        profile.history[today] = stat

        profile.xp += gained
        profile.totalReviews += 1
        profile.totalSeconds += seconds
        if grade.isCorrect { profile.totalCorrect += 1 }

        if stat.xp >= settings.dailyGoal, profile.lastGoalDay != today {
            profile.streak = (profile.lastGoalDay == today - 1) ? profile.streak + 1 : 1
            profile.lastGoalDay = today
            profile.bestStreak = max(profile.bestStreak, profile.streak)
            if profile.streak % XPRules.freezeEveryDays == 0, profile.freezes < XPRules.maxFreezes {
                profile.freezes += 1
            }
            streakJustAdvanced = true
        }

        if combo >= 25 { profile.badges.insert("combo25") }
        checkAchievements()
        return gained
    }

    private func checkAchievements() {
        for a in Achievement.all where !profile.badges.contains(a.id) && a.test(profile) {
            profile.badges.insert(a.id)
            freshBadges.append(a)
        }
    }

    // MARK: - Limits

    func newCardsRemaining(for deck: Deck) -> Int {
        let cap = deck.newLimitOverride ?? settings.newCardsPerDay
        let used = profile.todayStat.newByDeck[deck.id.uuidString] ?? 0
        return max(0, cap - used)
    }

    func reviewsAllowed(for deck: Deck) -> Int {
        deck.reviewLimitOverride ?? settings.maxReviewsPerDay
    }

    // MARK: - Counting what's waiting

    struct DueCounts {
        var newCards = 0
        var learning = 0
        var review = 0
        var total: Int { newCards + learning + review }
    }

    func counts(for deck: Deck) -> DueCounts {
        let today = DayMath.today
        var c = DueCounts()
        var freshAvailable = 0

        for card in deck.cards {
            switch card.state {
            case .new: freshAvailable += 1
            case .learning, .relearning: c.learning += 1
            case .review: if card.dueDay <= today { c.review += 1 }
            }
        }
        c.newCards = min(freshAvailable, newCardsRemaining(for: deck))
        c.review = min(c.review, reviewsAllowed(for: deck))
        return c
    }

    func counts(for decks: [Deck]) -> DueCounts {
        decks.reduce(into: DueCounts()) { acc, deck in
            let c = counts(for: deck)
            acc.newCards += c.newCards
            acc.learning += c.learning
            acc.review += c.review
        }
    }

    // MARK: - Queue building

    /// Learning cards first, then reviews with the day's new cards spread evenly
    /// through them rather than bunched at the front.
    func buildQueue(for decks: [Deck]) -> [Card] {
        let today = DayMath.today
        let now = Date()

        var learning: [Card] = []
        var reviews: [Card] = []
        var fresh: [Card] = []

        for deck in decks {
            var newBudget = newCardsRemaining(for: deck)
            var reviewBudget = reviewsAllowed(for: deck)
            let sorted = deck.cards.sorted { lhs, rhs in
                if lhs.state == .new && rhs.state == .new { return lhs.position < rhs.position }
                return lhs.dueAt < rhs.dueAt
            }
            for card in sorted {
                switch card.state {
                case .learning, .relearning:
                    learning.append(card)
                case .review:
                    if card.dueDay <= today, reviewBudget > 0 {
                        reviews.append(card)
                        reviewBudget -= 1
                    }
                case .new:
                    if newBudget > 0 {
                        fresh.append(card)
                        newBudget -= 1
                    }
                }
            }
        }

        learning.sort { $0.dueAt < $1.dueAt }
        reviews.shuffle()

        var queue = learning.filter { $0.dueAt <= now }
        var interleaved: [Card] = []
        let gap = fresh.isEmpty ? 0 : max(1, Int((Double(reviews.count) / Double(fresh.count + 1)).rounded(.up)))
        var freshIndex = 0

        for (i, card) in reviews.enumerated() {
            interleaved.append(card)
            if gap > 0, (i + 1) % gap == 0, freshIndex < fresh.count {
                interleaved.append(fresh[freshIndex])
                freshIndex += 1
            }
        }
        while freshIndex < fresh.count {
            interleaved.append(fresh[freshIndex])
            freshIndex += 1
        }

        queue.append(contentsOf: interleaved)
        queue.append(contentsOf: learning.filter { $0.dueAt > now })
        return queue
    }

    // MARK: - Badge on the app icon

    func refreshAppBadge(decks: [Deck]) {
        let due = counts(for: decks).total
        UNUserNotificationCenterBadge.set(due)
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard settings.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
