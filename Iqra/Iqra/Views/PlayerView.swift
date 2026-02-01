import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioPlayerService.self) private var playerService
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Ambient background with green gradient
                backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with glass dismiss button
                    headerView
                    
                    // Artwork - responsive sizing
                    let artworkSize = min(geometry.size.width - 64, geometry.size.height * 0.38)
                    
                    ArtworkView(artworkURL: playerService.currentArtworkURL)
                        .frame(width: artworkSize, height: artworkSize)
                        .padding(.top, geometry.size.height * 0.03)
                    
                    // Track info
                    trackInfoView
                        .padding(.top, 28)
                    
                    Spacer()
                    
                    // Progress bar
                    progressView
                        .padding(.horizontal, 32)
                    
                    // Playback controls with glass effect
                    playbackControlsView
                        .padding(.top, 24)
                    
                    // Volume slider
                    volumeView
                        .padding(.horizontal, 32)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    private var backgroundGradient: some View {
        ZStack {
            Theme.background
            
            LinearGradient(
                colors: [
                    Theme.accent.opacity(0.35),
                    Theme.accent.opacity(0.15),
                    Theme.accent.opacity(0.05),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            RadialGradient(
                colors: [Theme.accent.opacity(0.2), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 500
            )
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Theme.textTertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background {
                            if #available(iOS 26.0, *) {
                                Circle().glassEffect(.regular)
                            } else {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Circle().stroke(Theme.glassBorder, lineWidth: 1))
                            }
                        }
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("PLAYING FROM")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Iqra")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                
                Spacer()
                
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var trackInfoView: some View {
        VStack(spacing: 8) {
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
    }
    
    private var progressView: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.15))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * (isDragging ? dragProgress : playerService.progress), height: 6)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 4, y: 0)
                    
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: isDragging ? 16 : 0, height: isDragging ? 16 : 0)
                        .shadow(color: Theme.accent.opacity(0.5), radius: 6, y: 0)
                        .offset(x: geo.size.width * (isDragging ? dragProgress : playerService.progress) - 8)
                        .animation(.easeOut(duration: 0.15), value: isDragging)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragProgress = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { value in
                            playerService.seek(to: dragProgress * playerService.duration)
                            isDragging = false
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
    
    private var playbackControlsView: some View {
        HStack(spacing: 0) {
            Button { playerService.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(playerService.hasPrevious ? Theme.textPrimary : Theme.textTertiary)
            
            Button { playerService.seekBackward() } label: {
                Image(systemName: "gobackward.15")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Theme.textPrimary)
            
            Button { playerService.togglePlayPause() } label: {
                ZStack {
                    if #available(iOS 26.0, *) {
                        Circle()
                            .glassEffect(.regular.interactive().tint(Theme.accent))
                            .frame(width: 80, height: 80)
                    } else {
                        Circle()
                            .fill(Theme.accentSubtle)
                            .overlay(Circle().stroke(Theme.glassBorder, lineWidth: 1))
                            .frame(width: 80, height: 80)
                    }
                    
                    Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .offset(x: playerService.isPlaying ? 0 : 2)
                }
            }
            .frame(maxWidth: .infinity)
            
            Button { playerService.seekForward() } label: {
                Image(systemName: "goforward.15")
                    .font(.title3)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Theme.textPrimary)
            
            Button { playerService.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(playerService.hasNext ? Theme.textPrimary : Theme.textTertiary)
        }
        .padding(.horizontal, 16)
    }
    
    private var volumeView: some View {
        HStack(spacing: 16) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(Theme.textTertiary)
            
            Capsule()
                .fill(Theme.textPrimary.opacity(0.15))
                .frame(height: 4)
            
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(Theme.textTertiary)
        }
        .font(.caption)
    }
}

struct ArtworkView: View {
    var artworkURL: URL?
    
    private var hasArtwork: Bool {
        guard let url = artworkURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.3))
                .offset(y: 10)
                .blur(radius: 25)
            
            if hasArtwork, let url = artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        placeholderArtwork
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Theme.glassBorder, lineWidth: 1)
                }
            } else {
                placeholderArtwork
            }
        }
    }
    
    @ViewBuilder
    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(
                LinearGradient(
                    colors: [
                        Theme.accentGlow,
                        Theme.accentSubtle
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(Theme.accent.opacity(0.15), lineWidth: 1)
                                .frame(width: geo.size.width * (0.4 + Double(i) * 0.2))
                        }
                        
                        Image(systemName: "waveform")
                            .font(.system(size: geo.size.width * 0.25, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.accentMuted, Theme.accent.opacity(0.3)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.glassBorder, lineWidth: 1)
            }
    }
}
