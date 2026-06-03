// TimerHubActivityAttributes.swift
// Shared between the main app target and the TimerHubWidgetExtension target.
// Add this file to BOTH targets in Xcode (check both boxes in Target Membership).

import ActivityKit
import Foundation

// MARK: - Live Activity attributes

public struct TimerHubActivityAttributes: ActivityAttributes {

    // Static data — set once when the activity is created, never changes.
    public struct ContentState: Codable, Hashable {
        // Playback state
        public var isRunning: Bool
        public var isPaused: Bool
        public var isFinished: Bool

        // Current interval
        public var intervalName: String
        public var secondsRemaining: Int
        public var totalIntervalSeconds: Int

        // Progress through session
        public var stepIndex: Int        // 0-based current step
        public var totalSteps: Int       // total steps in session
        public var sessionRepeat: Int    // 0-based current session loop
        public var sessionRepeatTotal: Int

        // Color (traffic-light state encoded as a string so no SwiftUI dep here)
        // Values: "green", "yellow", "red"
        public var colorName: String

        // Next interval (empty string when none)
        public var nextIntervalName: String
        public var nextIntervalSeconds: Int

        // Absolute wall-clock end of the current interval.
        // Used by the Live Activity views with Text(date, style: .timer)
        // for accurate per-second countdown without polling.
        // Nil when paused or finished.
        public var timerEndDate: Date?

        public init(
            isRunning: Bool = false,
            isPaused: Bool = false,
            isFinished: Bool = false,
            intervalName: String = "",
            secondsRemaining: Int = 0,
            totalIntervalSeconds: Int = 0,
            stepIndex: Int = 0,
            totalSteps: Int = 0,
            sessionRepeat: Int = 0,
            sessionRepeatTotal: Int = 1,
            colorName: String = "green",
            nextIntervalName: String = "",
            nextIntervalSeconds: Int = 0,
            timerEndDate: Date? = nil
        ) {
            self.isRunning = isRunning
            self.isPaused = isPaused
            self.isFinished = isFinished
            self.intervalName = intervalName
            self.secondsRemaining = secondsRemaining
            self.totalIntervalSeconds = totalIntervalSeconds
            self.stepIndex = stepIndex
            self.totalSteps = totalSteps
            self.sessionRepeat = sessionRepeat
            self.sessionRepeatTotal = sessionRepeatTotal
            self.colorName = colorName
            self.nextIntervalName = nextIntervalName
            self.nextIntervalSeconds = nextIntervalSeconds
            self.timerEndDate = timerEndDate
        }

        // MARK: Convenience helpers (no SwiftUI dependency)

        public var progressFraction: Double {
            guard totalIntervalSeconds > 0 else { return 0 }
            return 1.0 - (Double(secondsRemaining) / Double(totalIntervalSeconds))
        }

        public var sessionProgressFraction: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(stepIndex) / Double(totalSteps)
        }

        public var countdownFormatted: String {
            let sec = secondsRemaining
            if sec >= 3600 {
                return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
            } else if sec >= 60 {
                return String(format: "%d:%02d", sec / 60, sec % 60)
            } else {
                return String(format: ":%02d", sec)
            }
        }

        public var nextIntervalFormatted: String {
            let sec = nextIntervalSeconds
            if sec >= 3600 {
                return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
            }
            return String(format: "%d:%02d", sec / 60, sec % 60)
        }
    }

    // Static: the session name, set at activity creation.
    public var sessionName: String

    public init(sessionName: String) {
        self.sessionName = sessionName
    }
}
