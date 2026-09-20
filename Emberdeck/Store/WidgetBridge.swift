//
//  WidgetBridge.swift
//  Emberdeck
//
//  The widget runs in its own process and can only see what the app leaves in
//  the shared App Group container. This is the one small record it reads.
//  A copy of `WidgetSnapshot` lives in the widget target; keep them identical.
//

import Foundation
import WidgetKit

struct WidgetSnapshot: Codable {
    static let suiteName = "group.com.emberdeck.shared"
    static let key = "widget.snapshot.v1"

    var streak: Int
    var due: Int
    var xpToday: Int
    var goal: Int
    var goalMet: Bool
    var freezes: Int
    var updated: Date

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.suiteName),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

enum WidgetBridge {
    /// Call whenever due counts or the streak may have changed.
    static func publish(model: AppModel, decks: [Deck]) {
        let snapshot = WidgetSnapshot(
            streak: model.profile.streak,
            due: model.counts(for: decks).total,
            xpToday: model.profile.todayStat.xp,
            goal: model.settings.dailyGoal,
            goalMet: model.goalMetToday,
            freezes: model.profile.freezes,
            updated: Date()
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
