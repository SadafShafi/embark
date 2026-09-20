//
//  StatsView.swift
//  Emberdeck
//

import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Query private var decks: [Deck]

    private let heatmapWeeks = 18

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Panel {
                        Eyebrow("Last \(heatmapWeeks) weeks")
                        Heatmap(profile: model.profile, weeks: heatmapWeeks)
                        Text(heatmapCaption)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.edMuted)
                    }

                    Panel {
                        Eyebrow("Reviews and forecast")
                        ReviewChart(points: chartPoints)
                            .frame(height: 150)
                        Text("Solid is what you reviewed; pale is what falls due.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.edMuted)
                    }

                    Panel {
                        Eyebrow("All time")
                        VStack(spacing: 0) {
                            StatRow("Current streak", "\(model.profile.streak)d")
                            StatRow("Longest streak", "\(model.profile.bestStreak)d")
                            StatRow("Total XP", model.profile.xp.formatted())
                            StatRow("Level", "\(model.profile.level)")
                            StatRow("Reviews", model.profile.totalReviews.formatted())
                            StatRow("Retention", model.profile.totalReviews > 0
                                    ? "\(Int(model.profile.retention * 100))%" : "—")
                            StatRow("Time studied", timeStudied)
                            StatRow("Cards", cardBreakdown, isLast: true)
                        }
                    }

                    Panel {
                        Eyebrow("Achievements")
                        FlowRow(spacing: 8) {
                            ForEach(Achievement.all, id: \.id) { badge in
                                let unlocked = model.profile.badges.contains(badge.id)
                                HStack(spacing: 6) {
                                    Image(systemName: unlocked ? "star.fill" : "star")
                                        .font(.system(size: 11))
                                    Text(badge.title)
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundStyle(unlocked ? Color.edGold : Color.edMuted)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 11)
                                .background(unlocked ? Color.edGoldSoft : Color.edSurface2, in: Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color.edPaper)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Derived data

    private var heatmapCaption: String {
        let today = DayMath.today
        let start = today - (heatmapWeeks * 7 - 1)
        let active = (start...today).filter { (model.profile.history[$0]?.reviews ?? 0) > 0 }.count
        return "\(active) active day\(active == 1 ? "" : "s") · best streak \(model.profile.bestStreak)"
    }

    private var timeStudied: String {
        let seconds = model.profile.totalSeconds
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return String(format: "%.1fh", seconds / 3600)
    }

    private var cardBreakdown: String {
        var new = 0, young = 0, mature = 0
        for deck in decks {
            for card in deck.cards {
                if card.state == .new { new += 1 }
                else if card.isMature { mature += 1 }
                else { young += 1 }
            }
        }
        return "\(new + young + mature) · \(new) new, \(young) young, \(mature) mature"
    }

    private var chartPoints: [ReviewPoint] {
        let today = DayMath.today
        var points: [ReviewPoint] = []

        for day in (today - 13)...today {
            points.append(ReviewPoint(day: day,
                                      count: model.profile.history[day]?.reviews ?? 0,
                                      isForecast: false))
        }
        var forecast = [Int](repeating: 0, count: 14)
        for deck in decks {
            for card in deck.cards where card.state == .review {
                let offset = card.dueDay - today
                if offset < 1 { forecast[0] += 1 }
                else if offset <= 14 { forecast[offset - 1] += 1 }
            }
        }
        for (i, count) in forecast.enumerated() {
            points.append(ReviewPoint(day: today + 1 + i, count: count, isForecast: true))
        }
        return points
    }
}

struct ReviewPoint: Identifiable {
    let day: Int
    let count: Int
    let isForecast: Bool
    var id: Int { day }
}

struct ReviewChart: View {
    let points: [ReviewPoint]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", DayMath.date(forDay: point.day), unit: .day),
                y: .value("Reviews", point.count)
            )
            .foregroundStyle(point.isForecast ? Color.edSurface3 : Color.edViolet)
            .cornerRadius(3)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.edLine)
                AxisValueLabel().foregroundStyle(Color.edMuted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine().foregroundStyle(Color.edLine)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Color.edMuted)
            }
        }
    }
}

struct Heatmap: View {
    let profile: Profile
    let weeks: Int

    private var columns: [[Int]] {
        let today = DayMath.today
        let start = today - (weeks * 7 - 1)
        var result: [[Int]] = []
        var column: [Int] = []
        for day in start...today {
            column.append(profile.history[day]?.reviews ?? 0)
            if column.count == 7 { result.append(column); column = [] }
        }
        if !column.isEmpty { result.append(column) }
        return result
    }

    private var peak: Int {
        max(1, columns.flatMap { $0 }.max() ?? 1)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: 3) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, count in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color(for: count))
                                .frame(width: 13, height: 13)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .defaultScrollAnchor(.trailing)
    }

    private func color(for count: Int) -> Color {
        guard count > 0 else { return .edSurface3 }
        let intensity = min(1.0, Double(count) / Double(peak))
        return Color.edMint.opacity(0.28 + 0.72 * intensity)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var isLast = false

    init(_ label: String, _ value: String, isLast: Bool = false) {
        self.label = label
        self.value = value
        self.isLast = isLast
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.edMuted)
                Spacer(minLength: 8)
                Text(value)
                    .font(.edNumber(16))
                    .foregroundStyle(Color.edInk)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 9)
            if !isLast { Divider().background(Color.edLine) }
        }
    }
}

/// A wrapping row, since achievement chips vary in width.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
