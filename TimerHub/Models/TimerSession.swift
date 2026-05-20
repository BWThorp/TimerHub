import SwiftUI
import SwiftData
import Combine

// MARK: - Alert Type

enum AlertType: String, Codable, CaseIterable {
    case none    = "None"
    case sound   = "Sound"
    case speak   = "Speak"
    case music   = "Music"
    case haptic  = "Haptic"
}

// MARK: - TimerSession

@Model
final class TimerSession {
    var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var sessionRepeatCount: Int   // 1 = play once, 2 = play twice, etc.

    @Relationship(deleteRule: .cascade)
    var intervals: [TimerInterval] = []

    init(name: String = "", notes: String = "") {
        self.id                 = UUID()
        self.name               = name
        self.notes              = notes
        self.createdAt          = Date()
        self.sessionRepeatCount = 1
    }

    /// Intervals sorted by sortOrder
    var sortedIntervals: [TimerInterval] {
        intervals.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Total duration in seconds, accounting for interval repeatCounts and session repeat
    var totalDurationSeconds: Int {
        let onceThrough = sortedIntervals.reduce(0) { $0 + ($1.durationSeconds * $1.repeatCount) }
        return onceThrough * sessionRepeatCount
    }

    var totalDurationFormatted: String {
        let total = totalDurationSeconds
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - TimerInterval

@Model
final class TimerInterval {
    var id: UUID
    var name: String
    var durationSeconds: Int
    var repeatCount: Int
    var alertType: String          // AlertType.rawValue — stored as String for SwiftData compat
    var alertSoundName: String     // built-in sound filename
    var alertMusicURL: String      // filename of copied audio in app documents
    var alertMusicTitle: String    // display name of the selected track
    var colorHex: String
    var sortOrder: Int

    var session: TimerSession?

    init(
        name: String = "Interval",
        durationSeconds: Int = 60,
        repeatCount: Int = 1,
        alertType: AlertType = .sound,
        alertSoundName: String = "Ding",
        alertMusicURL: String = "",
        alertMusicTitle: String = "",
        colorHex: String = "#34D97B",
        sortOrder: Int = 0
    ) {
        self.id              = UUID()
        self.name            = name
        self.durationSeconds = durationSeconds
        self.repeatCount     = repeatCount
        self.alertType       = alertType.rawValue
        self.alertSoundName  = alertSoundName
        self.alertMusicURL   = alertMusicURL
        self.alertMusicTitle = alertMusicTitle
        self.colorHex        = colorHex
        self.sortOrder       = sortOrder
    }

    var alertTypeEnum: AlertType {
        get { AlertType(rawValue: alertType) ?? .sound }
        set { alertType = newValue.rawValue }
    }

    var color: Color {
        Color(hex: colorHex) ?? .green
    }

    var durationFormatted: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Color hex helpers

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        guard Scanner(string: h).scanHexInt64(&int), h.count == 6 else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
