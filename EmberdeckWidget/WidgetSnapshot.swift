//
//  WidgetSnapshot.swift
//  EmberdeckWidget
//
//  Mirror of the struct in the app's Store/WidgetBridge.swift. Kept as a copy
//  so neither target depends on the other's sources.
//

import Foundation

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

    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static let placeholder = WidgetSnapshot(streak: 12, due: 23, xpToday: 30, goal: 50,
                                            goalMet: false, freezes: 1, updated: Date())
}
