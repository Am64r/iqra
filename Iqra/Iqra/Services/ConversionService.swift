import Foundation
import SwiftData
import Observation

/// Service for importing audio from YouTube
@Observable
final class ConversionService {
    private(set) var isConverting = false
    private(set) var progressMessage = ""
    private(set) var errorMessage: String?
    private(set) var pendingTitle: String?
    
    @MainActor
    func importFromYouTube(url: String, modelContext: ModelContext) async throws -> LocalTrack {
        guard isValidYouTubeURL(url) else {
            throw ConversionError.invalidURL
        }
        
        guard !isConverting else {
            throw ConversionError.alreadyConverting
        }
        
        isConverting = true
        errorMessage = nil
        
        defer {
            isConverting = false
            progressMessage = ""
            pendingTitle = nil
        }
        
        do {
            progressMessage = "Fetching video info..."
            let metadata = try await fetchMetadata(url: url)
            pendingTitle = metadata.title ?? "YouTube Import"
            
            progressMessage = "Converting to audio..."
            let (tempURL, title, artist, duration) = try await convertAndDownload(url: url, metadata: metadata)
            
            progressMessage = "Saving..."
            let trackId = UUID()
            let fileName = "imports/\(trackId.uuidString).mp3"
            let destURL = AppConfig.documentsURL.appendingPathComponent(fileName)
            
            try FileManager.default.createDirectory(at: AppConfig.importsDirectoryURL, withIntermediateDirectories: true)
            
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destURL)
            
            // Download thumbnail if available
            var thumbnailFileName: String? = nil
            if let thumbnailURLString = metadata.thumbnail,
               let thumbnailURL = URL(string: thumbnailURLString) {
                thumbnailFileName = try? await downloadThumbnail(from: thumbnailURL, trackId: trackId)
            }
            
            let track = LocalTrack(
                id: trackId,
                title: title,
                artist: artist,
                durationSeconds: duration,
                localFileName: fileName,
                sourceType: "youtube",
                sourceURL: url,
                thumbnailFileName: thumbnailFileName
            )
            
            modelContext.insert(track)
            try modelContext.save()
            
            return track
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func cancel() {
        isConverting = false
        progressMessage = ""
    }
    
    private func fetchMetadata(url: String) async throws -> TrackMetadata {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let metadataURL = URL(string: "\(CloudConfig.conversionServerURL)/metadata?url=\(encodedURL)")!
        
        let (data, response) = try await URLSession.shared.data(from: metadataURL)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConversionError.serverError("Failed to fetch metadata")
        }
        
        return try JSONDecoder().decode(TrackMetadata.self, from: data)
    }
    
    private func convertAndDownload(url: String, metadata: TrackMetadata) async throws -> (URL, String, String, Int) {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let convertURL = URL(string: "\(CloudConfig.conversionServerURL)/convert?url=\(encodedURL)")!
        
        let (tempURL, response) = try await URLSession.shared.download(from: convertURL)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConversionError.conversionFailed
        }
        
        let title = httpResponse.value(forHTTPHeaderField: "X-Track-Title")?
            .removingPercentEncoding ?? metadata.title ?? "Unknown Track"
        let artist = httpResponse.value(forHTTPHeaderField: "X-Track-Artist")?
            .removingPercentEncoding ?? metadata.artist ?? "Unknown"
        let duration = Int(httpResponse.value(forHTTPHeaderField: "X-Track-Duration") ?? "") ?? metadata.duration ?? 0
        
        let persistentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try FileManager.default.moveItem(at: tempURL, to: persistentURL)
        
        return (persistentURL, title, artist, duration)
    }
    
    private func isValidYouTubeURL(_ url: String) -> Bool {
        ["youtube.com/watch", "youtu.be/", "youtube.com/shorts/", "music.youtube.com/watch"]
            .contains { url.contains($0) }
    }
    
    private func downloadThumbnail(from url: URL, trackId: UUID) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ConversionError.serverError("Failed to download thumbnail")
        }
        
        // Determine file extension from content type or URL
        let ext: String
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            if contentType.contains("jpeg") || contentType.contains("jpg") {
                ext = "jpg"
            } else if contentType.contains("png") {
                ext = "png"
            } else if contentType.contains("webp") {
                ext = "webp"
            } else {
                ext = "jpg" // Default to jpg
            }
        } else {
            ext = "jpg"
        }
        
        let fileName = "imports/\(trackId.uuidString)_thumb.\(ext)"
        let destURL = AppConfig.documentsURL.appendingPathComponent(fileName)
        
        try data.write(to: destURL)
        
        return fileName
    }
}

struct TrackMetadata: Codable {
    let title: String?
    let artist: String?
    let duration: Int?
    let thumbnail: String?
}

enum ConversionError: LocalizedError {
    case invalidURL, alreadyConverting, serverError(String), conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid YouTube URL"
        case .alreadyConverting: return "A conversion is already in progress"
        case .serverError(let msg): return msg
        case .conversionFailed: return "Failed to convert video"
        }
    }
}
