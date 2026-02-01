import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AudioPlayerService.self) private var playerService
    @Environment(CatalogService.self) private var catalogService
    @State private var selectedTab = 0
    @State private var showingPlayer = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tabItem { Label("Library", systemImage: "books.vertical") }
                    .tag(0)
                
                QuranView()
                    .tabItem { Label("Quran", systemImage: "book") }
                    .tag(1)
                
                ImportsView()
                    .tabItem { Label("Imports", systemImage: "square.and.arrow.down") }
                    .tag(2)
            }
            
            // Now Playing Bar - sits ABOVE the tab bar
            if playerService.currentTrack != nil {
                NowPlayingBar(showingPlayer: $showingPlayer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: playerService.currentTrack != nil)
        .fullScreenCover(isPresented: $showingPlayer) {
            PlayerView()
        }
        .task {
            await catalogService.fetchCatalog()
        }
    }
}
