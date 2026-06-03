// WidgetDataWriter.swift
// Main app target only.
// Writes a lightweight WidgetSnapshot into shared App Group UserDefaults
// so the Home Screen widget can read it without IPC.

import WidgetKit
import Foundation

struct WidgetDataWriter {

    private static let appGroupID  = "group.com.briggthorp.timerhub"
    private static let snapshotKey = "timerhub.widget.snapshot"

    // MARK: - Write

    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        // Write an explicit inactive snapshot rather than just clearing the key.
        // This ensures the widget re-renders immediately showing the idle state
        // rather than serving a stale cached active entry.
        var stopped = WidgetSnapshot.placeholder
        stopped.isActive = false
        stopped.timerEndDate = nil
        stopped.pausedSecondsRemaining = nil
        stopped.updatedAt = Date()
        write(stopped)
    }
}
