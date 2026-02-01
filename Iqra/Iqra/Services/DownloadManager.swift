import Foundation
import SwiftData
import Observation

/// Manages downloading tracks from Cloudflare R2
@Observable
final class DownloadManager {
    private(set) var downloadProgress: [UUID: Double] = [:]
    private(set) var activeDownloads: Set<UUID> = []
    private(set) var failedDownloads: [UUID: String] = [:]
    
    func isDownloading(_ trackId: UUID) -> Bool {
        activeDownloads.contains(trackId)
    }
    
    func progress(for trackId: UUID) -> Double {
        downloadProgress[trackId] ?? 0
    }
    
    func isDownloaded(sharedTrack: SharedTrack) -> Bool {
        let localPath = localPath(for: sharedTrack)
        return FileManager.default.fileExists(atPath: localPath.path)
    }
    
    func localPath(for sharedTrack: SharedTrack) -> URL {
        let relativePath = sharedTrack.r2Path.replacingOccurrences(of: "quran/", with: "")
        return AppConfig.quranDirectoryURL.appendingPathComponent(relativePath)
    }
    
    @MainActor
    func download(_ track: SharedTrack, modelContext: ModelContext) async throws -> LocalTrack {
        guard !activeDownloads.contains(track.id) else {
            throw DownloadError.alreadyDownloading
        }
        
        if isDownloaded(sharedTrack: track) {
            throw DownloadError.alreadyDownloaded
        }
        
        activeDownloads.insert(track.id)
        downloadProgress[track.id] = 0
        failedDownloads.removeValue(forKey: track.id)
        
        do {
            let destURL = localPath(for: track)
            let directory = destURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            
            let (tempURL, _) = try await URLSession.shared.download(from: track.downloadURL)
            
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destURL)
            
            let localTrack = LocalTrack(
                title: track.title,
                artist: track.reciter,
                durationSeconds: track.durationSeconds ?? 0,
                localFileName: "quran/\(track.r2Path.replacingOccurrences(of: "quran/", with: ""))",
                sourceType: "quran",
                sourceURL: track.r2Path,
                surahNumber: track.surahNumber,
                sharedTrackId: track.id
            )
            
            modelContext.insert(localTrack)
            try modelContext.save()
            
            activeDownloads.remove(track.id)
            downloadProgress.removeValue(forKey: track.id)
            
            return localTrack
        } catch {
            activeDownloads.remove(track.id)
            downloadProgress.removeValue(forKey: track.id)
            failedDownloads[track.id] = error.localizedDescription
            throw error
        }
    }
}

enum DownloadError: LocalizedError {
    case alreadyDownloading
    case alreadyDownloaded
    
    var errorDescription: String? {
        switch self {
        case .alreadyDownloading: return "Track is already being downloaded"
        case .alreadyDownloaded: return "Track is already downloaded"
        }
    }
}
