import SwiftUI
import AVKit
import AVFoundation
import UIKit

struct VideoTrimView: View {
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
