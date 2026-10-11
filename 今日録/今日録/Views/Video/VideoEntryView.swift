import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct VideoTransfer: Transferable {
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

struct VideoEntryView: View {
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

struct MovieCameraPicker: UIViewControllerRepresentable {
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
