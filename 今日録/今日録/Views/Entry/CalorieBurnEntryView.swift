import SwiftUI

struct CalorieBurnEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (CalorieBurnRecord) -> Void

    @State private var activity = ""
    @State private var caloriesText = ""

    private var calories: Int? { Int(caloriesText) }
    private var canSave: Bool {
        !activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (calories ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("活動") {
                    TextField("例：ウォーキング", text: $activity)
                    TextField("消費カロリー（kcal）", text: $caloriesText).keyboardType(.numberPad)
                        .keyboardType(.numberPad)
                }
                Section {
                    Text("運動アプリなどで確認した消費カロリーを入力してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("消費カロリー")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let calories else { return }
                        onSave(CalorieBurnRecord(
                            activity: activity.trimmingCharacters(in: .whitespacesAndNewlines),
                            calories: calories,
                            createdAt: .now
                        ))
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
