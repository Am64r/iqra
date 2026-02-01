import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioPlayerService.self) private var playerService
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Ambient background
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.4),
                        Color.accentColor.opacity(0.15),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Drag handle + header
                    VStack(spacing: 12) {
                        // Pull-down indicator
                        Capsule()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)
                        
                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.down")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            Spacer()
                            VStack(spacing: 2) {
                                Text("PLAYING FROM")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("Quran")
                                    .font(.caption.weight(.medium))
                            }
                            Spacer()
                            Color.clear.frame(width: 44, height: 44)
                        }
                        .padding(.horizontal, 8)
                    }
                    
                    // Artwork - responsive sizing
                    let artworkSize = min(geometry.size.width - 64, geometry.size.height * 0.38)
                    
                    ArtworkView(artworkURL: playerService.currentArtworkURL)
                        .frame(width: artworkSize, height: artworkSize)
                        .padding(.top, geometry.size.height * 0.04)
                    
                    // Track info
                    VStack(spacing: 6) {
                        Text(playerService.currentTrack?.title ?? "Not Playing")
                            .font(.title2.weight(.bold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        
                        Text(playerService.currentTrack?.artist ?? "Unknown Artist")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    
                    Spacer()
                    
                    // Progress bar
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(height: 6)
                                
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * (isDragging ? dragProgress : playerService.progress), height: 6)
                                
                                // Thumb
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: isDragging ? 14 : 0, height: isDragging ? 14 : 0)
                                    .offset(x: geo.size.width * (isDragging ? dragProgress : playerService.progress) - 7)
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
                            Spacer()
                            Text("-\(playerService.formattedRemainingTime)")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32)
                    
                    // Playback controls
                    HStack(spacing: 0) {
                        Button { playerService.previous() } label: {
                            Image(systemName: "backward.fill")
                                .font(.title2)
                                .frame(maxWidth: .infinity)
                        }
                        .opacity(playerService.hasPrevious ? 1 : 0.35)
                        
                        Button { playerService.seekBackward() } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title3)
                                .frame(maxWidth: .infinity)
                        }
                        
                        Button { playerService.togglePlayPause() } label: {
                            Image(systemName: playerService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                                .frame(maxWidth: .infinity)
                        }
                        
                        Button { playerService.seekForward() } label: {
                            Image(systemName: "goforward.15")
                                .font(.title3)
                                .frame(maxWidth: .infinity)
                        }
                        
                        Button { playerService.next() } label: {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                                .frame(maxWidth: .infinity)
                        }
                        .opacity(playerService.hasNext ? 1 : 0.35)
                    }
                    .foregroundStyle(.primary)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    
                    // Volume / extras row
                    HStack(spacing: 24) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        
                        Capsule()
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: 4)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 32)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Artwork View

struct ArtworkView: View {
    var artworkURL: URL?
    
    private var hasArtwork: Bool {
        guard let url = artworkURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    var body: some View {
        ZStack {
            // Shadow layers
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.2))
                .offset(y: 8)
                .blur(radius: 20)
            
            if hasArtwork, let url = artworkURL {
                // Show thumbnail artwork
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
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
            } else {
                placeholderArtwork
            }
        }
    }
    
    @ViewBuilder
    private var placeholderArtwork: some View {
        // Main artwork container
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.3),
                        Color.accentColor.opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                // Islamic geometric pattern hint
                GeometryReader { geo in
                    ZStack {
                        // Decorative circles
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                                .frame(width: geo.size.width * (0.4 + Double(i) * 0.2))
                        }
                        
                        // Waveform icon
                        Image(systemName: "waveform")
                            .font(.system(size: geo.size.width * 0.25, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
    }
}
