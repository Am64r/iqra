import SwiftUI
import MediaPlayer

struct ExpandablePlayerView: View {
    @Environment(AudioPlayerService.self) private var playerService
    @Binding var isExpanded: Bool
    let collapsedScale: CGFloat
    @Namespace private var animation
    
    @State private var dragOffset: CGFloat = 0
    @State private var progressDragging = false
    @State private var dragProgress: Double = 0
    @State private var showTimespanSheet = false
    
    private let expandThreshold: CGFloat = 100
    
    var body: some View {
        let cornerRadius: CGFloat = 16
        
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
            
            if isExpanded {
                expandedPlayer
            } else {
                miniPlayer
            }
        }
        .offset(y: isExpanded ? max(0, dragOffset) : 0)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(isExpanded ? 0 : 0.3), radius: 20, y: -5)
        .gesture(
            isExpanded ?
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if value.translation.height > expandThreshold || value.velocity.height > 500 {
                            isExpanded = false
                        }
                        dragOffset = 0
                    }
                }
            : nil
        )
        .onTapGesture {
            if !isExpanded {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    isExpanded = true
                }
            }
        }
    }
    
    // MARK: - Mini Player
    
    private var miniPlayer: some View {
        let baseScale = max(1, collapsedScale)
        let sizeScale = 1 + (baseScale - 1) * 0.6
        let fontScale = 1 + (baseScale - 1) * 0.35
        let iconScale = 1 + (baseScale - 1) * 0.4
        
        let horizontalPadding = 12 * sizeScale
        let verticalPadding = 8 * sizeScale
        let artworkSize = 48 * sizeScale
        let artworkCornerRadius = 8 * sizeScale
        let titleFontSize = 15 * fontScale
        let artistFontSize = 12 * fontScale
        let playButtonSize = 44 * sizeScale
        let skipButtonWidth = 40 * sizeScale
        let skipButtonHeight = 44 * sizeScale
        let spacing = 12 * sizeScale
        let controlSpacing = 4 * sizeScale
        let playIconSize = 18 * iconScale
        let skipIconSize = 14 * iconScale
        
        return HStack(spacing: spacing) {
            // Artwork
            miniArtwork
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: artworkCornerRadius))
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(playerService.currentTrack?.title ?? "Not Playing")
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                
                Text(playerService.currentTrack?.artist ?? "")
                    .font(.system(size: artistFontSize))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: controlSpacing) {
                Button {
                    playerService.togglePlayPause()
                } label: {
                    Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: playIconSize, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: playButtonSize, height: playButtonSize)
                }
                
                Button {
                    if playerService.hasNext {
                        playerService.next()
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: skipIconSize, weight: .semibold))
                        .foregroundStyle(playerService.hasNext ? Theme.textPrimary : Theme.textTertiary)
                        .frame(width: skipButtonWidth, height: skipButtonHeight)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var miniArtwork: some View {
        if let artworkURL = playerService.currentArtworkURL,
           FileManager.default.fileExists(atPath: artworkURL.path) {
            AsyncImage(url: artworkURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
    }
    
    // MARK: - Expanded Player
    
    private var expandedPlayer: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            
            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Theme.textTertiary)
                    .frame(width: 36, height: 5)
                    .padding(.top, safeArea.top + 8)
                
                Spacer()
                
                // Large Artwork
                let artworkSize = min(geometry.size.width - 64, geometry.size.height * 0.35)
                expandedArtwork
                    .frame(width: artworkSize, height: artworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 15)
                
                // Track info
                VStack(spacing: 6) {
                    Text(playerService.currentTrack?.title ?? "Not Playing")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text(playerService.currentTrack?.artist ?? "Unknown Artist")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                
                // Progress
                progressView
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                
                // Controls
                playbackControlsView
                    .padding(.top, 16)

                // Loop button
                loopButton
                    .padding(.top, 12)

                Spacer()
            }
            .padding(.bottom, safeArea.bottom + 16)
        }
    }
    
    @ViewBuilder
    private var expandedArtwork: some View {
        if let artworkURL = playerService.currentArtworkURL,
           FileManager.default.fileExists(atPath: artworkURL.path) {
            AsyncImage(url: artworkURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    artworkPlaceholder
                }
            }
        } else {
            artworkPlaceholder
        }
    }
    
    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [Theme.accentGlow, Theme.accentSubtle],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: "waveform")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.accentMuted)
            }
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.2))
                        .frame(height: 4)

                    // Timespan range indicator
                    if playerService.isLooping, let span = playerService.activeTimespan, playerService.duration > 0 {
                        let startFrac = span.startTime / playerService.duration
                        let endFrac = min(span.endTime / playerService.duration, 1.0)

                        Capsule()
                            .fill(Theme.accent.opacity(0.25))
                            .frame(width: geo.size.width * (endFrac - startFrac), height: 4)
                            .offset(x: geo.size.width * startFrac)

                        Rectangle()
                            .fill(Theme.accent.opacity(0.6))
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * startFrac - 1)

                        Rectangle()
                            .fill(Theme.accent.opacity(0.6))
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * endFrac - 1)
                    }

                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * (progressDragging ? dragProgress : playerService.progress), height: 4)

                    Circle()
                        .fill(Theme.accent)
                        .frame(width: progressDragging ? 14 : 0, height: progressDragging ? 14 : 0)
                        .offset(x: geo.size.width * (progressDragging ? dragProgress : playerService.progress) - 7)
                        .animation(.easeOut(duration: 0.15), value: progressDragging)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            progressDragging = true
                            dragProgress = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { _ in
                            playerService.seek(to: dragProgress * playerService.duration)
                            progressDragging = false
                        }
                )
            }
            .frame(height: 24)
            
            HStack {
                Text(playerService.formattedCurrentTime)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("-\(playerService.formattedRemainingTime)")
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.caption.monospacedDigit())
        }
    }
    
    // MARK: - Playback Controls
    
    private var playbackControlsView: some View {
        HStack(spacing: 32) {
            Button {
                if playerService.hasPrevious {
                    playerService.previous()
                }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .foregroundStyle(playerService.hasPrevious ? Theme.textPrimary : Theme.textTertiary)
            
            Button { playerService.seekBackward() } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
            }
            .foregroundStyle(Theme.textPrimary)
            
            Button { playerService.togglePlayPause() } label: {
                Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            
            Button { playerService.seekForward() } label: {
                Image(systemName: "goforward.15")
                    .font(.title3)
            }
            .foregroundStyle(Theme.textPrimary)
            
            Button {
                if playerService.hasNext {
                    playerService.next()
                }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .foregroundStyle(playerService.hasNext ? Theme.textPrimary : Theme.textTertiary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Loop Button

    private var loopButton: some View {
        Button {
            showTimespanSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: playerService.isLooping ? "repeat.circle.fill" : "repeat.circle")
                    .font(.title3)
                if playerService.isLooping, let span = playerService.activeTimespan {
                    Text(span.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(playerService.isLooping ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                playerService.isLooping ? Theme.accent.opacity(0.15) : Color.clear,
                in: Capsule()
            )
        }
        .sheet(isPresented: $showTimespanSheet) {
            TimespanSheetView(
                trackId: playerService.currentTrackId ?? UUID(),
                trackDuration: playerService.duration
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
    }
}

// System volume slider using MPVolumeView
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsRouteButton = false
        
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.minimumTrackTintColor = Theme.accentUIColor
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
            slider.thumbTintColor = Theme.accentUIColor
        }
        
        return volumeView
    }
    
    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        if let slider = uiView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.minimumTrackTintColor = Theme.accentUIColor
            slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.2)
            slider.thumbTintColor = Theme.accentUIColor
        }
    }
}
