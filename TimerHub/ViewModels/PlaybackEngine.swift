import SwiftUI
import Combine
import AVFoundation
import UserNotifications

// MARK: - Playback step

struct PlaybackStep {
    let interval: TimerInterval
    let repeatIndex: Int   // 0-based repeat within this interval
}

// MARK: - Traffic light color

enum TimerColor {
    case green, yellow, red

    var color: Color {
        switch self {
        case .green:  return Color("AccentGreen")
        case .yellow: return Color("AccentYellow")
        case .red:    return Color("AccentRed")
        }
    }
}

// MARK: - PlaybackEngine

@Observable
final class PlaybackEngine {

    // Public state
    var isRunning: Bool       = false
    var isPaused: Bool        = false
    var isFinished: Bool      = false
    var stepIndex: Int        = 0
    var secondsRemaining: Int = 0
    var sessionRepeat: Int    = 0   // which session loop we're on (0-based)

    private var isAdvancing: Bool = false   // guards delayed advance during count-up

    private(set) var steps: [PlaybackStep]  = []
    private var baseSteps: [PlaybackStep]   = []   // one full pass, used for looping
    private var sessionRepeatCount: Int     = 1
    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var speechSynth: AVSpeechSynthesizer?
    private let settings = AppSettings.shared

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundDate: Date?                        // when we entered background
    private var sceneObservers: [NSObjectProtocol] = []

    // MARK: - Notification identifiers

    private static let notificationPrefix = "timerhub.playback."

    // MARK: - Derived state

    /// Total number of session repeats (exposed for UI)
    var sessionRepeatTotal: Int { sessionRepeatCount }

    var currentStep: PlaybackStep? {
        guard stepIndex < steps.count else { return nil }
        return steps[stepIndex]
    }

    var nextStep: PlaybackStep? {
        let next = stepIndex + 1
        guard next < steps.count else { return nil }
        return steps[next]
    }

    var currentInterval: TimerInterval? { currentStep?.interval }

    var totalSteps: Int { steps.count }

    /// True when on the very last step of the very last round
    var isOnLastStep: Bool {
        stepIndex >= steps.count - 1 && sessionRepeat >= sessionRepeatCount - 1
    }

    /// Elapsed seconds within the current interval
    var secondsElapsed: Int {
        guard let step = currentStep else { return 0 }
        return step.interval.durationSeconds - secondsRemaining
    }

    /// Whether the display should count up
    var countsUp: Bool {
        settings.countDirectionEnum == .up
    }

    var progressFraction: Double {
        guard let step = currentStep else { return 0 }
        let total = step.interval.durationSeconds
        guard total > 0 else { return 0 }
        // Lead by one tick so the 1-second animation completes
        // exactly as the next number appears on screen
        let leading = max(0, secondsRemaining - 1)
        return 1.0 - (Double(leading) / Double(total))
    }

    var timerColor: TimerColor {
        guard let step = currentStep else { return .green }
        let duration = step.interval.durationSeconds
        guard duration > 0 else { return .green }

        let remaining = secondsRemaining

        if duration < 15 {
            // Very short intervals: yellow at 5s, red at 2s
            if remaining <= 2 { return .red }
            if remaining <= 5 { return .yellow }
        } else if duration < 60 {
            // Short intervals: yellow at 10s, red at 5s
            if remaining <= 5  { return .red }
            if remaining <= 10 { return .yellow }
        } else if duration <= 3600 {
            // 1–60 minutes: yellow at 20%, red at 5%
            if Double(remaining) / Double(duration) <= 0.05 { return .red }
            if Double(remaining) / Double(duration) <= 0.20 { return .yellow }
        } else {
            // Over 60 minutes: yellow at 10%, red at 2.5%
            if Double(remaining) / Double(duration) <= 0.025 { return .red }
            if Double(remaining) / Double(duration) <= 0.10  { return .yellow }
        }

        return .green
    }

    // MARK: - Session loading

