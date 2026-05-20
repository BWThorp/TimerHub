import SwiftUI
import AVFoundation
import Combine

// MARK: - Voice previewer

@Observable
final class VoicePreviewer: NSObject, AVSpeechSynthesizerDelegate {
    var isPlaying = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func preview(voiceId: String, volume: Double) {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
            isPlaying = false
            return
        }

        let utterance = AVSpeechUtterance(string: "Interval 1, 30 seconds. 3, 2, 1. Session complete.")
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = Float(volume)

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        isPlaying = true
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isPlaying = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
}

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared

    @State private var availableVoices: [AVSpeechSynthesisVoice] = []
    @State private var previewer = VoicePreviewer()

    var body: some View {
        NavigationStack {
            ZStack {
                Color("Background").ignoresSafeArea()

                List {

                    // MARK: Defaults
                    Section {
                        Picker("Alert Type", selection: $settings.defaultAlertType) {
                            ForEach(AlertType.allCases, id: \.rawValue) { type in
                                Text(type.rawValue).tag(type.rawValue)
                            }
                        }

                        Picker("Alert Sound", selection: $settings.defaultAlertSound) {
                            ForEach(SoundLibrary.allNames, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        }

                        HStack {
                            Text("Interval Color")
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: settings.defaultColorHex) ?? .green },
                                set: { settings.defaultColorHex = $0.hexString }
                            ), supportsOpacity: false)
                            .labelsHidden()
                        }

                    } header: {
                        sectionHeader("Defaults")
                    }
                    .listRowBackground(Color("Surface"))

                    // MARK: Playback
                    Section {
                        Toggle("Keep Screen Awake", isOn: $settings.keepScreenAwake)

                        Picker("Default View", selection: $settings.playbackViewStyle) {
                            Text("Fill").tag(PlaybackViewStyle.fill.rawValue)
                            Text("Ring").tag(PlaybackViewStyle.ring.rawValue)
                        }

                        Picker("Count Direction", selection: $settings.countDirection) {
                            Text("Down").tag(CountDirection.down.rawValue)
                            Text("Up").tag(CountDirection.up.rawValue)
                        }

                        Toggle("Haptics", isOn: $settings.hapticsEnabled)

                    } header: {
                        sectionHeader("Playback")
                    }
                    .listRowBackground(Color("Surface"))

                    // MARK: Audio
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Alert Volume")
                                .font(.subheadline)
                            Slider(value: $settings.alertVolume, in: 0...1)
                                .tint(Color("AccentGreen"))
                        }
                        .padding(.vertical, 4)

                        if !availableVoices.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Announcement Voice")
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                HStack {
                                    Picker("", selection: $settings.announcementVoice) {
                                        ForEach(availableVoices, id: \.identifier) { voice in
                                            Text(voiceLabel(voice)).tag(voice.identifier)
                                        }
                                    }
                                    .labelsHidden()
                                    .tint(Color("AccentGreen"))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Button {
                                        previewer.preview(voiceId: settings.announcementVoice, volume: settings.alertVolume)
                                    } label: {
                                        Image(systemName: previewer.isPlaying ? "stop.fill" : "play.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color("AccentGreen"))
                                            .frame(width: 32, height: 32)
                                            .background(Color("AccentGreen").opacity(0.12))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .fixedSize()
                                }
                            }
                        }

                        Toggle("Speak Interval Name", isOn: $settings.speakIntervalName)
                        Toggle("Speak Countdown", isOn: $settings.speakCountdown)

                    } header: {
                        sectionHeader("Audio")
                    }
                    .listRowBackground(Color("Surface"))

                    // MARK: About — single row navigating to AboutView
                    Section {
                        NavigationLink(destination: AboutView()) {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color("AccentGreen").opacity(0.15))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "timer")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color("AccentGreen"))
                                    }
                                Text("About Timer Hub")
                                    .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        sectionHeader("About")
                    }
                    .listRowBackground(Color("Surface"))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { loadVoices() }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .kerning(1.2)
            .textCase(.uppercase)
    }

    private func loadVoices() {
        // AVSpeechSynthesisVoice.speechVoices() logs harmless DecodingError
        // messages on some iOS versions. Loading on a background queue
        // keeps the console quieter, and we update state on main.
        DispatchQueue.global(qos: .userInitiated).async {
            let allEnglish = AVSpeechSynthesisVoice.speechVoices()
                .filter { voice in
                    voice.language.hasPrefix("en")
                    // Novelty/joke voices all use the legacy synthesis prefix
                    && !voice.identifier.hasPrefix("com.apple.speech.synthesis.voice")
                }

            // Prefer enhanced/premium voices; fall back to all if none available
            var filtered = allEnglish.filter { $0.quality != .default }
            if filtered.isEmpty {
                filtered = allEnglish
            }

            let sorted = filtered.sorted { lhs, rhs in
                // Sort premium first, then enhanced, then default, then by name
                if lhs.quality != rhs.quality {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }

            DispatchQueue.main.async {
                availableVoices = sorted

                // If the stored voice isn't in the filtered list, fall back to the first available
                if !sorted.contains(where: { $0.identifier == settings.announcementVoice }),
                   let first = sorted.first {
                    settings.announcementVoice = first.identifier
                }
            }
        }
    }

    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let qualityTag: String
        switch voice.quality {
        case .premium:
            qualityTag = "Premium"
        case .enhanced:
            qualityTag = "Enhanced"
        default:
            qualityTag = ""
        }
        let locale = Locale.current.localizedString(forIdentifier: voice.language)
            ?? voice.language
        if qualityTag.isEmpty {
            return "\(voice.name) — \(locale)"
        }
        return "\(voice.name) — \(locale) (\(qualityTag))"
    }
}
