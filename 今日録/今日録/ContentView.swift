import SwiftUI
import Charts
import AVKit
import AVFoundation
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import VisionKit
import Vision
import UserNotifications

struct ContentView: View {
    @State private var showRecordMenu = false
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var activeSheet: EntrySheet?
    @State private var activeRecordCategory: RecordCategory?
    @State private var isShowingAppSettings = false
    @State private var isShowingMonthlyReport = false
    @State private var videoToTrim: VideoRecord?
    @State private var videoPendingDeletion: VideoRecord?
    @State private var isShowingVideoDeleteConfirmation = false
    @State private var videoDeleteError: String?
    @State private var isVideoListExpanded = false
    @State private var isTrimmedVideoListExpanded = false
    @State private var isMergedVideoListExpanded = false
    @State private var isClassifyingLegacyVideos = false
    @State private var isMergingVideos = false
    @State private var videoMergeError: String?
    @State private var exportingVideoIDs: Set<UUID> = []
    @State private var videoExportMessages: [UUID: String] = [:]
    @State private var expenseRecords: [ExpenseRecord] = []
    @State private var diaryRecords: [DiaryRecord] = []
    @State private var moodRecords: [MoodRecord] = []
    @State private var videoRecords: [VideoRecord] = []
    @State private var calorieBurnRecords: [CalorieBurnRecord] = []
    @State private var healthActiveCalories: Int?
    @State private var healthKitMessage: String?
    @AppStorage("healthKitLinked") private var hasRequestedHealthKitAccess = false
    @AppStorage("proteinGoal") private var proteinGoal = 120.0
    @AppStorage("fatGoal") private var fatGoal = 60.0
    @AppStorage("carbsGoal") private var carbsGoal = 250.0
    @AppStorage("showCaptureTimeOnTrimmedVideos") private var showCaptureTimeOnTrimmedVideos = true

    private var selectedExpenseRecords: [ExpenseRecord] {
        expenseRecords.filter { record in
            guard let createdAt = record.createdAt else { return true }
            return Calendar.current.isDate(createdAt, inSameDayAs: selectedDate)
        }
    }

    private var selectedDiaryRecords: [DiaryRecord] {
        diaryRecords.filter { record in
            guard let createdAt = record.createdAt else { return true }
            return Calendar.current.isDate(createdAt, inSameDayAs: selectedDate)
        }
    }

    private var selectedMoodRecords: [MoodRecord] {
        moodRecords.filter { record in
            guard let createdAt = record.createdAt else { return true }
            return Calendar.current.isDate(createdAt, inSameDayAs: selectedDate)
        }
    }

    private func recordItems(for category: RecordCategory) -> [RecordEditItem] {
        switch category {
        case .food:
            return foodRecords.enumerated().compactMap { entry in
                let index = entry.offset
                let record = entry.element
                guard record.createdAt.map({ Calendar.current.isDate($0, inSameDayAs: selectedDate) }) ?? true else { return nil }
                return RecordEditItem(sourceIndex: index, title: record.name, detail: "\(record.calories) kcal", payload: .food(record))
            }
        case .calorieBurn:
            return calorieBurnRecords.enumerated().compactMap { entry in
                let index = entry.offset
                let record = entry.element
                guard Calendar.current.isDate(record.createdAt, inSameDayAs: selectedDate) else { return nil }
                return RecordEditItem(sourceIndex: index, title: record.activity, detail: "\(record.calories) kcal", payload: .calorieBurn(record))
            }
        case .expense:
            return expenseRecords.enumerated().compactMap { entry in
                let index = entry.offset
                let record = entry.element
                guard record.createdAt.map({ Calendar.current.isDate($0, inSameDayAs: selectedDate) }) ?? true else { return nil }
                return RecordEditItem(sourceIndex: index, title: record.name, detail: "¥\(record.amount)・\(record.genre?.title ?? ExpenseGenre.other.title)", payload: .expense(record))
            }
        case .diary:
            return diaryRecords.enumerated().compactMap { entry in
                let index = entry.offset
                let record = entry.element
                guard record.createdAt.map({ Calendar.current.isDate($0, inSameDayAs: selectedDate) }) ?? true else { return nil }
                return RecordEditItem(sourceIndex: index, title: record.title, detail: String(record.body.prefix(60)), payload: .diary(record))
            }
        case .mood:
            return moodRecords.enumerated().compactMap { entry in
                let index = entry.offset
                let record = entry.element
                guard record.createdAt.map({ Calendar.current.isDate($0, inSameDayAs: selectedDate) }) ?? true else { return nil }
                return RecordEditItem(sourceIndex: index, title: record.mood, detail: record.note, payload: .mood(record))
            }
        }
    }

    private func deleteRecord(_ category: RecordCategory, at index: Int) {
        switch category {
        case .food:
            var records = foodRecords
            records.remove(at: index)
            foodRecords = records
        case .calorieBurn:
            var records = calorieBurnRecords
            records.remove(at: index)
            calorieBurnRecords = records
        case .expense:
            var records = expenseRecords
            records.remove(at: index)
            expenseRecords = records
        case .diary:
            var records = diaryRecords
            records.remove(at: index)
            diaryRecords = records
        case .mood:
            var records = moodRecords
            records.remove(at: index)
            moodRecords = records
        }
    }

    private func updateRecord(_ category: RecordCategory, at index: Int, with payload: RecordEditPayload) {
        switch (category, payload) {
        case let (.food, .food(record)): foodRecords[index] = record
        case let (.calorieBurn, .calorieBurn(record)): calorieBurnRecords[index] = record
        case let (.expense, .expense(record)): expenseRecords[index] = record
        case let (.diary, .diary(record)): diaryRecords[index] = record
        case let (.mood, .mood(record)): moodRecords[index] = record
        default: break
        }
    }

