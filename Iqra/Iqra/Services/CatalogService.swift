import Foundation
import Observation

/// Service for fetching the track catalog from R2
@Observable
final class CatalogService {
    private(set) var tracks: [SharedTrack] = []
    private(set) var reciters: [Reciter] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastSyncDate: Date?
    
    init() {
        loadCachedCatalog()
    }
    
    func fetchCatalog() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let catalog = try await downloadCatalog()
            reciters = catalog.reciters
            tracks = catalog.tracks.map { track in
                SharedTrack(
                    id: UUID(),
                    title: track.title,
                    surahNumber: track.surahNumber,
                    reciter: track.reciter,
                    r2Path: track.r2Path,
                    durationSeconds: track.durationSeconds,
                    createdAt: nil
                )
            }
            lastSyncDate = Date()
            cacheCatalog(catalog)
        } catch {
            errorMessage = error.localizedDescription
            print("Catalog fetch error: \(error)")
        }
        
        isLoading = false
    }
    
    func tracks(for reciter: String) -> [SharedTrack] {
        tracks.filter { $0.reciter == reciter }
    }
    
    func tracksBySurah() -> [SharedTrack] {
        tracks.sorted { ($0.surahNumber ?? 999) < ($1.surahNumber ?? 999) }
    }
    
    func uniqueReciters() -> [String] {
        Array(Set(tracks.map { $0.reciter })).sorted()
    }
    
    func reciterName(for slug: String) -> String {
        reciters.first { $0.slug == slug }?.name ?? slug
    }
    
    func search(_ query: String) -> [SharedTrack] {
        guard !query.isEmpty else { return tracks }
        let lowercased = query.lowercased()
        return tracks.filter {
            $0.title.lowercased().contains(lowercased) ||
            $0.reciter.lowercased().contains(lowercased) ||
            $0.surahName?.lowercased().contains(lowercased) == true
        }
    }
    
    private func downloadCatalog() async throws -> CatalogResponse {
        var request = URLRequest(url: CloudConfig.catalogURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = AppConfig.requestTimeout
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CatalogError.fetchFailed
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CatalogResponse.self, from: data)
    }
    
    private var cacheURL: URL {
        AppConfig.documentsURL.appendingPathComponent("catalog_cache.json")
    }
    
    private func cacheCatalog(_ catalog: CatalogResponse) {
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(catalog)
            try data.write(to: cacheURL)
        } catch {
            print("Failed to cache catalog: \(error)")
        }
    }
    
    private func loadCachedCatalog() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let catalog = try decoder.decode(CatalogResponse.self, from: data)
            
            reciters = catalog.reciters
            tracks = catalog.tracks.map { track in
                SharedTrack(
                    id: UUID(),
                    title: track.title,
                    surahNumber: track.surahNumber,
                    reciter: track.reciter,
                    r2Path: track.r2Path,
                    durationSeconds: track.durationSeconds,
                    createdAt: nil
                )
            }
        } catch {
            print("Failed to load cached catalog: \(error)")
        }
    }
}

struct CatalogResponse: Codable {
    let version: Int
    let generatedAt: String?
    let reciters: [Reciter]
    let tracks: [CatalogTrack]
}

struct CatalogTrack: Codable {
    let title: String
    let surahNumber: Int?
    let reciter: String
    let r2Path: String
    let durationSeconds: Int?
}

enum CatalogError: LocalizedError {
    case fetchFailed
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch catalog. Check your internet connection."
        }
    }
}
