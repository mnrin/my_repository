import SwiftUI

struct FoodRecord: Codable, Equatable {
    let name: String
    let calories: Int
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let createdAt: Date?
    var source: String? = nil
}

enum NutritionLabelBasis {
    case per100Grams
    case per100Milliliters
    case perServing

    var title: String {
        switch self {
        case .per100Grams: "100gあたり"
        case .per100Milliliters: "100mlあたり"
        case .perServing: "1食・1包装あたり"
        }
    }

    var unit: String {
        switch self {
        case .per100Grams: "g"
        case .per100Milliliters: "ml"
        case .perServing: "食分"
        }
    }
}

struct FoodItem: Codable, Identifiable {
    let id: String
    let name: String
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double
    var brand: String? = nil
    var servingGrams: Double? = nil
    var source: String? = nil

    static func loadFromBundle() -> [FoodItem] {
        guard let url = Bundle.main.url(forResource: "FoodComposition", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let foods = try? JSONDecoder().decode([FoodItem].self, from: data) else {
            return []
        }
        return foods
    }
}
