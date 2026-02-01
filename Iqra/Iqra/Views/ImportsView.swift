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
    @State private var showingError = false
    
    var body: some View {
        NavigationStack {
            Group {
                if imports.isEmpty && !conversionService.isConverting {
                    emptyStateView
                } else {
                    List {
                        if conversionService.isConverting {
                            PendingImportRow(
                                title: conversionService.pendingTitle ?? "Importing...",
                                status: conversionService.progressMessage,
                                onCancel: { conversionService.cancel() }
                            )
                            .listRowBackground(Color.clear)
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
                    .background(Theme.background)
                }
            }
            .background(Theme.background)
            .navigationTitle("Imports")
            .toolbar {
                Button { showingImportSheet = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Theme.accent)
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $showingImportSheet) {
                importSheet
            }
            .alert("Import Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importError ?? "An unknown error occurred")
            }
        }
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Imports", systemImage: "square.and.arrow.down")
                .foregroundStyle(Theme.accent)
        } description: {
            Text("Import audio from YouTube")
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            Button("Import from YouTube") { showingImportSheet = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .background(Theme.background)
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
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                
                Section {
                    Button {
                        startImport()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Import")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(youtubeURL.isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.surface)
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
        .presentationBackground(Theme.surface)
    }
    
    private func startImport() {
        let urlToImport = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !urlToImport.isEmpty else {
            importError = "Please enter a URL"
            return
        }
        
        showingImportSheet = false
        youtubeURL = ""
        importError = nil
        
        Task {
            do {
                _ = try await conversionService.importFromYouTube(url: urlToImport, modelContext: modelContext)
            } catch let error as ConversionError where error == .cancelled {
                // User cancelled, no need to show error
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    showingError = true
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

struct PendingImportRow: View {
    let title: String
    let status: String
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accentSubtle)
                    .frame(width: 48, height: 48)
                
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Theme.accent)
                    
                    Text(status.isEmpty ? "Starting..." : status)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                
                Text("We'll notify you when it's ready")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
            
            Spacer()
            
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
