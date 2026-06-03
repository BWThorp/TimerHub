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
        // Reload all timelines so the widget re-renders immediately.
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        var blank = WidgetSnapshot.placeholder
        blank.isActive = false
        if let data = try? JSONEncoder().encode(blank) {
            defaults.set(data, forKey: snapshotKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
