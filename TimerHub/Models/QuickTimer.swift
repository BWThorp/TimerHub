import SwiftUI
import Combine

// MARK: - QuickTimer
// A lightweight, in-memory timer for the Timers tab.
// No SwiftData persistence — these live only while active.

enum QuickTimerState {
    case idle
    case running
    case paused
    case finished
}

@Observable
final class QuickTimer: Identifiable {
    let id: UUID
    var name: String
    var totalSeconds: Int
    var alertType: AlertType
    var alertSoundName: String
    var state: QuickTimerState
    var secondsRemaining: Int
    var startedAt: Date?
    var finishedAt: Date?

    init(
        name: String,
        totalSeconds: Int,
        alertType: AlertType = .sound,
        alertSoundName: String = SoundLibrary.defaultSoundName
    ) {
        self.id              = UUID()
        self.name            = name
        self.totalSeconds    = totalSeconds
        self.alertType       = alertType
        self.alertSoundName  = alertSoundName
        self.state           = .idle
        self.secondsRemaining = totalSeconds
    }

    var progressFraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1.0 - (Double(secondsRemaining) / Double(totalSeconds))
    }

    var countdownFormatted: String {
        let sec = secondsRemaining
        if sec >= 3600 {
            return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
        } else if sec >= 60 {
            return String(format: "%d:%02d", sec / 60, sec % 60)
        } else {
            return String(format: ":%02d", sec)
        }
    }

    var totalFormatted: String {
        let sec = totalSeconds
        if sec >= 3600 {
            return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
        }
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}
