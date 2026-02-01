import SwiftUI
import SwiftData

struct ImportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ConversionService.self) private var conversionService
    @Environment(AudioPlayerService.self) private var playerService
    
    @Query(filter: #Predicate<LocalTrack> { $0.sourceType == "youtube" },
           sort: \LocalTrack.createdAt, order: .reverse) private var imports: [LocalTrack]
    
    @State private var showingImportSheet = false
    @State private var youtubeURL = ""
    @State private var importError: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if imports.isEmpty && !conversionService.isConverting {
                    ContentUnavailableView {
                        Label("No Imports", systemImage: "square.and.arrow.down")
                    } description: {
                        Text("Import audio from YouTube")
                    } actions: {
                        Button("Import from YouTube") { showingImportSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if conversionService.isConverting {
                            PendingImportRow(
                                title: conversionService.pendingTitle ?? "Importing...",
                                status: conversionService.progressMessage
                            )
                        }
                        
                        ForEach(imports) { track in
                            TrackRow(
                                title: track.title,
                                subtitle: track.displayArtist,
                                duration: track.formattedDuration,
                                isPlaying: playerService.currentTrackId == track.id && playerService.isPlaying,
                                thumbnailURL: track.thumbnailURL
                            ) {
                                playerService.play(track)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteTrack(track)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Imports")
            .toolbar {
                Button { showingImportSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingImportSheet) {
                importSheet
            }
        }
    }
    
    private var importSheet: some View {
        NavigationStack {
            Form {
                Section("Paste YouTube Link") {
                    TextField("YouTube URL", text: $youtubeURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                if let error = importError {
                    Section { Text(error).foregroundStyle(.red) }
                }
                
                Section {
                    Button {
                        startImport()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Import")
                            Spacer()
                        }
                    }
                    .disabled(youtubeURL.isEmpty)
                }
            }
            .navigationTitle("Import from YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        showingImportSheet = false
                        youtubeURL = ""
                        importError = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func startImport() {
        // Capture and clean URL before clearing state
        let urlToImport = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !urlToImport.isEmpty else {
            importError = "Please enter a URL"
            return
        }
        
        // Close sheet immediately
        showingImportSheet = false
        youtubeURL = ""
        importError = nil
        
        // Start import in background
        Task {
            do {
                _ = try await conversionService.importFromYouTube(url: urlToImport, modelContext: modelContext)
            } catch {
                await MainActor.run {
                    // Show error as an alert or notification if needed
                    print("Import failed: \(error.localizedDescription)")
                }
            }
        }
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

// MARK: - Pending Import Row

struct PendingImportRow: View {
    let title: String
    let status: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    
                    Text(status.isEmpty ? "Starting..." : status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
