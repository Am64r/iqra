import Foundation

/// App-wide configuration constants
enum AppConfig {
    /// App display name
    static let appName = "Iqra"
    
    // MARK: - File Storage
    
    /// Directory for downloaded Quran tracks
    static let quranDirectory = "quran"
    
    /// Directory for YouTube imports
    static let importsDirectory = "imports"
    
    /// Documents directory URL
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// Quran downloads directory URL
    static var quranDirectoryURL: URL {
        documentsURL.appendingPathComponent(quranDirectory)
    }
    
    /// Imports directory URL
    static var importsDirectoryURL: URL {
        documentsURL.appendingPathComponent(importsDirectory)
    }
    
    // MARK: - Audio Settings
    
    /// Default playback rate options
    static let playbackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    // MARK: - Network
    
    /// Request timeout interval
    static let requestTimeout: TimeInterval = 30
    
    /// Download timeout interval
    static let downloadTimeout: TimeInterval = 300
    
    // MARK: - Setup
    
    /// Ensures required directories exist
    static func createDirectoriesIfNeeded() {
        let fileManager = FileManager.default
        
        for directory in [quranDirectoryURL, importsDirectoryURL] {
            if !fileManager.fileExists(atPath: directory.path) {
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
}
