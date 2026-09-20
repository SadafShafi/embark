//
//  Scheduler.swift
//  Emberdeck
//
//  SM-2, in the variant Anki ships. Pure functions over a card, so it is easy to
//  unit test and easy to swap for FSRS later.
//

import Foundation

enum Grade: Int, CaseIterable, Identifiable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var isCorrect: Bool { self != .again }
}

struct SchedulerConfig {
    /// Minutes between the steps a new card walks through before graduating.
    var learningSteps: [Double] = [1, 10]
    var relearningSteps: [Double] = [10]
    var graduatingInterval: Double = 1
    var easyInterval: Double = 4
    var startingEase: Int = 2500
    var easyBonus: Double = 1.3
    var hardMultiplier: Double = 1.2
    /// Anki's "new interval" on a lapse: 0% of the old interval.
    var lapseMultiplier: Double = 0.0
    var minimumInterval: Double = 1
    var maximumInterval: Double = 36500

    static let standard = SchedulerConfig()
}

enum Scheduler {

    // MARK: - Answering

    /// Applies a grade to a card, mutating its scheduling fields in place.
    static func answer(_ card: Card, grade: Grade, config: SchedulerConfig = .standard, now: Date = Date()) {
        let todayNum = DayMath.dayNumber(now)
        card.reps += 1
        card.lastReviewed = now

        switch card.state {
        case .new, .learning:
            answerLearning(card, grade: grade, config: config, now: now, today: todayNum)
        case .relearning:
            answerRelearning(card, grade: grade, config: config, now: now, today: todayNum)
        case .review:
            answerReview(card, grade: grade, config: config, now: now, today: todayNum)
        }
    }

    private static func answerLearning(_ card: Card, grade: Grade, config: SchedulerConfig, now: Date, today: Int) {
        let steps = config.learningSteps
        let currentStep = card.state == .new ? 0 : card.step

        switch grade {
        case .again:
            card.state = .learning
            card.step = 0
            card.dueAt = now.addingTimeInterval(steps[0] * 60)

        case .hard:
            // Repeat the step. On the first step Anki averages the first two.
            card.state = .learning
            card.step = currentStep
            let mins = (steps.count > 1 && currentStep == 0)
                ? (steps[0] + steps[1]) / 2
                : steps[min(currentStep, steps.count - 1)]
            card.dueAt = now.addingTimeInterval(mins * 60)

        case .good:
            if currentStep + 1 >= steps.count {
                graduate(card, interval: config.graduatingInterval, config: config, today: today)
            } else {
                card.state = .learning
                card.step = currentStep + 1
                card.dueAt = now.addingTimeInterval(steps[currentStep + 1] * 60)
            }

        case .easy:
            graduate(card, interval: config.easyInterval, config: config, today: today)
        }
    }

    private static func answerRelearning(_ card: Card, grade: Grade, config: SchedulerConfig, now: Date, today: Int) {
        let steps = config.relearningSteps

        switch grade {
        case .again:
            card.step = 0
            card.dueAt = now.addingTimeInterval(steps[0] * 60)

        case .hard:
            card.dueAt = now.addingTimeInterval(steps[min(card.step, steps.count - 1)] * 60)

        case .good:
            if card.step + 1 >= steps.count {
                graduate(card, interval: max(config.minimumInterval, card.interval), config: config, today: today)
            } else {
                card.step += 1
                card.dueAt = now.addingTimeInterval(steps[card.step] * 60)
            }

        case .easy:
            graduate(card, interval: max(config.minimumInterval, card.interval) + 1, config: config, today: today)
        }
    }

