// WidgetSnapshot.swift
// Add to BOTH targets — main app + widget extension

import Foundation

struct WidgetSnapshot: Codable {
    var isActive: Bool
    var sessionName: String
    var intervalName: String
    var secondsRemaining: Int       // used for progress ring fraction only
    var totalIntervalSeconds: Int
    var stepIndex: Int
    var totalSteps: Int
    var sessionRepeat: Int
    var sessionRepeatTotal: Int
    var colorName: String
    var nextIntervalName: String
    var nextIntervalSeconds: Int
    var isPaused: Bool
    var isFinished: Bool
    var updatedAt: Date

    // The Date when the current interval ends (or nil if paused/inactive).
    // The widget renders this with Text(timerEndDate, style: .timer) which
    // counts down live every second with no polling needed.
    var timerEndDate: Date?

    // When paused, store how many seconds were left so we can display it statically.
    var pausedSecondsRemaining: Int?

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            isActive: false,
            sessionName: "Timer Hub",
            intervalName: "No Active Session",
            secondsRemaining: 0,
            totalIntervalSeconds: 0,
            stepIndex: 0,
            totalSteps: 0,
            sessionRepeat: 0,
            sessionRepeatTotal: 1,
            colorName: "green",
            nextIntervalName: "",
            nextIntervalSeconds: 0,
            isPaused: false,
            isFinished: false,
            updatedAt: Date(),
            timerEndDate: nil,
            pausedSecondsRemaining: nil
        )
    }

    var progressFraction: Double {
        guard totalIntervalSeconds > 0 else { return 0 }
        return 1.0 - (Double(secondsRemaining) / Double(totalIntervalSeconds))
    }

    var sessionProgressFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(stepIndex) / Double(totalSteps)
    }

    /// Formatted static countdown — used only when paused or as a fallback.
    var countdownFormatted: String {
        let sec = pausedSecondsRemaining ?? secondsRemaining
        if sec >= 3600 {
            return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
        } else if sec >= 60 {
            return String(format: "%d:%02d", sec / 60, sec % 60)
        } else {
            return String(format: ":%02d", sec)
        }
    }

    var nextIntervalFormatted: String {
        let sec = nextIntervalSeconds
        if sec >= 3600 {
            return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
        }
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}
