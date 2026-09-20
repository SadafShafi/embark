//
//  EmberdeckWidget.swift
//  EmberdeckWidget
//
//  Streak flame and due count on the Home Screen and Lock Screen.
//

import SwiftUI
import WidgetKit

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = StreakEntry(date: Date(), snapshot: WidgetSnapshot.load())
        // The app reloads the widget itself after every session; this refresh
        // only has to catch the day rolling over.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Palette (mirrors the app's, without a shared file)

private extension Color {
    static let wEmber = Color(red: 0.933, green: 0.353, blue: 0.141)
    static let wGold = Color(red: 0.788, green: 0.541, blue: 0.090)
    static let wMint = Color(red: 0.059, green: 0.541, blue: 0.447)
    static let wViolet = Color(red: 0.420, green: 0.294, blue: 0.769)
    static let wInk = Color(red: 0.102, green: 0.082, blue: 0.149)
    static let wMuted = Color(red: 0.459, green: 0.424, blue: 0.522)
}

// MARK: - Views

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .accessoryCircular: circular(s)
            case .accessoryRectangular: rectangular(s)
            case .systemMedium: medium(s)
            default: small(s)
            }
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "flame")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.wMuted)
            Text("Open Emberdeck once")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.wMuted)
                .multilineTextAlignment(.center)
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(s.goalMet ? Color.wEmber : Color.wMuted)
                Text("\(s.streak)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.wInk)
                    .contentTransition(.numericText())
            }
            Text(s.streak == 1 ? "day streak" : "day streak")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
                .kerning(1)
                .foregroundStyle(Color.wMuted)
            Spacer(minLength: 0)
            goalBar(s)
            Text(dueLine(s))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(s.due > 0 ? Color.wViolet : Color.wMint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(s.goalMet ? Color.wEmber : Color.wMuted)
                    Text("\(s.streak)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.wInk)
                }
                Text("day streak")
                    .font(.system(size: 11, weight: .bold)).textCase(.uppercase).kerning(1)
                    .foregroundStyle(Color.wMuted)
                if s.freezes > 0 {
                    Label("\(s.freezes) freeze\(s.freezes == 1 ? "" : "s")", systemImage: "snowflake")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.wViolet)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                Text("\(s.due)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(s.due > 0 ? Color.wViolet : Color.wMint)
                Text(s.due == 0 ? "all done" : "cards due")
                    .font(.system(size: 11, weight: .bold)).textCase(.uppercase).kerning(1)
                    .foregroundStyle(Color.wMuted)
                goalBar(s).frame(width: 110)
                Text(s.goalMet ? "Goal met" : "\(s.xpToday) / \(s.goal) XP")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(s.goalMet ? Color.wMint : Color.wMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func circular(_ s: WidgetSnapshot) -> some View {
        Gauge(value: min(1, Double(s.xpToday) / Double(max(1, s.goal)))) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(s.streak)").font(.system(size: 16, weight: .heavy, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(s.streak)-day streak", systemImage: "flame.fill")
                .font(.system(size: 14, weight: .bold))
            Text(dueLine(s))
                .font(.system(size: 12))
            Text(s.goalMet ? "Goal met" : "\(s.xpToday)/\(s.goal) XP today")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func goalBar(_ s: WidgetSnapshot) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.wMuted.opacity(0.18))
                Capsule()
                    .fill(s.goalMet ? Color.wMint : Color.wGold)
                    .frame(width: max(6, geo.size.width * min(1, Double(s.xpToday) / Double(max(1, s.goal)))))
            }
        }
        .frame(height: 8)
    }

    private func dueLine(_ s: WidgetSnapshot) -> String {
        s.due == 0 ? "All caught up" : "\(s.due) card\(s.due == 1 ? "" : "s") due"
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EmberdeckStreak", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.965, green: 0.957, blue: 0.973)
                }
        }
        .configurationDisplayName("Streak")
        .description("Your streak, today's goal and what's due.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct EmberdeckWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
    }
}
