//
//  StudySession.swift
//  Emberdeck
//
//  One run through a queue of cards. Learning cards are pushed back into the
//  queue so they come round again inside the same session, the way Anki does it.
//

import Foundation
import Observation
import SwiftData

@Observable
final class StudySession {
    private(set) var queue: [Card]
    private(set) var current: Card?
    private(set) var isRevealed = false

    private(set) var answered = 0
    private(set) var plannedTotal: Int
    private(set) var xpEarned = 0
    private(set) var correctCount = 0
    private(set) var wrongCount = 0
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var lastAward: Int?

    /// The card the leech rule just set aside, for the banner. Cleared on read.
    var leechFlagged: Card?

    /// Everything needed to take back the last answer. One level deep.
    struct Snapshot {
        let card: Card
        let stateRaw: Int, dueAt: Date, dueDay: Int, interval: Double, ease: Int
        let reps: Int, lapses: Int, step: Int, lastReviewed: Date?
        let isSuspended: Bool, tagString: String
        let profile: Profile
        let answered: Int, xpEarned: Int, correctCount: Int, wrongCount: Int
        let combo: Int, bestCombo: Int, plannedTotal: Int
        var requeued: Bool
        let wasNew: Bool
    }
    private(set) var undoSnapshot: Snapshot?
    var canUndo: Bool { undoSnapshot != nil }

    let title: String
    let isCram: Bool
    /// Captured at creation so "study again" still works after the queue drains.
    let deckIDs: Set<UUID>
    let startedAt = Date()
    private var shownAt = Date()
    private var currentWasNew = false

    var isFinished: Bool { current == nil && queue.isEmpty }
    var progress: Double {
        plannedTotal > 0 ? min(1, Double(answered) / Double(plannedTotal)) : 0
    }
    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }
    var accuracy: Double {
        let total = correctCount + wrongCount
        return total > 0 ? Double(correctCount) / Double(total) : 0
    }

    init(cards: [Card], title: String, isCram: Bool = false) {
        self.queue = cards
        self.title = title
        self.isCram = isCram
        self.deckIDs = Set(cards.compactMap { $0.deck?.id })
        self.plannedTotal = cards.count
        advance()
    }

    // MARK: - Flow

    func reveal() {
        guard current != nil else { return }
        isRevealed = true
    }

    func answer(_ grade: Grade, model: AppModel, context: ModelContext) {
        guard let card = current, isRevealed else { return }

        let seconds = min(120, Date().timeIntervalSince(shownAt))
        let deckID = card.deck?.id ?? UUID()
        let wasReview = card.state == .review

        var snapshot = Snapshot(
            card: card, stateRaw: card.stateRaw, dueAt: card.dueAt, dueDay: card.dueDay,
            interval: card.interval, ease: card.ease, reps: card.reps, lapses: card.lapses,
            step: card.step, lastReviewed: card.lastReviewed,
            isSuspended: card.isSuspended, tagString: card.tagString,
            profile: model.profile,
            answered: answered, xpEarned: xpEarned, correctCount: correctCount, wrongCount: wrongCount,
            combo: combo, bestCombo: bestCombo, plannedTotal: plannedTotal,
            requeued: false, wasNew: currentWasNew)

        if grade.isCorrect {
            correctCount += 1
            combo += 1
            bestCombo = max(bestCombo, combo)
        } else {
            wrongCount += 1
            combo = 0
        }

        if !isCram {
            Scheduler.answer(card, grade: grade)
            applyLeechRule(to: card, lapsedNow: wasReview && grade == .again, threshold: model.settings.leechThreshold)
        }
        let gained = model.award(grade: grade, seconds: seconds, deckID: deckID,
                                 wasNew: currentWasNew && !isCram, combo: combo)
        lastAward = gained
        xpEarned += gained
        answered += 1
        try? context.save()

        // A card still in a learning ladder comes back before the session ends,
        // unless the leech rule just set it aside.
        if !isCram, !card.isSuspended, card.state == .learning || card.state == .relearning {
            let soon = card.dueAt.timeIntervalSinceNow < 300
            let insertAt = min(queue.count, soon ? 3 : 10)
            queue.insert(card, at: insertAt)
            plannedTotal = max(plannedTotal, answered + queue.count)
            snapshot.requeued = true
        }
        undoSnapshot = snapshot

        advance()
    }

    /// Anki's rule: at the threshold, and every half-threshold after it, a
    /// lapsing card is tagged "leech" and suspended so it stops eating sessions.
    private func applyLeechRule(to card: Card, lapsedNow: Bool, threshold: Int) {
        guard lapsedNow, threshold > 0, card.lapses >= threshold else { return }
        let every = max(1, threshold / 2)
        guard (card.lapses - threshold) % every == 0 else { return }
        card.addTag("leech")
        card.isSuspended = true
        leechFlagged = card
    }

    /// Takes back the last answer: the card's scheduling, the XP and streak
    /// bookkeeping, and the session counters all go back to how they were.
    /// The card is shown again with its answer visible so it can be regraded.
    func undo(model: AppModel, context: ModelContext) {
        guard let s = undoSnapshot else { return }

        if s.requeued, let i = queue.firstIndex(where: { $0 === s.card }) {
            queue.remove(at: i)
        }
        if let showing = current { queue.insert(showing, at: 0) }

        let card = s.card
        card.stateRaw = s.stateRaw
        card.dueAt = s.dueAt
        card.dueDay = s.dueDay
        card.interval = s.interval
        card.ease = s.ease
        card.reps = s.reps
        card.lapses = s.lapses
        card.step = s.step
        card.lastReviewed = s.lastReviewed
        card.isSuspended = s.isSuspended
        card.tagString = s.tagString

        model.profile = s.profile
        answered = s.answered
        xpEarned = s.xpEarned
        correctCount = s.correctCount
        wrongCount = s.wrongCount
        combo = s.combo
        bestCombo = s.bestCombo
        plannedTotal = s.plannedTotal
        lastAward = nil
        leechFlagged = nil

        current = card
        currentWasNew = s.wasNew
        isRevealed = true
        shownAt = Date()
        undoSnapshot = nil
        try? context.save()
    }

    /// Ends the session early; scheduling already applied stays applied.
    func stop() {
        queue.removeAll()
        current = nil
    }

    // MARK: - Internals

    private func advance() {
        isRevealed = false

        // Drop anything deleted out from under us.
        queue.removeAll { $0.isDeleted }

        guard !queue.isEmpty else { current = nil; return }

        var index = 0
        let head = queue[0]
        // If the front card is a learning card that isn't ripe yet, prefer
        // something that is rather than making the user wait.
        if head.state == .learning || head.state == .relearning,
           head.dueAt.timeIntervalSinceNow > 30 {
            if let ready = queue.firstIndex(where: { card in
                switch card.state {
                case .learning, .relearning: return card.dueAt.timeIntervalSinceNow <= 30
                default: return true
                }
            }) {
                index = ready
            }
        }

        let card = queue.remove(at: index)
        currentWasNew = card.state == .new
        current = card
        shownAt = Date()
    }
}
