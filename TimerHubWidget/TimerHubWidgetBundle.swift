// TimerHubWidgetBundle.swift
// TimerHubWidgetExtension target only.

import WidgetKit
import SwiftUI

@main
struct TimerHubWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimerHubLiveActivity()   // Dynamic Island + Lock Screen Live Activity
        TimerHubWidget()         // Home Screen widget
    }
}
