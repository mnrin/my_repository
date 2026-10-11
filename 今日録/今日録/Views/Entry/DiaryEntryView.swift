import SwiftUI

struct DiaryEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (DiaryRecord) -> Void

    @State private var title = ""
    @State private var bodyText = ""

    private var canSave: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("タイトル") {
                    TextField("今日のタイトル", text: $title)
                }

                Section("本文") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 180)
                }
            }
            .navigationTitle("日記を書く")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let record = DiaryRecord(
                            title: trimmedTitle.isEmpty ? "今日の日記" : trimmedTitle,
                            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                            createdAt: .now
                        )
                        onSave(record)
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
