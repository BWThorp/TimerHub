// TimerHubWidget.swift
// TimerHubWidgetExtension target only.
//
// The widget shows whichever active state is most relevant:
//   • A running interval session (from the Live Activity state, via App Group)
//   • A placeholder "open the app" card when nothing is running
//
// NOTE: Widgets cannot directly observe in-memory state from the main app.
// We use a shared App Group UserDefaults to write a lightweight snapshot
// from PlaybackEngine on every tick, which the widget reads via a
// TimelineProvider. Add App Groups to both targets (see setup steps).

import WidgetKit
import SwiftUI

// MARK: - App Group key

// Must match the string in PlaybackEngine's WidgetDataWriter (below).
private let appGroupID    = "group.com.briggthorp.timerhub"
private let snapshotKey   = "timerhub.widget.snapshot"


// MARK: - Color helpers (mirrors TimerHubLiveActivity)

private extension Color {
    static let thGreen   = Color(red: 0.204, green: 0.851, blue: 0.482)
    static let thYellow  = Color(red: 1.0,   green: 0.820, blue: 0.259)
    static let thRed     = Color(red: 1.0,   green: 0.271, blue: 0.227)
    static let thBg      = Color(red: 0.094, green: 0.094, blue: 0.110)
    static let thSurface = Color(red: 0.145, green: 0.145, blue: 0.165)

    static func timerColor(named name: String) -> Color {
        switch name {
        case "yellow": return .thYellow
        case "red":    return .thRed
        default:       return .thGreen
        }
    }
}

// MARK: - CountdownText
// Uses Text(date, style: .timer) when running — updates every second automatically.
// Falls back to a static formatted string when paused or inactive.

private struct CountdownText: View {
    let snapshot: WidgetSnapshot
    var fontSize: CGFloat = 18
    var weight: Font.Weight = .bold
    let accent: Color

    var body: some View {
        if snapshot.isActive, !snapshot.isPaused, let endDate = snapshot.timerEndDate {
            Text(endDate, style: .timer)
                .font(.system(size: fontSize, weight: weight, design: .monospaced))
                .foregroundStyle(accent)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            Text(snapshot.isActive && !snapshot.isPaused ? snapshot.countdownFormatted : "--:--")
                .font(.system(size: fontSize, weight: weight, design: .monospaced))
                .foregroundStyle(accent)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Timeline provider

struct TimerHubWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> TimerHubWidgetEntry {
        TimerHubWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerHubWidgetEntry) -> Void) {
        completion(TimerHubWidgetEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerHubWidgetEntry>) -> Void) {
        let snapshot = loadSnapshot()
        let entry    = TimerHubWidgetEntry(date: Date(), snapshot: snapshot)

        // Refresh every 30 seconds while a session is active; every 5 min otherwise.
        // The main app also calls WidgetCenter.shared.reloadTimelines("TimerHubWidget")
        // on significant state changes (start, pause, finish) for immediate updates.
        let refreshInterval: TimeInterval = snapshot.isActive ? 30 : 300
        let nextUpdate = Date().addingTimeInterval(refreshInterval)

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    // MARK: Private

    private func loadSnapshot() -> WidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data     = defaults.data(forKey: snapshotKey),
            let decoded  = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return .placeholder
        }
        return decoded
    }
}

struct TimerHubWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Widget

struct TimerHubWidget: Widget {
    let kind = "TimerHubWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimerHubWidgetProvider()) { entry in
            TimerHubWidgetView(entry: entry)
                .containerBackground(Color.thBg, for: .widget)
        }
        .configurationDisplayName("Timer Hub")
        .description("See your active interval session at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget view dispatcher

struct TimerHubWidgetView: View {
    let entry: TimerHubWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(snapshot: entry.snapshot)
        case .systemMedium:
            MediumWidgetView(snapshot: entry.snapshot)
        case .systemLarge:
            LargeWidgetView(snapshot: entry.snapshot)
        default:
            SmallWidgetView(snapshot: entry.snapshot)
        }
    }
}

