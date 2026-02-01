import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var playerService
    @Environment(CatalogService.self) private var catalogService
    @Environment(ConversionService.self) private var conversionService
    @State private var selectedTab = 0
    @State private var showingPlayer = false
    @Namespace private var playerTransition
    
    var body: some View {
        ZStack(alignment: .bottom) {
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
            
            if playerService.currentTrack != nil {
                NowPlayingBar(showingPlayer: $showingPlayer)
                    .padding(.bottom, 49)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: playerService.currentTrack != nil)
        .fullScreenCover(isPresented: $showingPlayer) {
            PlayerView()
        }
        .preferredColorScheme(.dark)
        .task {
            await catalogService.fetchCatalog()
        }
        .onAppear {
            conversionService.resumePendingJobIfNeeded(modelContext: modelContext)
        }
    }
}
