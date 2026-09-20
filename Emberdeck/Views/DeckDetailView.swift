//
//  DeckDetailView.swift
//  Emberdeck
//

import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var deck: Deck
    let startSession: ([Deck], String) -> Void

    @State private var showingAddCard = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var confirmingDelete = false
    @State private var confirmingReset = false

    private var counts: AppModel.DueCounts { model.counts(for: deck) }

    var body: some View {
        List {
            Section {
                Button {
                    startSession([deck], deck.name)
                    dismiss()
                } label: {
                    Label(counts.total > 0 ? "Study \(counts.total) card\(counts.total == 1 ? "" : "s")" : "Nothing due today",
                          systemImage: "play.fill")
                }
                .disabled(counts.total == 0)

                NavigationLink {
                    CardBrowserView(deck: deck)
                } label: {
                    Label("Browse \(deck.cards.count) cards", systemImage: "list.bullet")
                }

                Button {
                    showingAddCard = true
                } label: {
                    Label("Add a card", systemImage: "plus")
                }
            }

            Section("Right now") {
                LabeledContent("New") { Text("\(counts.newCards)").font(.edMono(14)) }
                LabeledContent("Learning") { Text("\(counts.learning)").font(.edMono(14)) }
                LabeledContent("Due for review") { Text("\(counts.review)").font(.edMono(14)) }
                LabeledContent("Mature (21d+)") {
                    Text("\(deck.activeCards.filter(\.isMature).count)").font(.edMono(14))
                }
                if !deck.suspendedCards.isEmpty {
                    LabeledContent("Suspended") {
                        Text("\(deck.suspendedCards.count)").font(.edMono(14))
                    }
                    Button("Bring suspended cards back") {
                        for card in deck.suspendedCards { card.isSuspended = false }
                        save()
                    }
                }
            }

            Section {
                Toggle("Study both directions", isOn: bothDirectionsBinding)
                if deck.studyBothDirections {
                    LabeledContent("Reverse cards") {
                        Text("\(deck.cards.filter(\.isReverse).count)").font(.edMono(14))
                    }
                }
            } header: {
                Text("Direction")
            } footer: {
                Text(deck.studyBothDirections
                     ? "Every note is also asked back-to-front, with its own schedule. Turning this off hides the reverse cards but keeps their progress."
                     : "Also ask each card back-to-front — English → German as well as German → English.")
            }

            Section {
                Picker("Language", selection: speechLanguageBinding) {
                    Text("Off").tag("")
                    ForEach(SpeechLanguage.choices, id: \.code) { choice in
                        Text(choice.name).tag(choice.code)
                    }
                }
                if deck.speechLanguage != nil {
                    Picker("Foreign side", selection: speechSideBinding) {
                        ForEach(CardSide.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Pronunciation")
            } footer: {
                Text("Cards with their own audio play it. Cards without are read aloud by iOS in this language — pick which side holds the foreign words.")
            }

            Section {
                Stepper(value: newLimitBinding, in: 0...500, step: 5) {
                    LabeledContent("New cards per day") {
                        Text("\(deck.newLimitOverride ?? model.settings.newCardsPerDay)").font(.edMono(14))
                    }
                }
                if deck.newLimitOverride != nil {
                    Button("Use the global setting") { deck.newLimitOverride = nil; save() }
                }
            } header: {
                Text("Limits")
            } footer: {
                Text("Overrides the app-wide limit for this deck only.")
            }

            Section {
                Button("Rename deck") {
                    renameText = deck.name
                    showingRename = true
                }
                Button("Reset scheduling", role: .destructive) { confirmingReset = true }
                Button("Delete deck", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Resetting keeps every card but makes them all new again.")
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddCard) {
            AddCardView(deck: deck)
        }
        .alert("Rename deck", isPresented: $showingRename) {
            TextField("Deck name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { deck.name = trimmed; save() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Reset every card in \(deck.name) to new?",
                            isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset scheduling", role: .destructive) { resetScheduling() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deck.name) and its \(deck.cards.count) cards?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete deck", role: .destructive) { deleteDeck() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var bothDirectionsBinding: Binding<Bool> {
        Binding(
            get: { deck.studyBothDirections },
            set: { on in
                deck.studyBothDirections = on
                if on { deck.ensureReverseCards() }
                save()
            }
        )
    }

    private var speechLanguageBinding: Binding<String> {
        Binding(
            get: { deck.speechLanguage ?? "" },
            set: { deck.speechLanguage = $0.isEmpty ? nil : $0; save() }
        )
    }

    private var speechSideBinding: Binding<CardSide> {
        Binding(get: { deck.speechSide }, set: { deck.speechSide = $0; save() })
    }

    private var newLimitBinding: Binding<Int> {
        Binding(
            get: { deck.newLimitOverride ?? model.settings.newCardsPerDay },
            set: { deck.newLimitOverride = $0; save() }
        )
    }

    private func save() { try? context.save() }

    private func resetScheduling() {
        for (index, card) in deck.cards.sorted(by: { $0.position < $1.position }).enumerated() {
            card.state = .new
            card.position = index
            card.interval = 0
            card.ease = SchedulerConfig.standard.startingEase
            card.reps = 0
            card.lapses = 0
            card.step = 0
            card.dueDay = 0
            card.dueAt = Date()
            card.lastReviewed = nil
        }
        save()
    }

    private func deleteDeck() {
        context.delete(deck)
        save()
        dismiss()
    }
}

// MARK: - Add card

struct AddCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let deck: Deck

    @State private var front = ""
    @State private var back = ""
    @State private var added = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Front") { TextField("Question", text: $front, axis: .vertical) }
                Section("Back") { TextField("Answer", text: $back, axis: .vertical) }
                if added > 0 {
                    Section {
                        Text("\(added) card\(added == 1 ? "" : "s") added to \(deck.name).")
                            .foregroundStyle(Color.edMint)
                    }
                }
            }
            .navigationTitle("New card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(front.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {
        let card = Card(front: front.trimmingCharacters(in: .whitespaces),
                        back: back.trimmingCharacters(in: .whitespaces),
                        position: deck.cards.count,
                        deck: deck)
        context.insert(card)
        try? context.save()
        front = ""
        back = ""
        added += 1
    }
}

// MARK: - Browser

struct CardBrowserView: View {
    @Environment(\.modelContext) private var context
    let deck: Deck
    @State private var search = ""

    private var filtered: [Card] {
        let all = deck.cards.sorted { $0.position < $1.position }
        guard !search.isEmpty else { return all }
        let needle = search.lowercased()
        return all.filter {
            CardContent.plainText($0.front).lowercased().contains(needle)
                || CardContent.plainText($0.back).lowercased().contains(needle)
        }
    }

    var body: some View {
        List {
            ForEach(filtered) { card in
                NavigationLink {
                    EditCardView(card: card)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CardContent.plainText(card.promptHTML))
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                        Text(CardContent.plainText(card.answerHTML))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.edMuted)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if card.isSuspended { Text("suspended ·").foregroundStyle(Color.edDanger) }
                            if card.isReverse { Text("reverse ·") }
                            Text(card.state.label)
                            if card.state == .review {
                                Text("· \(Scheduler.formatDays(card.interval))")
                            }
                            if card.lapses > 0 {
                                Text("· \(card.lapses) lapse\(card.lapses == 1 ? "" : "s")")
                            }
                        }
                        .font(.edMono(10.5))
                        .foregroundStyle(Color.edMuted)
                    }
                    .padding(.vertical, 2)
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(filtered[index]) }
                try? context.save()
            }
        }
        .searchable(text: $search, prompt: "Search this deck")
        .navigationTitle("Cards")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EditCardView: View {
    @Environment(\.modelContext) private var context
    @Bindable var card: Card

    var body: some View {
        Form {
            Section("Front") { TextField("Front", text: $card.front, axis: .vertical) }
            Section("Back") { TextField("Back", text: $card.back, axis: .vertical) }
            Section("Tags") { TextField("Space separated", text: $card.tagString) }
            Section("Scheduling") {
                Toggle("Suspended", isOn: $card.isSuspended)
                LabeledContent("State") { Text(card.state.label).font(.edMono(14)) }
                LabeledContent("Interval") { Text(Scheduler.formatDays(card.interval)).font(.edMono(14)) }
                LabeledContent("Ease") { Text("\(card.ease / 10)%").font(.edMono(14)) }
                LabeledContent("Reviews") { Text("\(card.reps)").font(.edMono(14)) }
                LabeledContent("Lapses") { Text("\(card.lapses)").font(.edMono(14)) }
                Button("Make this card new again") {
                    card.state = .new
                    card.interval = 0
                    card.ease = SchedulerConfig.standard.startingEase
                    card.step = 0
                    card.dueDay = 0
                    card.dueAt = Date()
                    try? context.save()
                }
            }
        }
        .navigationTitle("Edit card")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
    }
}
