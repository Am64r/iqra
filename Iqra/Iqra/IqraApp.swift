import SwiftUI
import SwiftData
import AVFoundation

@main
struct IqraApp: App {
    let modelContainer: ModelContainer
    
    init() {
        // Initialize SwiftData container
        do {
            let schema = Schema([LocalTrack.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
        }
        
        // Configure audio session for background playback
        configureAudioSession()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(CatalogService())
                .environment(ConversionService())
                .environment(AudioPlayerService())
                .environment(DownloadManager())
        }
        .modelContainer(modelContainer)
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
}
