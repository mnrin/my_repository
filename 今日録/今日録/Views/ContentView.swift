import SwiftUI
import AVKit
import AVFoundation
import Photos
import HealthKit

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

    /// 日付が未設定の旧データは常に表示対象として扱う。
    private func isOnSelectedDate(_ date: Date?) -> Bool {
        date.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } ?? true
    }

    private var selectedExpenseRecords: [ExpenseRecord] {
        expenseRecords.filter { isOnSelectedDate($0.createdAt) }
    }

    private var selectedDiaryRecords: [DiaryRecord] {
        diaryRecords.filter { isOnSelectedDate($0.createdAt) }
    }

    private var selectedMoodRecords: [MoodRecord] {
        moodRecords.filter { isOnSelectedDate($0.createdAt) }
    }

    private func recordItems(for category: RecordCategory) -> [RecordEditItem] {
        switch category {
        case .food:
            return foodRecords.enumerated().compactMap { entry in
                let index = entry.offset
                let record = entry.element
                guard isOnSelectedDate(record.createdAt) else { return nil }
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
                guard isOnSelectedDate(record.createdAt) else { return nil }
                return RecordEditItem(sourceIndex: index, title: record.name, detail: "¥\(record.amount)・\(record.genre?.title ?? ExpenseGenre.other.title)", payload: .expense(record))
            }
        case .diary:
            return diaryRecords.enumerated().compactMap { entry in
                let index = entry.offset
                let record = entry.element
                guard isOnSelectedDate(record.createdAt) else { return nil }
                return RecordEditItem(sourceIndex: index, title: record.title, detail: String(record.body.prefix(60)), payload: .diary(record))
            }
        case .mood:
            return moodRecords.enumerated().compactMap { entry in
                let index = entry.offset
                let record = entry.element
                guard isOnSelectedDate(record.createdAt) else { return nil }
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
        foodRecords.filter { isOnSelectedDate($0.createdAt) }
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
        // createdAt が欠けている旧データは読み込み時に現在時刻で補完する。
        if let records: [FoodRecord] = RecordStorage.load(RecordStorage.Key.food) {
            foodRecords = records.map {
                FoodRecord(name: $0.name, calories: $0.calories, protein: $0.protein, fat: $0.fat,
                           carbs: $0.carbs, createdAt: $0.createdAt ?? .now, source: $0.source)
            }
        }
        if let records: [ExpenseRecord] = RecordStorage.load(RecordStorage.Key.expense) {
            expenseRecords = records.map {
                ExpenseRecord(name: $0.name, amount: $0.amount, createdAt: $0.createdAt ?? .now, genre: $0.genre ?? .other)
            }
        }
        if let records: [DiaryRecord] = RecordStorage.load(RecordStorage.Key.diary) {
            diaryRecords = records.map {
                DiaryRecord(title: $0.title, body: $0.body, createdAt: $0.createdAt ?? .now)
            }
        }
        if let records: [MoodRecord] = RecordStorage.load(RecordStorage.Key.mood) {
            moodRecords = records.map {
                MoodRecord(mood: $0.mood, note: $0.note, createdAt: $0.createdAt ?? .now)
            }
        }
        if let records: [VideoRecord] = RecordStorage.load(RecordStorage.Key.video) {
            videoRecords = records
        }
        if let records: [CalorieBurnRecord] = RecordStorage.load(RecordStorage.Key.calorieBurn) {
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
            RecordStorage.save(newRecords, forKey: RecordStorage.Key.food)
        }
        .onChange(of: expenseRecords) { _, newRecords in
            RecordStorage.save(newRecords, forKey: RecordStorage.Key.expense)
        }
        .onChange(of: diaryRecords) { _, newRecords in
            RecordStorage.save(newRecords, forKey: RecordStorage.Key.diary)
        }
        .onChange(of: moodRecords) { _, newRecords in
            RecordStorage.save(newRecords, forKey: RecordStorage.Key.mood)
        }
        .onChange(of: videoRecords) { _, newRecords in
            RecordStorage.save(newRecords, forKey: RecordStorage.Key.video)
        }
        .onChange(of: calorieBurnRecords) { _, newRecords in
            RecordStorage.save(newRecords, forKey: RecordStorage.Key.calorieBurn)
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
