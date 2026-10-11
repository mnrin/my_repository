import SwiftUI

struct VideoRecord: Codable, Identifiable, Equatable {
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

enum VideoMergeError: Error {
    case trackCreationFailed
    case missingVideoTrack
    case invalidDuration
    case exportUnavailable
}

enum VideoTrimError: Error {
    case exportUnavailable
}