    private static func answerReview(_ card: Card, grade: Grade, config: SchedulerConfig, now: Date, today: Int) {
        let overdue = Double(max(0, today - card.dueDay))
        let ease = Double(card.ease) / 1000.0

        switch grade {
        case .again:
            card.lapses += 1
            card.ease = clampEase(card.ease - 200)
            card.interval = max(config.minimumInterval, (card.interval * config.lapseMultiplier).rounded())
            card.state = .relearning
            card.step = 0
            card.dueAt = now.addingTimeInterval(config.relearningSteps[0] * 60)

        case .hard:
            card.ease = clampEase(card.ease - 150)
            let raw = max(card.interval + 1, card.interval * config.hardMultiplier)
            setReviewInterval(card, raw: raw, config: config, today: today)

        case .good:
            // Half the overdue time counts as extra study value, as in Anki.
            let raw = max(card.interval + 1, (card.interval + overdue / 2) * ease)
            setReviewInterval(card, raw: raw, config: config, today: today)

        case .easy:
            card.ease = clampEase(card.ease + 150)
            let raw = max(card.interval + 2, (card.interval + overdue) * ease * config.easyBonus)
            setReviewInterval(card, raw: raw, config: config, today: today)
        }
    }

    private static func graduate(_ card: Card, interval: Double, config: SchedulerConfig, today: Int) {
        card.state = .review
        card.step = 0
        card.interval = fuzz(interval, config: config)
        card.dueDay = today + Int(card.interval)
    }

    private static func setReviewInterval(_ card: Card, raw: Double, config: SchedulerConfig, today: Int) {
        card.interval = fuzz(raw, config: config)
        card.dueDay = today + Int(card.interval)
    }

    private static func clampEase(_ e: Int) -> Int { min(5000, max(1300, e)) }

    /// Anki spreads intervals a little so cards reviewed together don't stay
    /// clumped together forever.
    private static func fuzz(_ days: Double, config: SchedulerConfig) -> Double {
        let capped = min(days, config.maximumInterval)
        if capped < 2.5 { return max(1, capped.rounded()) }
        let ratio: Double = capped < 7 ? 0.25 : (capped < 30 ? 0.15 : 0.05)
        let spread = max(1.0, (capped * ratio).rounded())
        let offset = Double(Int.random(in: -Int(spread)...Int(spread)))
        return min(max(1, (capped + offset).rounded()), config.maximumInterval)
    }

    // MARK: - Button previews

    /// What each button would schedule, for the hints under the grade buttons.
    static func preview(_ card: Card, config: SchedulerConfig = .standard, today: Int = DayMath.today) -> [Grade: String] {
        var out: [Grade: String] = [:]

        switch card.state {
        case .new, .learning:
            let steps = config.learningSteps
            let i = card.state == .new ? 0 : card.step
            out[.again] = formatMinutes(steps[0])
            out[.hard] = formatMinutes(steps.count > 1 && i == 0 ? (steps[0] + steps[1]) / 2 : steps[min(i, steps.count - 1)])
            out[.good] = (i + 1 >= steps.count)
                ? formatDays(config.graduatingInterval)
                : formatMinutes(steps[i + 1])
            out[.easy] = formatDays(config.easyInterval)

        case .relearning:
            let steps = config.relearningSteps
            out[.again] = formatMinutes(steps[0])
            out[.hard] = formatMinutes(steps[min(card.step, steps.count - 1)])
            out[.good] = (card.step + 1 >= steps.count)
                ? formatDays(max(config.minimumInterval, card.interval))
                : formatMinutes(steps[card.step + 1])
            out[.easy] = formatDays(max(config.minimumInterval, card.interval) + 1)

        case .review:
            let overdue = Double(max(0, today - card.dueDay))
            let ease = Double(card.ease) / 1000.0
            out[.again] = formatMinutes(config.relearningSteps[0])
            out[.hard] = formatDays(max(card.interval + 1, card.interval * config.hardMultiplier))
            out[.good] = formatDays(max(card.interval + 1, (card.interval + overdue / 2) * ease))
            out[.easy] = formatDays(max(card.interval + 2, (card.interval + overdue) * ease * config.easyBonus))
        }
        return out
    }

    static func formatMinutes(_ m: Double) -> String {
        if m < 60 { return "\(Int(m.rounded()))m" }
        let h = m / 60
        return h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h)
    }

    static func formatDays(_ d: Double) -> String {
        if d < 1 { return "1d" }
        if d < 30 { return "\(Int(d.rounded()))d" }
        if d < 365 { return String(format: "%.1fmo", d / 30.4) }
        return String(format: "%.1fy", d / 365)
    }
}
