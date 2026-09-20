//
//  DecksView.swift
//  Emberdeck
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DecksView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.created) private var decks: [Deck]

    let startSession: ([Deck], String) -> Void

    @State private var showingImporter = false
    @State private var showingImportHelp = false
    @State private var showingPaste = false
    @State private var newDeckName = ""
    @State private var showingNewDeck = false
    @State private var importState: ImportState = .idle

    enum ImportState: Equatable {
        case idle
        case working(String)
        case failed(String)
        case done(String)
    }

    private static let importTypes: [UTType] = {
        var types: [UTType] = []
        for ext in ["apkg", "colpkg"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        types.append(contentsOf: [.commaSeparatedText, .tabSeparatedText, .plainText, .json, .data])
        return types
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    StreakHeader()

                    if case .working(let message) = importState {
                        Panel {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Importing").font(.system(size: 15, weight: .bold))
                                    Text(message).font(.system(size: 13)).foregroundStyle(Color.edMuted)
                                }
                            }
                        }
                    }

                    if decks.isEmpty {
                        Panel {
                            Eyebrow("Nothing here yet")
                            Text("Import an .apkg from Anki, or type your own cards.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.edMuted)
                        }
                    } else {
                        ForEach(decks) { deck in
                            NavigationLink {
                                DeckDetailView(deck: deck, startSession: startSession)
                            } label: {
                                DeckRow(deck: deck, counts: model.counts(for: deck))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button("Import cards") { showingImportHelp = true }
                        .buttonStyle(ChunkyButtonStyle(background: .edViolet))
                    Button("Create an empty deck") { showingNewDeck = true }
                        .buttonStyle(GhostButtonStyle())

                    Text("Decks and scheduling stay on this device. Nothing is uploaded anywhere.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.edMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.edPaper)
            .navigationTitle("Decks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImportHelp = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Import")
                }
            }
            .sheet(isPresented: $showingImportHelp) {
                ImportHelpView(
                    chooseFile: { showingImportHelp = false; showingImporter = true },
                    pasteList: { showingImportHelp = false; showingPaste = true }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingPaste) {
                PasteImportView { text, name in
                    showingPaste = false
                    importPastedText(text, name: name)
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: Self.importTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importFiles(urls)
                case .failure(let error): importState = .failed(error.localizedDescription)
                }
            }
            .alert("Import failed", isPresented: .constant(isFailed), presenting: failureMessage) { _ in
                Button("OK") { importState = .idle }
            } message: { message in
                Text(message)
            }
            .alert("Imported", isPresented: .constant(isDone), presenting: doneMessage) { _ in
                Button("OK") { importState = .idle }
            } message: { message in
                Text(message)
            }
            .alert("New deck", isPresented: $showingNewDeck) {
                TextField("Deck name", text: $newDeckName)
                Button("Create") { createDeck() }
                Button("Cancel", role: .cancel) { newDeckName = "" }
            }
        }
    }

    // MARK: - Alert plumbing

    private var isFailed: Bool { if case .failed = importState { return true }; return false }
    private var isDone: Bool { if case .done = importState { return true }; return false }
    private var failureMessage: String? { if case .failed(let m) = importState { return m }; return nil }
    private var doneMessage: String? { if case .done(let m) = importState { return m }; return nil }

    // MARK: - Actions

    private func createDeck() {
        let trimmed = newDeckName.trimmingCharacters(in: .whitespaces)
        newDeckName = ""
        guard !trimmed.isEmpty else { return }
        let deck = Deck(name: DeckNaming.unique(trimmed, among: decks))
        context.insert(deck)
        try? context.save()
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        importState = .working(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")

        Task {
            var results: [ImportResult] = []
            var failure: String?

            for url in urls {
                do {
                    let ext = url.pathExtension.lowercased()
                    let parsed: ImportResult
                    if ext == "apkg" || ext == "colpkg" {
                        parsed = try await Task.detached(priority: .userInitiated) {
                            try ApkgImporter.parse(url: url)
                        }.value
                    } else {
                        let needsScope = url.startAccessingSecurityScopedResource()
                        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                        let text = try String(contentsOf: url, encoding: .utf8)
                        let name = url.deletingPathExtension().lastPathComponent
                        parsed = try DelimitedImporter.parse(text: text, fallbackName: name)
                    }
                    results.append(parsed)
                } catch {
                    failure = error.localizedDescription
                    break
                }
            }

            await MainActor.run {
                if let failure {
                    importState = .failed(failure)
                } else {
                    let inserted = results.reduce(0) { $0 + insert($1) }
                    let media = results.reduce(0) { $0 + $1.mediaImported }
                    importState = .done(summaryText(cards: inserted, media: media))
                    model.refreshAppBadge(decks: decks)
                }
            }
        }
    }

    private func importPastedText(_ text: String, name: String) {
        do {
            let parsed = try DelimitedImporter.parse(text: text, fallbackName: name)
            let inserted = insert(parsed)
            importState = .done(summaryText(cards: inserted, media: 0))
        } catch {
            importState = .failed(error.localizedDescription)
        }
    }

    private func summaryText(cards: Int, media: Int) -> String {
        var s = "\(cards) card\(cards == 1 ? "" : "s") added."
        if media > 0 { s += " \(media) image\(media == 1 ? "" : "s") came along." }
        return s
    }

    @discardableResult
    private func insert(_ result: ImportResult) -> Int {
        var total = 0
        var existing = decks
        for parsed in result.decks {
            let deck = Deck(name: DeckNaming.unique(parsed.name, among: existing))
            context.insert(deck)
            existing.append(deck)
            for (index, note) in parsed.notes.enumerated() {
                let card = Card(front: note.front, back: note.back, tags: note.tags,
                                position: index, deck: deck)
                context.insert(card)
                total += 1
            }
        }
        try? context.save()
        return total
    }
}

enum DeckNaming {
    static func unique(_ name: String, among decks: [Deck]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Imported" : name
        let taken = Set(decks.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }
}

// MARK: - Import help

struct ImportHelpView: View {
    @Environment(\.dismiss) private var dismiss
    let chooseFile: () -> Void
    let pasteList: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bring in your cards")
                        .font(.edDisplay(22))
                        .foregroundStyle(Color.edInk)

                    Button("Choose a file", action: chooseFile)
                        .buttonStyle(ChunkyButtonStyle(background: .edViolet))
                    Button("Paste a list instead", action: pasteList)
                        .buttonStyle(GhostButtonStyle())

                    Text(".apkg and .colpkg from Anki or AnkiWeb · .csv, .tsv and .txt exports.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.edMuted)

                    Divider()

                    Eyebrow("Getting an AnkiWeb deck onto this phone")
                    VStack(alignment: .leading, spacing: 8) {
                        Step(1, "In Safari, open ankiweb.net/shared/decks, pick a deck and tap Download. It lands in Files → Downloads.")
                        Step(2, "Come back here, tap Choose a file, and pick it from Browse → Downloads.")
                        Step(3, "Decks exported from Anki on a computer work the same way — AirDrop or iCloud Drive them across first.")
                    }

                    Divider()

                    Text("""
                        Cards import as front = the note's first field, back = the rest. Emberdeck doesn't run \
                        Anki's card templates, so a note that generates three cards in Anki arrives as one here. \
                        Images come along from decks in the classic media format; audio is skipped.
                        """)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.edMuted)
                }
                .padding(20)
            }
            .background(Color.edPaper)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

struct Step: View {
    let number: Int
    let text: String
    init(_ number: Int, _ text: String) { self.number = number; self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.edMono(12))
                .foregroundStyle(Color.edViolet)
                .frame(width: 22, height: 22)
                .background(Color.edVioletSoft, in: Circle())
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.edInk2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PasteImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var name = "Pasted cards"
    let onImport: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Deck name") {
                    TextField("Deck name", text: $name)
                }
                Section {
                    TextEditor(text: $text)
                        .font(.edMono(13))
                        .frame(minHeight: 200)
                } header: {
                    Text("One card per line")
                } footer: {
                    Text("Separate front and back with a tab, comma or semicolon. Anki text exports with # header lines work as they are.")
                }
            }
            .navigationTitle("Paste cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { onImport(text, name) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
