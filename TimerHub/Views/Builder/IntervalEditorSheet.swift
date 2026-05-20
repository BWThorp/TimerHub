import SwiftUI
import Combine
import AVFoundation
import UniformTypeIdentifiers

struct IntervalEditorSheet: View {
    @ObservedObject var draft: IntervalDraft
    var onCancel: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Int = 1
    @State private var seconds: Int = 0
    @State private var showColorPicker = false
    @State private var pickedColor: Color = .green
    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewingSound: String?
    @State private var showMusicFilePicker = false

    // Snapshot of original values for cancel/restore
    @State private var originalName: String = ""
    @State private var originalDuration: Int = 60
    @State private var originalRepeatCount: Int = 1
    @State private var originalAlertType: AlertType = .sound
    @State private var originalAlertSoundName: String = "Ding"
    @State private var originalAlertMusicURL: String = ""
    @State private var originalAlertMusicTitle: String = ""
    @State private var originalColorHex: String = "#34D97B"

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Name
                        field(label: "Name") {
                            TextField("Interval name", text: $draft.name)
                                .textFieldStyle(.plain)
                        }

                        // Duration
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("Duration")
                            HStack(spacing: 0) {
                                Picker("Minutes", selection: $minutes) {
                                    ForEach(0..<60) { Text("\($0) min").tag($0) }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                                .clipped()

                                Text(":")
                                    .font(.title2).fontDesign(.monospaced)
                                    .foregroundStyle(.secondary)

                                Picker("Seconds", selection: $seconds) {
                                    ForEach(0..<60) { Text("\($0 < 10 ? "0" : "")\($0) sec").tag($0) }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                                .clipped()
                            }
                            .frame(height: 120)
                            .background(Color("Surface"))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            }
                        }

                        // Repeats
                        field(label: "Repeats") {
                            Stepper("\(draft.repeatCount)×", value: $draft.repeatCount, in: 1...99)
                        }

                        // Alert type chips
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("Alert")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(AlertType.allCases, id: \.self) { type in
                                        AlertChip(type: type, selected: draft.alertType == type) {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                draft.alertType = type
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 1)
                            }

                            if draft.alertType == .sound {
                                soundPicker
                            }

                            if draft.alertType == .speak {
                                infoRow("Will speak the interval name and duration aloud.")
                            }

                            if draft.alertType == .music {
                                musicPicker
                            }

