//
//  TodayView.swift
//  Emberdeck
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \Deck.created) private var decks: [Deck]

    let startSession: ([Deck], String) -> Void

    private var dueDecks: [Deck] {
        decks.filter { model.counts(for: $0).total > 0 }
    }
    private var totalDue: Int { model.counts(for: decks).total }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StreakHeader()

                    Panel {
                        HStack(spacing: 18) {
                            GoalRing(progress: model.goalProgress,
                                     value: model.profile.todayStat.xp,
                                     target: model.settings.dailyGoal,
                                     met: model.goalMetToday)
                            VStack(alignment: .leading, spacing: 6) {
                                Eyebrow(model.goalMetToday ? "Goal met" : "Today's goal")
                                Text(headline)
                                    .font(.edDisplay(20))
                                    .foregroundStyle(Color.edInk)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(subhead)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.edMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    Button {
                        model.haptic(.medium)
                        startSession(dueDecks, "All decks")
                    } label: {
                        Text(totalDue > 0 ? "Study \(totalDue) card\(totalDue == 1 ? "" : "s")" : "All caught up today")
                    }
                    .buttonStyle(ChunkyButtonStyle(background: totalDue > 0 ? .edEmber : .edSurface3,
                                                   foreground: totalDue > 0 ? .white : .edMuted))
                    .disabled(totalDue == 0)

                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow("Your decks")
                        if decks.isEmpty {
                            Text("No decks yet. Open Decks to import an Anki file.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.edMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 26)
                        } else {
                            ForEach(sortedDecks) { deck in
                                Button {
                                    model.haptic()
                                    startSession([deck], deck.name)
                                } label: {
                                    DeckRow(deck: deck, counts: model.counts(for: deck))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.edPaper)
            .navigationTitle("Emberdeck")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var sortedDecks: [Deck] {
        decks.sorted { model.counts(for: $0).total > model.counts(for: $1).total }
    }

    private var headline: String {
        if model.goalMetToday {
            return model.profile.streak > 1 ? "\(model.profile.streak) days in a row" : "Streak started"
        }
        if model.profile.todayStat.xp == 0 {
            return model.profile.streak > 0
                ? "Keep the \(model.profile.streak)-day streak"
                : "Light the first ember"
        }
        return "\(model.settings.dailyGoal - model.profile.todayStat.xp) XP to go"
    }

    private var subhead: String {
        let p = model.profile
        if model.goalMetToday {
            return "Level \(p.level) · extra reviews still count toward the next level."
        }
        if p.freezes > 0 {
            return "Level \(p.level) · \(p.freezes) streak freeze\(p.freezes == 1 ? "" : "s") banked."
        }
        return "Level \(p.level) · \(p.xpToNextLevel) XP to level \(p.level + 1)."
    }
}

// MARK: - Goal ring

struct GoalRing: View {
    let progress: Double
    let value: Int
    let target: Int
    let met: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.edSurface3, lineWidth: 11)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(met ? Color.edMint : Color.edGold,
                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.edNumber(27))
                    .foregroundStyle(Color.edInk)
                Text("of \(target) xp")
                    .font(.system(size: 9.5, weight: .heavy))
                    .kerning(0.8)
                    .foregroundStyle(Color.edMuted)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityLabel("\(value) of \(target) XP today")
    }
}

// MARK: - Deck row

struct DeckRow: View {
    let deck: Deck
    let counts: AppModel.DueCounts

    private var cardCount: Int { deck.activeCards.count }
    private var matureShare: Int {
        guard cardCount > 0 else { return 0 }
        return Int(Double(deck.activeCards.filter(\.isMature).count) / Double(cardCount) * 100)
    }
    /// A rough "how well known is this deck" number, in the spirit of a crown level.
    private var level: Int {
        guard cardCount > 0 else { return 0 }
        let mean = deck.activeCards.reduce(0.0) { $0 + min($1.interval, 180) } / Double(cardCount)
        return min(13, Int(mean.squareRoot()))
    }

    var body: some View {
        HStack(spacing: 13) {
            Text("\(level)")
                .font(.edDisplay(17))
                .foregroundStyle(Color.edViolet)
                .frame(width: 42, height: 42)
                .background(Color.edVioletSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(deck.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.edInk)
                    .lineLimit(1)
                Text("\(cardCount) card\(cardCount == 1 ? "" : "s") · \(matureShare)% mature")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.edMuted)
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                CountPill(value: counts.newCards, tint: .edViolet, soft: .edVioletSoft)
                CountPill(value: counts.learning, tint: .edDanger, soft: .edDangerSoft)
                CountPill(value: counts.review, tint: .edMint, soft: .edMintSoft)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(Color.edSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.edLine, lineWidth: 1)
        )
    }
}
