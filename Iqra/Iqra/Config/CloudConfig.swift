import Foundation

/// Cloud service configuration
enum CloudConfig {
    // MARK: - Cloudflare R2
    
    /// Base URL for R2 public bucket
    static let r2BaseURL = "https://pub-6feee86591a64e2c84327292d1713d26.r2.dev"
    
    /// URL for the track catalog JSON
    static var catalogURL: URL {
        URL(string: "\(r2BaseURL)/catalog.json")!
    }
    
    // MARK: - Conversion Server
    
    /// Fly.io conversion server URL (update after deploying)
    static let conversionServerURL = "https://iqra-converter.fly.dev"
    
    // MARK: - Helpers
    
    /// Get full R2 URL for a track path
    static func r2URL(for path: String) -> URL {
        URL(string: "\(r2BaseURL)/\(path)")!
    }
}