                            if draft.alertType == .haptic {
                                infoRow("A strong haptic pattern fires at interval end.")
                            }
                        }

                        // Color
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("Color")
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(pickedColor)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    }
                                    .shadow(color: pickedColor.opacity(0.4), radius: 8, y: 3)

                                ColorPicker("Choose color", selection: $pickedColor, supportsOpacity: false)
                                    .labelsHidden()

                                Text(pickedColor.hexString)
                                    .font(.caption).fontDesign(.monospaced)
                                    .foregroundStyle(.secondary)

                                Spacer()
                            }
                            .padding(14)
                            .background(Color("Surface"))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            }
                        }

                    }
                    .padding(16)
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New Interval" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelAndDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitAndDismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadFromDraft() }
            .onDisappear { stopPreview() }
        }
    }

    // MARK: - Sub-views

    private var soundPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                ForEach(SoundLibrary.sounds) { entry in
                    HStack {
                        if draft.alertSoundName == entry.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color("AccentGreen"))
                                .fontWeight(.semibold)
                                .frame(width: 20)
                        } else {
                            Color.clear.frame(width: 20, height: 1)
                        }

                        Text(entry.id)
                            .font(.subheadline)
                            .foregroundStyle(draft.alertSoundName == entry.id ? Color("AccentGreen") : .primary)

                        Spacer()

                        Button {
                            if previewingSound == entry.id {
                                stopPreview()
                            } else {
                                previewSound(named: entry.id)
                            }
                        } label: {
                            Image(systemName: previewingSound == entry.id ? "stop.fill" : "speaker.wave.2")
                                .font(.subheadline)
                                .foregroundStyle(previewingSound == entry.id ? Color("AccentGreen") : .secondary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(draft.alertSoundName == entry.id ? Color("AccentGreen").opacity(0.08) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        draft.alertSoundName = entry.id
                        if previewingSound == entry.id {
                            stopPreview()
                        } else {
                            previewSound(named: entry.id)
                        }
                    }

                    if entry.id != SoundLibrary.sounds.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
        }
    }

    private var musicPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Music")
            HStack {
                if draft.alertMusicURL.isEmpty {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                    Text("No track selected")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(Color("AccentGreen"))
                    Text(draft.alertMusicTitle.isEmpty ? "Custom track" : draft.alertMusicTitle)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Spacer()

                if !draft.alertMusicURL.isEmpty {
                    Button {
                        previewMusicFile()
                    } label: {
                        Image(systemName: previewingSound == "music" ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.subheadline)
                            .foregroundStyle(previewingSound == "music" ? Color("AccentGreen") : .secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        draft.alertMusicURL = ""
                        draft.alertMusicTitle = ""
                        stopPreview()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Button("Choose…") {
                    showMusicFilePicker = true
                }
                .font(.subheadline)
                .foregroundStyle(Color("AccentGreen"))
            }
            .padding(14)
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
            .fileImporter(
                isPresented: $showMusicFilePicker,
                allowedContentTypes: [.audio, .mp3, .wav, .aiff, UTType("com.apple.m4a-audio") ?? .audio],
                allowsMultipleSelection: false
            ) { result in
                handleMusicFileSelection(result)
            }

            Text("Pick an audio file from Files. The file is copied into the app so it's always available.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func infoRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    // MARK: - Sound preview

    private func previewSound(named name: String) {
        previewPlayer?.stop()

        let volume = Float(AppSettings.shared.alertVolume)
        if let player = SoundLibrary.play(named: name, volume: volume) {
            previewPlayer = player
            previewingSound = name

            let duration = player.duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if previewingSound == name { previewingSound = nil }
            }
        } else {
            previewingSound = nil
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewingSound = nil
    }

    // MARK: - Music file handling

    private func handleMusicFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }

            // Gain access to the security-scoped resource
            guard sourceURL.startAccessingSecurityScopedResource() else {
                print("Could not access security-scoped resource")
                return
            }
            defer { sourceURL.stopAccessingSecurityScopedResource() }

            let fileName = sourceURL.lastPathComponent
            let displayName = sourceURL.deletingPathExtension().lastPathComponent

            // Copy to app's documents/Music directory
            let musicDir = Self.musicDirectory()
            let destURL  = musicDir.appendingPathComponent(fileName)

            do {
                // Remove existing file with the same name if present
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destURL)

                draft.alertMusicURL   = fileName
                draft.alertMusicTitle = displayName

                // Auto-preview
                previewMusicFile()
            } catch {
                print("Failed to copy music file: \(error)")
            }

        case .failure(let error):
            print("File picker error: \(error)")
        }
    }

    private func previewMusicFile() {
        stopPreview()
        guard !draft.alertMusicURL.isEmpty else { return }

        let fileURL = Self.musicDirectory().appendingPathComponent(draft.alertMusicURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            previewPlayer = try AVAudioPlayer(contentsOf: fileURL)
            previewPlayer?.volume = Float(AppSettings.shared.alertVolume)
            // Only preview the first 5 seconds
            previewPlayer?.play()
            previewingSound = "music"

            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [self] in
                if previewingSound == "music" {
                    previewPlayer?.stop()
                    previewingSound = nil
                }
            }
        } catch {
            print("Music preview error: \(error)")
        }
    }

    /// Returns (and creates if needed) the Music subdirectory in the app's Documents folder.
    static func musicDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let musicDir = docs.appendingPathComponent("Music", isDirectory: true)
        if !FileManager.default.fileExists(atPath: musicDir.path) {
            try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        }
        return musicDir
    }

    // MARK: - Reusable field

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(label)
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color("Surface"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2).fontDesign(.monospaced)
            .foregroundStyle(.secondary)
            .kerning(1.2)
    }

    // MARK: - State sync

    private func loadFromDraft() {
        minutes       = draft.durationSeconds / 60
        seconds       = draft.durationSeconds % 60
        pickedColor   = Color(hex: draft.colorHex) ?? Color("AccentGreen")

        // Snapshot for cancel/restore
        originalName           = draft.name
        originalDuration       = draft.durationSeconds
        originalRepeatCount    = draft.repeatCount
        originalAlertType      = draft.alertType
        originalAlertSoundName = draft.alertSoundName
        originalAlertMusicURL  = draft.alertMusicURL
        originalAlertMusicTitle = draft.alertMusicTitle
        originalColorHex       = draft.colorHex
    }

    private func commitAndDismiss() {
        draft.durationSeconds = minutes * 60 + seconds
        draft.colorHex        = pickedColor.hexString
        draft.isNew           = false
        stopPreview()
        dismiss()
    }

    private func cancelAndDismiss() {
        // Restore original values (undoes live edits to the reference type)
        draft.name            = originalName
        draft.durationSeconds = originalDuration
        draft.repeatCount     = originalRepeatCount
        draft.alertType       = originalAlertType
        draft.alertSoundName  = originalAlertSoundName
        draft.alertMusicURL   = originalAlertMusicURL
        draft.alertMusicTitle = originalAlertMusicTitle
        draft.colorHex        = originalColorHex
        stopPreview()
        onCancel?()
        dismiss()
    }
}

// MARK: - Alert Chip

struct AlertChip: View {
    let type: AlertType
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Text(type.rawValue)
            .font(.subheadline).fontWeight(.medium)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selected ? Color("AccentGreen").opacity(0.15) : Color("Surface2"))
            .foregroundStyle(selected ? Color("AccentGreen") : Color.secondary)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        selected ? Color("AccentGreen").opacity(0.4) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            }
            .contentShape(Capsule())
            .onTapGesture { action() }
    }
}