    private var selectedVideoRecords: [VideoRecord] {
        videoRecords.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: selectedDate) }
    }

    private var selectedOriginalVideos: [VideoRecord] {
        selectedVideoRecords.filter { $0.isTrimmed != true && $0.isMerged != true }
    }

    private var selectedTrimmedVideos: [VideoRecord] {
        selectedVideoRecords.filter { $0.isTrimmed == true && $0.isMerged != true }
    }

    private var selectedMergedVideos: [VideoRecord] {
        selectedVideoRecords.filter { $0.isMerged == true }
    }

    private var selectedExpenseTotal: Int {
        selectedExpenseRecords.reduce(0) { $0 + $1.amount }
    }

    private var selectedCalorieBurnRecords: [CalorieBurnRecord] {
        calorieBurnRecords.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: selectedDate) }
    }

    private var burnedCalories: Int {
        healthActiveCalories ?? selectedCalorieBurnRecords.reduce(0) { $0 + $1.calories }
    }
    @State private var foodRecords: [FoodRecord] = []

    private var selectedFoodRecords: [FoodRecord] {
        foodRecords.filter { record in
            guard let createdAt = record.createdAt else { return true }
            return Calendar.current.isDate(createdAt, inSameDayAs: selectedDate)
        }
    }

    private var isShowingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var selectedDateLabel: String {
        isShowingToday
            ? "今日"
            : selectedDate.formatted(.dateTime.locale(Locale(identifier: "ja_JP")).month().day())
    }

    private func moveSelectedDate(by days: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = Calendar.current.startOfDay(for: newDate)
    }

    private var intakeCalories: Int {
        selectedFoodRecords.reduce(0) { $0 + $1.calories }
    }

    private var calorieDifference: Int { intakeCalories - burnedCalories }

    private var hasCalorieEntries: Bool {
        !selectedFoodRecords.isEmpty || !selectedCalorieBurnRecords.isEmpty || healthActiveCalories != nil
    }

    private var calorieDifferenceColor: Color {
        if calorieDifference == 0 { return mutedBlue.opacity(0.7) }
        return calorieDifference < 0 ? mutedCoral : mutedOrange
    }

    private func requestHealthKitAccessAndRefresh() {
        guard HKHealthStore.isHealthDataAvailable(),
              let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            healthKitMessage = "ヘルスケアはこの端末では利用できません。"
            return
        }

        let store = HKHealthStore()
        store.requestAuthorization(toShare: [], read: [energyType]) { _, error in
            if let error {
                Task { @MainActor in
                    healthKitMessage = "ヘルスケアに接続できませんでした。"
                    print("HealthKit authorization error: \(error.localizedDescription)")
                }
                return
            }

            Task { @MainActor in
                hasRequestedHealthKitAccess = true
                fetchHealthKitActiveEnergy(using: store, quantityType: energyType)
            }
        }
    }

    private func refreshHealthKitActiveEnergy() {
        guard HKHealthStore.isHealthDataAvailable(),
              let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            healthKitMessage = "ヘルスケアはこの端末では利用できません。"
            return
        }
        fetchHealthKitActiveEnergy(using: HKHealthStore(), quantityType: energyType)
    }

    private func fetchHealthKitActiveEnergy(using store: HKHealthStore, quantityType: HKQuantityType) {
        let start = Calendar.current.startOfDay(for: selectedDate)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            Task { @MainActor in
                if error != nil {
                    healthKitMessage = "ヘルスケアのデータを読み込めませんでした。"
                    healthActiveCalories = nil
                    return
                }
                let total = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                healthActiveCalories = Int(total.rounded())
                healthKitMessage = "ヘルスケアのアクティブエネルギーを使用中"
            }
        }
        store.execute(query)
    }

    private var totalProtein: Double {
        selectedFoodRecords.reduce(0) { $0 + ($1.protein ?? 0) }
    }

    private var totalFat: Double {
        selectedFoodRecords.reduce(0) { $0 + ($1.fat ?? 0) }
    }

    private var totalCarbs: Double {
        selectedFoodRecords.reduce(0) { $0 + ($1.carbs ?? 0) }
    }
    
    private func saveDiaryRecords(_ records: [DiaryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "diaryRecords")
    }
    
    private let orange = Color(red: 0.96, green: 0.48, blue: 0.25)
    private let purple = Color(red: 0.48, green: 0.39, blue: 0.86)
    private let blue = Color(red: 0.30, green: 0.57, blue: 0.88)
    private let green = Color(red: 0.26, green: 0.66, blue: 0.49)
    private let yellow = Color(red: 0.91, green: 0.68, blue: 0.25)
    private let paperBackground = Color(red: 0.995, green: 0.99, blue: 0.97)
    private let mutedOrange = Color(red: 0.84, green: 0.47, blue: 0.29)
    private let mutedGreen = Color(red: 0.31, green: 0.58, blue: 0.46)
    private let mutedBlue = Color(red: 0.34, green: 0.53, blue: 0.72)
    private let mutedCoral = Color(red: 0.78, green: 0.39, blue: 0.33)
    private let pastelPeach = Color(red: 1.00, green: 0.79, blue: 0.72)
    private let pastelMint = Color(red: 0.70, green: 0.91, blue: 0.83)
    private let pastelLavender = Color(red: 0.80, green: 0.76, blue: 0.98)
    private let pastelAqua = Color(red: 0.68, green: 0.91, blue: 0.95)
    private let pastelButter = Color(red: 1.00, green: 0.91, blue: 0.61)

    private func loadRecords() {
        let decoder = JSONDecoder()

        if let data = UserDefaults.standard.data(forKey: "foodRecords"),
           let records = try? decoder.decode([FoodRecord].self, from: data) {
            foodRecords = records.map { record in
                FoodRecord(
                    name: record.name,
                    calories: record.calories,
                    protein: record.protein,
                    fat: record.fat,
                    carbs: record.carbs,
                    createdAt: record.createdAt ?? .now,
                    source: record.source
                )
            }
        }

        if let data = UserDefaults.standard.data(forKey: "expenseRecords"),
           let records = try? decoder.decode([ExpenseRecord].self, from: data) {
            expenseRecords = records.map { record in
                ExpenseRecord(
                    name: record.name,
                    amount: record.amount,
                    createdAt: record.createdAt ?? .now,
                    genre: record.genre ?? .other
                )
            }
        }
        
        if let data = UserDefaults.standard.data(forKey: "diaryRecords"),
           let records = try? decoder.decode([DiaryRecord].self, from: data) {
            diaryRecords = records.map { record in
                DiaryRecord(
                    title: record.title,
                    body: record.body,
                    createdAt: record.createdAt ?? .now
                )
            }
        }
        
        if let data = UserDefaults.standard.data(forKey: "moodRecords"),
           let records = try? decoder.decode([MoodRecord].self, from: data) {
            moodRecords = records.map { record in
                MoodRecord(
                    mood: record.mood,
                    note: record.note,
                    createdAt: record.createdAt ?? .now
                )
            }
        }

        if let data = UserDefaults.standard.data(forKey: "videoRecords"),
           let records = try? decoder.decode([VideoRecord].self, from: data) {
            videoRecords = records
        }

        if let data = UserDefaults.standard.data(forKey: "calorieBurnRecords"),
           let records = try? decoder.decode([CalorieBurnRecord].self, from: data) {
            calorieBurnRecords = records
        }

        Task { await classifyLegacyVideos() }
    }

    @MainActor
    private func classifyLegacyVideos() async {
        guard !isClassifyingLegacyVideos else { return }
        isClassifyingLegacyVideos = true
        defer { isClassifyingLegacyVideos = false }

        let recordsToClassify = videoRecords.filter { $0.isTrimmed == nil }
        for record in recordsToClassify {
            var isTrimmed = false
            if FileManager.default.fileExists(atPath: record.fileURL.path) {
                do {
                    let duration = try await AVURLAsset(url: record.fileURL).load(.duration).seconds
                    isTrimmed = duration.isFinite && abs(duration - 2) <= 0.25
                } catch {
                    isTrimmed = false
                }
            }

            if let index = videoRecords.firstIndex(where: { $0.id == record.id }) {
                videoRecords[index] = record.withTrimmedState(isTrimmed)
            }
        }
    }

    @MainActor
    private func mergeSelectedVideos() async {
        let clipsToMerge = selectedTrimmedVideos
        guard clipsToMerge.count >= 2, isShowingToday else { return }

        isMergingVideos = true
        videoMergeError = nil
        defer { isMergingVideos = false }

        let outputName = "\(UUID().uuidString).mov"
        let outputURL = VideoRecord.videoDirectory.appendingPathComponent(outputName)

        do {
            try FileManager.default.createDirectory(
                at: VideoRecord.videoDirectory,
                withIntermediateDirectories: true
            )

            let composition = AVMutableComposition()
            guard let videoCompositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw VideoMergeError.trackCreationFailed
            }

            var audioCompositionTrack: AVMutableCompositionTrack?
            var insertionTime = CMTime.zero
            var hasVideoTransform = false

            for record in clipsToMerge {
                let asset = AVURLAsset(url: record.fileURL)
                let assetTracks = try await asset.load(.tracks)
                guard let sourceVideoTrack = assetTracks.first(where: { $0.mediaType == .video }) else {
                    throw VideoMergeError.missingVideoTrack
                }

                let sourceVideoRange = try await sourceVideoTrack.load(.timeRange)
                let clipDuration = sourceVideoRange.duration
                guard clipDuration.seconds.isFinite, clipDuration.seconds > 0 else {
                    throw VideoMergeError.invalidDuration
                }

                try videoCompositionTrack.insertTimeRange(
                    sourceVideoRange,
                    of: sourceVideoTrack,
                    at: insertionTime
                )

                if !hasVideoTransform {
                    videoCompositionTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
                    hasVideoTransform = true
                }

                if let sourceAudioTrack = assetTracks.first(where: { $0.mediaType == .audio }) {
                    if audioCompositionTrack == nil {
                        audioCompositionTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )
                    }

                    if let audioCompositionTrack {
                        let sourceAudioRange = try await sourceAudioTrack.load(.timeRange)
                        let audioOffset = max(sourceAudioRange.start.seconds, 0)
                        let audioDuration = min(
                            sourceAudioRange.duration.seconds,
                            max(clipDuration.seconds - audioOffset, 0)
                        )

                        if audioDuration > 0 {
                            let audioTimeRange = CMTimeRange(
                                start: sourceAudioRange.start,
                                duration: CMTime(seconds: audioDuration, preferredTimescale: 600)
                            )
                            let audioInsertionTime = CMTimeAdd(
                                insertionTime,
                                CMTime(seconds: audioOffset, preferredTimescale: 600)
                            )
                            try audioCompositionTrack.insertTimeRange(
                                audioTimeRange,
                                of: sourceAudioTrack,
                                at: audioInsertionTime
                            )
                        }
                    }
                }

                insertionTime = CMTimeAdd(insertionTime, clipDuration)
            }

            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw VideoMergeError.exportUnavailable
            }

            try await exportSession.export(to: outputURL, as: .mov)
            videoRecords.append(
                VideoRecord(
                    id: UUID(),
                    fileName: outputName,
                    createdAt: selectedDate,
                    isTrimmed: false,
                    isMerged: true
                )
            )
            isTrimmedVideoListExpanded = false
            isMergedVideoListExpanded = false
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            videoMergeError = "動画をまとめられませんでした。別の動画でもう一度お試しください。"
        }
    }

    private func saveFoodRecords(_ records: [FoodRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "foodRecords")
    }

    private func saveExpenseRecords(_ records: [ExpenseRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "expenseRecords")
    }
    
    private func saveMoodRecords(_ records: [MoodRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "moodRecords")
    }

    private func saveVideoRecords(_ records: [VideoRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "videoRecords")
    }

    private func saveCalorieBurnRecords(_ records: [CalorieBurnRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "calorieBurnRecords")
    }

    private func exportMergedVideoToPhotos(_ record: VideoRecord) {
        guard FileManager.default.fileExists(atPath: record.fileURL.path) else {
            videoExportMessages[record.id] = "動画ファイルが見つかりません。"
            return
        }

        exportingVideoIDs.insert(record.id)
        videoExportMessages[record.id] = nil

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    exportingVideoIDs.remove(record.id)
                    videoExportMessages[record.id] = "写真アプリへの追加を許可してください。"
                }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: record.fileURL)
            } completionHandler: { success, _ in
                Task { @MainActor in
                    exportingVideoIDs.remove(record.id)
                    videoExportMessages[record.id] = success
                        ? "写真アプリに保存しました。"
                        : "写真アプリに保存できませんでした。もう一度お試しください。"
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                paperBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        header
                        calorieCard
                        pfcCard
                        videoCard
                        recordsCard
                        expenseSummaryCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }

                Button {
                    showRecordMenu = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(
                            LinearGradient(
                                colors: [orange, Color(red: 0.98, green: 0.36, blue: 0.30)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
                        .shadow(color: orange.opacity(0.32), radius: 12, y: 6)
                }
                .padding(.trailing, 22)
                .padding(.bottom, 20)
                .disabled(!isShowingToday)
                .opacity(isShowingToday ? 1 : 0.55)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .food:
                    FoodEntryView { record in
                        foodRecords.append(record)
                        activeSheet = nil
                    }

                case .expense:
                    ExpenseEntryView { record in
                        expenseRecords.append(record)
                        activeSheet = nil
                    }
                
                case .diary:
                    DiaryEntryView { record in
                        diaryRecords.append(record)
                        activeSheet = nil
                    }
                case .mood:
                    MoodEntryView { record in
                        moodRecords.append(record)
                        activeSheet = nil
                    }
                case .video:
                    VideoEntryView(date: selectedDate) { record in
                        videoRecords.append(record)
                        isVideoListExpanded = false
                        isTrimmedVideoListExpanded = false
                        activeSheet = nil
                    }
                case .calorieBurn:
                    CalorieBurnEntryView { record in
                        calorieBurnRecords.append(record)
                        activeSheet = nil
                    }
                }
            }
            .sheet(item: $activeRecordCategory) { category in
                RecordManagementView(
                    category: category,
                    records: recordItems(for: category),
                    onDelete: { index in deleteRecord(category, at: index) },
                    onSave: { index, payload in updateRecord(category, at: index, with: payload) }
                )
            }
            .sheet(isPresented: $isShowingAppSettings) {
                AppSettingsView(
                    proteinGoal: $proteinGoal,
                    fatGoal: $fatGoal,
                    carbsGoal: $carbsGoal,
                    showCaptureTime: $showCaptureTimeOnTrimmedVideos
                )
            }
            .sheet(isPresented: $isShowingMonthlyReport) {
                MonthlyReportView(
                    expenses: expenseRecords,
                    foods: foodRecords,
                    manualBurns: calorieBurnRecords,
                    useHealthKit: hasRequestedHealthKitAccess
                )
            }
            .navigationBarHidden(true)
        }
        .confirmationDialog(
            "記録を追加",
            isPresented: $showRecordMenu,
            titleVisibility: .visible
        ) {
            Button("食事を記録") {
                activeSheet = .food
            }

            Button("家計簿を記録") {
                activeSheet = .expense
            }
            Button("日記を書く") {
                activeSheet = .diary
            }
            Button("気分を記録") {
                activeSheet = .mood
            }
            Button("動画を追加") {
                activeSheet = .video
            }
            Button("消費カロリーを記録") {
                activeSheet = .calorieBurn
            }
            Button("キャンセル", role: .cancel) {}
        }
        .onAppear {
            loadRecords()
            if hasRequestedHealthKitAccess {
                refreshHealthKitActiveEnergy()
            }
        }
        .onChange(of: foodRecords) { _, newRecords in
            saveFoodRecords(newRecords)
        }
        .onChange(of: expenseRecords) { _, newRecords in
            saveExpenseRecords(newRecords)
        }
        .onChange(of: diaryRecords) { _, newRecords in
            saveDiaryRecords(newRecords)
        }
        .onChange(of: moodRecords) { _, newRecords in
            saveMoodRecords(newRecords)
        }
        .onChange(of: videoRecords) { _, newRecords in
            saveVideoRecords(newRecords)
        }
        .onChange(of: calorieBurnRecords) { _, newRecords in
            saveCalorieBurnRecords(newRecords)
        }
        .onChange(of: selectedDate) { _, _ in
            isVideoListExpanded = false
            isTrimmedVideoListExpanded = false
            isMergedVideoListExpanded = false
            healthActiveCalories = nil
            if hasRequestedHealthKitAccess {
                refreshHealthKitActiveEnergy()
            }
        }
        .confirmationDialog("動画を削除しますか？", isPresented: $isShowingVideoDeleteConfirmation) {
            Button("削除", role: .destructive) {
                if let videoPendingDeletion {
                    deleteVideo(videoPendingDeletion)
                }
                videoPendingDeletion = nil
            }
            Button("キャンセル", role: .cancel) {
                videoPendingDeletion = nil
            }
        } message: {
            Text("この動画ファイルを削除します。この操作は取り消せません。")
        }
        .alert("動画を削除できませんでした", isPresented: Binding(
            get: { videoDeleteError != nil },
            set: { if !$0 { videoDeleteError = nil } }
        )) {
            Button("OK", role: .cancel) { videoDeleteError = nil }
        } message: {
            Text(videoDeleteError ?? "")
        }
        .preferredColorScheme(.light)
    }

    private func confirmDeleteVideo(_ record: VideoRecord) {
        videoPendingDeletion = record
        isShowingVideoDeleteConfirmation = true
    }

    private func deleteVideo(_ record: VideoRecord) {
        do {
            if FileManager.default.fileExists(atPath: record.fileURL.path) {
                try FileManager.default.removeItem(at: record.fileURL)
            }
            videoRecords.removeAll { $0.id == record.id }
            videoExportMessages[record.id] = nil
            exportingVideoIDs.remove(record.id)
        } catch {
            videoDeleteError = "動画ファイルを削除できませんでした。もう一度お試しください。"
        }
    }

    private func deleteVideoButton(for record: VideoRecord) -> some View {
        Button(role: .destructive) {
            confirmDeleteVideo(record)
        } label: {
            Label("この動画を削除", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isShowingToday ? "今日" : "過去の記録")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.primary)

                Spacer()

                Button {
                    isShowingAppSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(yellow)
                        .frame(width: 48, height: 48)
                        .background(yellow.opacity(0.14), in: Circle())
                }
                .accessibilityLabel("設定")

                Button {
                    isShowingMonthlyReport = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(blue)
                        .frame(width: 48, height: 48)
                        .background(blue.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("月次レポート")
            }

            HStack(spacing: 12) {
                Button {
                    moveSelectedDate(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(orange)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.82), in: Circle())
                }
                .accessibilityLabel("前の日")

                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(orange)
                    Text(selectedDate.formatted(
                        .dateTime.locale(Locale(identifier: "ja_JP"))
                            .year().month().day().weekday(.wide)
                    ))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(.white.opacity(0.76), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))

                Button {
                    moveSelectedDate(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(orange)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.82), in: Circle())
                }
                .disabled(isShowingToday)
                .accessibilityLabel("次の日")

                if !isShowingToday {
                    Button("今日へ") {
                        selectedDate = Calendar.current.startOfDay(for: .now)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var calorieCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardTitle("カロリー収支", icon: "flame.fill", color: mutedOrange, fontSize: 19)

            Button(action: requestHealthKitAccessAndRefresh) {
                Label(
                    healthActiveCalories == nil ? "ヘルスケアと連携" : "ヘルスケアを更新",
                    systemImage: "heart.text.square.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mutedCoral)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 8) {
                calorieValue(title: "摂取", value: "\(intakeCalories)", color: mutedOrange, isZero: intakeCalories == 0)
                Text("−")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.tertiary)
                calorieValue(title: "消費", value: "\(burnedCalories)", color: mutedGreen, isZero: burnedCalories == 0)
                Text("=")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.tertiary)
                calorieValue(
                    title: "差分",
                    value: "\(calorieDifference)",
                    color: calorieDifferenceColor,
                    isZero: calorieDifference == 0 && !hasCalorieEntries,
                    isProminent: true
                )
            }

            if !hasCalorieEntries {
                Text("食事や運動を記録すると、ここに反映されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, -5)
            }

            if let healthKitMessage {
                Text(healthKitMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if healthActiveCalories != nil {
                Text("ヘルスケアの値を優先します。0の場合はデータまたは許可設定をご確認ください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(mutedGreen)
                Text("\(selectedDateLabel)の記録をここにまとめています")
                    .fontWeight(.semibold)
                    .foregroundStyle(mutedGreen)
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(mutedGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .heroCalorieCardStyle(tint: pastelPeach)
        .sheet(item: $videoToTrim) { record in
            VideoTrimView(record: record) { trimmedRecord in
                videoRecords.append(trimmedRecord)
                isVideoListExpanded = false
                isTrimmedVideoListExpanded = false
                videoToTrim = nil
            }
        }
    }

    private func calorieValue(
        title: String,
        value: String,
        color: Color,
        isZero: Bool,
        isProminent: Bool = false
    ) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(isProminent ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: isProminent ? 30 : 24, weight: .semibold))
                .foregroundStyle(color.opacity(isZero ? 0.48 : 1))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .layoutPriority(isProminent ? 1 : 0)
        .padding(.vertical, isProminent ? 16 : 12)
        .padding(.horizontal, isProminent ? 4 : 0)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(color.opacity(isProminent ? 0.17 : 0.11))
                }
        }
        .overlay {
            if isProminent {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(color.opacity(0.2), lineWidth: 1)
            }
        }
    }

    private var pfcCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("PFCバランス", icon: "chart.pie.fill", color: purple, fontSize: 15)

            HStack(spacing: 8) {
                nutrientValue(name: "タンパク質", amount: totalProtein, goal: proteinGoal, color: blue)
                nutrientValue(name: "脂質", amount: totalFat, goal: fatGoal, color: yellow)
                nutrientValue(name: "炭水化物", amount: totalCarbs, goal: carbsGoal, color: orange)
            }
        }
        .detailCardStyle(tint: pastelAqua)
    }

    private func nutrientValue(name: String, amount: Double, goal: Double, color: Color) -> some View {
        VStack(spacing: 7) {
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(amount, format: .number.precision(.fractionLength(1)))
                .font(.system(size: 25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.primary.opacity(amount == 0 ? 0.48 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text("g")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("目標 \(goal, specifier: "%.0f") g")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 15)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 15).fill(color.opacity(0.12)))
        }
    }

    private var expenseSummaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "yensign.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(yellow)
                .frame(width: 46, height: 46)
                .background(yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(selectedDateLabel)の支出")
                    .font(.subheadline.weight(.semibold))
                Text("\(selectedExpenseRecords.count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(selectedExpenseTotal, format: .currency(code: "JPY").precision(.fractionLength(0)))
                .font(.system(size: 25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(yellow)
        }
        .glassCardStyle(tint: pastelButter)
    }

    private var videoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                cardTitle("\(selectedDateLabel)の動画", icon: "video.fill", color: purple)
                Spacer()
                Text("\(selectedOriginalVideos.count)本")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(purple.opacity(0.1), in: Capsule())
            }

            if selectedOriginalVideos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "video")
                        .font(.system(size: 30))
                        .foregroundStyle(purple.opacity(0.75))
                    Text("まだ元動画がありません")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            } else {
                DisclosureGroup(isExpanded: $isVideoListExpanded) {
                    ForEach(selectedOriginalVideos) { record in
                        VStack(spacing: 10) {
                            if FileManager.default.fileExists(atPath: record.fileURL.path) {
                                LocalVideoPlayer(url: record.fileURL)
                                    .frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))

                                Button {
                                    videoToTrim = record
                                } label: {
                                    Label("この動画から2秒を切り出す", systemImage: "scissors")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .foregroundStyle(purple)
                                        .background(purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(!isShowingToday)
                                .opacity(isShowingToday ? 1 : 0.55)
                            } else {
                                Label("動画ファイルが見つかりません", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            deleteVideoButton(for: record)
                        }
                    }
                } label: {
                    Label(
                        isVideoListExpanded ? "動画一覧を閉じる" : "動画一覧を表示・再生・編集",
                        systemImage: "play.rectangle"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(purple)
                }
            }

            if !selectedTrimmedVideos.isEmpty {
                DisclosureGroup(isExpanded: $isTrimmedVideoListExpanded) {
                    ForEach(selectedTrimmedVideos) { record in
                        VStack(spacing: 10) {
                            if FileManager.default.fileExists(atPath: record.fileURL.path) {
                                LocalVideoPlayer(url: record.fileURL)
                                    .frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            } else {
                                Label("動画ファイルが見つかりません", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            deleteVideoButton(for: record)
                        }
                    }
                } label: {
                    Label("切り出した動画（\(selectedTrimmedVideos.count)本）", systemImage: "scissors")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(purple)
                }

                if selectedTrimmedVideos.count >= 2 {
                    Button {
                        videoMergeError = nil
                        Task { await mergeSelectedVideos() }
                    } label: {
                        if isMergingVideos {
                            ProgressView("動画をまとめています…")
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("この日の切り出し動画をまとめる", systemImage: "film.stack")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isMergingVideos || !isShowingToday)
                }

                if let videoMergeError {
                    Text(videoMergeError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if !selectedMergedVideos.isEmpty {
                DisclosureGroup(isExpanded: $isMergedVideoListExpanded) {
                    ForEach(selectedMergedVideos) { record in
                        if FileManager.default.fileExists(atPath: record.fileURL.path) {
                            VStack(spacing: 10) {
                                LocalVideoPlayer(url: record.fileURL)
                                    .frame(height: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))

                                Button {
                                    exportMergedVideoToPhotos(record)
                                } label: {
                                    if exportingVideoIDs.contains(record.id) {
                                        ProgressView("写真に保存しています…")
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Label("写真アプリに保存", systemImage: "square.and.arrow.down")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(exportingVideoIDs.contains(record.id))

                                if let message = videoExportMessages[record.id] {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(message == "写真アプリに保存しました。" ? Color.green : Color.gray)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                deleteVideoButton(for: record)
                            }
                        } else {
                            VStack(spacing: 10) {
                                Label("動画ファイルが見つかりません", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                deleteVideoButton(for: record)
                            }
                        }
                    }
                } label: {
                    Label("まとめた動画（\(selectedMergedVideos.count)本）", systemImage: "film.stack")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(purple)
                }
            }

            Button {
                activeSheet = .video
            } label: {
                Label("動画を追加", systemImage: "video.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(purple)
                    .background(purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!isShowingToday)
            .opacity(isShowingToday ? 1 : 0.55)
        }
        .glassCardStyle(tint: pastelLavender)
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("\(selectedDateLabel)の記録", icon: "square.grid.2x2.fill", color: green)
                .padding(.bottom, 4)

            recordRow(
                category: .food,
                icon: "fork.knife",
                title: "食事",
                subtitle: selectedFoodRecords.last.map {
                    "\(selectedFoodRecords.count)件・最新：\($0.name)"
                } ?? "まだ記録がありません",
                color: orange
            )
            Divider()
            recordRow(
                category: .calorieBurn,
                icon: "figure.walk",
                title: "消費カロリー（手動）",
                subtitle: selectedCalorieBurnRecords.isEmpty
                    ? "まだ記録がありません"
                    : "\(selectedCalorieBurnRecords.count)件・合計：\(selectedCalorieBurnRecords.reduce(0) { $0 + $1.calories }) kcal",
                color: green
            )
            Divider()
            recordRow(
                category: .expense,
                icon: "yensign.circle",
                title: "家計簿",
                subtitle: selectedExpenseRecords.last.map {
                    "\(selectedDateLabel)の支出 ¥\(selectedExpenseTotal)・最新：\($0.name)"
                } ?? "\(selectedDateLabel)の支出 ¥0",
                color: green
            )
            Divider()
            recordRow(
                category: .diary,
                icon: "book.closed",
                title: "日記",
                subtitle: selectedDiaryRecords.last.map { "\(selectedDateLabel)：\($0.title)" } ?? "まだ記録がありません",
                color: blue
            )
            Divider()

            recordRow(
                category: .mood,
                icon: "face.smiling",
                title: "気分",
                subtitle: selectedMoodRecords.last.map { "\(selectedDateLabel)の気分：\($0.mood)" } ?? "まだ記録がありません",
                color: yellow
            )
        }
        .glassCardStyle(tint: pastelMint)
    }

    private func recordRow(category: RecordCategory, icon: String, title: String, subtitle: String, color: Color) -> some View {
        Button {
            activeRecordCategory = category
        } label: {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.15), in: Circle())
                    .overlay(Circle().strokeBorder(color.opacity(0.22), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private func cardTitle(_ title: String, icon: String, color: Color, fontSize: CGFloat = 17) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.14), in: Circle())
                .overlay(Circle().strokeBorder(color.opacity(0.22), lineWidth: 1))
            Text(title)
                .font(.system(size: fontSize, weight: .medium))
            Spacer()
        }
    }
}

private struct MonthlyReportView: View {
    @Environment(\.dismiss) private var dismiss
    let expenses: [ExpenseRecord]
    let foods: [FoodRecord]
    let manualBurns: [CalorieBurnRecord]
    let useHealthKit: Bool

    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var healthBurnByDay: [Date: Int] = [:]
    @State private var isLoadingHealthData = false
    @State private var calendarDisplay: MonthlyCalendarMetric = .calorieDifference

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthRange: DateInterval? { calendar.dateInterval(of: .month, for: month) }
    private var monthDays: [Date] {
        guard let range = monthRange else { return [] }
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: range.start) }
    }
    private var leadingDayCount: Int { max(0, (calendar.component(.weekday, from: month) + 5) % 7) }
    private var monthExpenses: [ExpenseRecord] {
        guard let range = monthRange else { return [] }
        return expenses.filter { record in
            guard let date = record.createdAt else { return false }
            return date >= range.start && date < range.end
        }
    }
    private var monthTotalExpense: Int { monthExpenses.reduce(0) { $0 + $1.amount } }
    private let genreColors: [ExpenseGenre: Color] = [
        .food: Color(red: 0.96, green: 0.48, blue: 0.25),
        .daily: Color(red: 0.91, green: 0.68, blue: 0.25),
        .transport: Color(red: 0.30, green: 0.57, blue: 0.88),
        .housing: Color(red: 0.48, green: 0.39, blue: 0.86),
        .health: Color(red: 0.94, green: 0.39, blue: 0.48),
        .entertainment: Color(red: 0.20, green: 0.68, blue: 0.68),
        .other: Color(red: 0.56, green: 0.59, blue: 0.64)
    ]
    private var genreTotals: [(genre: ExpenseGenre, amount: Int)] {
        ExpenseGenre.allCases.map { genre in
            (genre, monthExpenses.filter { ($0.genre ?? .other) == genre }.reduce(0) { $0 + $1.amount })
        }.filter { $0.amount > 0 }.sorted { $0.amount > $1.amount }
    }
    private var monthIntake: Int {
        guard let range = monthRange else { return 0 }
        return foods.filter { record in
            guard let date = record.createdAt else { return false }
            return date >= range.start && date < range.end
        }.reduce(0) { $0 + $1.calories }
    }
    private var manualBurnByDay: [Date: Int] {
        Dictionary(grouping: manualBurns, by: { calendar.startOfDay(for: $0.createdAt) })
            .mapValues { $0.reduce(0) { $0 + $1.calories } }
    }
    private func intake(on day: Date) -> Int {
        foods.filter { $0.createdAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .reduce(0) { $0 + $1.calories }
    }
    private func expenses(on day: Date) -> Int {
        expenses.filter { $0.createdAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
            .reduce(0) { $0 + $1.amount }
    }
    private func burn(on day: Date) -> Int {
        healthBurnByDay[calendar.startOfDay(for: day)] ?? manualBurnByDay[calendar.startOfDay(for: day), default: 0]
    }
    private var monthBurn: Int { monthDays.reduce(0) { $0 + burn(on: $1) } }
    private var monthDifference: Int { monthIntake - monthBurn }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthPicker
                    VStack(alignment: .leading, spacing: 14) {
                        reportTitle("支出ジャンル別", icon: "yensign.circle.fill", color: Color(red: 0.26, green: 0.66, blue: 0.49))
                        HStack {
                            Text("今月の支出合計")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(monthTotalExpense, format: .currency(code: "JPY").precision(.fractionLength(0)))
                                .font(.title3.bold())
                        }
                        if genreTotals.isEmpty {
                            Text("この月の支出記録はありません")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 14) {
                                Chart {
                                    ForEach(Array(genreTotals.enumerated()), id: \.offset) { entry in
                                        SectorMark(
                                            angle: .value("金額", entry.element.amount),
                                            innerRadius: .ratio(0.64),
                                            angularInset: 2
                                        )
                                        .foregroundStyle(genreColors[entry.element.genre] ?? .gray)
                                    }
                                }
                                .chartLegend(.hidden)
                                .frame(width: 150, height: 150)
                                .overlay {
                                    VStack(spacing: 2) {
                                        Text("合計").font(.caption2).foregroundStyle(.secondary)
                                        Text(monthTotalExpense, format: .currency(code: "JPY").precision(.fractionLength(0)))
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .minimumScaleFactor(0.7)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 90)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(genreTotals.enumerated()), id: \.offset) { entry in
                                        let item = entry.element
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(genreColors[item.genre] ?? .gray)
                                                .frame(width: 8, height: 8)
                                            Text(item.genre.title)
                                                .font(.caption)
                                                .lineLimit(1)
                                            Spacer(minLength: 2)
                                            VStack(alignment: .trailing, spacing: 1) {
                                                Text(item.amount, format: .currency(code: "JPY").precision(.fractionLength(0)))
                                                    .font(.caption2.weight(.semibold))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.75)
                                                Text("\(Int((Double(item.amount) / Double(monthTotalExpense) * 100).rounded()))%")
                                                    .font(.system(size: 9, design: .rounded))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                        }
                    }
                    .reportCard()

                    VStack(alignment: .leading, spacing: 14) {
                        reportTitle("カロリー収支", icon: "flame.fill", color: Color(red: 0.96, green: 0.48, blue: 0.25))
                        HStack(spacing: 8) {
                            monthCalorieValue("摂取", value: monthIntake, color: Color(red: 0.96, green: 0.48, blue: 0.25))
                            monthCalorieValue("消費", value: monthBurn, color: Color(red: 0.26, green: 0.66, blue: 0.49))
                            monthCalorieValue("差分", value: monthDifference, color: Color(red: 0.30, green: 0.57, blue: 0.88))
                        }
                        HStack(spacing: 12) {
                            Label("摂取 − 消費", systemImage: "equal")
                            Spacer()
                            if isLoadingHealthData { ProgressView().controlSize(.small) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .reportCard()

                    VStack(alignment: .leading, spacing: 12) {
                        reportTitle("日別カレンダー", icon: "calendar", color: Color(red: 0.30, green: 0.57, blue: 0.88))
                        Picker("カレンダー表示", selection: $calendarDisplay) {
                            ForEach(MonthlyCalendarMetric.allCases) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { day in
                                Text(day).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            ForEach(0..<leadingDayCount, id: \.self) { _ in Color.clear.frame(height: 66) }
                            ForEach(monthDays, id: \.self) { day in
                                let difference = intake(on: day) - burn(on: day)
                                let dayExpense = expenses(on: day)
                                let displayValue = calendarDisplay == .calorieDifference
                                    ? (difference > 0 ? "+\(difference)" : "\(difference)")
                                    : "\(dayExpense)"
                                let displayUnit = calendarDisplay == .calorieDifference ? "kcal" : "円"
                                let displayColor: Color = calendarDisplay == .expense
                                    ? Color(red: 0.26, green: 0.66, blue: 0.49)
                                    : (difference > 0 ? .orange : difference < 0 ? .blue : .secondary)
                                VStack(spacing: 4) {
                                    Text("\(calendar.component(.day, from: day))")
                                        .font(.caption.weight(.semibold))
                                    Text(displayValue)
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .foregroundStyle(displayColor)
                                    Text(displayUnit).font(.system(size: 8)).foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 66)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        Text(calendarDisplay == .calorieDifference
                             ? "日ごとの差分は、摂取カロリー − 消費カロリーです。ヘルスケアの日別データが取得できない日は手動記録を使います。"
                             : "日ごとの支出記録の合計を表示しています。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .reportCard()
                }
                .padding(16)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.98))
            .navigationTitle("月次レポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
            .task(id: month) { await loadHealthMonth() }
        }
    }

    private var monthPicker: some View {
        HStack {
            Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
            }
            Spacer()
            Text(month.formatted(.dateTime.locale(Locale(identifier: "ja_JP")).year().month()))
                .font(.title3.bold())
            Spacer()
            Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
            }
            .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
        }
        .padding(.horizontal, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func reportTitle(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
    }

    private func monthCalorieValue(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .number).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text("kcal").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor
    private func loadHealthMonth() async {
        healthBurnByDay = [:]
        guard useHealthKit, HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let range = monthRange else { return }
        isLoadingHealthData = true
        defer { isLoadingHealthData = false }
        let store = HKHealthStore()
        let predicate = HKQuery.predicateForSamples(withStart: range.start, end: range.end, options: .strictStartDate)
        let anchor = calendar.startOfDay(for: range.start)
        let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
        let results: [Date: Int] = await withCheckedContinuation { continuation in
            query.initialResultsHandler = { _, collection, _ in
                var values: [Date: Int] = [:]
                collection?.enumerateStatistics(from: range.start, to: range.end) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        values[calendar.startOfDay(for: statistics.startDate)] = Int(quantity.doubleValue(for: .kilocalorie()).rounded())
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
        healthBurnByDay = results
    }
}

private enum MonthlyCalendarMetric: String, CaseIterable, Identifiable {
    case calorieDifference
    case expense

    var id: String { rawValue }
    var title: String {
        switch self {
        case .calorieDifference: "カロリー差分"
        case .expense: "支出合計"
        }
    }
}

private extension View {
    func reportCard() -> some View {
        self.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.04), radius: 9, y: 4)
    }
}

private struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var proteinGoal: Double
    @Binding private var fatGoal: Double
    @Binding private var carbsGoal: Double
    @Binding private var storedShowCaptureTime: Bool

    @State private var proteinText: String
    @State private var fatText: String
    @State private var carbsText: String
    @State private var showCaptureTime = true
    @State private var remindersEnabled: Bool
    @State private var breakfastReminderEnabled: Bool
    @State private var lunchReminderEnabled: Bool
    @State private var dinnerReminderEnabled: Bool
    @State private var eveningReminderEnabled: Bool
    @State private var breakfastReminderTime: Date
    @State private var lunchReminderTime: Date
    @State private var dinnerReminderTime: Date
    @State private var eveningReminderTime: Date
    @State private var isShowingNotificationSettingsAlert = false

    init(
        proteinGoal: Binding<Double>,
        fatGoal: Binding<Double>,
        carbsGoal: Binding<Double>,
        showCaptureTime: Binding<Bool>
    ) {
        _proteinGoal = proteinGoal
        _fatGoal = fatGoal
        _carbsGoal = carbsGoal
        _storedShowCaptureTime = showCaptureTime
        _proteinText = State(initialValue: String(proteinGoal.wrappedValue))
        _fatText = State(initialValue: String(fatGoal.wrappedValue))
        _carbsText = State(initialValue: String(carbsGoal.wrappedValue))
        _showCaptureTime = State(initialValue: showCaptureTime.wrappedValue)

        let defaults = UserDefaults.standard
        _remindersEnabled = State(initialValue: defaults.bool(forKey: "dailyRemindersEnabled"))
        _breakfastReminderEnabled = State(initialValue: Self.boolValue(forKey: "breakfastReminderEnabled", default: true))
        _lunchReminderEnabled = State(initialValue: Self.boolValue(forKey: "lunchReminderEnabled", default: true))
        _dinnerReminderEnabled = State(initialValue: Self.boolValue(forKey: "dinnerReminderEnabled", default: true))
        _eveningReminderEnabled = State(initialValue: Self.boolValue(forKey: "eveningReminderEnabled", default: true))
        _breakfastReminderTime = State(initialValue: Self.reminderDate(minutesAfterMidnight: defaults.object(forKey: "breakfastReminderMinutes") as? Int ?? 8 * 60))
        _lunchReminderTime = State(initialValue: Self.reminderDate(minutesAfterMidnight: defaults.object(forKey: "lunchReminderMinutes") as? Int ?? 12 * 60 + 30))
        _dinnerReminderTime = State(initialValue: Self.reminderDate(minutesAfterMidnight: defaults.object(forKey: "dinnerReminderMinutes") as? Int ?? 19 * 60))
        _eveningReminderTime = State(initialValue: Self.reminderDate(minutesAfterMidnight: defaults.object(forKey: "eveningReminderMinutes") as? Int ?? 21 * 60))
    }

    private static func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil
            ? defaultValue
            : UserDefaults.standard.bool(forKey: key)
    }

    private static func reminderDate(minutesAfterMidnight: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutesAfterMidnight / 60,
            minute: minutesAfterMidnight % 60,
            second: 0,
            of: .now
        ) ?? .now
    }

    private static func minutesAfterMidnight(for date: Date) -> Int {
        Calendar.current.component(.hour, from: date) * 60
            + Calendar.current.component(.minute, from: date)
    }

    private var canSave: Bool {
        [proteinText, fatText, carbsText].allSatisfy { text in
            guard let value = Double(text) else { return false }
            return value >= 0 && value.isFinite
        }
    }

    private func isValidGoal(_ text: String) -> Bool {
        guard let value = Double(text) else { return false }
        return value >= 0 && value.isFinite
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("PFCの1日目標") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("タンパク質")
                            .font(.subheadline)
                        TextField("g", text: $proteinText)
                            .keyboardType(.decimalPad)
                        if !isValidGoal(proteinText) {
                            goalValidationMessage
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("脂質")
                            .font(.subheadline)
                        TextField("g", text: $fatText)
                            .keyboardType(.decimalPad)
                        if !isValidGoal(fatText) {
                            goalValidationMessage
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("炭水化物")
                            .font(.subheadline)
                        TextField("g", text: $carbsText)
                            .keyboardType(.decimalPad)
                        if !isValidGoal(carbsText) {
                            goalValidationMessage
                        }
                    }
                }
                Section("切り出し動画") {
                    Toggle("撮影時刻を中央に表示", isOn: $showCaptureTime)
                    Text("元動画の日時メタデータがある場合、時刻を白字で動画に入れます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("通知") {
                    Toggle("通知を有効にする", isOn: $remindersEnabled)
                    Text("食事の入力と、その日の記録を振り返る通知を設定できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if remindersEnabled {
                        VStack(spacing: 4) {
                            reminderRow(title: "朝食", isOn: $breakfastReminderEnabled, time: $breakfastReminderTime)
                            reminderRow(title: "昼食", isOn: $lunchReminderEnabled, time: $lunchReminderTime)
                            reminderRow(title: "夕食", isOn: $dinnerReminderEnabled, time: $dinnerReminderTime)
                            reminderRow(title: "夜の記録確認", isOn: $eveningReminderEnabled, time: $eveningReminderTime)
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.22), value: remindersEnabled)
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let protein = Double(proteinText),
                              let fat = Double(fatText),
                              let carbs = Double(carbsText) else { return }
                        proteinGoal = protein
                        fatGoal = fat
                        carbsGoal = carbs
                        storedShowCaptureTime = showCaptureTime
                        saveReminderSettings()
                    }
                    .disabled(!canSave)
                }
            }
            .alert("通知を許可してください", isPresented: $isShowingNotificationSettingsAlert) {
                Button("設定を開く") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                Button("あとで", role: .cancel) { dismiss() }
            } message: {
                Text("iPhoneの設定で「今日録」の通知を許可すると、設定したリマインドを受け取れます。")
            }
        }
    }

    private func saveReminderSettings() {
        let defaults = UserDefaults.standard
        defaults.set(remindersEnabled, forKey: "dailyRemindersEnabled")
        defaults.set(breakfastReminderEnabled, forKey: "breakfastReminderEnabled")
        defaults.set(lunchReminderEnabled, forKey: "lunchReminderEnabled")
        defaults.set(dinnerReminderEnabled, forKey: "dinnerReminderEnabled")
        defaults.set(eveningReminderEnabled, forKey: "eveningReminderEnabled")
        defaults.set(Self.minutesAfterMidnight(for: breakfastReminderTime), forKey: "breakfastReminderMinutes")
        defaults.set(Self.minutesAfterMidnight(for: lunchReminderTime), forKey: "lunchReminderMinutes")
        defaults.set(Self.minutesAfterMidnight(for: dinnerReminderTime), forKey: "dinnerReminderMinutes")
        defaults.set(Self.minutesAfterMidnight(for: eveningReminderTime), forKey: "eveningReminderMinutes")

        let preferences = ReminderNotificationPreferences(
            enabled: remindersEnabled,
            breakfastEnabled: breakfastReminderEnabled,
            lunchEnabled: lunchReminderEnabled,
            dinnerEnabled: dinnerReminderEnabled,
            eveningEnabled: eveningReminderEnabled,
            breakfastMinutes: Self.minutesAfterMidnight(for: breakfastReminderTime),
            lunchMinutes: Self.minutesAfterMidnight(for: lunchReminderTime),
            dinnerMinutes: Self.minutesAfterMidnight(for: dinnerReminderTime),
            eveningMinutes: Self.minutesAfterMidnight(for: eveningReminderTime)
        )

        Task {
            let isReady = await ReminderNotificationScheduler.apply(preferences)
            if remindersEnabled && !isReady {
                isShowingNotificationSettingsAlert = true
            } else {
                dismiss()
            }
        }
    }

    private var goalValidationMessage: some View {
        Text("0以上の数値を入力してください。")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func reminderRow(title: String, isOn: Binding<Bool>, time: Binding<Date>) -> some View {
        HStack(spacing: 8) {
            Toggle(title, isOn: isOn)
                .font(.subheadline)
                .toggleStyle(.switch)
                .frame(width: 170, alignment: .leading)

            Spacer(minLength: 0)

            DatePicker("\(title)の通知時刻", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(width: 100, alignment: .trailing)
                .accessibilityLabel("\(title)の通知時刻")
                .disabled(!isOn.wrappedValue)
        }
    }
}

private struct ReminderNotificationPreferences {
    let enabled: Bool
    let breakfastEnabled: Bool
    let lunchEnabled: Bool
    let dinnerEnabled: Bool
    let eveningEnabled: Bool
    let breakfastMinutes: Int
    let lunchMinutes: Int
    let dinnerMinutes: Int
    let eveningMinutes: Int

    var hasAnyEnabledReminder: Bool {
        breakfastEnabled || lunchEnabled || dinnerEnabled || eveningEnabled
    }
}

private enum ReminderNotificationScheduler {
    private struct Reminder {
        let id: String
        let enabled: Bool
        let minutesAfterMidnight: Int
        let title: String
        let body: String
    }

    private static let identifiers = [
        "mealReminder.breakfast",
        "mealReminder.lunch",
        "mealReminder.dinner",
        "dailyReminder.evening"
    ]

    static func apply(_ preferences: ReminderNotificationPreferences) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard preferences.enabled, preferences.hasAnyEnabledReminder else { return true }

        let settings = await center.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined:
            do {
                isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        default:
            isAuthorized = false
        }

        guard isAuthorized else { return false }

        let reminders = [
            Reminder(
                id: "mealReminder.breakfast",
                enabled: preferences.breakfastEnabled,
                minutesAfterMidnight: preferences.breakfastMinutes,
                title: "朝食を記録しませんか？",
                body: "食べたものを今日録に残しておきましょう。"
            ),
            Reminder(
                id: "mealReminder.lunch",
                enabled: preferences.lunchEnabled,
                minutesAfterMidnight: preferences.lunchMinutes,
                title: "昼食を記録しませんか？",
                body: "食べたものを今日録に残しておきましょう。"
            ),
            Reminder(
                id: "mealReminder.dinner",
                enabled: preferences.dinnerEnabled,
                minutesAfterMidnight: preferences.dinnerMinutes,
                title: "夕食を記録しませんか？",
                body: "食べたものを今日録に残しておきましょう。"
            ),
            Reminder(
                id: "dailyReminder.evening",
                enabled: preferences.eveningEnabled,
                minutesAfterMidnight: preferences.eveningMinutes,
                title: "今日の記録を振り返りましょう",
                body: "まだ記録していないことがあれば、無理のない範囲で追加できます。"
            )
        ]

        for reminder in reminders where reminder.enabled {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default

            var time = DateComponents()
            time.hour = reminder.minutesAfterMidnight / 60
            time.minute = reminder.minutesAfterMidnight % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                return false
            }
        }

        return true
    }
}

private extension View {
    func heroCalorieCardStyle(tint: Color) -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.68), tint.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.88), lineWidth: 1.2)
            }
            .shadow(color: tint.opacity(0.2), radius: 16, y: 8)
    }

    func detailCardStyle(tint: Color) -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 18).fill(tint.opacity(0.08)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.86), lineWidth: 1)
            }
    }

    func glassCardStyle(tint: Color) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 20).fill(tint.opacity(0.10)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.88), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.13), radius: 12, y: 5)
    }

    func cardStyle() -> some View {
        self
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.045), radius: 12, y: 5)
    }
}
private struct FoodEntryView: View {
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

