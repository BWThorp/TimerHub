import SwiftUI
import SwiftData
import Combine

struct SessionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TimerSession.createdAt, order: .reverse) private var sessions: [TimerSession]

    @State private var showingBuilder     = false
    @State private var editingSession: TimerSession?
    @State private var playingSession: TimerSession?
    @State private var engine             = PlaybackEngine()

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                if sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sessions) { session in
                            SessionCard(session: session) {
                                playingSession = session
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .contextMenu {
                                Button {
                                    editingSession = session
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    context.delete(session)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    context.delete(session)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    editingSession = session
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color("AccentGreen"))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Interval")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingBuilder = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingBuilder) {
                SessionBuilderView()
            }
            .sheet(item: $editingSession) { session in
                SessionBuilderView(session: session)
            }
            .fullScreenCover(item: $playingSession) { session in
                PlaybackView(session: session, engine: engine)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer")
                .font(.system(size: 48))
                .foregroundStyle(Color("AccentGreen").opacity(0.5))
            Text("No Sessions Yet")
                .font(.title3).fontWeight(.semibold)
            Text("Tap + to create your first timer session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let session: TimerSession
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name.isEmpty ? "Untitled" : session.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(session.totalDurationFormatted)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !session.sortedIntervals.isEmpty {
                IntervalPillStrip(intervals: session.sortedIntervals)
            }

            HStack {
                Text(sessionMetaLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: onPlay) {
                    Circle()
                        .fill(Color("AccentGreen"))
                        .frame(width: 34, height: 34)
                        .overlay {
                            PlayIcon(size: 13, color: .black)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color("Surface"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var sessionMetaLabel: String {
        let count  = session.sortedIntervals.count
        let rounds = session.sortedIntervals.map(\.repeatCount).max() ?? 1
        let iLabel = count == 1 ? "interval" : "intervals"
        if rounds > 1 {
            return "\(count) \(iLabel) · \(rounds) rounds"
        }
        return "\(count) \(iLabel)"
    }
}

// MARK: - Interval Pill Strip

struct IntervalPillStrip: View {
    let intervals: [TimerInterval]

    private var totalDuration: Int {
        max(1, intervals.reduce(0) { $0 + ($1.durationSeconds * $1.repeatCount) })
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(intervals) { interval in
                    let fraction = Double(interval.durationSeconds * interval.repeatCount) / Double(totalDuration)
                    let width    = max(8, geo.size.width * fraction)
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(interval.color.opacity(0.85))
                        .frame(width: width, height: 9)
                }
            }
        }
        .frame(height: 9)
    }
}
