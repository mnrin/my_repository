import SwiftUI
import PhotosUI
import UIKit
import Vision

struct FoodEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (FoodRecord) -> Void

    @State private var isManualEntry = false
    @State private var searchText = ""
    @State private var foods = FoodItem.loadFromBundle()
    @State private var commercialFoods: [FoodItem] = []
    @State private var isSearchingCommercialFoods = false
    @State private var commercialSearchMessage: String?
    @State private var isShowingBarcodeScanner = false
    @State private var barcodeScanMessage: String?
    @State private var selectedFood: FoodItem?
    @State private var amountText = "100"
    @State private var manualFoodName = ""
    @State private var manualCaloriesText = ""
    @State private var manualProteinText = ""
    @State private var manualFatText = ""
    @State private var manualCarbsText = ""
    @State private var isShowingNutritionCamera = false
    @State private var selectedNutritionPhoto: PhotosPickerItem?
    @State private var nutritionLabelBasis: NutritionLabelBasis?
    @State private var manualUnitAmountText = "1"
    @State private var nutritionOCRMessage: String?

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        if isManualEntry {
            let hasName = !manualFoodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasValidCalories = Int(manualCaloriesText).map { $0 >= 0 } ?? false
            let optionalMacrosAreValid = [manualProteinText, manualFatText, manualCarbsText].allSatisfy { text in
                text.isEmpty || (Double(text).map { $0 >= 0 } ?? false)
            }
            let validAmount = nutritionLabelBasis == nil || (Double(manualUnitAmountText).map { $0 > 0 } ?? false)
            return hasName && hasValidCalories && optionalMacrosAreValid && validAmount
        }
        return selectedFood != nil && (amount ?? 0) > 0
    }

    private var manualScale: Double {
        guard nutritionLabelBasis != nil,
              let value = Double(manualUnitAmountText.replacingOccurrences(of: ",", with: ".")) else { return 1 }
        switch nutritionLabelBasis {
        case .per100Grams, .per100Milliliters: return value / 100
        case .perServing: return value
        case nil: return 1
        }
    }

    @MainActor
    private func recognizeNutritionLabel(_ image: UIImage) async {
        nutritionOCRMessage = "栄養成分表示を読み取り中…"
        guard let cgImage = image.cgImage else {
            nutritionOCRMessage = "画像を読み込めませんでした。"
            return
        }

        do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ja-JP", "en-US"]
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
            guard let calories = Self.readNutrient(from: lines, labels: ["エネルギー", "熱量", "energy"]) else {
                nutritionOCRMessage = "カロリーを読み取れませんでした。表示が正面に写るよう撮り直してください。"
                return
            }

            manualCaloriesText = String(Int(calories.rounded()))
            manualProteinText = Self.readNutrient(from: lines, labels: ["たんぱく質", "タンパク質", "たん白質", "protein"]).map(Self.decimalText) ?? ""
            manualFatText = Self.readNutrient(from: lines, labels: ["脂質", "fat"]).map(Self.decimalText) ?? ""
            manualCarbsText = Self.readNutrient(from: lines, labels: ["炭水化物", "carbohydrate", "carbs"]).map(Self.decimalText) ?? ""

            let normalized = lines.joined(separator: " ").lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "　", with: "")
            if normalized.range(of: #"100\s*(?:g|ｇ|グラム)\s*(?:あたり|当たり|につき|あたり)"#, options: .regularExpression) != nil {
                nutritionLabelBasis = .per100Grams
                manualUnitAmountText = "100"
            } else if normalized.range(of: #"100\s*(?:ml|ｍｌ|ミリリットル)\s*(?:あたり|当たり|につき)"#, options: .regularExpression) != nil {
                nutritionLabelBasis = .per100Milliliters
                manualUnitAmountText = "100"
            } else {
                nutritionLabelBasis = .perServing
                manualUnitAmountText = "1"
            }

            let missing = [
                (manualProteinText.isEmpty, "たんぱく質"),
                (manualFatText.isEmpty, "脂質"),
                (manualCarbsText.isEmpty, "炭水化物")
            ].filter(\.0).map(\.1)
            nutritionOCRMessage = missing.isEmpty
                ? "読み取りました。商品名と数値を表示ラベルと照合してください。"
                : "読み取りました。\(missing.joined(separator: "・"))は手入力して確認してください。"
            isManualEntry = true
        } catch {
            nutritionOCRMessage = "文字を読み取れませんでした。明るい場所で撮り直してください。"
        }
    }

    private static func readNutrient(from lines: [String], labels: [String]) -> Double? {
        let numberPattern = #"([0-9]+(?:[.,][0-9]+)?)\s*(?:kcal|kJ|g|ｇ)?"#
        for (index, line) in lines.enumerated() {
            guard let labelRange = labels.compactMap({ line.range(of: $0, options: .caseInsensitive) }).first else { continue }
            let trailing = String(line[labelRange.upperBound...])
            if let value = firstNumber(in: trailing, pattern: numberPattern) { return value }
            if index + 1 < lines.count,
               !labels.contains(where: { lines[index + 1].range(of: $0, options: .caseInsensitive) != nil }),
               let value = firstNumber(in: lines[index + 1], pattern: numberPattern) {
                return value
            }
        }
        return nil
    }

    private static func firstNumber(in text: String, pattern: String) -> Double? {
        guard let range = text.range(of: pattern, options: .regularExpression),
              let numberRange = text[range].range(of: #"[0-9]+(?:[.,][0-9]+)?"#, options: .regularExpression) else { return nil }
        return Double(String(text[numberRange]).replacingOccurrences(of: ",", with: "."))
    }

    private static func decimalText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private var searchResults: [FoodItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let searchTerms = (query == "ごはん" || query == "白米")
            ? [query, "めし", "精白米"]
            : [query]
        return Array(
            foods.lazy
                .filter { food in
                    searchTerms.contains { food.name.localizedStandardContains($0) }
                }
                .prefix(40)
        )
    }

    @MainActor
    private func searchCommercialFoods() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            commercialSearchMessage = "商品名を入力してください。"
            commercialFoods = []
            return
        }

        isSearchingCommercialFoods = true
        commercialSearchMessage = nil
        commercialFoods = []
        defer { isSearchingCommercialFoods = false }

        guard var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl") else {
            commercialSearchMessage = "商品検索を開始できませんでした。"
            return
        }
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "lc", value: "ja"),
            URLQueryItem(name: "cc", value: "jp"),
            URLQueryItem(name: "page_size", value: "30"),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_ja,brands,quantity,serving_size,serving_quantity,serving_quantity_unit,nutriments,lc,countries_tags")
        ]
        guard let url = components.url else {
            commercialSearchMessage = "商品検索を開始できませんでした。"
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Kyoroku/1.0 (iOS food log app)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let products = json["products"] as? [[String: Any]] else {
                commercialSearchMessage = "商品データを取得できませんでした。通信状況をご確認ください。"
                return
            }

            commercialFoods = products.compactMap(Self.foodItem(from:))

            if commercialFoods.isEmpty {
                commercialSearchMessage = "栄養成分がそろった商品は見つかりませんでした。手動入力も利用できます。"
            }
        } catch {
            commercialSearchMessage = "商品検索に失敗しました。時間をおいてもう一度お試しください。"
        }
    }

    @MainActor
    private func searchCommercialFood(barcode: String) async {
        isSearchingCommercialFoods = true
        commercialSearchMessage = nil
        commercialFoods = []
        defer { isSearchingCommercialFoods = false }

        guard let encodedBarcode = barcode.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: "https://world.openfoodfacts.org/api/v3/product/\(encodedBarcode)") else {
            commercialSearchMessage = "バーコードを確認できませんでした。"
            return
        }
        components.queryItems = [URLQueryItem(name: "fields", value: "code,product_name,product_name_ja,brands,quantity,serving_size,serving_quantity,serving_quantity_unit,nutriments")]
        guard let url = components.url else {
            commercialSearchMessage = "商品検索を開始できませんでした。"
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Kyoroku/1.0 (iOS food log app)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["status"] as? Int) == 1,
                  let product = json["product"] as? [String: Any],
                  let food = Self.foodItem(from: product) else {
                commercialSearchMessage = "商品が見つからないか、栄養成分が不足しています。商品名検索または手動入力をお試しください。"
                return
            }
            commercialFoods = [food]
            selectedFood = food
            if let servingGrams = food.servingGrams, servingGrams > 0 {
                amountText = String(Int(servingGrams.rounded()))
            }
            commercialSearchMessage = "バーコード \(barcode) の商品です。内容を確認してください。"
        } catch {
            commercialSearchMessage = "商品検索に失敗しました。通信状況をご確認ください。"
        }
    }

    private static func foodItem(from product: [String: Any]) -> FoodItem? {
        guard let code = product["code"] as? String,
              let nutriments = product["nutriments"] as? [String: Any],
              let calories = nutrientValue(nutriments, key: "energy-kcal_100g"),
              let protein = nutrientValue(nutriments, key: "proteins_100g"),
              let fat = nutrientValue(nutriments, key: "fat_100g"),
              let carbs = nutrientValue(nutriments, key: "carbohydrates_100g") else { return nil }

        let productName = ["product_name_ja", "product_name"]
            .compactMap { product[$0] as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let productName else { return nil }
        let brand = (product["brands"] as? String)?
            .components(separatedBy: ",")
            .first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = [brand, productName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "　")
        let servingGrams = (product["serving_quantity_unit"] as? String == "g"
            ? numericValue(product["serving_quantity"])
            : nil)
            ?? gramsValue(from: product["serving_size"] as? String)
            ?? gramsValue(from: product["quantity"] as? String)

        return FoodItem(
            id: "off-\(code)", name: displayName, calories: calories,
            protein: protein, fat: fat, carbs: carbs, brand: brand,
            servingGrams: servingGrams, source: "Open Food Facts"
        )
    }

    private static func nutrientValue(_ values: [String: Any], key: String) -> Double? {
        guard let value = numericValue(values[key]), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func gramsValue(from text: String?) -> Double? {
        guard let text,
              let gramsRange = text.range(
                of: #"[0-9]+(?:[.,][0-9]+)?\s*(?:g|グラム)"#,
                options: [.regularExpression, .caseInsensitive]
              ),
              let numberRange = text[gramsRange].range(of: #"[0-9]+(?:[.,][0-9]+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(String(text[numberRange]).replacingOccurrences(of: ",", with: "."))
    }

    private func scaled(_ value: Double) -> Double {
        value * (amount ?? 0) / 100
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("入力方法") {
                    Picker("入力方法", selection: $isManualEntry) {
                        Text("食品検索").tag(false)
                        Text("手動入力").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if isManualEntry {
                    Section("栄養成分表示を読み取る") {
                        Button {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                isShowingNutritionCamera = true
                            } else {
                                nutritionOCRMessage = "この端末ではカメラを使えません。写真から選択してください。"
                            }
                        } label: {
                            Label("カメラで撮影して読み取る", systemImage: "camera.viewfinder")
                        }

                        PhotosPicker(selection: $selectedNutritionPhoto, matching: .images) {
                            Label("写真から読み取る", systemImage: "photo")
                        }

                        if let nutritionLabelBasis {
                            LabeledContent("ラベルの表示基準", value: nutritionLabelBasis.title)
                            TextField("今回食べた量（\(nutritionLabelBasis.unit)）", text: $manualUnitAmountText)
                                .keyboardType(.decimalPad)
                            Text("読み取った栄養値を表示基準に合わせて換算します。保存前にパッケージと照合してください。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let nutritionOCRMessage {
                            Text(nutritionOCRMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("食事") {
                        TextField("食べたもの", text: $manualFoodName)
                        TextField("カロリー（kcal）", text: $manualCaloriesText).keyboardType(.numberPad)
                    }

                    Section("栄養成分（任意）") {
                        TextField("タンパク質（g）", text: $manualProteinText).keyboardType(.decimalPad)
                        TextField("脂質（g）", text: $manualFatText).keyboardType(.decimalPad)
                        TextField("炭水化物（g）", text: $manualCarbsText).keyboardType(.decimalPad)
                        Text("空欄の栄養素はPFC合計に加算されません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("食品を検索") {
                        TextField("例：ごはん、鶏肉、りんご", text: $searchText)

                        if !searchText.isEmpty {
                            if searchResults.isEmpty {
                                Text("食品が見つかりません。手動入力も利用できます。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(searchResults) { food in
                                    Button {
                                        selectedFood = food
                                    } label: {
                                        HStack {
                                            Text(food.name)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            if selectedFood?.id == food.id {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.tint)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Section("市販品を検索") {
                        Button {
                            barcodeScanMessage = nil
                            selectedFood = nil
                            commercialFoods = []
                            isShowingBarcodeScanner = true
                        } label: {
                            Label("バーコードを読み取る", systemImage: "barcode.viewfinder")
                        }

                        Button {
                            Task { await searchCommercialFoods() }
                        } label: {
                            if isSearchingCommercialFoods {
                                ProgressView("商品を検索中…")
                            } else {
                                Label("Open Food Factsで検索", systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(isSearchingCommercialFoods || searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Text("検索語はOpen Food Factsへ送信されます。商品情報は利用者投稿のため、栄養値を商品パッケージと照合してください。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let barcodeScanMessage {
                            Text(barcodeScanMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let commercialSearchMessage {
                            Text(commercialSearchMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(commercialFoods) { food in
                            Button {
                                selectedFood = food
                                if let servingGrams = food.servingGrams, servingGrams > 0 {
                                    amountText = String(Int(servingGrams.rounded()))
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(food.name)
                                            .foregroundStyle(.primary)
                                        Spacer(minLength: 4)
                                        if selectedFood?.id == food.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                    Text("100gあたり \(Int(food.calories.rounded())) kcal" + (food.servingGrams.map { "　\(Int($0.rounded()))g目安" } ?? ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let selectedFood {
                        Section("食べた量") {
                            LabeledContent("選択した食品", value: selectedFood.name)
                            if let source = selectedFood.source {
                                LabeledContent("データ元", value: source)
                            }
                            TextField("量（g）", text: $amountText).keyboardType(.decimalPad)
                        }

                        Section("自動計算（\(amount ?? 0, specifier: "%.0f") g）") {
                            LabeledContent("カロリー", value: "\(Int(scaled(selectedFood.calories).rounded())) kcal")
                            LabeledContent("タンパク質", value: "\(String(format: "%.1f", scaled(selectedFood.protein))) g")
                            LabeledContent("脂質", value: "\(String(format: "%.1f", scaled(selectedFood.fat))) g")
                            LabeledContent("炭水化物", value: "\(String(format: "%.1f", scaled(selectedFood.carbs))) g")
                        }
                    }

                    Section {
                        Text("食品成分データ：日本食品標準成分表（八訂）増補2023年")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: selectedNutritionPhoto) { _, item in
                guard let item else { return }
                Task {
                    defer { selectedNutritionPhoto = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        nutritionOCRMessage = "写真を読み込めませんでした。"
                        return
                    }
                    await recognizeNutritionLabel(image)
                }
            }
            .sheet(isPresented: $isShowingNutritionCamera) {
                NutritionLabelCameraPicker { image in
                    isShowingNutritionCamera = false
                    guard let image else { return }
                    Task { await recognizeNutritionLabel(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: searchText) { _, _ in
                commercialFoods = []
                commercialSearchMessage = nil
            }
            .sheet(isPresented: $isShowingBarcodeScanner) {
                NavigationStack {
                    BarcodeScannerScreen { barcode in
                        isShowingBarcodeScanner = false
                        Task { await searchCommercialFood(barcode: barcode) }
                    }
                    .navigationTitle("バーコード読み取り")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { isShowingBarcodeScanner = false }
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .navigationTitle("食事を記録")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if isManualEntry {
                            guard let calories = Int(manualCaloriesText) else { return }
                            let name = manualFoodName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let recordedName: String
                            if let nutritionLabelBasis {
                                let unitAmount = Double(manualUnitAmountText.replacingOccurrences(of: ",", with: ".")) ?? 0
                                recordedName = "\(name)（\(Self.decimalText(unitAmount))\(nutritionLabelBasis.unit)）"
                            } else {
                                recordedName = name
                            }
                            let record = FoodRecord(
                                name: recordedName,
                                calories: Int((Double(calories) * manualScale).rounded()),
                                protein: Double(manualProteinText).map { $0 * manualScale },
                                fat: Double(manualFatText).map { $0 * manualScale },
                                carbs: Double(manualCarbsText).map { $0 * manualScale },
                                createdAt: .now,
                                source: nutritionLabelBasis == nil ? nil : "栄養成分表示（OCR読み取り・確認済み）"
                            )
                            onSave(record)
                        } else {
                            guard let selectedFood, let amount, amount > 0 else { return }
                            let record = FoodRecord(
                                name: "\(selectedFood.name) \(Int(amount.rounded()))g",
                                calories: Int(scaled(selectedFood.calories).rounded()),
                                protein: scaled(selectedFood.protein),
                                fat: scaled(selectedFood.fat),
                                carbs: scaled(selectedFood.carbs),
                                createdAt: .now,
                                source: selectedFood.source
                            )
                            onSave(record)
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
