//
//  EmberdeckApp.swift
//  Emberdeck
//

import SwiftUI
import SwiftData

@main
struct EmberdeckApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer = {
        let schema = Schema([Deck.self, Card.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A schema the store can't migrate would otherwise wedge the app on
            // launch; fall back to memory so the user can at least re-import.
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(colorScheme)
                .tint(.edViolet)
                .task {
                    model.reconcileStreak()
                    await NotificationManager.shared.reschedule(using: model)
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.reconcileStreak()
                Task { await NotificationManager.shared.reschedule(using: model) }
            case .background, .inactive:
                model.persistAll()
            @unknown default:
                break
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
