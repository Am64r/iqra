import SwiftUI

struct TrackRow: View {
    let title: String
    let subtitle: String
    let duration: String
    let isPlaying: Bool
    var thumbnailURL: URL? = nil
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let thumbnailURL, FileManager.default.fileExists(atPath: thumbnailURL.path) {
                    AsyncImage(url: thumbnailURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            placeholderView
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if isPlaying {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.black.opacity(0.5))
                            PlayingIndicator()
                        }
                    }
                } else {
                    placeholderView
                }
            }
            .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(isPlaying ? Theme.accent : Theme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(duration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
            
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                .font(.caption)
                .foregroundStyle(isPlaying ? Theme.accent : Theme.textTertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Theme.accentSubtle, Theme.accent.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            if isPlaying {
                PlayingIndicator()
            } else {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(Theme.accentMuted)
            }
        }
    }
}

struct PlayingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.accent)
                    .frame(width: 3, height: animating ? CGFloat.random(in: 8...16) : 8)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(i) * 0.1),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
