import SwiftUI

struct ExpenseEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (ExpenseRecord) -> Void

    @State private var itemName = ""
    @State private var amountText = ""
    @State private var genre: ExpenseGenre = .other

    private var parsedAmount: Int? {
        Int(amountText)
    }

    private var canSave: Bool {
        !itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && parsedAmount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("支出") {
                    TextField("何に使ったか", text: $itemName)
                    TextField("金額（円）", text: $amountText).keyboardType(.numberPad)
                    Picker("ジャンル", selection: $genre) {
                        ForEach(ExpenseGenre.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
            }
            .navigationTitle("家計簿を記録")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let parsedAmount else { return }

                        let record = ExpenseRecord(
                            name: itemName.trimmingCharacters(in: .whitespacesAndNewlines),
                            amount: parsedAmount,
                            createdAt: .now,
                            genre: genre
                        )
                        onSave(record)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
