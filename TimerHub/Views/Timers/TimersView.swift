import SwiftUI
import Combine

struct TimersView: View {
    private var manager = TimerManager.shared
    @State private var showAddSheet = false
    @State private var editingTimer: QuickTimer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                if manager.timers.isEmpty {
                    emptyState
                } else {
                    timerList
                }
            }
            .navigationTitle("Timers")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }

                if !manager.finishedTimers.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") {
                            withAnimation {
                                manager.removeFinished()
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddTimerSheet()
            }
            .sheet(item: $editingTimer) { timer in
                AddTimerSheet(editingTimer: timer)
            }
            .onAppear {
                manager.requestNotificationPermission()
            }
        }
    }

    // MARK: - Timer list

    private var timerList: some View {
        List {
            // Active timers
            if !manager.activeTimers.isEmpty {
                Section {
                    ForEach(manager.activeTimers) { timer in
                        ActiveTimerCard(timer: timer)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .contextMenu {
                                Button {
                                    editingTimer = timer
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    manager.remove(timer)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    manager.remove(timer)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    editingTimer = timer
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color("AccentGreen"))
                            }
                    }
                } header: {
                    if !manager.finishedTimers.isEmpty {
                        sectionLabel("Running")
                    }
                }
            }

            // Finished timers
            if !manager.finishedTimers.isEmpty {
                Section {
                    ForEach(manager.finishedTimers) { timer in
                        FinishedTimerCard(timer: timer)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .contextMenu {
                                Button {
                                    editingTimer = timer
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    manager.remove(timer)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    manager.remove(timer)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    editingTimer = timer
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color("AccentGreen"))
                            }
                    }
                } header: {
                    sectionLabel("Completed")
                }
            }

            // Add timer row
            Section {
                AddTimerRow {
                    showAddSheet = true
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundStyle(Color("AccentGreen").opacity(0.5))
            Text("No Timers Yet")
                .font(.title3).fontWeight(.semibold)
            Text("Tap + to create your first timer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .kerning(1.2)
    }
}

// MARK: - Active Timer Card

struct ActiveTimerCard: View {
    let timer: QuickTimer

    private let ringSize: CGFloat = 48
    private let strokeWidth: CGFloat = 4.5
    private var manager: TimerManager { TimerManager.shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Mini ring
                ZStack {
                    Circle()
                        .stroke(Color("Surface2"), lineWidth: strokeWidth)
                    Circle()
                        .trim(from: 0, to: timer.progressFraction)
                        .stroke(
                            accentColor,
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1.0), value: timer.progressFraction)

                    Text(timer.countdownFormatted)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(accentColor)
                }
                .frame(width: ringSize, height: ringSize)

                // Name + meta
                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(timer.totalFormatted + " total")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)

                        if timer.state == .paused {
                            Text("PAUSED")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color("AccentYellow"))
                                .kerning(0.8)
                        }
                    }
                }

                Spacer()

                // Pause / Resume
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        manager.togglePause(timer)
                    }
                } label: {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Circle()
                                .stroke(accentColor.opacity(0.25), lineWidth: 0.5)
                        }
                        .overlay {
                            Image(systemName: timer.state == .paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(accentColor)
                        }
                }
                .buttonStyle(.plain)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color("Surface2"))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: geo.size.width * timer.progressFraction)
                        .animation(.linear(duration: 1.0), value: timer.progressFraction)
                }
            }
            .frame(height: 4)
            .padding(.top, 10)
        }
        .padding(14)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var accentColor: Color {
        timer.state == .paused ? Color("AccentYellow") : Color("AccentGreen")
    }
}

// MARK: - Finished Timer Card

struct FinishedTimerCard: View {
    let timer: QuickTimer
    private var manager: TimerManager { TimerManager.shared }

    var body: some View {
        HStack(spacing: 14) {
            // Checkmark circle
            ZStack {
                Circle()
                    .fill(Color("AccentGreen").opacity(0.1))
                Circle()
                    .stroke(Color("AccentGreen").opacity(0.2), lineWidth: 0.5)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color("AccentGreen"))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(timer.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Done · \(timer.totalFormatted)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Restart button
            Button {
                withAnimation {
                    manager.restart(timer)
                }
            } label: {
                Circle()
                    .fill(Color("Surface2"))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    }
                    .overlay {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        }
        .opacity(0.6)
    }
}

// MARK: - Add Timer Row

struct AddTimerRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color("Surface2"))
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color("AccentGreen"))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add timer")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Name, time, and alert")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(14)
            .background(Color("Surface").opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
                    .foregroundStyle(Color.white.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
    }
}
