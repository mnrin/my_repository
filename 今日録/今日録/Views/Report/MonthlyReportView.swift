import SwiftUI
import Charts
import HealthKit

struct MonthlyReportView: View {
    @Environment(\.dismiss) private var dismiss
    let expenses: [ExpenseRecord]
    let foods: [FoodRecord]
    let manualBurns: [CalorieBurnRecord]
    let useHealthKit: Bool

    // 日別の集計は初期化時に1度だけ行い、カレンダー描画時の再計算を避ける。
    private let intakeByDay: [Date: Int]
    private let expenseByDay: [Date: Int]
    private let manualBurnByDay: [Date: Int]

    init(expenses: [ExpenseRecord], foods: [FoodRecord], manualBurns: [CalorieBurnRecord], useHealthKit: Bool) {
        self.expenses = expenses
        self.foods = foods
        self.manualBurns = manualBurns
        self.useHealthKit = useHealthKit

        let calendar = Calendar.current
        var intake: [Date: Int] = [:]
        for food in foods {
            guard let date = food.createdAt else { continue }
            intake[calendar.startOfDay(for: date), default: 0] += food.calories
        }
        var expense: [Date: Int] = [:]
        for record in expenses {
            guard let date = record.createdAt else { continue }
            expense[calendar.startOfDay(for: date), default: 0] += record.amount
        }
        var burn: [Date: Int] = [:]
        for record in manualBurns {
            burn[calendar.startOfDay(for: record.createdAt), default: 0] += record.calories
        }
        intakeByDay = intake
        expenseByDay = expense
        manualBurnByDay = burn
    }

    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var healthBurnByDay: [Date: Int] = [:]
    @State private var isLoadingHealthData = false
    @State private var calendarDisplay: MonthlyCalendarMetric = .calorieDifference

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthRange: DateInterval? { calendar.dateInterval(of: .month, for: month) }
    private var monthDays: [Date] {
        guard let range = monthRange else { return [] }
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: range.start) }
    }
    private var leadingDayCount: Int { max(0, (calendar.component(.weekday, from: month) + 5) % 7) }
    private var monthExpenses: [ExpenseRecord] {
        guard let range = monthRange else { return [] }
        return expenses.filter { record in
            guard let date = record.createdAt else { return false }
            return date >= range.start && date < range.end
        }
    }
    private var monthTotalExpense: Int { monthExpenses.reduce(0) { $0 + $1.amount } }
    private let genreColors: [ExpenseGenre: Color] = [
        .food: Color(red: 0.96, green: 0.48, blue: 0.25),
        .daily: Color(red: 0.91, green: 0.68, blue: 0.25),
        .transport: Color(red: 0.30, green: 0.57, blue: 0.88),
        .housing: Color(red: 0.48, green: 0.39, blue: 0.86),
        .health: Color(red: 0.94, green: 0.39, blue: 0.48),
        .entertainment: Color(red: 0.20, green: 0.68, blue: 0.68),
        .other: Color(red: 0.56, green: 0.59, blue: 0.64)
    ]
    private var genreTotals: [(genre: ExpenseGenre, amount: Int)] {
        ExpenseGenre.allCases.map { genre in
            (genre, monthExpenses.filter { ($0.genre ?? .other) == genre }.reduce(0) { $0 + $1.amount })
        }.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
    }
    private var monthIntake: Int {
        guard let range = monthRange else { return 0 }
        return foods.filter { record in
            guard let date = record.createdAt else { return false }
            return date >= range.start && date < range.end
        }.reduce(0) { $0 + $1.calories }
    }
    private func intake(on day: Date) -> Int {
        intakeByDay[calendar.startOfDay(for: day), default: 0]
    }
    private func expenses(on day: Date) -> Int {
        expenseByDay[calendar.startOfDay(for: day), default: 0]
    }
    private func burn(on day: Date) -> Int {
        healthBurnByDay[calendar.startOfDay(for: day)] ?? manualBurnByDay[calendar.startOfDay(for: day), default: 0]
    }
    private var monthBurn: Int { monthDays.reduce(0) { $0 + burn(on: $1) } }
    private var monthDifference: Int { monthIntake - monthBurn }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthPicker
                    VStack(alignment: .leading, spacing: 14) {
                        reportTitle("支出ジャンル別", icon: "yensign.circle.fill", color: Color(red: 0.26, green: 0.66, blue: 0.49))
                        HStack {
                            Text("今月の支出合計")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(monthTotalExpense, format: .currency(code: "JPY").precision(.fractionLength(0)))
                                .font(.title3.bold())
                        }
                        if genreTotals.isEmpty {
                            Text("この月の支出記録はありません")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 14) {
                                Chart {
                                    ForEach(Array(genreTotals.enumerated()), id: \.offset) { entry in
                                        SectorMark(
                                            angle: .value("金額", entry.element.amount),
                                            innerRadius: .ratio(0.64),
                                            angularInset: 2
                                        )
                                        .foregroundStyle(genreColors[entry.element.genre] ?? .gray)
                                    }
                                }
                                .chartLegend(.hidden)
                                .frame(width: 150, height: 150)
                                .overlay {
                                    VStack(spacing: 2) {
                                        Text("合計").font(.caption2).foregroundStyle(.secondary)
                                        Text(monthTotalExpense, format: .currency(code: "JPY").precision(.fractionLength(0)))
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .minimumScaleFactor(0.7)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 90)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(genreTotals.enumerated()), id: \.offset) { entry in
                                        let item = entry.element
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(genreColors[item.genre] ?? .gray)
                                                .frame(width: 8, height: 8)
                                            Text(item.genre.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            Spacer(minLength: 2)
                                            VStack(alignment: .trailing, spacing: 1) {
                                                Text(item.amount, format: .currency(code: "JPY").precision(.fractionLength(0)))
                                                    .font(.caption2.weight(.semibold))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.75)
                                                Text("\(Int((Double(item.amount) / Double(monthTotalExpense) * 100).rounded()))%")
                                                    .font(.system(size: 9, design: .rounded))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                        }
                    }
                    .reportCard()

                    VStack(alignment: .leading, spacing: 14) {
                        reportTitle("カロリー収支", icon: "flame.fill", color: Color(red: 0.96, green: 0.48, blue: 0.25))
                        HStack(spacing: 8) {
                            monthCalorieValue("摂取", value: monthIntake, color: Color(red: 0.96, green: 0.48, blue: 0.25))
                            monthCalorieValue("消費", value: monthBurn, color: Color(red: 0.26, green: 0.66, blue: 0.49))
                            monthCalorieValue("差分", value: monthDifference, color: Color(red: 0.30, green: 0.57, blue: 0.88))
                        }
                        HStack(spacing: 12) {
                            Label("摂取 − 消費", systemImage: "equal")
                            Spacer()
                            if isLoadingHealthData { ProgressView().controlSize(.small) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .reportCard()

                    VStack(alignment: .leading, spacing: 12) {
                        reportTitle("日別カレンダー", icon: "calendar", color: Color(red: 0.30, green: 0.57, blue: 0.88))
                        Picker("カレンダー表示", selection: $calendarDisplay) {
                            ForEach(MonthlyCalendarMetric.allCases) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { day in
                                Text(day).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            ForEach(0..<leadingDayCount, id: \.self) { _ in Color.clear.frame(height: 66) }
                            ForEach(monthDays, id: \.self) { day in
                                let difference = intake(on: day) - burn(on: day)
                                let dayExpense = expenses(on: day)
                                let displayValue = calendarDisplay == .calorieDifference
                                    ? (difference > 0 ? "+\(difference)" : "\(difference)")
                                    : "\(dayExpense)"
                                let displayUnit = calendarDisplay == .calorieDifference ? "kcal" : "円"
                                let displayColor: Color = calendarDisplay == .expense
                                    ? Color(red: 0.26, green: 0.66, blue: 0.49)
                                    : (difference > 0 ? .orange : difference < 0 ? .blue : .secondary)
                                VStack(spacing: 4) {
                                    Text("\(calendar.component(.day, from: day))")
                                        .font(.caption.weight(.semibold))
                                    Text(displayValue)
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .foregroundStyle(displayColor)
                                    Text(displayUnit).font(.system(size: 8)).foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 66)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text(calendarDisplay == .calorieDifference
                             ? "日ごとの差分は、摂取カロリー − 消費カロリーです。ヘルスケアの日別データが取得できない日は手動記録を使います。"
                             : "日ごとの支出記録の合計を表示しています。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .reportCard()
                }
                .padding(16)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.98))
            .navigationTitle("月次レポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .task(id: month) { await loadHealthMonth() }
        }
    }

    private var monthPicker: some View {
        HStack {
            Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
            }
            Spacer()
            Text(month.formatted(.dateTime.locale(Locale(identifier: "ja_JP")).year().month()))
                .font(.title3.bold())
            Spacer()
            Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
            }
            .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .padding(.horizontal, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func reportTitle(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
    }

    private func monthCalorieValue(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .number).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text("kcal").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor
    private func loadHealthMonth() async {
        healthBurnByDay = [:]
        guard useHealthKit, HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let range = monthRange else { return }
        isLoadingHealthData = true
        defer { isLoadingHealthData = false }
        let store = HKHealthStore()
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let anchor = calendar.startOfDay(for: range.start)
        let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
        let results: [Date: Int] = await withCheckedContinuation { continuation in
            query.initialResultsHandler = { _, collection, _ in
                var values: [Date: Int] = [:]
                collection?.enumerateStatistics(from: range.start, to: range.end) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        values[calendar.startOfDay(for: statistics.startDate)] = Int(quantity.doubleValue(for: .kilocalorie()).rounded())
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
        healthBurnByDay = results
    }
}

enum MonthlyCalendarMetric: String, CaseIterable, Identifiable {
    case calorieDifference
    case expense

    var id: String { rawValue }
    var title: String {
        switch self {
        case .calorieDifference: "カロリー差分"
        case .expense: "支出合計"
        }
    }
}
