import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AudioPlayerService.self) private var playerService
    @Environment(CatalogService.self) private var catalogService
    @Environment(ConversionService.self) private var conversionService
    @State private var selectedTab = 0
    @State private var playerExpanded = false
    
    private let expandedTopGap: CGFloat = 86
    private let collapsedPlayerHeight: CGFloat = 64 * 1.5
    
    var body: some View {
        GeometryReader { geometry in
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
                
                // Expandable player overlay
                if playerService.currentTrack != nil {
                    let topGap = geometry.safeAreaInsets.top + expandedTopGap
                    let collapsedScale = collapsedPlayerHeight / 64
                    ExpandablePlayerView(isExpanded: $playerExpanded, collapsedScale: collapsedScale)
                        .frame(maxWidth: .infinity)
                        .frame(
                            height: playerExpanded ? geometry.size.height - topGap : collapsedPlayerHeight
                        )
                        .padding(.horizontal, playerExpanded ? 0 : 8)
                        .padding(.bottom, playerExpanded ? 0 : 57)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: playerService.currentTrack != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: playerExpanded)
        .ignoresSafeArea(edges: playerExpanded ? .all : [])
        .preferredColorScheme(.dark)
        .task {
            await catalogService.fetchCatalog()
        }
        .onAppear {
            conversionService.resumePendingJobIfNeeded(modelContext: modelContext)
        }
    }
}