            commercialFoods = products.compactMap { product in
                guard let code = product["code"] as? String,
                      let nutriments = product["nutriments"] as? [String: Any],
                      let calories = Self.nutrientValue(nutriments, key: "energy-kcal_100g"),
                      let protein = Self.nutrientValue(nutriments, key: "proteins_100g"),
                      let fat = Self.nutrientValue(nutriments, key: "fat_100g"),
                      let carbs = Self.nutrientValue(nutriments, key: "carbohydrates_100g") else {
                    return nil
                }

                let productName = ["product_name_ja", "product_name"]
                    .compactMap { product[$0] as? String }
                    .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                guard let productName else { return nil }

                let brand = (product["brands"] as? String)?
                    .components(separatedBy: ",")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = [brand, productName]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "　")
                let servingGrams = (product["serving_quantity_unit"] as? String == "g"
                    ? Self.numericValue(product["serving_quantity"])
                    : nil)
                    ?? Self.gramsValue(from: product["serving_size"] as? String)
                    ?? Self.gramsValue(from: product["quantity"] as? String)

                return FoodItem(
                    id: "off-\(code)",
                    name: displayName,
                    calories: calories,
                    protein: protein,
                    fat: fat,
                    carbs: carbs,
                    brand: brand,
                    servingGrams: servingGrams,
                    source: "Open Food Facts"
                )
            }

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

