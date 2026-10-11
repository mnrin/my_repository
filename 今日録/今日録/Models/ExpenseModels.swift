import SwiftUI

enum ExpenseGenre: String, CaseIterable, Codable, Identifiable {
    case food, daily, transport, housing, health, entertainment, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .food: "食費"
        case .daily: "日用品"
        case .transport: "交通費"
        case .housing: "住居・光熱費"
        case .health: "医療・健康"
        case .entertainment: "娯楽"
        case .other: "その他"
        }
    }
}

struct ExpenseRecord: Codable, Equatable {
    let name: String
    let amount: Int
    let createdAt: Date?
    var genre: ExpenseGenre? = .other
}
