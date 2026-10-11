import SwiftUI

struct MoodEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var noteIsFocused: Bool

    let onSave: (MoodRecord) -> Void

    @State private var selectedMood = "😊 良い"
    @State private var note = ""

    private let moods = [
        "😄 とても良い",
        "😊 良い",
        "😐 ふつう",
        "😟 少し疲れた",
        "😢 つらい"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("今日の気分") {
                    Picker("気分", selection: $selectedMood) {
                        ForEach(moods, id: \.self) { mood in
                            Text(mood).tag(mood)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("メモ（任意）") {
                    TextEditor(text: $note)
                        .frame(minHeight: 120)
                        .focused($noteIsFocused)
                }
            }
            .navigationTitle("気分を記録")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        noteIsFocused = false
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let record = MoodRecord(
                            mood: selectedMood,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                            createdAt: .now
                        )
                        noteIsFocused = false
                        onSave(record)
                        dismiss()
                    }
                }
            }
        }
    }
}
