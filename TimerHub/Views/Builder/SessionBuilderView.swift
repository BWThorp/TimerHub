import SwiftUI
import SwiftData
import Combine

struct SessionBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var session: TimerSession?

    @State private var name: String               = ""
    @State private var notes: String              = ""
    @State private var sessionRepeatCount: Int    = 1
    @State private var intervals: [IntervalDraft] = []
    @State private var editingInterval: IntervalDraft?
    @State private var isReordering = false
    @State private var hasPopulated = false
    @FocusState private var nameFieldFocused: Bool

    private var isEditing: Bool { session != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                List {
                    // Name
                    Section {
                        TextField("Session name", text: $name)
                            .textFieldStyle(.plain)
                            .focused($nameFieldFocused)
                    } header: {
                        sectionLabel("Name")
                    }
                    .listRowBackground(Color("Surface"))

                    // Notes
                    Section {
                        TextField("Optional notes…", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                    } header: {
                        sectionLabel("Notes")
                    }
                    .listRowBackground(Color("Surface"))

                    // Session repeat
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sessionRepeatCount == 1 ? "Play once" : "Repeat \(sessionRepeatCount)×")
                                    .font(.subheadline)
                                if sessionRepeatCount > 1 {
                                    Text("Full session plays \(sessionRepeatCount) times")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Stepper("", value: $sessionRepeatCount, in: 1...99)
                                .labelsHidden()
                        }
                    } header: {
                        sectionLabel("Session Repeat")
                    }
                    .listRowBackground(Color("Surface"))

                    // Intervals
                    Section {
                        if intervals.isEmpty {
                            Text("No intervals yet. Tap + Add to get started.")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .listRowBackground(Color("Surface"))
                        } else {
                            ForEach(intervals) { draft in
                                IntervalDraftRow(draft: draft) {
                                    editingInterval = draft
                                }
                                .listRowBackground(Color("Surface"))
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        intervals.removeAll { $0.id == draft.id }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        editingInterval = draft
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Color("AccentGreen"))
                                }
                            }
                            .onMove { from, to in
                                intervals.move(fromOffsets: from, toOffset: to)
                            }
                        }
                    } header: {
                        HStack {
                            sectionLabel("Intervals")
                            Spacer()
                            if intervals.count > 1 {
                                Button {
                                    withAnimation { isReordering.toggle() }
                                } label: {
                                    Image(systemName: isReordering ? "checkmark.circle.fill" : "arrow.up.arrow.down")
                                        .font(.caption)
                                        .foregroundStyle(Color("AccentGreen"))
                                }
                                .textCase(nil)
                            }
                            Button("+ Add") {
                                let draft = IntervalDraft()
                                intervals.append(draft)
                                editingInterval = draft
                            }
                            .font(.caption).fontWeight(.medium)
                            .foregroundStyle(Color("AccentGreen"))
                            .textCase(nil)
                        }
                    }

                    // Summary
                    if !intervals.isEmpty {
                        Section {
                            summaryCard
                                .listRowBackground(Color("Surface"))
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(isReordering ? .active : .inactive))
            }
            .navigationTitle(isEditing ? "Edit Session" : "New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(item: $editingInterval, onDismiss: assignDefaultIntervalNames) { draft in
                IntervalEditorSheet(draft: draft) {
                    if draft.isNew {
                        intervals.removeAll { $0.id == draft.id }
                    }
                }
            }
            .onAppear {
                populateFromSession()
                if !isEditing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        nameFieldFocused = true
                    }
                }
            }
        }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        let onceSec     = intervals.reduce(0) { $0 + ($1.durationSeconds * $1.repeatCount) }
        let totalSec    = onceSec * sessionRepeatCount
        let m           = totalSec / 60
        let s           = totalSec % 60
        let totalRounds = intervals.map(\.repeatCount).max() ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            Text("TOTAL DURATION")
                .font(.caption2).fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
                .kerning(1.5)
            Text(String(format: "%d:%02d", m, s))
                .font(.system(size: 32, weight: .light, design: .monospaced))
            Text(summaryMeta(intervalCount: intervals.count,
                             rounds: totalRounds,
                             sessionRepeats: sessionRepeatCount))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryMeta(intervalCount: Int, rounds: Int, sessionRepeats: Int) -> String {
        var parts: [String] = []
        parts.append("\(intervalCount) \(intervalCount == 1 ? "interval" : "intervals")")
        if rounds > 1 { parts.append("\(rounds) rounds") }
        if sessionRepeats > 1 { parts.append("session ×\(sessionRepeats)") }
        return parts.joined(separator: " · ")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .kerning(1.2)
    }

    private func assignDefaultIntervalNames() {
        var counter = 1
        for draft in intervals {
            if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                draft.name = "Interval \(counter)"
            }
            counter += 1
        }
    }

    private func populateFromSession() {
        guard let session, !hasPopulated else { return }
        hasPopulated       = true
        name               = session.name
        notes              = session.notes
        sessionRepeatCount = session.sessionRepeatCount
        intervals          = session.sortedIntervals.map { IntervalDraft(from: $0) }
    }

    // MARK: - Save

    private func save() {
        let target: TimerSession
        if let existing = session {
            target = existing
        } else {
            target = TimerSession()
            context.insert(target)
        }

        target.name               = name.trimmingCharacters(in: .whitespaces)
        target.notes              = notes.trimmingCharacters(in: .whitespaces)
        target.sessionRepeatCount = sessionRepeatCount

        for old in target.intervals {
            context.delete(old)
        }
        target.intervals = []

        for (i, draft) in intervals.enumerated() {
            let iv = TimerInterval(
                name:            draft.name,
                durationSeconds: draft.durationSeconds,
                repeatCount:     draft.repeatCount,
                alertType:       draft.alertType,
                alertSoundName:  draft.alertSoundName,
                alertMusicURL:   draft.alertMusicURL,
                alertMusicTitle: draft.alertMusicTitle,
                colorHex:        draft.colorHex,
                sortOrder:       i
            )
            context.insert(iv)
            iv.session = target
            target.intervals.append(iv)
        }

        do {
            try context.save()
        } catch {
            print("Save error: \(error)")
        }

        dismiss()
    }
}

