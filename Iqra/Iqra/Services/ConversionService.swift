import Foundation
import SwiftData
import Observation
import UserNotifications

@Observable
final class ConversionService: NSObject, UNUserNotificationCenterDelegate {
    private(set) var isConverting = false
    private(set) var progressMessage = ""
    private(set) var errorMessage: String?
    private(set) var pendingTitle: String?
    private(set) var elapsedSeconds: Int = 0
    
    private var currentDownloadTask: URLSessionDownloadTask?
    private var isCancelled = false
    private var progressTimer: Task<Void, Never>?
    private var currentJobTask: Task<LocalTrack?, Error>?
    
    private static let pendingJobKey = "PendingConversionJob"
    private static let jobCreationMaxRetries = 3
    private static let jobPollingMaxErrors = 5
    private static let jobPollingMaxDuration: TimeInterval = 35 * 60
    private static let pollingIntervalSeconds: UInt64 = 2
    private static let pollingMaxBackoffSeconds: UInt64 = 10
    private static let downloadRequestTimeout: TimeInterval = 60
    private static let downloadResourceTimeout: TimeInterval = 60 * 60
    
    private static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = downloadRequestTimeout
        config.timeoutIntervalForResource = downloadResourceTimeout
        return URLSession(configuration: config)
    }()
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
    
    private struct PendingJob: Codable {
        let jobId: String
        let url: String
        let title: String?
        let videoDuration: Int?
        let startTime: Date
    }
    
    private func savePendingJob(_ job: PendingJob) {
        if let data = try? JSONEncoder().encode(job) {
            UserDefaults.standard.set(data, forKey: Self.pendingJobKey)
        }
    }
    
    private func loadPendingJob() -> PendingJob? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingJobKey) else { return nil }
        return try? JSONDecoder().decode(PendingJob.self, from: data)
    }
    
    private func clearPendingJob() {
        UserDefaults.standard.removeObject(forKey: Self.pendingJobKey)
    }
    
    @MainActor
    func resumePendingJobIfNeeded(modelContext: ModelContext) {
        guard let pending = loadPendingJob() else { return }
        guard !isConverting else { return }
        
        if Date().timeIntervalSince(pending.startTime) > 30 * 60 {
            clearPendingJob()
            return
        }
        
        isConverting = true
        isCancelled = false
        pendingTitle = pending.title ?? "Resuming download..."
        progressMessage = "Checking conversion status..."
        elapsedSeconds = Int(Date().timeIntervalSince(pending.startTime))
        startProgressTimer()
        
        currentJobTask = Task { @MainActor in
            defer {
                Task { @MainActor in
                    self.isConverting = false
                    self.progressMessage = ""
                    self.pendingTitle = nil
                    self.stopProgressTimer()
                }
            }
            
            do {
                let track = try await resumeJob(
                    jobId: pending.jobId,
                    url: pending.url,
                    videoDuration: pending.videoDuration,
                    modelContext: modelContext
                )
                clearPendingJob()
                sendCompletionNotification(title: track.title)
                return track
            } catch {
                clearPendingJob()
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
                return nil
            }
        }
    }
    
    private func sendCompletionNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = "\(title) is ready to play"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    @MainActor
    private func startProgressTimer() {
        elapsedSeconds = 0
        progressTimer = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                elapsedSeconds += 1
            }
        }
    }
    
    @MainActor
    private func stopProgressTimer() {
        progressTimer?.cancel()
        progressTimer = nil
    }
    
    private func formatElapsed(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let mins = seconds / 60
            let secs = seconds % 60
            return "\(mins)m \(secs)s"
        }
    }

    private func shouldRetryStatusCode(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (statusCode >= 500 && statusCode != 503)
    }

    private func pollDelayNanoseconds(forErrorRetries retries: Int) -> UInt64 {
        let backoff = min(Self.pollingMaxBackoffSeconds, Self.pollingIntervalSeconds * UInt64(1 << retries))
        return backoff * 1_000_000_000
    }
    
    @MainActor
    func importFromYouTube(url: String, modelContext: ModelContext) async throws -> LocalTrack {
        guard isValidYouTubeURL(url) else {
            throw ConversionError.invalidURL
        }
        
        guard !isConverting else {
            throw ConversionError.alreadyConverting
        }
        
        isConverting = true
        isCancelled = false
        errorMessage = nil
        startProgressTimer()
        
        defer {
            isConverting = false
            progressMessage = ""
            pendingTitle = nil
            currentDownloadTask = nil
            stopProgressTimer()
        }
        
        do {
            progressMessage = "Waking up server..."
            let metadata = try await fetchMetadata(url: url, updateProgress: { [weak self] msg in
                Task { @MainActor in self?.progressMessage = msg }
            })
            
            if isCancelled { throw ConversionError.cancelled }
            
            pendingTitle = metadata.title ?? "YouTube Import"
            
            progressMessage = "Converting to audio..."
            let (tempURL, title, artist, duration) = try await convertAndDownload(url: url, metadata: metadata, videoDuration: metadata.duration)
            
            if isCancelled { throw ConversionError.cancelled }
            
            progressMessage = "Saving..."
            let trackId = UUID()
            let fileName = "imports/\(trackId.uuidString).m4a"
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
            
            // Send push notification
            sendCompletionNotification(title: title)
            
            return track
        } catch is CancellationError {
            throw ConversionError.cancelled
        } catch let error as ConversionError where error == .cancelled {
            throw error
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func cancel() {
        isCancelled = true
        currentDownloadTask?.cancel()
        currentDownloadTask = nil
        currentJobTask?.cancel()
        currentJobTask = nil
        isConverting = false
        progressMessage = ""
        pendingTitle = nil
        clearPendingJob()
    }
    
    private func fetchMetadata(url: String, updateProgress: @escaping (String) -> Void) async throws -> TrackMetadata {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let metadataURL = URL(string: "\(CloudConfig.conversionServerURL)/metadata?url=\(encodedURL)")!
        
        // Retry with backoff to handle Fly.io cold starts
        let maxRetries = 3
        let baseDelay: UInt64 = 5_000_000_000 // 5 seconds
        
        for attempt in 0..<maxRetries {
            do {
                if isCancelled { throw ConversionError.cancelled }
                
                if attempt == 0 {
                    updateProgress("Connecting to server...")
                } else {
                    updateProgress("Retrying... (\(attempt + 1)/\(maxRetries))")
                }
                
                let (data, response) = try await URLSession.shared.data(from: metadataURL)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ConversionError.serverError("Invalid server response")
                }
                
                guard httpResponse.statusCode == 200 else {
                    throw ConversionError.serverError("Server returned status \(httpResponse.statusCode)")
                }
                
                updateProgress("Fetching video info...")
                return try JSONDecoder().decode(TrackMetadata.self, from: data)
            } catch let error as ConversionError {
                throw error // Don't retry our own errors
            } catch {
                let isLastAttempt = attempt == maxRetries - 1
                if isLastAttempt {
                    throw ConversionError.serverError("Server unavailable after \(maxRetries) attempts")
                }
                // Wait before retry (exponential backoff: 5s, 10s, 20s)
                let delay = baseDelay * UInt64(1 << attempt)
                try await Task.sleep(nanoseconds: delay)
            }
        }
        
        throw ConversionError.serverError("Failed to fetch metadata")
    }
    
    private func convertAndDownload(url: String, metadata: TrackMetadata, videoDuration: Int?) async throws -> (URL, String, String, Int) {
        let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let jobsURL = URL(string: "\(CloudConfig.conversionServerURL)/jobs?url=\(encodedURL)")!
        var request = URLRequest(url: jobsURL)
        request.httpMethod = "POST"

        var jobResult: JobResponse?
        for attempt in 0..<Self.jobCreationMaxRetries {
            do {
                let (jobData, jobResponse) = try await URLSession.shared.data(for: request)
                guard let httpResponse = jobResponse as? HTTPURLResponse else {
                    throw ConversionError.serverError("Invalid server response")
                }
                guard httpResponse.statusCode == 200 else {
                    if httpResponse.statusCode == 503 {
                        let detail = (try? JSONDecoder().decode([String: String].self, from: jobData))?["detail"]
                        throw ConversionError.serverError(detail ?? "Queue full, please try again in a few minutes")
                    }
                    if shouldRetryStatusCode(httpResponse.statusCode) && attempt < Self.jobCreationMaxRetries - 1 {
                        try await Task.sleep(nanoseconds: pollDelayNanoseconds(forErrorRetries: attempt))
                        continue
                    }
                    throw ConversionError.serverError("Failed to start conversion")
                }
                jobResult = try JSONDecoder().decode(JobResponse.self, from: jobData)
                break
            } catch let error as ConversionError {
                throw error
            } catch {
                if attempt == Self.jobCreationMaxRetries - 1 {
                    throw ConversionError.serverError("Failed to start conversion after retries")
                }
                try await Task.sleep(nanoseconds: pollDelayNanoseconds(forErrorRetries: attempt))
            }
        }

        guard let jobResult else {
            throw ConversionError.serverError("Invalid job response")
        }
        
        let jobId = jobResult.jobId
        savePendingJob(PendingJob(
            jobId: jobId,
            url: url,
            title: metadata.title,
            videoDuration: videoDuration,
            startTime: Date()
        ))
        
        let statusURL = URL(string: "\(CloudConfig.conversionServerURL)/jobs/\(jobId)")!
        
        let pollStartTime = Date()
        var pollErrorCount = 0
        while true {
            if isCancelled { throw ConversionError.cancelled }
            if Date().timeIntervalSince(pollStartTime) > Self.jobPollingMaxDuration {
                throw ConversionError.serverError("Conversion timed out. Please try again.")
            }
            
            // Update progress message with elapsed time
            await MainActor.run {
                let elapsed = formatElapsed(elapsedSeconds)
                if let duration = videoDuration, duration > 0 {
                    let durationStr = formatElapsed(duration)
                    progressMessage = "Converting \(durationStr) of audio... (\(elapsed))"
                } else {
                    progressMessage = "Converting to audio... (\(elapsed))"
                }
            }
            
            do {
                let (statusData, statusResponse) = try await URLSession.shared.data(from: statusURL)
                if let httpResponse = statusResponse as? HTTPURLResponse, httpResponse.statusCode == 404 {
                    throw ConversionError.serverError("Job expired. Please try again.")
                }

                guard let status = try? JSONDecoder().decode(JobStatus.self, from: statusData) else {
                    throw ConversionError.serverError("Failed to check job status")
                }
            
                switch status.status {
                case "completed":
                    break
                case "failed":
                    throw ConversionError.serverError(status.error ?? "Conversion failed")
                case "pending", "processing":
                    try await Task.sleep(nanoseconds: Self.pollingIntervalSeconds * 1_000_000_000)
                    continue
                default:
                    try await Task.sleep(nanoseconds: Self.pollingIntervalSeconds * 1_000_000_000)
                    continue
                }
            } catch let error as ConversionError {
                throw error
            } catch {
                pollErrorCount += 1
                if pollErrorCount > Self.jobPollingMaxErrors {
                    throw ConversionError.serverError("Failed to check job status. Please try again.")
                }
                try await Task.sleep(nanoseconds: pollDelayNanoseconds(forErrorRetries: pollErrorCount))
                continue
            }
            
            break
        }
        
        await MainActor.run {
            progressMessage = "Downloading audio..."
        }
        
        let downloadURL = URL(string: "\(CloudConfig.conversionServerURL)/jobs/\(jobId)/download")!
        let (tempURL, downloadResponse) = try await Self.downloadSession.download(from: downloadURL)
        
        guard let httpDownloadResponse = downloadResponse as? HTTPURLResponse,
              httpDownloadResponse.statusCode == 200 else {
            throw ConversionError.serverError("Failed to download converted audio")
        }
        
        let title = httpDownloadResponse.value(forHTTPHeaderField: "X-Track-Title")?
            .removingPercentEncoding ?? metadata.title ?? "Unknown Track"
        let artist = httpDownloadResponse.value(forHTTPHeaderField: "X-Track-Artist")?
            .removingPercentEncoding ?? metadata.artist ?? "Unknown"
        let duration = Int(httpDownloadResponse.value(forHTTPHeaderField: "X-Track-Duration") ?? "") ?? metadata.duration ?? 0
        
        let persistentURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try FileManager.default.moveItem(at: tempURL, to: persistentURL)
        clearPendingJob()
        
        return (persistentURL, title, artist, duration)
    }
    
    private func resumeJob(jobId: String, url: String, videoDuration: Int?, modelContext: ModelContext) async throws -> LocalTrack {
        let statusURL = URL(string: "\(CloudConfig.conversionServerURL)/jobs/\(jobId)")!

        let pollStartTime = Date()
        var pollErrorCount = 0
        while true {
            if isCancelled { throw ConversionError.cancelled }
            if Date().timeIntervalSince(pollStartTime) > Self.jobPollingMaxDuration {
                throw ConversionError.serverError("Conversion timed out. Please try again.")
            }
            
            await MainActor.run {
                let elapsed = formatElapsed(elapsedSeconds)
                if let duration = videoDuration, duration > 0 {
                    let durationStr = formatElapsed(duration)
                    progressMessage = "Converting \(durationStr) of audio... (\(elapsed))"
                } else {
                    progressMessage = "Converting to audio... (\(elapsed))"
                }
            }
            
            do {
                let (statusData, statusResponse) = try await URLSession.shared.data(from: statusURL)

                if let httpResponse = statusResponse as? HTTPURLResponse, httpResponse.statusCode == 404 {
                    throw ConversionError.serverError("Job expired. Please try again.")
                }

                guard let status = try? JSONDecoder().decode(JobStatus.self, from: statusData) else {
                    throw ConversionError.serverError("Failed to check job status")
                }

                switch status.status {
                case "completed":
                    break
                case "failed":
                    throw ConversionError.serverError(status.error ?? "Conversion failed")
                case "pending", "processing":
                    try await Task.sleep(nanoseconds: Self.pollingIntervalSeconds * 1_000_000_000)
                    continue
                default:
                    try await Task.sleep(nanoseconds: Self.pollingIntervalSeconds * 1_000_000_000)
                    continue
                }
            } catch let error as ConversionError {
                throw error
            } catch {
                pollErrorCount += 1
                if pollErrorCount > Self.jobPollingMaxErrors {
                    throw ConversionError.serverError("Failed to check job status. Please try again.")
                }
                try await Task.sleep(nanoseconds: pollDelayNanoseconds(forErrorRetries: pollErrorCount))
                continue
            }
            break
        }
        
        await MainActor.run { progressMessage = "Downloading audio..." }
        
        let downloadURL = URL(string: "\(CloudConfig.conversionServerURL)/jobs/\(jobId)/download")!
        let (tempURL, downloadResponse) = try await Self.downloadSession.download(from: downloadURL)
        
        guard let httpDownloadResponse = downloadResponse as? HTTPURLResponse,
              httpDownloadResponse.statusCode == 200 else {
            throw ConversionError.serverError("Failed to download converted audio")
        }
        
        let title = httpDownloadResponse.value(forHTTPHeaderField: "X-Track-Title")?
            .removingPercentEncoding ?? "Unknown Track"
        let artist = httpDownloadResponse.value(forHTTPHeaderField: "X-Track-Artist")?
            .removingPercentEncoding ?? "Unknown"
        let duration = Int(httpDownloadResponse.value(forHTTPHeaderField: "X-Track-Duration") ?? "") ?? videoDuration ?? 0
        
        await MainActor.run { progressMessage = "Saving..." }
        
        let trackId = UUID()
        let fileName = "imports/\(trackId.uuidString).m4a"
        let destURL = AppConfig.documentsURL.appendingPathComponent(fileName)
        
        try FileManager.default.createDirectory(at: AppConfig.importsDirectoryURL, withIntermediateDirectories: true)
        
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        
        let track = LocalTrack(
            id: trackId,
            title: title,
            artist: artist,
            durationSeconds: duration,
            localFileName: fileName,
            sourceType: "youtube",
            sourceURL: url,
            thumbnailFileName: nil
        )
        
        await MainActor.run {
            modelContext.insert(track)
            try? modelContext.save()
        }
        
        return track
    }
    
    private struct JobResponse: Codable {
        let jobId: String
        let status: String
        let message: String?
        
        enum CodingKeys: String, CodingKey {
            case jobId = "job_id"
            case status, message
        }
    }
    
    private struct JobStatus: Codable {
        let jobId: String
        let status: String
        let progress: String?
        let title: String?
        let artist: String?
        let duration: Int?
        let fileSize: Int?
        let error: String?
        
        enum CodingKeys: String, CodingKey {
            case jobId = "job_id"
            case status, progress, title, artist, duration, error
            case fileSize = "file_size"
        }
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
        
        let ext: String
        if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            if contentType.contains("jpeg") || contentType.contains("jpg") {
                ext = "jpg"
            } else if contentType.contains("png") {
                ext = "png"
            } else if contentType.contains("webp") {
                ext = "webp"
            } else {
                ext = "jpg"
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

enum ConversionError: LocalizedError, Equatable {
    case invalidURL, alreadyConverting, serverError(String), conversionFailed, cancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid YouTube URL"
        case .alreadyConverting: return "A conversion is already in progress"
        case .serverError(let msg): return msg
        case .conversionFailed: return "Failed to convert video"
        case .cancelled: return "Import cancelled"
        }
    }
}
