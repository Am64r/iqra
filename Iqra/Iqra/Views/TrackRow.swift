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
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        if isPlaying {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.black.opacity(0.4))
                            PlayingIndicator()
                        }
                    }
                } else {
                    placeholderView
                }
            }
            .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(isPlaying ? Color.accentColor : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(duration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                .font(.caption)
                .foregroundStyle(isPlaying ? Color.accentColor : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    @ViewBuilder
    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.1))
            
            if isPlaying {
                PlayingIndicator()
            } else {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor.opacity(0.5))
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
                    .fill(Color.accentColor)
                    .frame(width: 3, height: animating ? CGFloat.random(in: 8...16) : 8)
                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.1), value: animating)
            }
        }
        .onAppear { animating = true }
    }
}
