import Foundation
import SwiftData

/// Local track stored on device using SwiftData
@Model
final class LocalTrack {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String?
    var durationSeconds: Int
    var localFileName: String
    var sourceType: String
    var sourceURL: String?
    var surahNumber: Int?
    var createdAt: Date
    var sharedTrackId: UUID?
    var thumbnailFileName: String?
    
    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        durationSeconds: Int,
        localFileName: String,
        sourceType: String,
        sourceURL: String? = nil,
        surahNumber: Int? = nil,
        sharedTrackId: UUID? = nil,
        thumbnailFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.localFileName = localFileName
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.surahNumber = surahNumber
        self.createdAt = Date()
        self.sharedTrackId = sharedTrackId
        self.thumbnailFileName = thumbnailFileName
    }
    
    var localURL: URL {
        AppConfig.documentsURL.appendingPathComponent(localFileName)
    }
    
    var thumbnailURL: URL? {
        guard let thumbnailFileName else { return nil }
        return AppConfig.documentsURL.appendingPathComponent(thumbnailFileName)
    }
    
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: localURL.path)
    }
    
    var thumbnailExists: Bool {
        guard let thumbnailURL else { return false }
        return FileManager.default.fileExists(atPath: thumbnailURL.path)
    }
    
    var formattedDuration: String {
        TimeFormatter.format(seconds: durationSeconds)
    }
    
    var isQuran: Bool { sourceType == "quran" }
    var isYouTubeImport: Bool { sourceType == "youtube" }
    var displayArtist: String { artist ?? "Unknown" }
}
