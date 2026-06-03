// LiveActivityManager.swift
// Main app target only.
// Called by PlaybackEngine to drive the Live Activity lifecycle.

import ActivityKit
import Combine
import SwiftUI

@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private init() {}

    private var activity: Activity<TimerHubActivityAttributes>?

    // MARK: - Public API

    /// Start a new Live Activity when a session begins.
    func start(sessionName: String, state: TimerHubActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any stale activity from a previous session.
        endAll()

        let attributes = TimerHubActivityAttributes(sessionName: sessionName)
        let content    = ActivityContent(state: state, staleDate: nil)

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("LiveActivityManager: failed to start activity — \(error)")
        }
    }

    /// Push a state update (called on every tick from PlaybackEngine).
    func update(state: TimerHubActivityAttributes.ContentState) {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
    }

    /// End the activity when the session finishes or is cancelled.
    func end(finalState: TimerHubActivityAttributes.ContentState) {
        guard let activity else { return }
        let content = ActivityContent(state: finalState, staleDate: nil)
        Task {
            await activity.end(content, dismissalPolicy: .after(.now + 4))
        }
        self.activity = nil
    }

    // MARK: - Private

    /// End any lingering activities (e.g., app crash recovery).
    private func endAll() {
        Task {
            for existing in Activity<TimerHubActivityAttributes>.activities {
                let dismissed = TimerHubActivityAttributes.ContentState()
                let content   = ActivityContent(state: dismissed, staleDate: nil)
                await existing.end(content, dismissalPolicy: .immediate)
            }
        }
    }
}
