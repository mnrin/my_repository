import SwiftUI

struct RecordManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editingRecord: RecordEditItem?
    @State private var isEditing = false

    let category: RecordCategory
    let records: [RecordEditItem]
    let onDelete: (Int) -> Void
    let onSave: (Int, RecordEditPayload) -> Void

    var body: some View {
        NavigationStack {
            List {
                if records.isEmpty {
                    ContentUnavailableView("記録はありません", systemImage: "tray")
                } else {
                    ForEach(records) { record in
                        HStack(spacing: 12) {
                            Button {
                                editingRecord = record
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if !record.detail.isEmpty {
                                        Text(record.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if isEditing {
                                Button("削除", role: .destructive) {
                                    onDelete(record.sourceIndex)
                                    dismiss()
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle(category.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if !records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "完了" : "編集") {
                            isEditing.toggle()
                        }
                    }
                }
            }
            .sheet(item: $editingRecord) { record in
                RecordEditView(item: record) { payload in
                    onSave(record.sourceIndex, payload)
                    editingRecord = nil
                }
            }
        }
    }
}

struct RecordEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var nameText: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var carbsText: String
    @State private var amountText: String
    @State private var expenseGenre: ExpenseGenre
    @State private var diaryBody: String
    @State private var moodText: String

    let item: RecordEditItem
    let onSave: (RecordEditPayload) -> Void

    private let moodOptions = ["😄 とても良い", "😊 良い", "😐 ふつう", "😟 少し疲れた", "😢 つらい"]

    init(item: RecordEditItem, onSave: @escaping (RecordEditPayload) -> Void) {
        self.item = item
        self.onSave = onSave
        switch item.payload {
        case .food(let record):
            _nameText = State(initialValue: record.name)
            _caloriesText = State(initialValue: "\(record.calories)")
            _proteinText = State(initialValue: record.protein.map { String($0) } ?? "")
            _fatText = State(initialValue: record.fat.map { String($0) } ?? "")
            _carbsText = State(initialValue: record.carbs.map { String($0) } ?? "")
            _amountText = State(initialValue: "")
            _expenseGenre = State(initialValue: .other)
            _diaryBody = State(initialValue: "")
            _moodText = State(initialValue: "😊 良い")
        case .calorieBurn(let record):
            _nameText = State(initialValue: record.activity)
            _caloriesText = State(initialValue: "\(record.calories)")
            _proteinText = State(initialValue: "")
            _fatText = State(initialValue: "")
            _carbsText = State(initialValue: "")
            _amountText = State(initialValue: "")
            _expenseGenre = State(initialValue: .other)
            _diaryBody = State(initialValue: "")
            _moodText = State(initialValue: "😊 良い")
        case .expense(let record):
            _nameText = State(initialValue: record.name)
            _caloriesText = State(initialValue: "")
            _proteinText = State(initialValue: "")
            _fatText = State(initialValue: "")
            _carbsText = State(initialValue: "")
            _amountText = State(initialValue: "\(record.amount)")
            _expenseGenre = State(initialValue: record.genre ?? .other)
            _diaryBody = State(initialValue: "")
            _moodText = State(initialValue: "😊 良い")
        case .diary(let record):
            _nameText = State(initialValue: record.title)
            _caloriesText = State(initialValue: "")
            _proteinText = State(initialValue: "")
            _fatText = State(initialValue: "")
            _carbsText = State(initialValue: "")
            _amountText = State(initialValue: "")
            _expenseGenre = State(initialValue: .other)
            _diaryBody = State(initialValue: record.body)
            _moodText = State(initialValue: "😊 良い")
        case .mood(let record):
            _nameText = State(initialValue: "")
            _caloriesText = State(initialValue: "")
            _proteinText = State(initialValue: "")
            _fatText = State(initialValue: "")
            _carbsText = State(initialValue: "")
            _amountText = State(initialValue: "")
            _expenseGenre = State(initialValue: .other)
            _diaryBody = State(initialValue: record.note)
            _moodText = State(initialValue: record.mood)
        }
    }

    private var canSave: Bool {
        switch item.payload {
        case .food:
            return !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (Int(caloriesText) ?? -1) >= 0
                && [proteinText, fatText, carbsText].allSatisfy { $0.isEmpty || Double($0) != nil }
        case .calorieBurn:
            return !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Int(caloriesText) ?? 0) > 0
        case .expense:
            return !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Int(amountText) != nil
        case .diary:
            return !diaryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .mood:
            return true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch item.payload {
                case .food:
                    Section("食事") {
                        TextField("食べたもの", text: $nameText)
                        TextField("カロリー（kcal）", text: $caloriesText).keyboardType(.numberPad)
                    }
                    Section("栄養成分（任意）") {
                        TextField("タンパク質（g）", text: $proteinText).keyboardType(.decimalPad)
                        TextField("脂質（g）", text: $fatText).keyboardType(.decimalPad)
                        TextField("炭水化物（g）", text: $carbsText).keyboardType(.decimalPad)
                    }
                case .calorieBurn:
                    Section("活動") {
                        TextField("活動", text: $nameText)
                        TextField("消費カロリー（kcal）", text: $caloriesText).keyboardType(.numberPad)
                    }
                case .expense:
                    Section("支出") {
                        TextField("何に使ったか", text: $nameText)
                        TextField("金額（円）", text: $amountText).keyboardType(.numberPad)
                        Picker("ジャンル", selection: $expenseGenre) {
                            ForEach(ExpenseGenre.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                case .diary:
                    Section("タイトル") { TextField("タイトル", text: $nameText) }
                    Section("本文") { TextEditor(text: $diaryBody).frame(minHeight: 180) }
                case .mood:
                    Section("気分") {
                        Picker("気分", selection: $moodText) {
                            ForEach(moodOptions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Section("メモ") { TextEditor(text: $diaryBody).frame(minHeight: 120) }
                }
            }
            .navigationTitle("記録を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveChanges() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func saveChanges() {
        let cleanedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: RecordEditPayload
        switch item.payload {
        case .food(let old):
            guard let calories = Int(caloriesText) else { return }
            payload = .food(FoodRecord(name: cleanedName, calories: calories, protein: Double(proteinText), fat: Double(fatText), carbs: Double(carbsText), createdAt: old.createdAt, source: old.source))
        case .calorieBurn(let old):
            guard let calories = Int(caloriesText) else { return }
            payload = .calorieBurn(CalorieBurnRecord(activity: cleanedName, calories: calories, createdAt: old.createdAt))
        case .expense(let old):
            guard let amount = Int(amountText) else { return }
            payload = .expense(ExpenseRecord(name: cleanedName, amount: amount, createdAt: old.createdAt, genre: expenseGenre))
        case .diary(let old):
            payload = .diary(DiaryRecord(title: cleanedName.isEmpty ? "今日の日記" : cleanedName, body: diaryBody.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: old.createdAt))
        case .mood(let old):
            payload = .mood(MoodRecord(mood: moodText, note: diaryBody.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: old.createdAt))
        }
        onSave(payload)
        dismiss()
    }
}
