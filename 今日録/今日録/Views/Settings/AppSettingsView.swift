import SwiftUI
import UserNotifications

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var proteinGoal: Double
    @Binding private var fatGoal: Double
    @Binding private var carbsGoal: Double
    @Binding private var storedShowCaptureTime: Bool

    @State private var proteinText: String
    @State private var fatText: String
    @State private var carbsText: String
    @State private var showCaptureTime = true
    @State private var remindersEnabled: Bool
    @State private var breakfastReminderEnabled: Bool
    @State private var lunchReminderEnabled: Bool
    @State private var dinnerReminderEnabled: Bool
    @State private var eveningReminderEnabled: Bool
    @State private var breakfastReminderTime: Date
    @State private var lunchReminderTime: Date
    @State private var dinnerReminderTime: Date
    @State private var eveningReminderTime: Date
    @State private var isShowingNotificationSettingsAlert = false

    init(
        proteinGoal: Binding<Double>,
        fatGoal: Binding<Double>,
        carbsGoal: Binding<Double>,
        showCaptureTime: Binding<Bool>
    ) {
        _proteinGoal = proteinGoal
        _fatGoal = fatGoal
        _carbsGoal = carbsGoal
        _storedShowCaptureTime = showCaptureTime
        _proteinText = State(initialValue: String(proteinGoal.wrappedValue))
        _fatText = State(initialValue: String(fatGoal.wrappedValue))
        _carbsText = State(initialValue: String(carbsGoal.wrappedValue))
        _showCaptureTime = State(initialValue: showCaptureTime.wrappedValue)

        let defaults = UserDefaults.standard
        _remindersEnabled = State(initialValue: defaults.bool(forKey: "dailyRemindersEnabled"))
        _breakfastReminderEnabled = State(initialValue: Self.boolValue(forKey: "breakfastReminderEnabled", default: true))
        _lunchReminderEnabled = State(initialValue: Self.boolValue(forKey: "lunchReminderEnabled", default: true))
        _dinnerReminderEnabled = State(initialValue: Self.boolValue(forKey: "dinnerReminderEnabled", default: true))
        _eveningReminderEnabled = State(initialValue: Self.boolValue(forKey: "eveningReminderEnabled", default: true))
        _breakfastReminderTime = State(initialValue: Self.reminderDate(minutesAfterMidnight: defaults.object(forKey: "breakfastReminderMinutes") as? Int ?? 8 * 60))
        _lunchReminderTime = State(initialValue: Self.reminderDate(minutesAfterMidnight: defaults.object(forKey: "lunchReminderMinutes") as? Int ?? 12 * 60 + 30))
        _dinnerReminderTime = State(initialValue: Self.reminderDate(minutesAfterMidnight: defaults.object(forKey: "dinnerReminderMinutes") as? Int ?? 19 * 60))
        _eveningReminderTime = State(initialValue: Self.reminderDate(minutesAfterMidnight: defaults.object(forKey: "eveningReminderMinutes") as? Int ?? 21 * 60))
    }

    private static func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? defaultValue
            : UserDefaults.standard.bool(forKey: key)
    }

    private static func reminderDate(minutesAfterMidnight: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutesAfterMidnight / 60,
            minute: minutesAfterMidnight % 60,
            second: 0,
            of: .now
        ) ?? .now
    }

    private static func minutesAfterMidnight(for date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60
            + Calendar.current.component(.minute, from: date)
    }

    private var canSave: Bool {
        [proteinText, fatText, carbsText].allSatisfy { text in
            guard let value = Double(text) else { return false }
            return value >= 0 && value.isFinite
        }
    }

    private func isValidGoal(_ text: String) -> Bool {
        guard let value = Double(text) else { return false }
        return value >= 0 && value.isFinite
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("PFCの1日目標") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("タンパク質")
                            .font(.subheadline)
                        TextField("g", text: $proteinText)
                            .keyboardType(.decimalPad)
                        if !isValidGoal(proteinText) {
                            goalValidationMessage
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("脂質")
                            .font(.subheadline)
                        TextField("g", text: $fatText)
                            .keyboardType(.decimalPad)
                        if !isValidGoal(fatText) {
                            goalValidationMessage
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("炭水化物")
                            .font(.subheadline)
                        TextField("g", text: $carbsText)
                            .keyboardType(.decimalPad)
                        if !isValidGoal(carbsText) {
                            goalValidationMessage
                        }
                    }
                }
                Section("切り出し動画") {
                    Toggle("撮影時刻を中央に表示", isOn: $showCaptureTime)
                    Text("元動画の日時メタデータがある場合、時刻を白字で動画に入れます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("通知") {
                    Toggle("通知を有効にする", isOn: $remindersEnabled)
                    Text("食事の入力と、その日の記録を振り返る通知を設定できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if remindersEnabled {
                        VStack(spacing: 4) {
                            reminderRow(title: "朝食", isOn: $breakfastReminderEnabled, time: $breakfastReminderTime)
                            reminderRow(title: "昼食", isOn: $lunchReminderEnabled, time: $lunchReminderTime)
                            reminderRow(title: "夕食", isOn: $dinnerReminderEnabled, time: $dinnerReminderTime)
                            reminderRow(title: "夜の記録確認", isOn: $eveningReminderEnabled, time: $eveningReminderTime)
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: remindersEnabled)
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let protein = Double(proteinText),
                              let fat = Double(fatText),
                              let carbs = Double(carbsText) else { return }
                        proteinGoal = protein
                        fatGoal = fat
                        carbsGoal = carbs
                        storedShowCaptureTime = showCaptureTime
                        saveReminderSettings()
                    }
                    .disabled(!canSave)
                }
            }
            .alert("通知を許可してください", isPresented: $isShowingNotificationSettingsAlert) {
                Button("設定を開く") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                Button("あとで", role: .cancel) { dismiss() }
            } message: {
                Text("iPhoneの設定で「今日録」の通知を許可すると、設定したリマインドを受け取れます。")
            }
        }
    }

    private func saveReminderSettings() {
        let defaults = UserDefaults.standard
        defaults.set(remindersEnabled, forKey: "dailyRemindersEnabled")
        defaults.set(breakfastReminderEnabled, forKey: "breakfastReminderEnabled")
        defaults.set(lunchReminderEnabled, forKey: "lunchReminderEnabled")
        defaults.set(dinnerReminderEnabled, forKey: "dinnerReminderEnabled")
        defaults.set(eveningReminderEnabled, forKey: "eveningReminderEnabled")
        defaults.set(Self.minutesAfterMidnight(for: breakfastReminderTime), forKey: "breakfastReminderMinutes")
        defaults.set(Self.minutesAfterMidnight(for: lunchReminderTime), forKey: "lunchReminderMinutes")
        defaults.set(Self.minutesAfterMidnight(for: dinnerReminderTime), forKey: "dinnerReminderMinutes")
        defaults.set(Self.minutesAfterMidnight(for: eveningReminderTime), forKey: "eveningReminderMinutes")

        let preferences = ReminderNotificationPreferences(
            enabled: remindersEnabled,
            breakfastEnabled: breakfastReminderEnabled,
            lunchEnabled: lunchReminderEnabled,
            dinnerEnabled: dinnerReminderEnabled,
            eveningEnabled: eveningReminderEnabled,
            breakfastMinutes: Self.minutesAfterMidnight(for: breakfastReminderTime),
            lunchMinutes: Self.minutesAfterMidnight(for: lunchReminderTime),
            dinnerMinutes: Self.minutesAfterMidnight(for: dinnerReminderTime),
            eveningMinutes: Self.minutesAfterMidnight(for: eveningReminderTime)
        )

        Task {
            let isReady = await ReminderNotificationScheduler.apply(preferences)
            if remindersEnabled && !isReady {
                isShowingNotificationSettingsAlert = true
            } else {
                dismiss()
            }
        }
    }

    private var goalValidationMessage: some View {
        Text("0以上の数値を入力してください。")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func reminderRow(title: String, isOn: Binding<Bool>, time: Binding<Date>) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: isOn)
                .font(.subheadline)
                .toggleStyle(.switch)
                .frame(width: 170, alignment: .leading)

            Spacer(minLength: 0)

            DatePicker("\(title)の通知時刻", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(width: 100, alignment: .trailing)
                .accessibilityLabel("\(title)の通知時刻")
                .disabled(!isOn.wrappedValue)
        }
    }
}
