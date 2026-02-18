import Foundation
import AVFoundation
import MediaPlayer
import Observation
import Combine

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
    private(set) var currentTrackId: UUID?
    private(set) var currentArtworkURL: URL?
    private(set) var activeTimespan: TrackTimespan?
    private(set) var isLooping = false

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
        let maxTime = isLooping ? (activeTimespan?.endTime ?? duration) : duration
        seek(to: min(currentTime + seconds, maxTime))
    }

    func seekBackward(by seconds: TimeInterval = 15) {
        let minTime = isLooping ? (activeTimespan?.startTime ?? 0) : 0
        seek(to: max(currentTime - seconds, minTime))
    }

    func activateTimespan(_ timespan: TrackTimespan) {
        activeTimespan = timespan
        isLooping = true
        if currentTime < timespan.startTime || currentTime > timespan.endTime {
            seek(to: timespan.startTime)
        }
        if !isPlaying { resume() }
    }

    func deactivateTimespan() {
        activeTimespan = nil
        isLooping = false
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
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self, self.hasNext else { return .commandFailed }
            self.next()
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.seekForward(by: 15)
            return .success
        }
        
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seekBackward(by: 15)
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: positionEvent.positionTime)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        let displayTitle: String
        let displayDuration: TimeInterval
        let displayElapsed: TimeInterval

        if isLooping, let span = activeTimespan {
            displayTitle = "\(span.name) (\(span.formattedRange))"
            displayDuration = span.endTime - span.startTime
            displayElapsed = max(0, currentTime - span.startTime)
        } else {
            displayTitle = track.title
            displayDuration = duration
            displayElapsed = currentTime
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: displayTitle,
            MPMediaItemPropertyArtist: track.artist ?? "Unknown Artist",
            MPMediaItemPropertyPlaybackDuration: displayDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: displayElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPMediaItemPropertyMediaType: MPMediaType.music.rawValue
        ]
        
        if queue.count > 1 {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = currentIndex
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
        }
        
        let artworkImage = createArtworkImage()
        let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in
            artworkImage
        }
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func createArtworkImage() -> UIImage {
        let size = CGSize(width: 600, height: 600)
        
        if let artworkURL = currentArtworkURL,
           let imageData = try? Data(contentsOf: artworkURL),
           let thumbnailImage = UIImage(data: imageData) {
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                let imageSize = thumbnailImage.size
                let scale = max(size.width / imageSize.width, size.height / imageSize.height)
                let scaledWidth = imageSize.width * scale
                let scaledHeight = imageSize.height * scale
                let x = (size.width - scaledWidth) / 2
                let y = (size.height - scaledHeight) / 2
                
                thumbnailImage.draw(in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight))
            }
        }
        
        let renderer = UIGraphicsImageRenderer(size: size)
        let accentColor = Theme.accentUIColor
        
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            let colors = [
                accentColor.withAlphaComponent(0.35).cgColor,
                accentColor.withAlphaComponent(0.15).cgColor,
                accentColor.withAlphaComponent(0.05).cgColor
            ]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: colors as CFArray,
                                       locations: [0, 0.5, 1])!
            
            context.cgContext.drawLinearGradient(gradient,
                                                  start: CGPoint(x: 0, y: 0),
                                                  end: CGPoint(x: size.width, y: size.height),
                                                  options: [])
            
            let circleColor = accentColor.withAlphaComponent(0.15)
            context.cgContext.setStrokeColor(circleColor.cgColor)
            context.cgContext.setLineWidth(1)
            for i in 0..<3 {
                let circleSize = size.width * (0.4 + CGFloat(i) * 0.2)
                let circleRect = CGRect(
                    x: (size.width - circleSize) / 2,
                    y: (size.height - circleSize) / 2,
                    width: circleSize,
                    height: circleSize
                )
                context.cgContext.strokeEllipse(in: circleRect)
            }
            
            let iconConfig = UIImage.SymbolConfiguration(pointSize: 150, weight: .light)
            if let waveformImage = UIImage(systemName: "waveform", withConfiguration: iconConfig) {
                let tintedImage = waveformImage.withTintColor(accentColor.withAlphaComponent(0.6))
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
    
    private func setupNotificationObservers() {
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
    
    private func playCurrentTrack() {
        guard currentIndex < queue.count else { return }
        deactivateTimespan()

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
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handleTrackEnded()
        }
        
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds

            if self.isLooping, let span = self.activeTimespan {
                if time.seconds >= span.endTime {
                    self.player?.seek(to: CMTime(seconds: span.startTime, preferredTimescale: 600))
                    self.currentTime = span.startTime
                }
            }

            if Int(time.seconds) % 5 == 0 {
                self.updateNowPlayingInfo()
            }
        }
        
        player?.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    private func handleTrackEnded() {
        if isLooping, let span = activeTimespan {
            seek(to: span.startTime)
            resume()
            return
        }
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
    var artworkURL: URL? { nil }
    
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
