import Foundation
import SwiftData

@Model
final class TrackTimespan {
    @Attribute(.unique) var id: UUID
    var trackId: UUID
    var name: String
    var startTime: Double
    var endTime: Double
    var createdAt: Date

    init(
        id: UUID = UUID(),
        trackId: UUID,
        name: String,
        startTime: Double,
        endTime: Double
    ) {
        self.id = id
        self.trackId = trackId
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = Date()
    }

    var formattedRange: String {
        "\(TimeFormatter.format(timeInterval: startTime)) - \(TimeFormatter.format(timeInterval: endTime))"
    }

    var durationSeconds: Double {
        endTime - startTime
    }
}