private struct FoodRecord: Codable, Equatable {
    let name: String
    let calories: Int
    let protein: Double?
    let fat: Double?
    let carbs: Double?
    let createdAt: Date?
    var source: String? = nil
}

private enum NutritionLabelBasis {
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

private struct FoodItem: Codable, Identifiable {
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

private struct BarcodeScannerScreen: View {
    let onBarcode: (String) -> Void
    @State private var scannerError: String?

    var body: some View {
        Group {
            if !DataScannerViewController.isSupported {
                ContentUnavailableView(
                    "この端末では読み取れません",
                    systemImage: "barcode.viewfinder",
                    description: Text("バーコード読み取りは対応するiPhoneの実機でお試しください。商品名検索または手動入力も利用できます。")
                )
            } else if let scannerError {
                ContentUnavailableView(
                    "カメラを利用できません",
                    systemImage: "camera.fill",
                    description: Text(scannerError)
                )
            } else {
                BarcodeScannerController(onBarcode: onBarcode, scannerError: $scannerError)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("商品のバーコードを枠内に合わせてください")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 24)
                    }
            }
        }
    }
}

private struct BarcodeScannerController: UIViewControllerRepresentable {
    let onBarcode: (String) -> Void
    @Binding var scannerError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcode: onBarcode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        guard DataScannerViewController.isAvailable else {
            scannerError = "カメラが使えないか、カメラへのアクセスが許可されていません。iPhoneの設定で今日録のカメラ利用を許可してください。"
            return scanner
        }
        do {
            try scanner.startScanning()
        } catch {
            scannerError = "カメラを起動できませんでした。カメラのアクセス許可をご確認ください。"
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onBarcode: (String) -> Void
        private var didReturnBarcode = false

        init(onBarcode: @escaping (String) -> Void) {
            self.onBarcode = onBarcode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didReturnBarcode else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item,
                   let value = barcode.payloadStringValue,
                   !value.isEmpty {
                    didReturnBarcode = true
                    onBarcode(value)
                    return
                }
            }
        }
    }
}

