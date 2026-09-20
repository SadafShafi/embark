//
//  RootView.swift
//  Emberdeck
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.created) private var decks: [Deck]

    @State private var tab: Tab = .today
    @State private var session: StudySession?
    @State private var summary: SessionSummary?
    @State private var notice: String?

    enum Tab: Hashable { case today, decks, progress, settings }

    var body: some View {
        TabView(selection: $tab) {
            TodayView(startSession: start)
                .tabItem { Label("Today", systemImage: "flame.fill") }
                .tag(Tab.today)

            DecksView(startSession: start)
                .tabItem { Label("Decks", systemImage: "rectangle.stack.fill") }
                .tag(Tab.decks)

            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(Tab.progress)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .fullScreenCover(item: $session) { active in
            StudyView(session: active) { result in
                session = nil
                summary = result
                if result.answered > 0 {
                    AudioEngine.shared.play(result.streakAdvanced ? .streak : .complete,
                                            enabled: model.settings.soundEffects)
                }
                model.refreshAppBadge(decks: decks)
                Task { await NotificationManager.shared.reschedule(using: model) }
            }
        }
        .sheet(item: $summary) { result in
            SessionSummaryView(summary: result) { again in
                let decksToRepeat = decks.filter { result.deckIDs.contains($0.id) }
                summary = nil
                if again { start(decks: decksToRepeat, title: result.title) }
            }
            .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .top) {
            if let notice {
                NoticeBanner(text: notice)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            SeedDecks.installIfEmpty(context: context)
            model.refreshAppBadge(decks: decks)
        }
        .onChange(of: model.pendingNotice) { _, new in
            guard let new else { return }
            withAnimation(.spring(duration: 0.35)) { notice = new }
            model.pendingNotice = nil
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { notice = nil }
            }
        }
    }

    private func start(decks decksToStudy: [Deck], title: String) {
        let cards = model.buildQueue(for: decksToStudy)
        guard !cards.isEmpty else {
            model.pendingNotice = "Nothing is due there right now."
            return
        }
        model.streakJustAdvanced = false
        model.freshBadges = []
        session = StudySession(cards: cards, title: title)
    }
}

extension StudySession: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}

struct NoticeBanner: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Color.edPaper)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(Color.edInk, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

// MARK: - Streak and XP header, shared by Today and Decks

struct StreakHeader: View {
    @Environment(AppModel.self) private var model
    @State private var showingStreakDetail = false

    var body: some View {
        HStack(spacing: 10) {
            Button { showingStreakDetail = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                    Text("\(model.profile.streak)")
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(model.goalMetToday ? Color.edEmber : Color.edMuted)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(model.goalMetToday ? Color.edEmberSoft : Color.edSurface2, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if model.profile.freezes > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "snowflake")
                    Text("\(model.profile.freezes)")
                }
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.edViolet)
                .padding(.vertical, 6)
                .padding(.horizontal, 11)
                .background(Color.edVioletSoft, in: Capsule())
            }

            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                Text(model.profile.xp >= 10000
                     ? String(format: "%.1fk", Double(model.profile.xp) / 1000)
                     : "\(model.profile.xp)")
            }
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Color.edGold)
            .padding(.vertical, 6)
            .padding(.horizontal, 11)
            .background(Color.edGoldSoft, in: Capsule())
        }
        .sheet(isPresented: $showingStreakDetail) { StreakDetailView() }
    }
}

struct StreakDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Today") {
                        Text("\(model.profile.todayStat.xp) / \(model.settings.dailyGoal) XP")
                            .font(.edMono(14))
                    }
                    LabeledContent("Current streak") { Text("\(model.profile.streak) days").font(.edMono(14)) }
                    LabeledContent("Longest streak") { Text("\(model.profile.bestStreak) days").font(.edMono(14)) }
                    LabeledContent("Freezes banked") { Text("\(model.profile.freezes)").font(.edMono(14)) }
                    LabeledContent("Level") {
                        Text("\(model.profile.level) · \(model.profile.xpToNextLevel) XP to go").font(.edMono(14))
                    }
                } footer: {
                    Text("""
                        A day counts once you reach your XP goal. Miss a day and a streak freeze covers it \
                        automatically — you earn one every seventh day, up to two in the bank.
                        """)
                }
            }
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
