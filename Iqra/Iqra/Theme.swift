import SwiftUI

enum Theme {
    static let accent = Color(hex: "#9dd4a1")
    static let background = Color(hex: "#000000")
    static let surface = Color(hex: "#1C1C1E")
    static let surfaceLight = Color(hex: "#2C2C2E")
    
    static let accentGlow = accent.opacity(0.3)
    static let accentSubtle = accent.opacity(0.15)
    static let accentMuted = accent.opacity(0.6)
    
    static let glassTint = accent.opacity(0.1)
    static let glassBorder = Color.white.opacity(0.15)
    
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.4)
    
    static var accentUIColor: UIColor {
        UIColor(red: 157/255, green: 212/255, blue: 161/255, alpha: 1.0)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
