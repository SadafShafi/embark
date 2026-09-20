//
//  StudyView.swift
//  Emberdeck
//

import SwiftUI
import SwiftData

struct SessionSummary: Identifiable {
    let id = UUID()
    let title: String
    let deckIDs: Set<UUID>
    let answered: Int
    let xp: Int
    let accuracy: Double
    let bestCombo: Int
    let elapsed: TimeInterval
    let streakAdvanced: Bool
    let streak: Int
    let freezes: Int
    let goalMet: Bool
    let xpRemaining: Int
    let unlocked: [String]
}

struct StudyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @State var session: StudySession
    let onFinish: (SessionSummary) -> Void

    @State private var floatingXP: Int?
    @State private var floatingID = UUID()
    @State private var didFinish = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if let card = session.current {
                ScrollView {
                    cardFace(card)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .id(card.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity))
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                Spacer()
                ProgressView().controlSize(.large)
                Spacer()
            }

            Spacer(minLength: 0)
            footer
        }
        .background(Color.edPaper)
        .overlay(alignment: .center) {
            if let gained = floatingXP {
                Text("+\(gained)")
                    .font(.edNumber(28))
                    .foregroundStyle(Color.edGold)
                    .id(floatingID)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.7).combined(with: .opacity),
                        removal: .offset(y: -70).combined(with: .opacity)))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: session.isFinished) { _, finished in
            if finished { finish() }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                session.stop()
                finish()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.edInk2)
                    .frame(width: 36, height: 36)
                    .background(Color.edSurface2, in: Circle())
            }
            .accessibilityLabel("End session")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.edSurface3)
                    Capsule()
                        .fill(Color.edMint)
                        .frame(width: max(6, geo.size.width * session.progress))
                        .animation(.spring(duration: 0.35), value: session.progress)
                }
            }
            .frame(height: 13)

            Text(session.combo >= 3 ? "\(session.combo)×" : " ")
                .font(.edDisplay(15))
                .foregroundStyle(Color.edEmber)
                .frame(width: 44, alignment: .trailing)
                .opacity(session.combo >= 3 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: session.combo)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func cardFace(_ card: Card) -> some View {
        VStack(spacing: 16) {
            CardFieldView(html: card.front, font: .edDisplay(30), color: .edInk)

            if session.isRevealed {
                Divider().background(Color.edLine)
                CardFieldView(html: card.back, font: .system(size: 20), color: .edInk2)
                    .transition(.opacity)
            }

            HStack(spacing: 6) {
                TagChip(text: stateLabel(card))
                ForEach(card.tags.prefix(3), id: \.self) { TagChip(text: $0) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 22)
        .background(Color.edSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.edLine, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 22, y: 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if !session.isRevealed {
                withAnimation(.easeOut(duration: 0.2)) { session.reveal() }
            }
        }
    }

    private func stateLabel(_ card: Card) -> String {
        switch card.state {
        case .new: return "new"
        case .review: return "\(Scheduler.formatDays(card.interval)) interval"
        case .learning: return "learning"
        case .relearning: return "relearning"
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 8) {
            if session.isRevealed, let card = session.current {
                let hints = Scheduler.preview(card)
                HStack(spacing: 7) {
                    ForEach(Grade.allCases) { grade in
                        Button {
                            submit(grade)
                        } label: {
                            VStack(spacing: 2) {
                                Text(grade.title)
                                    .font(.system(size: 13, weight: .heavy))
                                Text(hints[grade] ?? "")
                                    .font(.edMono(10.5))
                                    .opacity(0.9)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(grade.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Button("Show answer") {
                    withAnimation(.easeOut(duration: 0.2)) { session.reveal() }
                }
                .buttonStyle(ChunkyButtonStyle(background: .edViolet))
                .disabled(session.current == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Actions

    private func submit(_ grade: Grade) {
        model.haptic(grade.isCorrect ? .light : .rigid)
        session.answer(grade, model: model, context: context)

        if let gained = session.lastAward {
            floatingID = UUID()
            withAnimation(.easeOut(duration: 0.2)) { floatingXP = gained }
            Task {
                try? await Task.sleep(for: .milliseconds(550))
                withAnimation(.easeIn(duration: 0.35)) { floatingXP = nil }
            }
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true

        let summary = SessionSummary(
            title: session.title,
            deckIDs: session.deckIDs,
            answered: session.answered,
            xp: session.xpEarned,
            accuracy: session.accuracy,
            bestCombo: session.bestCombo,
            elapsed: session.elapsed,
            streakAdvanced: model.streakJustAdvanced,
            streak: model.profile.streak,
            freezes: model.profile.freezes,
            goalMet: model.goalMetToday,
            xpRemaining: max(0, model.settings.dailyGoal - model.profile.todayStat.xp),
            unlocked: model.freshBadges.map(\.title)
        )
        onFinish(summary)
    }
}

struct TagChip: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .kerning(0.7)
            .foregroundStyle(Color.edMuted)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(Color.edSurface2, in: Capsule())
    }
}

// MARK: - Summary

struct SessionSummaryView: View {
    @Environment(AppModel.self) private var model
    let summary: SessionSummary
    let onDismiss: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Eyebrow(summary.answered > 0 ? "Session complete" : "Session ended")
                Text(headline)
                    .font(.edDisplay(24))
                    .foregroundStyle(Color.edInk)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SummaryTile(label: "XP earned", value: "+\(summary.xp)", tint: .edGold)
                    SummaryTile(label: "Cards", value: "\(summary.answered)", tint: .edInk)
                    SummaryTile(label: "Accuracy",
                                value: "\(Int(summary.accuracy * 100))%",
                                tint: summary.accuracy >= 0.85 ? .edMint : (summary.accuracy >= 0.65 ? .edGold : .edDanger))
                    SummaryTile(label: "Best combo", value: "\(summary.bestCombo)×", tint: .edEmber)
                }

                Text(footnote)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.edMuted)

                ForEach(summary.unlocked, id: \.self) { badge in
                    Label("Unlocked: \(badge)", systemImage: "star.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.edGold)
                }

                Button("Study again") { onDismiss(true) }
                    .buttonStyle(ChunkyButtonStyle(background: .edViolet))
                Button("Done for now") { onDismiss(false) }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(20)
        }
        .background(Color.edPaper)
    }

    private var headline: String {
        if summary.answered == 0 { return "Nothing reviewed" }
        if summary.streakAdvanced { return "Day \(summary.streak) locked in" }
        if summary.goalMet { return "Goal already met today" }
        return "\(summary.xpRemaining) XP to today's goal"
    }

    private var footnote: String {
        let minutes = Int((summary.elapsed / 60).rounded())
        let time = minutes < 1 ? "Under a minute" : "\(minutes) min"
        var parts = ["\(time) of study", "streak \(summary.streak) day\(summary.streak == 1 ? "" : "s")"]
        if summary.freezes > 0 {
            parts.append("\(summary.freezes) freeze\(summary.freezes == 1 ? "" : "s") banked")
        }
        return parts.joined(separator: " · ")
    }
}

struct SummaryTile: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.edNumber(26))
                .foregroundStyle(tint)
            Eyebrow(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.edSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.edLine, lineWidth: 1)
        )
    }
}
