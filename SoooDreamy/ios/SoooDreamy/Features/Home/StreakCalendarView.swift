import SwiftUI

/// Month-grid calendar sheet behind the dashboard streak pill: shows on
/// which days you both answered the question of the day (and, dimmer, the
/// days only you did). Data comes from the existing daily-history API.
struct StreakCalendarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    /// Days where both answered / where only I answered ("YYYY-MM-DD" keys).
    @State private var bothKeys: Set<String> = []
    @State private var mineOnlyKeys: Set<String> = []
    /// First day of the displayed month.
    @State private var displayedMonth = Self.startOfMonth(Date())

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                if loading {
                    LoadingView()
                } else {
                    ScrollView {
                        VStack(spacing: LayoutMetrics.s(14)) {
                            monthNav
                            calendarCard
                            legend
                            summary
                        }
                        .padding(LayoutMetrics.s(16))
                        .padding(.bottom, LayoutMetrics.s(12))
                    }
                }
            }
            .navigationTitle(L10n.t("home.streakCalendar.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task { await loadEntries() }
    }

    // MARK: Calendar math

    /// Grid calendar — German convention starts the week on Monday.
    private var calendar: Calendar {
        var c = SharedDates.calendar
        c.firstWeekday = L10n.isGerman ? 2 : 1
        return c
    }

    private static func startOfMonth(_ date: Date) -> Date {
        let cal = SharedDates.calendar
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    /// "YYYY-MM-" prefix of the displayed month, for dateKey matching.
    private var monthKeyPrefix: String {
        let comps = SharedDates.calendar.dateComponents([.year, .month], from: displayedMonth)
        return String(format: "%04d-%02d-", comps.year ?? 0, comps.month ?? 0)
    }

    private struct DayCell: Identifiable {
        let id: Int
        let day: Int?       // nil = leading blank before the 1st
        let key: String?    // "YYYY-MM-DD"
    }

    private var dayCells: [DayCell] {
        let cal = calendar
        guard let range = cal.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWeekday = cal.component(.weekday, from: displayedMonth)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        var cells: [DayCell] = (0..<leading).map { DayCell(id: $0, day: nil, key: nil) }
        for day in range {
            cells.append(DayCell(id: leading + day, day: day, key: monthKeyPrefix + String(format: "%02d", day)))
        }
        return cells
    }

    /// Weekday letters rotated to the grid's first weekday.
    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        let symbols = formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: Month navigation

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: displayedMonth)
    }

    private var monthNav: some View {
        HStack {
            navButton(systemImage: "chevron.left",
                      a11yKey: "home.streakCalendar.prevMonth",
                      disabled: false) {
                shiftMonth(-1)
            }
            Spacer()
            Text(monthTitle)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            navButton(systemImage: "chevron.right",
                      a11yKey: "home.streakCalendar.nextMonth",
                      disabled: isCurrentMonth) {
                shiftMonth(1)
            }
        }
    }

    private func navButton(systemImage: String, a11yKey: String,
                           disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(disabled ? Theme.textTertiary : Theme.textPrimary)
                .frame(width: LayoutMetrics.s(32), height: LayoutMetrics.s(32))
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(L10n.t(a11yKey))
    }

    private func shiftMonth(_ delta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        Haptics.shared.tap()
        withAnimation(.spring(response: 0.3)) {
            displayedMonth = Self.startOfMonth(shifted)
        }
    }

    // MARK: Grid

    private var calendarCard: some View {
        VStack(spacing: LayoutMetrics.s(8)) {
            LazyVGrid(columns: gridColumns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            LazyVGrid(columns: gridColumns, spacing: 6) {
                ForEach(dayCells) { cell in
                    dayView(cell)
                }
            }
        }
        .glassCard(padding: 12)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    @ViewBuilder
    private func dayView(_ cell: DayCell) -> some View {
        if let day = cell.day, let key = cell.key {
            let both = bothKeys.contains(key)
            let mine = mineOnlyKeys.contains(key)
            let isToday = key == SharedDates.todayKey()
            ZStack {
                Circle()
                    .fill(both ? AnyShapeStyle(Theme.heroGradient)
                          : mine ? AnyShapeStyle(Theme.purple.opacity(0.25))
                          : AnyShapeStyle(Color.white.opacity(0.04)))
                if isToday {
                    Circle().strokeBorder(Theme.gold, lineWidth: 1.5)
                }
                Text("\(day)")
                    .font(.system(.footnote, design: .rounded).weight(both ? .heavy : .semibold))
                    .foregroundStyle(both ? .white : mine ? Theme.textPrimary : Theme.textTertiary)
                    .monospacedDigit()
            }
            .frame(height: LayoutMetrics.s(40))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(both ? "\(day): " + L10n.t("home.streakCalendar.legendBoth")
                                : mine ? "\(day): " + L10n.t("home.streakCalendar.legendMine")
                                : "\(day)")
        } else {
            Color.clear
                .frame(height: LayoutMetrics.s(40))
        }
    }

    // MARK: Legend & summary

    private var legend: some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            legendItem(fill: AnyShapeStyle(Theme.heroGradient),
                       label: L10n.t("home.streakCalendar.legendBoth"))
            legendItem(fill: AnyShapeStyle(Theme.purple.opacity(0.25)),
                       label: L10n.t("home.streakCalendar.legendMine"))
            Spacer(minLength: 0)
        }
    }

    private func legendItem(fill: AnyShapeStyle, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(fill)
                .frame(width: LayoutMetrics.s(14), height: LayoutMetrics.s(14))
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var monthBothCount: Int {
        let prefix = monthKeyPrefix
        return bothKeys.filter { $0.hasPrefix(prefix) }.count
    }

    @ViewBuilder
    private var summary: some View {
        if bothKeys.isEmpty {
            Text(L10n.t("home.streakCalendar.empty"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .glassCard()
        } else {
            HStack(spacing: LayoutMetrics.s(10)) {
                if let streak = appState.dailyEntry?.streak, streak > 1 {
                    StreakFirePill(streak: streak)
                }
                Text(L10n.t("home.streakCalendar.monthCount", ["n": String(monthBothCount)]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .glassCard(padding: 12)
        }
    }

    // MARK: Data

    private func loadEntries() async {
        guard let api = appState.api else {
            loading = false
            return
        }
        do {
            let entries = try await api.dailyHistory(limit: 366)
            bothKeys = Set(entries.filter(\.bothAnswered).map(\.dateKey))
            mineOnlyKeys = Set(entries.filter { !$0.bothAnswered && $0.myAnswer != nil }
                .map(\.dateKey))
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }
}
