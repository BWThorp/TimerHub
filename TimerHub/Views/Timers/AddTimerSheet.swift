import SwiftUI
import Combine

struct AddTimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// When non-nil we are editing an existing timer rather than creating a new one.
    var editingTimer: QuickTimer?

    @State private var name: String          = ""
    @State private var hours: Int            = 0
    @State private var minutes: Int          = 5
    @State private var seconds: Int          = 0
    @State private var alertType: AlertType  = AppSettings.shared.defaultAlertTypeEnum
    @State private var alertSoundName: String = AppSettings.shared.defaultAlertSound
    @FocusState private var nameFieldFocused: Bool

    private let manager = TimerManager.shared

    private var isEditing: Bool { editingTimer != nil }

    private var totalSeconds: Int {
        hours * 3600 + minutes * 60 + seconds
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                List {
                    // Name
                    Section {
                        TextField("Timer name", text: $name)
                            .textFieldStyle(.plain)
                            .focused($nameFieldFocused)
                    } header: {
                        sectionLabel("Name")
                    }
                    .listRowBackground(Color("Surface"))

                    // Duration picker
                    Section {
                        HStack(spacing: 0) {
                            // Hours
                            Picker("Hours", selection: $hours) {
                                ForEach(0..<24, id: \.self) { h in
                                    Text("\(h)h").tag(h)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()

                            // Minutes
                            Picker("Minutes", selection: $minutes) {
                                ForEach(0..<60, id: \.self) { m in
                                    Text("\(m)m").tag(m)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()

                            // Seconds
                            Picker("Seconds", selection: $seconds) {
                                ForEach(0..<60, id: \.self) { s in
                                    Text("\(s)s").tag(s)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            .clipped()
                        }
                        .frame(height: 150)
                    } header: {
                        sectionLabel("Duration")
                    }
                    .listRowBackground(Color("Surface"))

                    // Alert
                    Section {
                        Picker("Alert Type", selection: $alertType) {
                            ForEach(quickTimerAlertTypes, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }

                        if alertType == .sound {
                            Picker("Sound", selection: $alertSoundName) {
                                ForEach(SoundLibrary.allNames, id: \.self) { sound in
                                    Text(sound).tag(sound)
                                }
                            }
                        }
                    } header: {
                        sectionLabel("Alert")
                    }
                    .listRowBackground(Color("Surface"))
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "Edit Timer" : "Add Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Start") {
                        if isEditing {
                            saveEdits()
                        } else {
                            startTimer()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(totalSeconds == 0)
                }
            }
            .onAppear {
                if let timer = editingTimer {
                    populateFromTimer(timer)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    nameFieldFocused = true
                }
            }
        }
    }

    // Quick timers don't support music alerts (no file picker)
    private var quickTimerAlertTypes: [AlertType] {
        [.none, .sound, .speak, .haptic]
    }

    private func populateFromTimer(_ timer: QuickTimer) {
        name           = timer.name
        hours          = timer.totalSeconds / 3600
        minutes        = (timer.totalSeconds % 3600) / 60
        seconds        = timer.totalSeconds % 60
        alertType      = timer.alertType
        alertSoundName = timer.alertSoundName
    }

    private func startTimer() {
        let timerName = name.trimmingCharacters(in: .whitespaces)
        let finalName = timerName.isEmpty ? "Timer" : timerName

        let timer = QuickTimer(
            name: finalName,
            totalSeconds: totalSeconds,
            alertType: alertType,
            alertSoundName: alertSoundName
        )

        manager.addAndStart(timer)
        dismiss()
    }

    private func saveEdits() {
        guard let timer = editingTimer else { return }

        let timerName = name.trimmingCharacters(in: .whitespaces)
        let finalName = timerName.isEmpty ? "Timer" : timerName

        manager.update(
            timer,
            name: finalName,
            totalSeconds: totalSeconds,
            alertType: alertType,
            alertSoundName: alertSoundName
        )

        dismiss()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .kerning(1.2)
    }
}
