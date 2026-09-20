//
//  SettingsView.swift
//  Emberdeck
//

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.created) private var decks: [Deck]

    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var exporting = false
    @State private var exportDocument: BackupDocument?
    @State private var importingBackup = false
    @State private var confirmingErase = false
    @State private var message: String?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                // MARK: Goal
                Section {
                    Picker("Daily goal", selection: $model.settings.dailyGoal) {
                        ForEach(Settings.goalChoices) { choice in
                            Text("\(choice.label) · \(choice.xp) XP").tag(choice.xp)
                        }
                    }
                } header: {
                    Text("Daily goal")
                } footer: {
                    Text("A correct answer is worth \(XPRules.correct) XP, a lapse \(XPRules.again), plus \(XPRules.comboBonus) every \(XPRules.comboEvery) in a row.")
                }

                // MARK: Reminders
                Section {
                    Toggle("Daily reminder", isOn: $model.settings.remindersEnabled)

                    DatePicker("Remind me at",
                               selection: reminderTimeBinding,
                               displayedComponents: .hourAndMinute)
                        .disabled(!model.settings.remindersEnabled)

                    if authorization != .authorized {
                        Button("Allow notifications") {
                            Task {
                                await NotificationManager.shared.requestAuthorization()
                                authorization = await NotificationManager.shared.authorizationStatus()
                                await NotificationManager.shared.reschedule(using: model)
                            }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text(reminderFootnote)
                }

                // MARK: Limits
                Section {
                    Stepper(value: $model.settings.newCardsPerDay, in: 0...500, step: 5) {
                        LabeledContent("New cards per day") {
                            Text("\(model.settings.newCardsPerDay)").font(.edMono(14))
                        }
                    }
                    Stepper(value: $model.settings.maxReviewsPerDay, in: 10...2000, step: 10) {
                        LabeledContent("Max reviews per day") {
                            Text("\(model.settings.maxReviewsPerDay)").font(.edMono(14))
                        }
                    }
                } header: {
                    Text("Session limits")
                } footer: {
                    Text("Applied per deck. A deck can override the new-card limit on its own screen.")
                }

                // MARK: Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $model.settings.appearance) {
                        ForEach(Settings.Appearance.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Haptics", isOn: $model.settings.hapticsEnabled)
                }

                // MARK: Data
                Section {
                    Button("Export a backup") { exportBackup() }
                    Button("Restore from a backup") { importingBackup = true }
                    Button("Erase everything", role: .destructive) { confirmingErase = true }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("\(decks.count) deck\(decks.count == 1 ? "" : "s"), \(totalCards) cards, \(mediaSize) of images on this device. A backup holds every card's scheduling as well as your streak.")
                }

                Section {
                    LabeledContent("Scheduler", value: "SM-2")
                    LabeledContent("Version", value: appVersion)
                } footer: {
                    Text("Emberdeck keeps everything on device. It has no account, no server and no analytics.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                authorization = await NotificationManager.shared.authorizationStatus()
            }
            .fileExporter(isPresented: $exporting,
                          document: exportDocument,
                          contentType: .json,
                          defaultFilename: Backup.suggestedFilename()) { result in
                switch result {
                case .success: message = "Backup saved."
                case .failure(let error): message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importingBackup,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                restoreBackup(result)
            }
            .confirmationDialog("Erase every deck, card, streak and setting?",
                                isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { eraseAll() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Emberdeck", isPresented: .constant(message != nil)) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    // MARK: - Derived

    private var totalCards: Int { decks.reduce(0) { $0 + $1.cards.count } }

    private var mediaSize: String {
        ByteCountFormatter.string(fromByteCount: MediaStore.totalBytes(), countStyle: .file)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var reminderFootnote: String {
        switch authorization {
        case .authorized:
            return "Emberdeck schedules a fortnight of reminders ahead and rewrites them each time you open it, so today's is dropped the moment you hit your goal."
        case .denied:
            return "Notifications are switched off. Turn them back on in iOS Settings → Emberdeck → Notifications."
        default:
            return "Allow notifications and Emberdeck will nudge you at this time each day, plus a last call at 21:30 when a streak is at risk."
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = model.settings.reminderHour
                comps.minute = model.settings.reminderMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                model.settings.reminderHour = comps.hour ?? 19
                model.settings.reminderMinute = comps.minute ?? 0
            }
        )
    }

    // MARK: - Actions

    private func exportBackup() {
        do {
            let payload = Backup.make(decks: decks, model: model)
            exportDocument = BackupDocument(data: try Backup.encode(payload))
            exporting = true
        } catch {
            message = "Could not build the backup: \(error.localizedDescription)"
        }
    }

    private func restoreBackup(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result { message = error.localizedDescription }
            return
        }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let payload = try Backup.decode(try Data(contentsOf: url))
            try Backup.restore(payload, context: context, model: model)
            message = "Restored \(payload.cardCount) cards from \(payload.exportedAt.formatted(date: .abbreviated, time: .shortened))."
        } catch {
            message = "That backup could not be read: \(error.localizedDescription)"
        }
    }

    private func eraseAll() {
        for deck in decks { context.delete(deck) }
        try? context.save()
        MediaStore.removeAll()
        model.profile = Profile()
        model.settings = Settings()
        NotificationManager.shared.cancelAll()
        UNUserNotificationCenterBadge.set(0)
        message = "Everything erased."
    }
}