// MARK: - IntervalDraft

class IntervalDraft: Identifiable, ObservableObject {
    let id: UUID
    var isNew: Bool
    @Published var name: String
    @Published var durationSeconds: Int
    @Published var repeatCount: Int
    @Published var alertType: AlertType
    @Published var alertSoundName: String
    @Published var alertMusicURL: String
    @Published var alertMusicTitle: String
    @Published var colorHex: String

    init(
        name: String           = "",
        durationSeconds: Int   = 60,
        repeatCount: Int       = 1,
        alertType: AlertType   = AppSettings.shared.defaultAlertTypeEnum,
        alertSoundName: String = AppSettings.shared.defaultAlertSound,
        alertMusicURL: String  = "",
        alertMusicTitle: String = "",
        colorHex: String       = AppSettings.shared.defaultColorHex
    ) {
        self.id              = UUID()
        self.isNew           = true
        self.name            = name
        self.durationSeconds = durationSeconds
        self.repeatCount     = repeatCount
        self.alertType       = alertType
        self.alertSoundName  = alertSoundName
        self.alertMusicURL   = alertMusicURL
        self.alertMusicTitle = alertMusicTitle
        self.colorHex        = colorHex
    }

    init(from interval: TimerInterval) {
        self.id              = interval.id
        self.isNew           = false
        self.name            = interval.name
        self.durationSeconds = interval.durationSeconds
        self.repeatCount     = interval.repeatCount
        self.alertType       = interval.alertTypeEnum
        self.alertSoundName  = interval.alertSoundName
        self.alertMusicURL   = interval.alertMusicURL
        self.alertMusicTitle = interval.alertMusicTitle
        self.colorHex        = interval.colorHex
    }

    var color: Color { Color(hex: colorHex) ?? .green }
    var durationFormatted: String {
        String(format: "%d:%02d", durationSeconds / 60, durationSeconds % 60)
    }
}

// MARK: - Interval Draft Row

struct IntervalDraftRow: View {
    @ObservedObject var draft: IntervalDraft
    let onEdit: () -> Void

    private var alertDetailLabel: String {
        switch draft.alertType {
        case .sound:
            return draft.alertSoundName.isEmpty
                ? "Sound"
                : "Sound - " + draft.alertSoundName
        case .music:
            let title = draft.alertMusicTitle.isEmpty ? "Music" : draft.alertMusicTitle
            return "Music – \(title)"
        case .none, .speak, .haptic:
            return draft.alertType.rawValue
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(draft.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name.isEmpty ? "Interval" : draft.name)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(draft.durationFormatted) · \(draft.repeatCount)×  ·  \(alertDetailLabel)")
                    .font(.caption).fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}
