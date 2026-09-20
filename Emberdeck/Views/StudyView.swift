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
    @State private var shownCardID: UUID?
    @State private var choices: [Choice]?
    @State private var pickedChoice: UUID?
    @State private var banner: String?

    struct Choice: Identifiable {
        let id = UUID()
        let text: String
        let isCorrect: Bool
    }

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
        .overlay(alignment: .top) {
            if let banner {
                NoticeBanner(text: banner)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: session.leechFlagged?.id) { _, id in
            guard id != nil else { return }
            session.leechFlagged = nil
            showBanner("Set aside as a leech — find it under the deck's suspended cards.")
        }
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
        .onChange(of: session.current?.id) { _, id in
            cardDidAppear(id)
        }
        .onAppear { cardDidAppear(session.current?.id) }
        .onDisappear { AudioEngine.shared.stopEverything() }
    }

    // MARK: - Audio

    private func cardDidAppear(_ id: UUID?) {
        guard let id, id != shownCardID, let card = session.current else { return }
        shownCardID = id
        pickedChoice = nil
        choices = makeChoices(for: card)
        AudioEngine.shared.stopEverything()
        playSide(of: card, prompt: true)
    }

    private func showBanner(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { banner = text }
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            withAnimation { banner = nil }
        }
    }

    // MARK: - Multiple choice

    /// For a card's very first showing, four options are a fairer question
    /// than a blank. Distractors come from the same deck and direction.
    private func makeChoices(for card: Card) -> [Choice]? {
        guard model.settings.multipleChoiceForNew, !session.isCram,
              card.state == .new, card.reps == 0, let deck = card.deck else { return nil }
        let correct = CardContent.plainText(card.answerHTML)
        guard !correct.isEmpty, correct.count <= 80 else { return nil }

        let pool = deck.activeCards
            .filter { $0.noteKey != card.noteKey && $0.isReverse == card.isReverse }
            .map { CardContent.plainText($0.answerHTML) }
            .filter { !$0.isEmpty && $0 != correct && $0.count <= 80 }
        let distractors = Array(Set(pool)).shuffled().prefix(3)
        guard distractors.count == 3 else { return nil }

        var out = distractors.map { Choice(text: $0, isCorrect: false) }
        out.append(Choice(text: correct, isCorrect: true))
        return out.shuffled()
    }

    private func pick(_ choice: Choice) {
        guard pickedChoice == nil else { return }
        pickedChoice = choice.id
        model.haptic(choice.isCorrect ? .light : .rigid)
        withAnimation(.easeOut(duration: 0.2)) { session.reveal() }
        if let card = session.current { playSide(of: card, prompt: false) }
        Task {
            try? await Task.sleep(for: .milliseconds(choice.isCorrect ? 650 : 1100))
            guard pickedChoice == choice.id else { return }
            submit(choice.isCorrect ? .good : .again)
        }
    }

    private func undo() {
        guard session.canUndo else { return }
        AudioEngine.shared.stopEverything()
        pickedChoice = nil
        choices = nil
        session.undo(model: model, context: context)
        shownCardID = session.current?.id
        model.haptic()
        showBanner("Answer taken back — grade it again.")
    }

    /// A card's own audio wins; speech fills in for cards that have none.
    private func playSide(of card: Card, prompt: Bool) {
        let html = prompt ? card.promptHTML : card.answerHTML
        var played = false
        if model.settings.autoPlayCardAudio {
            played = AudioEngine.shared.playCardAudio(CardContent.audioNames(from: html))
        }
        guard !played, model.settings.speakCards,
              let deck = card.deck, let language = deck.speechLanguage,
              card.foreignSideIsPrompt(for: deck) == prompt else { return }
        AudioEngine.shared.speak(CardContent.speechText(html), language: language)
    }

    private func replayAudio() {
        guard let card = session.current else { return }
        AudioEngine.shared.stopEverything()
        playSide(of: card, prompt: !session.isRevealed)
    }

    private var hasAnyAudio: Bool {
        guard let card = session.current else { return false }
        if !CardContent.audioNames(from: card.front).isEmpty || !CardContent.audioNames(from: card.back).isEmpty { return true }
        return model.settings.speakCards && card.deck?.speechLanguage != nil
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

            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(session.canUndo ? Color.edInk2 : Color.edMuted.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .background(Color.edSurface2, in: Circle())
            }
            .disabled(!session.canUndo)
            .accessibilityLabel("Undo last answer")

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
            CardFieldView(html: card.promptHTML, font: .edDisplay(30), color: .edInk)

            if session.isRevealed {
                Divider().background(Color.edLine)
                CardFieldView(html: card.answerHTML, font: .system(size: 20), color: .edInk2)
                    .transition(.opacity)
            }

            HStack(spacing: 6) {
                TagChip(text: stateLabel(card))
                if card.isReverse { TagChip(text: "reverse") }
                ForEach(card.tags.prefix(2), id: \.self) { TagChip(text: $0) }
                if hasAnyAudio {
                    Spacer(minLength: 0)
                    Button(action: replayAudio) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.edViolet)
                            .frame(width: 32, height: 32)
                            .background(Color.edVioletSoft, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play audio")
                }
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
        .onTapGesture { revealCard() }
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
            if let choices, pickedChoice != nil || !session.isRevealed {
                VStack(spacing: 7) {
                    ForEach(choices) { choice in
                        Button { pick(choice) } label: {
                            HStack {
                                Text(choice.text)
                                    .font(.system(size: 15, weight: .semibold))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                if pickedChoice != nil, choice.isCorrect {
                                    Image(systemName: "checkmark.circle.fill")
                                } else if pickedChoice == choice.id {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                            .foregroundStyle(choiceForeground(choice))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(choiceBackground(choice), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(choiceBorder(choice), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(pickedChoice != nil)
                    }
                }
            } else if session.isRevealed, let card = session.current {
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
                Button("Show answer") { revealCard() }
                .buttonStyle(ChunkyButtonStyle(background: .edViolet))
                .disabled(session.current == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private func choiceBackground(_ c: Choice) -> Color {
        guard pickedChoice != nil else { return .edSurface }
        if c.isCorrect { return .edMintSoft }
        if pickedChoice == c.id { return .edDangerSoft }
        return .edSurface
    }
    private func choiceForeground(_ c: Choice) -> Color {
        guard pickedChoice != nil else { return .edInk }
        if c.isCorrect { return .edMint }
        if pickedChoice == c.id { return .edDanger }
        return .edMuted
    }
    private func choiceBorder(_ c: Choice) -> Color {
        guard pickedChoice != nil else { return .edLine }
        if c.isCorrect { return .edMint }
        if pickedChoice == c.id { return .edDanger }
        return .edLine
    }

    // MARK: - Actions

    private func revealCard() {
        guard !session.isRevealed, let card = session.current else { return }
        withAnimation(.easeOut(duration: 0.2)) { session.reveal() }
        AudioEngine.shared.play(.flip, enabled: model.settings.soundEffects)
        playSide(of: card, prompt: false)
    }

    private func submit(_ grade: Grade) {
        model.haptic(grade.isCorrect ? .light : .rigid)
        AudioEngine.shared.stopEverything()
        session.answer(grade, model: model, context: context)

        let sfx = model.settings.soundEffects
        if !grade.isCorrect {
            AudioEngine.shared.play(.wrong, enabled: sfx)
        } else if session.combo > 0, session.combo % XPRules.comboEvery == 0 {
            AudioEngine.shared.play(.combo, enabled: sfx)
        } else {
            AudioEngine.shared.play(.correct, enabled: sfx)
        }

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
