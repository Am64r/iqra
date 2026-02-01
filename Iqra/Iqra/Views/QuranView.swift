import SwiftUI
import SwiftData

struct QuranView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CatalogService.self) private var catalogService
    @Environment(AudioPlayerService.self) private var playerService
    @Environment(DownloadManager.self) private var downloadManager
    @State private var searchText = ""
    
    var filteredTracks: [SharedTrack] {
        let tracks = searchText.isEmpty ? catalogService.tracks : catalogService.search(searchText)
        return tracks.sorted { ($0.surahNumber ?? 999) < ($1.surahNumber ?? 999) }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if catalogService.isLoading && catalogService.tracks.isEmpty {
                    ProgressView("Loading catalog...")
                } else if catalogService.tracks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tracks", systemImage: "book.closed")
                    } description: {
                        Text(catalogService.errorMessage ?? "Pull to refresh")
                    } actions: {
                        Button("Refresh") { Task { await catalogService.fetchCatalog() } }
                    }
                } else {
                    List {
                        ForEach(filteredTracks) { track in
                            SharedTrackRow(
                                track: track,
                                isDownloading: downloadManager.isDownloading(track.id),
                                downloadProgress: downloadManager.progress(for: track.id),
                                isPlaying: playerService.currentTrackId == track.id && playerService.isPlaying,
                                onPlay: { playerService.play(track) },
                                onDownload: { Task { try? await downloadManager.download(track, modelContext: modelContext) } }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Quran")
            .searchable(text: $searchText, prompt: "Search surahs")
            .refreshable { await catalogService.fetchCatalog() }
        }
    }
}

struct SharedTrackRow: View {
    let track: SharedTrack
    let isDownloading: Bool
    let downloadProgress: Double
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDownload: () -> Void
    
    @Environment(DownloadManager.self) private var downloadManager
    
    var isDownloaded: Bool { downloadManager.isDownloaded(sharedTrack: track) }
    
    var body: some View {
        HStack(spacing: 12) {
            if let num = track.surahNumber {
                Text("\(num)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .lineLimit(1)
                Text(track.reciter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(track.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            
            if isDownloading {
                ProgressView()
                    .frame(width: 24, height: 24)
            } else if isDownloaded {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isDownloaded { onPlay() }
            else if !isDownloading { onDownload() }
        }
    }
}
