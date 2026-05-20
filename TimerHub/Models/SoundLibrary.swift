import Foundation
import Combine
import AVFoundation

// MARK: - SoundLibrary
// Central registry of available alert sounds backed by bundled .wav files.
// Both the IntervalEditorSheet (preview) and PlaybackEngine (actual alerts)
// use this so the mapping stays in sync.

struct SoundEntry: Identifiable {
    let id: String          // display name
    let fileName: String    // resource name without extension (e.g. "Alarm Buzz")
}

struct SoundLibrary {

    /// All available sounds, alphabetically ordered.
    static let sounds: [SoundEntry] = [
        SoundEntry(id: "Alarm Buzz",   fileName: "Alarm Buzz"),
        SoundEntry(id: "Bleep",        fileName: "Bleep"),
        SoundEntry(id: "Chirp",        fileName: "Chirp"),
        SoundEntry(id: "Cow Bell",     fileName: "Cow Bell"),
        SoundEntry(id: "Ding",         fileName: "Ding"),
        SoundEntry(id: "Drip",         fileName: "Drip"),
        SoundEntry(id: "Marimba",      fileName: "Marimba"),
        SoundEntry(id: "Rooster",      fileName: "Rooster"),
        SoundEntry(id: "Sci-Fi",       fileName: "Sci-Fi"),
        SoundEntry(id: "Summer Bells", fileName: "Summer Bells"),
        SoundEntry(id: "Toy Train",    fileName: "Toy Train"),
        SoundEntry(id: "Fairy",       fileName: "Fairy"),
    ]

    static let defaultSoundName = "Ding"

    /// Look up a sound by name; returns nil if not found.
    static func entry(named name: String) -> SoundEntry? {
        sounds.first { $0.id == name }
    }

    /// All sound names, for simple iteration.
    static var allNames: [String] {
        sounds.map(\.id)
    }

    /// Play a bundled sound by name. Returns the player (caller must hold a
    /// strong reference until playback finishes) or nil if the sound wasn't found.
    @discardableResult
    static func play(named name: String, volume: Float = 1.0) -> AVAudioPlayer? {
        guard let entry = entry(named: name),
              let url = Bundle.main.url(forResource: entry.fileName, withExtension: "wav") else {
            return nil
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.play()
            return player
        } catch {
            #if DEBUG
            print("🔊 Failed to play sound \(name): \(error)")
            #endif
            return nil
        }
    }

    /// Validate a sound name; if invalid, return the default.
    static func validated(_ name: String) -> String {
        entry(named: name) != nil ? name : defaultSoundName
    }
}
