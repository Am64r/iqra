import Foundation

/// Reciter information from catalog
struct Reciter: Identifiable, Codable, Hashable {
    var id: String { slug }
    let name: String
    let slug: String
}
