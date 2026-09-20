//
//  Notifications.swift
//  Emberdeck
//
//  The reason this app is native: real scheduled reminders that fire whether or
//  not the app is running.
//
//  iOS will not let a notification decide at fire time whether it is still
//  needed, so instead of one repeating trigger we lay down a rolling fortnight
//  of one-shot notifications and rewrite them every time the app opens or the
//  daily goal is met. Today's is dropped as soon as the goal is hit.
//

import Foundation
import UserNotifications

enum UNUserNotificationCenterBadge {
    static func set(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { _ in }
    }
}

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    /// How many days ahead to lay down reminders. The app rewrites them on every
    /// launch, so this only has to outlast a long absence.
    private let horizon = 14

    private static let dailyPrefix = "emberdeck.daily."
    private static let rescuePrefix = "emberdeck.rescue."

    // MARK: - Permission

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Scheduling

    func reschedule(using model: AppModel) async {
        let ids = (0...horizon).flatMap { [Self.dailyPrefix + String($0), Self.rescuePrefix + String($0)] }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        guard model.settings.remindersEnabled else { return }
        guard await authorizationStatus() == .authorized else { return }

        let cal = Calendar.current
        let now = Date()
        let streak = model.profile.streak
        let goalMetToday = model.goalMetToday

        for offset in 0...horizon {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }

            // Nothing to nag about today once the goal is already met.
            if offset == 0 && goalMetToday { continue }

            if let fire = fireDate(on: day, hour: model.settings.reminderHour, minute: model.settings.reminderMinute),
               fire > now {
                let streakOnThatDay = streak + offset
                let content = UNMutableNotificationContent()
                content.title = "Emberdeck"
                content.body = reminderBody(streak: streakOnThatDay, goal: model.settings.dailyGoal, offset: offset)
                content.sound = .default
                content.interruptionLevel = .active
                await add(content, at: fire, id: Self.dailyPrefix + String(offset))
            }

            // A last call before midnight, only when there is a streak worth saving.
            if streak >= 3 {
                if let rescue = fireDate(on: day, hour: 21, minute: 30), rescue > now {
                    let content = UNMutableNotificationContent()
                    content.title = "Streak at risk"
                    content.body = "A few cards now keeps your \(max(1, streak + offset))-day streak alive."
                    content.sound = .default
                    content.interruptionLevel = .timeSensitive
                    await add(content, at: rescue, id: Self.rescuePrefix + String(offset))
                }
            }
        }
    }

    private func reminderBody(streak: Int, goal: Int, offset: Int) -> String {
        if streak <= 0 { return "Five minutes of cards is enough to start a streak." }
        if offset == 0 { return "Your \(streak)-day streak needs \(goal) XP today." }
        return "Day \(streak). Keep the ember lit."
    }

    private func fireDate(on day: Date, hour: Int, minute: Int) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)
    }

    private func add(_ content: UNMutableNotificationContent, at date: Date, id: String) async {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
