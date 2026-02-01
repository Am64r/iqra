import SwiftUI

struct NowPlayingBar: View {
    @Binding var showingPlayer: Bool
    @Environment(AudioPlayerService.self) private var playerService
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: geo.size.width * playerService.progress, height: 3)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 4, y: 0)
            }
            .frame(height: 3)
            .background(Theme.textTertiary.opacity(0.2))
            .clipShape(Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            HStack(spacing: 14) {
                artworkView
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(playerService.currentTrack?.title ?? "Not Playing")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    
                    Text(playerService.currentTrack?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Button { playerService.togglePlayPause() } label: {
                        Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    
                    Button { playerService.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(playerService.hasNext ? Theme.textPrimary : Theme.textTertiary)
                            .frame(width: 44, height: 48)
                            .contentShape(Rectangle())
                    }
                    .disabled(!playerService.hasNext)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background {
            if #available(iOS 26.0, *) {
                Capsule()
                    .glassEffect(.regular.interactive())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture { showingPlayer = true }
    }
    
    @ViewBuilder
    private var artworkView: some View {
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
    
    @ViewBuilder
    private var artworkPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Theme.accentSubtle, Theme.accent.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.accentMuted)
        }
    }
}
