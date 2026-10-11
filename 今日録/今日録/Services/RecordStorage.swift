import Foundation

/// UserDefaults への記録の保存・読み込みを一箇所にまとめた簡易ストレージ。
enum RecordStorage {
    enum Key {
        static let food = "foodRecords"
        static let expense = "expenseRecords"
        static let diary = "diaryRecords"
        static let mood = "moodRecords"
        static let video = "videoRecords"
        static let calorieBurn = "calorieBurnRecords"
    }

    static func load<T: Decodable>(_ key: String) -> [T]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }

    static func save<T: Encodable>(_ records: [T], forKey key: String) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