private struct NutritionLabelCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: (UIImage?) -> Void

        init(onImage: @escaping (UIImage?) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}

private struct VideoRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let createdAt: Date
    let isTrimmed: Bool?
    let isMerged: Bool?

    init(
        id: UUID,
        fileName: String,
        createdAt: Date,
        isTrimmed: Bool? = nil,
        isMerged: Bool? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.createdAt = createdAt
        self.isTrimmed = isTrimmed
        self.isMerged = isMerged
    }

    func withTrimmedState(_ isTrimmed: Bool) -> VideoRecord {
        VideoRecord(
            id: id,
            fileName: fileName,
            createdAt: createdAt,
            isTrimmed: isTrimmed,
            isMerged: false
        )
    }

    var fileURL: URL {
        Self.videoDirectory.appendingPathComponent(fileName)
    }

    static var videoDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyVideos", isDirectory: true)
    }
}

private struct LocalVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        }
        .task {
            if player == nil {
                player = AVPlayer(url: url)
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}

private struct VideoTrimView: View {
    @Environment(\.dismiss) private var dismiss

    let record: VideoRecord
    let onSave: (VideoRecord) -> Void

    @State private var player: AVPlayer?
    @State private var duration = 0.0
    @State private var startTime = 0.0
    @State private var captureDate: Date?
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var errorMessage: String?
    @AppStorage("showCaptureTimeOnTrimmedVideos") private var showCaptureTime = true

    private var maximumStartTime: Double {
        max(duration - 2, 0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if isLoading {
                    ProgressView("動画を読み込み中…")
                        .frame(height: 220)
                }

                if duration >= 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("切り出す位置")
                            .font(.headline)

                        if maximumStartTime > 0 {
                            Slider(value: $startTime, in: 0...maximumStartTime)
                                .tint(.purple)
                        }

                        HStack {
                            Text("開始 \(startTime, specifier: "%.1f") 秒")
                            Spacer()
                            Text("長さ 2 秒")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if showCaptureTime {
                            if let captureDate {
                                Text("動画から取得した時刻：\(formattedCaptureTime(captureDate))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("撮影時刻のメタデータがない場合、時刻は表示されません。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("撮影時刻の表示は設定でオフになっています。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task { await exportTrimmedVideo() }
                    } label: {
                        if isExporting {
                            ProgressView("2秒を切り出し中…")
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("2秒を切り出して保存", systemImage: "scissors")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isExporting || isLoading)
                } else if !isLoading {
                    Text("この動画は2秒より短いため、切り出せません。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("2秒を切り出す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                        .disabled(isExporting)
                }
            }
            .onChange(of: startTime) { _, newValue in
                player?.seek(to: CMTime(seconds: newValue, preferredTimescale: 600))
            }
            .task { await loadVideo() }
        }
    }

    @MainActor
    private func loadVideo() async {
        defer { isLoading = false }
        do {
            let asset = AVURLAsset(url: record.fileURL)
            let loadedDuration = try await asset.load(.duration).seconds
            guard loadedDuration.isFinite, loadedDuration > 0 else {
                errorMessage = "動画の長さを読み取れませんでした。"
                return
            }
            duration = loadedDuration
            captureDate = await loadCaptureDate(from: asset)
            player = AVPlayer(url: record.fileURL)
        } catch {
            errorMessage = "動画を開けませんでした。もう一度お試しください。"
        }
    }

    @MainActor
    private func exportTrimmedVideo() async {
        guard duration >= 2 else { return }
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        let outputName = "\(UUID().uuidString).mov"
        let outputURL = VideoRecord.videoDirectory.appendingPathComponent(outputName)

        do {
            try FileManager.default.createDirectory(
                at: VideoRecord.videoDirectory,
                withIntermediateDirectories: true
            )

            let asset = AVURLAsset(url: record.fileURL)
            guard let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw VideoTrimError.exportUnavailable
            }

            exportSession.timeRange = CMTimeRange(
                start: CMTime(seconds: startTime, preferredTimescale: 600),
                duration: CMTime(seconds: 2, preferredTimescale: 600)
            )
            if showCaptureTime, let captureDate {
                exportSession.videoComposition = try await makeTimestampComposition(
                    for: asset,
                    timestamp: formattedCaptureTime(captureDate)
                )
            }
            try await exportSession.export(to: outputURL, as: .mov)

            onSave(VideoRecord(
                id: UUID(),
                fileName: outputName,
                createdAt: record.createdAt,
                isTrimmed: true,
                isMerged: false
            ))
            dismiss()
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            errorMessage = "動画を切り出せませんでした。別の位置を選んでもう一度お試しください。"
        }
    }

    private func loadCaptureDate(from asset: AVAsset) async -> Date? {
        if let item = try? await asset.load(.creationDate) {
            if let date = try? await item.load(.dateValue) {
                return date
            }
            if let value = try? await item.load(.stringValue),
               let date = parseMetadataDate(value) {
                return date
            }
        }

        guard let items = try? await asset.load(.metadata) else { return nil }
        let creationDateIdentifiers: [AVMetadataIdentifier] = [
            .commonIdentifierCreationDate,
            .quickTimeMetadataCreationDate
        ]
        for item in items where creationDateIdentifiers.contains(item.identifier ?? .commonIdentifierTitle) {
            if let date = try? await item.load(.dateValue) {
                return date
            }
            if let value = try? await item.load(.stringValue),
               let date = parseMetadataDate(value) {
                return date
            }
        }
        return nil
    }

    private func parseMetadataDate(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) { return date }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func formattedCaptureTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func makeTimestampComposition(for asset: AVAsset, timestamp: String) async throws -> AVVideoComposition {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else { throw VideoTrimError.exportUnavailable }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        var normalizedTransform = preferredTransform
        normalizedTransform.tx -= transformedRect.minX
        normalizedTransform.ty -= transformedRect.minY

        let renderSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let duration = try await asset.load(.duration)
        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
        layerConfiguration.setTransform(normalizedTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfiguration)

        let instructionConfiguration = AVVideoCompositionInstruction.Configuration(
            layerInstructions: [layerInstruction],
            timeRange: CMTimeRange(start: .zero, duration: duration)
        )
        let instruction = AVVideoCompositionInstruction(configuration: instructionConfiguration)

        let parentLayer = CALayer()
        let videoLayer = CALayer()
        let overlayLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        videoLayer.frame = parentLayer.bounds
        overlayLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        let textLayer = CATextLayer()
        let fontSize = max(36, min(renderSize.width, renderSize.height) * 0.075)
        textLayer.string = timestamp
        textLayer.alignmentMode = .center
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.font = UIFont.boldSystemFont(ofSize: fontSize)
        textLayer.fontSize = fontSize
        textLayer.shadowColor = UIColor.black.cgColor
        textLayer.shadowOpacity = 0.85
        textLayer.shadowRadius = 4
        textLayer.shadowOffset = CGSize(width: 0, height: 2)
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isGeometryFlipped = true
        textLayer.isHidden = false
        textLayer.opacity = 1
        textLayer.beginTime = AVCoreAnimationBeginTimeAtZero
        textLayer.frame = CGRect(x: 0, y: renderSize.height / 2 - fontSize, width: renderSize.width, height: fontSize * 1.5)
        overlayLayer.addSublayer(textLayer)

        let animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        var compositionConfiguration = try await AVVideoComposition.Configuration(
            for: asset,
            prototypeInstruction: instruction
        )
        compositionConfiguration.instructions = [instruction]
        compositionConfiguration.renderSize = renderSize
        compositionConfiguration.frameDuration = CMTime(value: 1, timescale: 30)
        compositionConfiguration.animationTool = animationTool
        return AVVideoComposition(configuration: compositionConfiguration)
    }
}

private enum VideoMergeError: Error {
    case trackCreationFailed
    case missingVideoTrack
    case invalidDuration
    case exportUnavailable
}

private enum VideoTrimError: Error {
    case exportUnavailable
}

private struct VideoTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try FileManager.default.copyItem(at: received.file, to: temporaryURL)
            return VideoTransfer(url: temporaryURL)
        }
    }
}

private struct VideoEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let onSave: (VideoRecord) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var isVideoCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && (UIImagePickerController.availableMediaTypes(for: .camera)?.contains(UTType.movie.identifier) ?? false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "video.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.purple)

                Text("写真ライブラリから動画を選びます。選んだ動画はこの端末に保存されます。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if isVideoCameraAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("カメラで動画を撮影", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isImporting)
                } else {
                    Label("カメラ撮影はiPhone実機でお試しください", systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    Label("ライブラリから動画を選ぶ", systemImage: "video.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)

                if isImporting {
                    ProgressView("動画を読み込み中…")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("動画を追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                Task {
                    await importVideo(from: item)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                MovieCameraPicker { capturedURL in
                    Task { await importCameraVideo(from: capturedURL) }
                }
                .ignoresSafeArea()
            }
        }
    }

    @MainActor
    private func importCameraVideo(from temporaryURL: URL) async {
        isImporting = true
        errorMessage = nil
        defer {
            isImporting = false
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        do {
            let directory = VideoRecord.videoDirectory
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let fileExtension = temporaryURL.pathExtension.isEmpty ? "mov" : temporaryURL.pathExtension
            let fileName = "\(UUID().uuidString).\(fileExtension)"
            let destination = directory.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: temporaryURL, to: destination)

            onSave(VideoRecord(
                id: UUID(),
                fileName: fileName,
                createdAt: date,
                isTrimmed: false,
                isMerged: false
            ))
            dismiss()
        } catch {
            errorMessage = "撮影した動画を保存できませんでした。もう一度お試しください。"
        }
    }

    @MainActor
    private func importVideo(from item: PhotosPickerItem) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }

        do {
            guard let importedVideo = try await item.loadTransferable(type: VideoTransfer.self) else {
                errorMessage = "この動画を読み込めませんでした。別の動画を選んでください。"
                return
            }

            let directory = VideoRecord.videoDirectory
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let fileExtension = importedVideo.url.pathExtension.isEmpty
                ? "mov"
                : importedVideo.url.pathExtension
            let fileName = "\(UUID().uuidString).\(fileExtension)"
            let destination = directory.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: importedVideo.url, to: destination)
            try? FileManager.default.removeItem(at: importedVideo.url)

            onSave(VideoRecord(
                id: UUID(),
                fileName: fileName,
                createdAt: date,
                isTrimmed: false,
                isMerged: false
            ))
            dismiss()
        } catch {
            errorMessage = "動画を保存できませんでした。もう一度お試しください。"
        }
    }
}

