import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var playerService
    @Query(sort: \LocalTrack.createdAt, order: .reverse) private var localTracks: [LocalTrack]
    @State private var searchText = ""
    
    var filteredTracks: [LocalTrack] {
        guard !searchText.isEmpty else { return localTracks }
        let query = searchText.lowercased()
        return localTracks.filter {
            $0.title.lowercased().contains(query) ||
            $0.artist?.lowercased().contains(query) == true
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if localTracks.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(filteredTracks) { track in
                            TrackRow(
                                title: track.title,
                                subtitle: track.displayArtist,
                                duration: track.formattedDuration,
                                isPlaying: playerService.currentTrackId == track.id && playerService.isPlaying,
                                thumbnailURL: track.thumbnailURL
                            ) {
                                playerService.play(track)
                            }
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteTrack(track)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, 80)
                    .background(Theme.background)
                }
            }
            .background(Theme.background)
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search tracks")
            .toolbarBackground(Theme.background, for: .navigationBar)
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Downloads", systemImage: "arrow.down.circle")
                .foregroundStyle(Theme.accent)
        } description: {
            Text("Download tracks from the Quran tab or import from YouTube")
                .foregroundStyle(Theme.textSecondary)
        }
        .background(Theme.background)
    }
    
    private func deleteTrack(_ track: LocalTrack) {
        if playerService.currentTrackId == track.id { playerService.stop() }
        if track.fileExists { try? FileManager.default.removeItem(at: track.localURL) }
        if track.thumbnailExists, let thumbURL = track.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbURL)
        }
        modelContext.delete(track)
        try? modelContext.save()
    }
}