    init() {
        let didEnterBackground = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
        let willEnterForeground = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWillEnterForeground()
        }
        sceneObservers = [didEnterBackground, willEnterForeground]
    }

    deinit {
        for observer in sceneObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Background / Foreground

    private func handleDidEnterBackground() {
        guard isRunning, !isPaused else { return }
        backgroundDate = Date()
        schedulePlaybackNotifications()

        // Request a short background task so the timer stays alive briefly
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func handleWillEnterForeground() {
        cancelPlaybackNotifications()

        // Reconcile elapsed time while we were in the background
        if let bgDate = backgroundDate, isRunning, !isPaused {
            let elapsed = Int(Date().timeIntervalSince(bgDate))
            reconcileAfterBackground(elapsedSeconds: elapsed)
        }
        backgroundDate = nil
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    /// Fast-forward the playback state by the number of seconds that passed
    /// while the app was suspended.
    private func reconcileAfterBackground(elapsedSeconds: Int) {
        var remaining = elapsedSeconds

        while remaining > 0 && isRunning && !isFinished {
            if secondsRemaining > remaining {
                // Still within the current step
                secondsRemaining -= remaining
                remaining = 0
            } else {
                // This step completed while we were away
                remaining -= secondsRemaining
                secondsRemaining = 0
                // Advance without playing sounds (the notification handled alerting)
                advanceStep()
            }
        }
    }

    // MARK: - Playback notifications

    /// Schedule a local notification for every remaining interval transition.
    private func schedulePlaybackNotifications() {
        let center = UNUserNotificationCenter.current()
        var cumulativeSeconds = secondsRemaining  // time until first transition

        // Notification for the current step ending
        if let current = currentStep, cumulativeSeconds > 0 {
            scheduleOneNotification(
                center: center,
                identifier: "\(Self.notificationPrefix)\(stepIndex)",
                title: "Interval Complete",
                body: current.interval.name,
                soundName: notificationSoundFile(for: current.interval),
                timeInterval: Double(cumulativeSeconds)
            )
        }

        // Notifications for subsequent steps
        for i in (stepIndex + 1)..<steps.count {
            cumulativeSeconds += steps[i].interval.durationSeconds
            scheduleOneNotification(
                center: center,
                identifier: "\(Self.notificationPrefix)\(i)",
                title: "Interval Complete",
                body: steps[i].interval.name,
                soundName: notificationSoundFile(for: steps[i].interval),
                timeInterval: Double(cumulativeSeconds)
            )
        }

        // Schedule a "Session Complete" notification at the very end,
        // using the last interval's sound so it matches in-app behavior.
        let sessionEnd = cumulativeSeconds
        if sessionEnd > 0 {
            let lastSound: String?
            if let lastInterval = steps.last?.interval {
                lastSound = notificationSoundFile(for: lastInterval)
            } else {
                lastSound = nil
            }
            scheduleOneNotification(
                center: center,
                identifier: "\(Self.notificationPrefix)session-complete",
                title: "Session Complete",
                body: "All intervals finished",
                soundName: lastSound,
                timeInterval: Double(sessionEnd)
            )
        }
    }

    /// Returns the bundled sound filename (e.g. "Ding.wav") for a given interval,
    /// or nil if the interval uses a non-sound alert type.
    private func notificationSoundFile(for interval: TimerInterval) -> String? {
        guard interval.alertTypeEnum == .sound else { return nil }
        let name = SoundLibrary.validated(interval.alertSoundName)
        guard let entry = SoundLibrary.entry(named: name) else { return nil }
        return "\(entry.fileName).wav"
    }

    private func scheduleOneNotification(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String,
        soundName: String?,
        timeInterval: Double
    ) {
        guard timeInterval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body

        if let soundName {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        } else {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private func cancelPlaybackNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.notificationPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Load session

    func load(session: TimerSession) {
        stop()
        baseSteps = session.sortedIntervals.flatMap { interval in
            (0..<max(1, interval.repeatCount)).map { rep in
                PlaybackStep(interval: interval, repeatIndex: rep)
            }
        }
        sessionRepeatCount = max(1, session.sessionRepeatCount)
        steps              = baseSteps
        stepIndex          = 0
        sessionRepeat      = 0
        secondsRemaining   = steps.first?.interval.durationSeconds ?? 0
        isFinished         = false
    }

    // MARK: - Controls

    func start() {
        guard !steps.isEmpty else { return }
        isRunning = true
        isPaused  = false
        scheduleTimer()
        handleScreenAwake(true)
        announceCurrentInterval()
    }

    func pause() {
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        isPaused = false
        scheduleTimer()
    }

    func skipForward() {
        advanceStep()
    }

    func skipBackward() {
        if stepIndex > 0 {
            stepIndex -= 1
            secondsRemaining = currentStep?.interval.durationSeconds ?? 0
            announceCurrentInterval()
        } else {
            secondsRemaining = currentStep?.interval.durationSeconds ?? 0
        }
    }

    func stop() {
        timer?.invalidate()
        timer              = nil
        isRunning          = false
        isPaused           = false
        isFinished         = false
        isAdvancing        = false
        stepIndex          = 0
        sessionRepeat      = 0
        audioPlayer?.stop()
        speechSynth?.stopSpeaking(at: .immediate)
        handleScreenAwake(false)
        cancelPlaybackNotifications()
        endBackgroundTask()
    }

    // MARK: - Timer

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        guard isRunning, !isPaused, !isAdvancing else { return }

        if secondsRemaining > 0 {
            secondsRemaining -= 1

            if settings.speakCountdown {
                if countsUp {
                    // Announce the last 3 elapsed values (e.g. 6, 7, 8 for an 8s timer)
                    let duration = currentStep?.interval.durationSeconds ?? 0
                    let elapsed = duration - secondsRemaining
                    if elapsed >= duration - 2 && elapsed <= duration {
                        speak(String(elapsed))
                    }
                } else {
                    if [3, 2, 1].contains(secondsRemaining) {
                        speak(String(secondsRemaining))
                    }
                }
            }

            if secondsRemaining == 0 {
                fireAlert()
                if countsUp {
                    // Briefly show the final elapsed value before advancing
                    isAdvancing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        self?.isAdvancing = false
                        self?.advanceStep()
                    }
                } else {
                    advanceStep()
                }
            }
        } else {
            // Edge case: interval with 0 duration
            fireAlert()
            advanceStep()
        }
    }

    private func advanceStep() {
        let next = stepIndex + 1
        if next >= steps.count {
            // End of one full pass — check if we need to loop
            let nextRepeat = sessionRepeat + 1
            if nextRepeat < sessionRepeatCount {
                sessionRepeat    = nextRepeat
                stepIndex        = 0
                secondsRemaining = steps.first?.interval.durationSeconds ?? 0
                announceCurrentInterval()
            } else {
                finish()
            }
        } else {
            stepIndex        = next
            secondsRemaining = currentStep?.interval.durationSeconds ?? 0
            announceCurrentInterval()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer      = nil
        isRunning  = false
        isFinished = true
        handleScreenAwake(false)
        fireSessionCompleteAlert()
    }

    // MARK: - Alerts

    private func fireAlert() {
        guard let interval = currentInterval else { return }
        switch interval.alertTypeEnum {
        case .none:   break
        case .sound:  playSound(named: interval.alertSoundName)
        case .speak:  announceCurrentInterval()
        case .music:  playMusicURL(interval.alertMusicURL)
        case .haptic: triggerHaptic()
        }
    }

    private func fireSessionCompleteAlert() {
        // Only play the session-complete sound if the last interval
        // doesn't have its own sound — otherwise it would cut it off.
        let lastInterval = steps.last?.interval
        let lastHasSound = lastInterval?.alertTypeEnum == .sound ||
                           lastInterval?.alertTypeEnum == .music

        if !lastHasSound {
            playSound(named: "SessionComplete")
        }

        if settings.hapticsEnabled {
            #if DEBUG
            print("🫨 Haptic: session complete (notification .success)")
            #endif
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if settings.speakIntervalName {
            // Small delay so the completion sound plays first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.speak("Session complete")
            }
        }
    }

    func playSound(named name: String) {
        let validName = SoundLibrary.validated(name)
        let volume = Float(settings.alertVolume)
        audioPlayer = SoundLibrary.play(named: validName, volume: volume)
    }

    private func playMusicURL(_ fileName: String) {
        guard !fileName.isEmpty else { return }

        // Build path to the Music subdirectory in Documents
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent("Music", isDirectory: true)
                         .appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            #if DEBUG
            print("🎵 Music file not found: \(fileURL.path)")
            #endif
            return
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioPlayer = try? AVAudioPlayer(contentsOf: fileURL)
        audioPlayer?.volume = Float(settings.alertVolume)
        audioPlayer?.play()
    }

    private func triggerHaptic() {
        guard settings.hapticsEnabled else { return }
        #if DEBUG
        print("🫨 Haptic: interval alert (impact .heavy)")
        #endif
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Speech

    private func announceCurrentInterval() {
        guard settings.speakIntervalName, let interval = currentInterval else { return }
        speak("\(interval.name) — \(spokenDuration(interval.durationSeconds))")
    }

    private func spokenDuration(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        var parts: [String] = []
        if m > 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        if s > 0 { parts.append("\(s) \(s == 1 ? "second" : "seconds")") }
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }

    private func speak(_ text: String) {
        if speechSynth == nil { speechSynth = AVSpeechSynthesizer() }
        if speechSynth?.isSpeaking == true {
            speechSynth?.stopSpeaking(at: .immediate)
        }
        let utt = AVSpeechUtterance(string: text)
        utt.voice  = AVSpeechSynthesisVoice(identifier: settings.announcementVoice)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utt.volume = Float(settings.alertVolume)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        speechSynth?.speak(utt)
    }

    // MARK: - Screen awake

    private func handleScreenAwake(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on && settings.keepScreenAwake
    }
}
