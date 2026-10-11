import SwiftUI

enum EntrySheet: String, Identifiable {
    case food
    case expense
    case diary
    case mood
    case video
    case calorieBurn

    var id: String { rawValue }
}

struct CalorieBurnRecord: Codable, Equatable {
    let activity: String
    let calories: Int
    let createdAt: Date
}

enum RecordCategory: String, Identifiable {
    case food
    case calorieBurn
    case expense
    case diary
    case mood

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: "食事の記録"
        case .calorieBurn: "消費カロリーの記録"
        case .expense: "家計簿の記録"
        case .diary: "日記の記録"
        case .mood: "気分の記録"
        }
    }
}

enum RecordEditPayload {
    case food(FoodRecord)
    case calorieBurn(CalorieBurnRecord)
    case expense(ExpenseRecord)
    case diary(DiaryRecord)
    case mood(MoodRecord)
}

struct RecordEditItem: Identifiable {
    let sourceIndex: Int
    let title: String
    let detail: String
    let payload: RecordEditPayload

    var id: Int { sourceIndex }
}

struct DiaryRecord: Codable, Equatable {
    let title: String
    let body: String
    let createdAt: Date?
}

struct MoodRecord: Codable, Equatable {
    let mood: String
    let note: String
    let createdAt: Date?
}