// MARK: - Small widget

private struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot
    private var accent: Color { .timerColor(named: snapshot.colorName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Timer Hub")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if snapshot.isActive {
                // Ring + countdown
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.15), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: snapshot.progressFraction)
                        .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    CountdownText(snapshot: snapshot, fontSize: 16, weight: .bold, accent: accent)
                }
                .frame(width: 64, height: 64)
                .frame(maxWidth: .infinity)

                Spacer()

                Text(snapshot.intervalName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if snapshot.isPaused {
                    Text("PAUSED")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .kerning(1)
                }
            } else {
                Image(systemName: "play.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(accent.opacity(0.6))
                    .frame(maxWidth: .infinity)

                Spacer()

                Text("Open to\nstart a session")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .widgetURL(URL(string: "timerhub://playback"))
    }
}

// MARK: - Medium widget

private struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot
    private var accent: Color { .timerColor(named: snapshot.colorName) }

    var body: some View {
        HStack(spacing: 16) {
            // Left: ring
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: snapshot.isActive ? snapshot.progressFraction : 0)
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    CountdownText(snapshot: snapshot, fontSize: 18, weight: .bold, accent: accent)
                    if snapshot.isPaused {
                        Text("PAUSED")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .kerning(0.8)
                    }
                }
            }
            .frame(width: 78, height: 78)

            // Right: info
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    Text("Timer Hub")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if snapshot.isActive {
                    Text(snapshot.sessionName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(snapshot.intervalName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(snapshot.isFinished ? Color.thGreen : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Session progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accent.opacity(0.7))
                                .frame(width: geo.size.width * snapshot.sessionProgressFraction)
                        }
                    }
                    .frame(height: 3)

                    if !snapshot.nextIntervalName.isEmpty {
                        HStack(spacing: 3) {
                            Text("Next:")
                                .foregroundStyle(.tertiary)
                            Text(snapshot.nextIntervalName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }

                    Text("\(snapshot.stepIndex + 1) of \(snapshot.totalSteps) intervals")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else {
                    Spacer()
                    Text("No active\ninterval session")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .widgetURL(URL(string: "timerhub://playback"))
    }
}

// MARK: - Large widget

private struct LargeWidgetView: View {
    let snapshot: WidgetSnapshot
    private var accent: Color { .timerColor(named: snapshot.colorName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                Text("TIMER HUB")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .kerning(1.5)
                Spacer()
                if snapshot.isActive && snapshot.sessionRepeatTotal > 1 {
                    Text("Round \(snapshot.sessionRepeat + 1)/\(snapshot.sessionRepeatTotal)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            if snapshot.isActive {
                // Session name
                Text(snapshot.sessionName)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Large ring
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.12), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: snapshot.progressFraction)
                        .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        CountdownText(snapshot: snapshot, fontSize: 38, weight: .light, accent: accent)
                        Text(snapshot.intervalName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if snapshot.isPaused {
                            Text("PAUSED")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .kerning(1)
                        }
                    }
                }
                .frame(width: 160, height: 160)
                .frame(maxWidth: .infinity)

                // Session progress
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Session Progress")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(snapshot.stepIndex + 1)/\(snapshot.totalSteps)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent.opacity(0.7))
                                .frame(width: geo.size.width * snapshot.sessionProgressFraction)
                        }
                    }
                    .frame(height: 5)
                }

                // Next interval
                if !snapshot.nextIntervalName.isEmpty {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent.opacity(0.4))
                            .frame(width: 3, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEXT")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .kerning(1)
                            Text(snapshot.nextIntervalName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 52))
                        .foregroundStyle(accent.opacity(0.5))
                    Text("No Active Session")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Open Timer Hub and start an interval session to see it here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(16)
        .widgetURL(URL(string: "timerhub://playback"))
    }
}
