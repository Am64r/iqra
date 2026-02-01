import Foundation
import AVFoundation
import MediaPlayer
import Observation
import Combine

/// Service for audio playback using AVPlayer
@Observable
final class AudioPlayerService {
    private(set) var currentTrack: (any PlayableTrack)?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var playbackRate: Float = 1.0
    private(set) var isLoading = false
    private(set) var queue: [any PlayableTrack] = []
    private(set) var currentIndex: Int = 0
    
    // Store these separately to avoid Sendable issues with PersistentModels
    private(set) var currentTrackId: UUID?
    private(set) var currentArtworkURL: URL?
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotificationObservers()
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
    
    func play(_ track: some PlayableTrack) {
        queue = [track]
        currentIndex = 0
        playCurrentTrack()
    }
    
    func play(_ tracks: [some PlayableTrack], startingAt index: Int = 0) {
        queue = tracks
        currentIndex = min(index, tracks.count - 1)
        playCurrentTrack()
    }
    
    func resume() {
        player?.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }
    
    func stop() {
        pause()
        player?.replaceCurrentItem(with: nil)
        currentTrack = nil
        currentTrackId = nil
        currentArtworkURL = nil
        currentTime = 0
        duration = 0
        queue = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func next() {
        guard currentIndex < queue.count - 1 else { return }
        currentIndex += 1
        playCurrentTrack()
    }
    
    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        playCurrentTrack()
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] _ in
            self?.currentTime = time
            self?.updateNowPlayingInfo()
        }
    }
    
    func seekForward(by seconds: TimeInterval = 15) {
        seek(to: min(currentTime + seconds, duration))
    }
    
    func seekBackward(by seconds: TimeInterval = 15) {
        seek(to: max(currentTime - seconds, 0))
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player?.rate = rate }
        updateNowPlayingInfo()
    }
    
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var formattedCurrentTime: String { TimeFormatter.format(timeInterval: currentTime) }
    var formattedDuration: String { TimeFormatter.format(timeInterval: duration) }
    var formattedRemainingTime: String { TimeFormatter.format(timeInterval: max(0, duration - currentTime)) }
    var hasNext: Bool { currentIndex < queue.count - 1 }
    var hasPrevious: Bool { currentIndex > 0 || currentTime > 3 }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - Remote Command Center (Lock Screen Controls)
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        // Toggle Play/Pause
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        // Next Track
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.hasNext else { return .commandFailed }
            self.next()
            return .success
        }
        
        // Previous Track
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        
        // Skip Forward 15 seconds
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.seekForward(by: 15)
            return .success
        }
        
        // Skip Backward 15 seconds
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seekBackward(by: 15)
            return .success
        }
        
        // Seek (scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: positionEvent.positionTime)
            return .success
        }
    }
    
    // MARK: - Now Playing Info (Lock Screen Display)
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist ?? "Unknown Artist",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPMediaItemPropertyMediaType: MPMediaType.music.rawValue
        ]
        
        // Add queue info if available
        if queue.count > 1 {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentIndex
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
        }
        
        // Create artwork
        let artworkImage = createArtworkImage()
        let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in
            artworkImage
        }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func createArtworkImage() -> UIImage {
        let size = CGSize(width: 600, height: 600)
        
        // Try to load thumbnail from stored URL
        if let artworkURL = currentArtworkURL,
           let imageData = try? Data(contentsOf: artworkURL),
           let thumbnailImage = UIImage(data: imageData) {
            // Scale and crop thumbnail to square
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                // Calculate aspect fill rect
                let imageSize = thumbnailImage.size
                let scale = max(size.width / imageSize.width, size.height / imageSize.height)
                let scaledWidth = imageSize.width * scale
                let scaledHeight = imageSize.height * scale
                let x = (size.width - scaledWidth) / 2
                let y = (size.height - scaledHeight) / 2
                
                thumbnailImage.draw(in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight))
            }
        }
        
        // Fallback to default artwork
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Background gradient
            let colors = [
                UIColor.systemTeal.withAlphaComponent(0.3).cgColor,
                UIColor.systemTeal.withAlphaComponent(0.1).cgColor
            ]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: colors as CFArray,
                                       locations: [0, 1])!
            
            context.cgContext.drawLinearGradient(gradient,
                                                  start: CGPoint(x: 0, y: 0),
                                                  end: CGPoint(x: size.width, y: size.height),
                                                  options: [])
            
            // Waveform icon
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 150, weight: .light)
            if let waveformImage = UIImage(systemName: "waveform", withConfiguration: iconConfig) {
                let tintedImage = waveformImage.withTintColor(.systemTeal.withAlphaComponent(0.6))
                let iconSize = tintedImage.size
                let iconRect = CGRect(
                    x: (size.width - iconSize.width) / 2,
                    y: (size.height - iconSize.height) / 2,
                    width: iconSize.width,
                    height: iconSize.height
                )
                tintedImage.draw(in: iconRect)
            }
        }
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Listen for audio interruptions (phone calls, etc.)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
    }
    
    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }
    
    // MARK: - Playback
    
    private func playCurrentTrack() {
        guard currentIndex < queue.count else { return }
        
        let track = queue[currentIndex]
        guard let url = track.getPlaybackURL() else { return }
        
        isLoading = true
        currentTrack = track
        currentTrackId = track.id
        currentArtworkURL = track.artworkURL
        
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        cancellables.removeAll()
        
        let playerItem = AVPlayerItem(url: url)
        
        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }
        
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .readyToPlay {
                    self?.isLoading = false
                    self?.updateNowPlayingInfo()
                }
            }
            .store(in: &cancellables)
        
        playerItem.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in
                if dur.isNumeric {
                    self?.duration = dur.seconds
                    self?.updateNowPlayingInfo()
                }
            }
            .store(in: &cancellables)
        
        // Track end notification
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handleTrackEnded()
        }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            // Update now playing info periodically for accurate progress
            if Int(time.seconds) % 5 == 0 {
                self?.updateNowPlayingInfo()
            }
        }
        
        player?.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    private func handleTrackEnded() {
        if hasNext {
            next()
        } else {
            isPlaying = false
            currentTime = 0
            seek(to: 0)
            updateNowPlayingInfo()
        }
    }
}

// MARK: - PlayableTrack Protocol

protocol PlayableTrack {
    var id: UUID { get }
    var title: String { get }
    var artist: String? { get }
    var trackDuration: Int { get }
    var artworkURL: URL? { get }
    func getPlaybackURL() -> URL?
}

extension SharedTrack: PlayableTrack {
    var artist: String? { reciter }
    var trackDuration: Int { durationSeconds ?? 0 }
    var artworkURL: URL? { nil } // Quran tracks don't have artwork yet
    
    func getPlaybackURL() -> URL? {
        let localPath = AppConfig.quranDirectoryURL
            .appendingPathComponent(r2Path.replacingOccurrences(of: "quran/", with: ""))
        return FileManager.default.fileExists(atPath: localPath.path) ? localPath : downloadURL
    }
}

extension LocalTrack: PlayableTrack {
    var trackDuration: Int { durationSeconds }
    var artworkURL: URL? { thumbnailExists ? thumbnailURL : nil }
    func getPlaybackURL() -> URL? { fileExists ? localURL : nil }
}
