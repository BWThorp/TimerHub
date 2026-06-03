// PlaybackEngine.swift  (replace existing file)
// Main app target.

import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import WidgetKit

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

    /// String representation for ContentState (no SwiftUI dependency needed there).
    var name: String {
        switch self {
        case .green:  return "green"
        case .yellow: return "yellow"
        case .red:    return "red"
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
    private var sessionName: String         = ""
    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var speechSynth: AVSpeechSynthesizer?
    private let settings = AppSettings.shared

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundDate: Date?                        // when we entered background
    private(set) var intervalEndDate: Date?                  // absolute wall-clock end of current interval
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
        let leading = max(0, secondsRemaining - 1)
        return 1.0 - (Double(leading) / Double(total))
    }

    var timerColor: TimerColor {
        guard let step = currentStep else { return .green }
        let duration = step.interval.durationSeconds
        guard duration > 0 else { return .green }

        let remaining = secondsRemaining

        if duration < 15 {
            if remaining <= 2 { return .red }
            if remaining <= 5 { return .yellow }
        } else if duration < 60 {
            if remaining <= 5  { return .red }
            if remaining <= 10 { return .yellow }
        } else if duration <= 3600 {
            if Double(remaining) / Double(duration) <= 0.05 { return .red }
            if Double(remaining) / Double(duration) <= 0.20 { return .yellow }
        } else {
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

        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func handleWillEnterForeground() {
        cancelPlaybackNotifications()

        // Reconcile using the absolute end date if we have one — much more
        // accurate than counting elapsed integer seconds.
        if isRunning, !isPaused {
            if let endDate = intervalEndDate {
                let remaining = Int(endDate.timeIntervalSinceNow.rounded(.up))
                if remaining <= 0 {
                    // The interval(s) expired while we were backgrounded.
                    // Use the old integer path to advance through steps.
                    if let bgDate = backgroundDate {
                        let elapsed = Int(Date().timeIntervalSince(bgDate))
                        reconcileAfterBackground(elapsedSeconds: elapsed)
                    }
                } else {
                    // Still in the same interval — just correct secondsRemaining.
                    secondsRemaining = remaining
                }
            } else if let bgDate = backgroundDate {
                let elapsed = Int(Date().timeIntervalSince(bgDate))
                reconcileAfterBackground(elapsedSeconds: elapsed)
            }
        }

        backgroundDate = nil
        endBackgroundTask()

        // After reconciliation, recompute intervalEndDate for the current step
        // and push a fresh snapshot so the widget gets the correct end date.
        if isRunning, !isFinished, !isPaused {
            intervalEndDate = Date().addingTimeInterval(Double(secondsRemaining))
            let state = makeContentState()
            writeWidgetSnapshot(state)
            Task { @MainActor in
                LiveActivityManager.shared.update(state: state)
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func reconcileAfterBackground(elapsedSeconds: Int) {
        var remaining = elapsedSeconds

        while remaining > 0 && isRunning && !isFinished {
            if secondsRemaining > remaining {
                secondsRemaining -= remaining
                remaining = 0
            } else {
                remaining -= secondsRemaining
                secondsRemaining = 0
                advanceStep()
            }
        }
    }

    // MARK: - Playback notifications

    private func schedulePlaybackNotifications() {
        let center = UNUserNotificationCenter.current()
        var cumulativeSeconds = secondsRemaining

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
        sessionName = session.name
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
        intervalEndDate = Date().addingTimeInterval(Double(secondsRemaining))
        scheduleTimer()
        handleScreenAwake(true)
        announceCurrentInterval()
        startLiveActivity()
    }

    func pause() {
        isPaused = true
        timer?.invalidate()
        timer = nil
        intervalEndDate = nil   // no countdown while paused
        updateLiveActivity()
    }

    func resume() {
        isPaused = false
        // Recompute end date from current secondsRemaining when resuming
        intervalEndDate = Date().addingTimeInterval(Double(secondsRemaining))
        scheduleTimer()
        updateLiveActivity()
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
        updateLiveActivity()
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
        intervalEndDate    = nil
        audioPlayer?.stop()
        speechSynth?.stopSpeaking(at: .immediate)
        handleScreenAwake(false)
        cancelPlaybackNotifications()
        endBackgroundTask()
        endLiveActivity(finished: false)
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

        // Derive secondsRemaining from the absolute end date so the app
        // display stays in sync with the widget and never drifts.
        if let endDate = intervalEndDate {
            let remaining = Int(endDate.timeIntervalSinceNow.rounded(.up))
            secondsRemaining = max(0, remaining)
        } else {
            secondsRemaining = max(0, secondsRemaining - 1)
        }

        if settings.speakCountdown {
            if countsUp {
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

        // Update Live Activity every tick
        updateLiveActivity()

        if secondsRemaining == 0 {
            fireAlert()
            if countsUp {
                isAdvancing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.isAdvancing = false
                    self?.advanceStep()
                }
            } else {
                advanceStep()
            }
        }
    }

    private func advanceStep() {
        let next = stepIndex + 1
        if next >= steps.count {
            let nextRepeat = sessionRepeat + 1
            if nextRepeat < sessionRepeatCount {
                sessionRepeat    = nextRepeat
                stepIndex        = 0
                secondsRemaining = steps.first?.interval.durationSeconds ?? 0
                intervalEndDate  = Date().addingTimeInterval(Double(secondsRemaining))
                announceCurrentInterval()
                updateLiveActivity()
            } else {
                finish()
            }
        } else {
            stepIndex        = next
            secondsRemaining = currentStep?.interval.durationSeconds ?? 0
            intervalEndDate  = Date().addingTimeInterval(Double(secondsRemaining))
            announceCurrentInterval()
            updateLiveActivity()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer           = nil
        isRunning       = false
        isFinished      = true
        intervalEndDate = nil
        handleScreenAwake(false)
        fireSessionCompleteAlert()
        endLiveActivity(finished: true)
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
        let lastInterval = steps.last?.interval
        let lastHasSound = lastInterval?.alertTypeEnum == .sound ||
                           lastInterval?.alertTypeEnum == .music

        if !lastHasSound {
            playSound(named: "SessionComplete")
        }

        if settings.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if settings.speakIntervalName {
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
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = docs.appendingPathComponent("Music", isDirectory: true)
                         .appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioPlayer = try? AVAudioPlayer(contentsOf: fileURL)
        audioPlayer?.volume = Float(settings.alertVolume)
        audioPlayer?.play()
    }

    private func triggerHaptic() {
        guard settings.hapticsEnabled else { return }
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

    // MARK: - Live Activity helpers

    /// Snapshot of the current engine state as a ContentState.
    private func makeContentState(isFinished: Bool = false) -> TimerHubActivityAttributes.ContentState {
        TimerHubActivityAttributes.ContentState(
            isRunning: isRunning,
            isPaused: isPaused,
            isFinished: isFinished,
            intervalName: currentInterval?.name ?? "",
            secondsRemaining: secondsRemaining,
            totalIntervalSeconds: currentStep?.interval.durationSeconds ?? 0,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            sessionRepeat: sessionRepeat,
            sessionRepeatTotal: sessionRepeatCount,
            colorName: timerColor.name,
            nextIntervalName: nextStep?.interval.name ?? "",
            nextIntervalSeconds: nextStep?.interval.durationSeconds ?? 0,
            timerEndDate: (isRunning && !isPaused && !isFinished) ? intervalEndDate : nil
        )
    }

    private func startLiveActivity() {
        let state = makeContentState()
        Task { @MainActor in
            LiveActivityManager.shared.start(sessionName: sessionName, state: state)
        }
        writeWidgetSnapshot(state)
    }

    private func updateLiveActivity() {
        let state = makeContentState()
        Task { @MainActor in
            LiveActivityManager.shared.update(state: state)
        }
        // Write every tick so the widget stays current.
        writeWidgetSnapshot(state)
    }

    private func endLiveActivity(finished: Bool) {
        let finalState = makeContentState(isFinished: finished)
        Task { @MainActor in
            LiveActivityManager.shared.end(finalState: finalState)
        }
        WidgetDataWriter.clear()
    }

    // MARK: - Widget snapshot bridge

    /// Convert current engine state to a WidgetSnapshot and persist it
    /// to the shared App Group so the Home Screen widget can read it.
    private func writeWidgetSnapshot(_ state: TimerHubActivityAttributes.ContentState) {
        // Use the engine's absolute intervalEndDate directly — this is the same
        // date the app timer is counting toward, so widget and app stay in sync.
        let snapshot = WidgetSnapshot(
            isActive: isRunning || isPaused,
            sessionName: sessionName,
            intervalName: state.intervalName,
            secondsRemaining: state.secondsRemaining,
            totalIntervalSeconds: state.totalIntervalSeconds,
            stepIndex: state.stepIndex,
            totalSteps: state.totalSteps,
            sessionRepeat: state.sessionRepeat,
            sessionRepeatTotal: state.sessionRepeatTotal,
            colorName: state.colorName,
            nextIntervalName: state.nextIntervalName,
            nextIntervalSeconds: state.nextIntervalSeconds,
            isPaused: isPaused,
            isFinished: isFinished,
            updatedAt: Date(),
            timerEndDate: (isRunning && !isPaused) ? intervalEndDate : nil,
            pausedSecondsRemaining: isPaused ? state.secondsRemaining : nil
        )
        WidgetDataWriter.write(snapshot)
    }
}
