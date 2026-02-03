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
                    loadingView
                } else if catalogService.tracks.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredTracks) { track in
                            SharedTrackRow(
                                track: track,
                                isDownloading: downloadManager.isDownloading(track.id),
                                downloadProgress: downloadManager.progress(for: track.id),
                                isPlaying: playerService.currentTrackId == track.id && playerService.isPlaying,
                                onPlay: { playerService.play(track) },
                                onDownload: { Task { @MainActor in try? await downloadManager.download(track, modelContext: modelContext) } }
                            )
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                }
            }
            .background(Theme.background)
            .navigationTitle("Quran")
            .searchable(text: $searchText, prompt: "Search surahs")
            .refreshable { await catalogService.fetchCatalog() }
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.accent)
            Text("Loading catalog...")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Tracks", systemImage: "book.closed")
                .foregroundStyle(Theme.accent)
        } description: {
            Text(catalogService.errorMessage ?? "Pull to refresh")
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            Button("Refresh") {
                Task { @MainActor in await catalogService.fetchCatalog() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .background(Theme.background)
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
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 30)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isPlaying ? Theme.accent : Theme.textPrimary)
                    .lineLimit(1)
                Text(track.reciter)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            
            Spacer()
            
            Text(track.formattedDuration)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
            
            if isDownloading {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(width: 28, height: 28)
            } else if isDownloaded {
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
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