private struct MovieCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let onCapture: (URL) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: MovieCameraPicker

        init(parent: MovieCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let videoURL = info[.mediaURL] as? URL {
                parent.onCapture(videoURL)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

private struct ExpenseEntryView: View {
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

private enum ExpenseGenre: String, CaseIterable, Codable, Identifiable {
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

private struct ExpenseRecord: Codable, Equatable {
    let name: String
    let amount: Int
    let createdAt: Date?
    var genre: ExpenseGenre? = .other
}

private enum EntrySheet: String, Identifiable {
    case food
    case expense
    case diary
    case mood
    case video
    case calorieBurn

    var id: String { rawValue }
}

private struct CalorieBurnRecord: Codable, Equatable {
    let activity: String
    let calories: Int
    let createdAt: Date
}

private enum RecordCategory: String, Identifiable {
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

private enum RecordEditPayload {
    case food(FoodRecord)
    case calorieBurn(CalorieBurnRecord)
    case expense(ExpenseRecord)
    case diary(DiaryRecord)
    case mood(MoodRecord)
}

private struct RecordEditItem: Identifiable {
    let sourceIndex: Int
    let title: String
    let detail: String
    let payload: RecordEditPayload

    var id: Int { sourceIndex }
}

private struct RecordManagementView: View {
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

private struct RecordEditView: View {
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

private struct CalorieBurnEntryView: View {
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

private struct DiaryRecord: Codable, Equatable {
    let title: String
    let body: String
    let createdAt: Date?
}

private struct DiaryEntryView: View {
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

private struct MoodRecord: Codable, Equatable {
    let mood: String
    let note: String
    let createdAt: Date?
}

private struct MoodEntryView: View {
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
