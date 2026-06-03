// TimerHubLiveActivity.swift
// TimerHubWidgetExtension target only.

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Color helpers (no access to asset catalog in widget extension)

private extension Color {
    static let thGreen  = Color(red: 0.204, green: 0.851, blue: 0.482)   // #34D97B
    static let thYellow = Color(red: 1.0,   green: 0.820, blue: 0.259)   // #FFD142
    static let thRed    = Color(red: 1.0,   green: 0.271, blue: 0.227)   // #FF453A
    static let thBg     = Color(red: 0.094, green: 0.094, blue: 0.110)   // #181818
    static let thSurface = Color(red: 0.145, green: 0.145, blue: 0.165)

    static func timerColor(named name: String) -> Color {
        switch name {
        case "yellow": return .thYellow
        case "red":    return .thRed
        default:       return .thGreen
        }
    }
}

// MARK: - Live Activity countdown helper
// Uses Text(date, style: .timer) when a wall-clock end date is present,
// falling back to the static formatted string when paused or finished.

private struct LiveActivityCountdown: View {
    let state: TimerHubActivityAttributes.ContentState
    var fontSize: CGFloat
    var weight: Font.Weight = .semibold
    let accent: Color

    var body: some View {
        if !state.isPaused, !state.isFinished, let endDate = state.timerEndDate {
            Text(endDate, style: .timer)
                .font(.system(size: fontSize, weight: weight, design: .monospaced))
                .foregroundStyle(accent)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
        } else {
            Text(state.countdownFormatted)
                .font(.system(size: fontSize, weight: weight, design: .monospaced))
                .foregroundStyle(accent)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Live Activity registration

struct TimerHubLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerHubActivityAttributes.self) { context in
            // ── Lock Screen / StandBy banner ──────────────────────────────
            LockScreenLiveActivityView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color.thBg)
            .activitySystemActionForegroundColor(Color.thGreen)

        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded (long press) ─────────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
            } compactLeading: {
                // ── Compact leading: color dot ────────────────────────────
                Circle()
                    .fill(Color.timerColor(named: context.state.colorName))
                    .frame(width: 8, height: 8)
                    .padding(.leading, 4)
            } compactTrailing: {
                // ── Compact trailing: countdown ───────────────────────────
                LiveActivityCountdown(
                    state: context.state,
                    fontSize: 14,
                    weight: .semibold,
                    accent: Color.timerColor(named: context.state.colorName)
                )
                .padding(.trailing, 4)
            } minimal: {
                // ── Minimal (two activities): color dot ───────────────────
                Circle()
                    .fill(Color.timerColor(named: context.state.colorName))
                    .frame(width: 10, height: 10)
            }
            .widgetURL(URL(string: "timerhub://playback"))
            .keylineTint(Color.timerColor(named: context.state.colorName))
        }
    }
}

// MARK: - Lock Screen banner

private struct LockScreenLiveActivityView: View {
    let attributes: TimerHubActivityAttributes
    let state: TimerHubActivityAttributes.ContentState

    private var accent: Color { .timerColor(named: state.colorName) }

    var body: some View {
        HStack(spacing: 14) {
            // Left: ring progress
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: state.progressFraction)
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: state.progressFraction)
                LiveActivityCountdown(state: state, fontSize: 13, weight: .semibold, accent: accent)
            }
            .frame(width: 58, height: 58)

            // Centre: session + interval info
            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.sessionName.uppercased())
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .kerning(1.2)
                    .lineLimit(1)

                Text(state.isFinished ? "Session Complete" : state.intervalName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(state.isFinished ? Color.thGreen : .primary)
                    .lineLimit(1)

                if !state.isFinished, !state.nextIntervalName.isEmpty {
                    HStack(spacing: 3) {
                        Text("Next:")
                            .foregroundStyle(.tertiary)
                        Text(state.nextIntervalName)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(state.nextIntervalFormatted)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                } else if state.isPaused {
                    Text("PAUSED")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .kerning(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: step progress
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(state.stepIndex + 1)/\(state.totalSteps)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)

                if state.sessionRepeatTotal > 1 {
                    Text("R\(state.sessionRepeat + 1)/\(state.sessionRepeatTotal)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Dynamic Island expanded views

private struct ExpandedLeadingView: View {
    let state: TimerHubActivityAttributes.ContentState
    private var accent: Color { .timerColor(named: state.colorName) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: state.progressFraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: state.progressFraction)
            LiveActivityCountdown(state: state, fontSize: 12, weight: .bold, accent: accent)
        }
        .frame(width: 52, height: 52)
        .padding(.leading, 8)
    }
}

private struct ExpandedTrailingView: View {
    let state: TimerHubActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(state.stepIndex + 1) of \(state.totalSteps)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if state.sessionRepeatTotal > 1 {
                Text("Round \(state.sessionRepeat + 1)/\(state.sessionRepeatTotal)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.trailing, 8)
    }
}

private struct ExpandedBottomView: View {
    let attributes: TimerHubActivityAttributes
    let state: TimerHubActivityAttributes.ContentState
    private var accent: Color { .timerColor(named: state.colorName) }

    var body: some View {
        VStack(spacing: 6) {
            // Session name + current interval
            HStack {
                Text(attributes.sessionName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if state.isPaused {
                    Text("PAUSED")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .kerning(0.8)
                }
            }

            Text(state.isFinished ? "Session Complete ✓" : state.intervalName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state.isFinished ? Color.thGreen : accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            // Session progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent.opacity(0.7))
                        .frame(width: geo.size.width * state.sessionProgressFraction)
                        .animation(.linear(duration: 1), value: state.sessionProgressFraction)
                }
            }
            .frame(height: 3)

            // Next interval
            if !state.nextIntervalName.isEmpty {
                HStack(spacing: 4) {
                    Text("Next:")
                        .foregroundStyle(.tertiary)
                    Text(state.nextIntervalName)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(state.nextIntervalFormatted)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .font(.system(size: 11, design: .monospaced))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
