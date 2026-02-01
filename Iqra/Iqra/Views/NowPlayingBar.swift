import SwiftUI

struct NowPlayingBar: View {
    @Binding var showingPlayer: Bool
    @Environment(AudioPlayerService.self) private var playerService
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator at top
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * playerService.progress)
            }
            .frame(height: 3)
            .background(Color.primary.opacity(0.08))
            
            // Main content
            HStack(spacing: 14) {
                // Artwork thumbnail
                Group {
                    if let artworkURL = playerService.currentArtworkURL,
                       FileManager.default.fileExists(atPath: artworkURL.path) {
                        AsyncImage(url: artworkURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                artworkPlaceholder
                            }
                        }
                    } else {
                        artworkPlaceholder
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text(playerService.currentTrack?.title ?? "Not Playing")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    
                    Text(playerService.currentTrack?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: 4) {
                    Button { playerService.togglePlayPause() } label: {
                        Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    
                    Button { playerService.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 48)
                            .contentShape(Rectangle())
                    }
                    .opacity(playerService.hasNext ? 1 : 0.35)
                    .disabled(!playerService.hasNext)
                }
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 10, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture { showingPlayer = true }
    }
    
    @ViewBuilder
    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.7))
        }
    }
}
