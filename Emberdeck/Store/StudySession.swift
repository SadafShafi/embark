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
        }
        let gained = model.award(grade: grade, seconds: seconds, deckID: deckID,
                                 wasNew: currentWasNew && !isCram, combo: combo)
        lastAward = gained
        xpEarned += gained
        answered += 1
        try? context.save()

        // A card still in a learning ladder comes back before the session ends.
        if !isCram, card.state == .learning || card.state == .relearning {
            let soon = card.dueAt.timeIntervalSinceNow < 300
            let insertAt = min(queue.count, soon ? 3 : 10)
            queue.insert(card, at: insertAt)
            plannedTotal = max(plannedTotal, answered + queue.count)
        }

        advance()
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
