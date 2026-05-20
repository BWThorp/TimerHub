import SwiftUI
import Combine

// MARK: - Playback view preference

enum PlaybackViewStyle: String {
    case fill = "fill"
    case ring = "ring"
}

enum CountDirection: String {
    case down = "down"
    case up   = "up"
}

// MARK: - AppSettings

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // Defaults
    @AppStorage("defaultAlertType")   var defaultAlertType: String  = AlertType.sound.rawValue
    @AppStorage("defaultAlertSound")  var defaultAlertSound: String = "Ding"
    @AppStorage("defaultColorHex")    var defaultColorHex: String   = "#34D97B"

    // Playback
    @AppStorage("keepScreenAwake")    var keepScreenAwake: Bool    = true
    @AppStorage("playbackViewStyle")  var playbackViewStyle: String = PlaybackViewStyle.fill.rawValue
    @AppStorage("countDirection")     var countDirection: String    = CountDirection.down.rawValue
    @AppStorage("hapticsEnabled")     var hapticsEnabled: Bool     = true

    // Audio
    @AppStorage("alertVolume")        var alertVolume: Double = 0.8
    @AppStorage("announcementVoice")  var announcementVoice: String = "com.apple.ttsbundle.Samantha-compact"
    @AppStorage("speakIntervalName")  var speakIntervalName: Bool  = true
    @AppStorage("speakCountdown")     var speakCountdown: Bool     = false

    var defaultAlertTypeEnum: AlertType {
        AlertType(rawValue: defaultAlertType) ?? .sound
    }

    var playbackViewStyleEnum: PlaybackViewStyle {
        PlaybackViewStyle(rawValue: playbackViewStyle) ?? .fill
    }

    var countDirectionEnum: CountDirection {
        CountDirection(rawValue: countDirection) ?? .down
    }
}
