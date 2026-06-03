import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import WidgetKit

// MARK: - TimerManager
// Manages all concurrent QuickTimers from the Timers tab.
// Runs a single shared 1-second Timer that ticks every active QuickTimer.

@Observable
final class TimerManager {
    static let shared = TimerManager()

    var timers: [QuickTimer] = []

    // Completion banner state
    var completedTimerName: String?
    var showCompletionBanner: Bool = false

    private var ticker: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var speechSynthesizer: AVSpeechSynthesizer?
    private let settings = AppSettings.shared

    private init() {}

    // MARK: - Active / finished helpers

    var activeTimers: [QuickTimer] {
        timers.filter { $0.state == .running || $0.state == .paused }
    }

    var finishedTimers: [QuickTimer] {
        timers.filter { $0.state == .finished }
    }

    var hasActiveTimers: Bool {
        timers.contains { $0.state == .running || $0.state == .paused }
    }

    var runningCount: Int {
        timers.filter { $0.state == .running }.count
    }

    // MARK: - Timer lifecycle

    func addAndStart(_ timer: QuickTimer) {
        timer.state           = .running
        timer.startedAt       = Date()
        timer.secondsRemaining = timer.totalSeconds
        timers.insert(timer, at: 0)
        scheduleNotification(for: timer)
        ensureTickerRunning()
        updateScreenAwake()
        writeWidgetSnapshot()
    }

    func pause(_ timer: QuickTimer) {
        guard timer.state == .running else { return }
        timer.state = .paused
        cancelNotification(for: timer)
        updateScreenAwake()
        writeWidgetSnapshot()
    }

    func resume(_ timer: QuickTimer) {
        guard timer.state == .paused else { return }
        timer.state = .running
        scheduleNotification(for: timer)
        ensureTickerRunning()
        updateScreenAwake()
        writeWidgetSnapshot()
    }

    func togglePause(_ timer: QuickTimer) {
        if timer.state == .running {
            pause(timer)
        } else if timer.state == .paused {
            resume(timer)
        }
    }

    func restart(_ timer: QuickTimer) {
        timer.secondsRemaining = timer.totalSeconds
        timer.state            = .running
        timer.startedAt        = Date()
        timer.finishedAt       = nil
        scheduleNotification(for: timer)
        ensureTickerRunning()
        updateScreenAwake()
    }

    func remove(_ timer: QuickTimer) {
        cancelNotification(for: timer)
        timers.removeAll { $0.id == timer.id }
        updateScreenAwake()
        writeWidgetSnapshot()
    }

    func removeFinished() {
        let finished = finishedTimers
        for t in finished {
            cancelNotification(for: t)
        }
        timers.removeAll { $0.state == .finished }
        writeWidgetSnapshot()
    }

    /// Update an existing timer's settings and restart it with the new duration.
    func update(_ timer: QuickTimer, name: String, totalSeconds: Int, alertType: AlertType, alertSoundName: String) {
        cancelNotification(for: timer)
        timer.name            = name
        timer.totalSeconds    = totalSeconds
        timer.alertType       = alertType
        timer.alertSoundName  = alertSoundName
        timer.secondsRemaining = totalSeconds
        timer.state           = .running
        timer.startedAt       = Date()
        timer.finishedAt      = nil
        scheduleNotification(for: timer)
        ensureTickerRunning()
        updateScreenAwake()
    }

    // MARK: - Tick

    private func ensureTickerRunning() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    private func tick() {
        var anyRunning = false

        for timer in timers where timer.state == .running {
            if timer.secondsRemaining > 0 {
                timer.secondsRemaining -= 1
                anyRunning = true

                if timer.secondsRemaining == 0 {
                    completeTimer(timer)
                }
            }
        }

        // Update widget every tick while timers are running
        if anyRunning {
            writeWidgetSnapshot()
        }

        if !anyRunning {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func completeTimer(_ timer: QuickTimer) {
        timer.state      = .finished
        timer.finishedAt = Date()
        fireAlert(for: timer)
        showBanner(timerName: timer.name)
        updateScreenAwake()
        writeWidgetSnapshot()

        if settings.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Alerts

    private func fireAlert(for timer: QuickTimer) {
        switch timer.alertType {
        case .none:
            break
        case .sound:
            let name   = SoundLibrary.validated(timer.alertSoundName)
            let volume = Float(settings.alertVolume)
            audioPlayer = SoundLibrary.play(named: name, volume: volume)
        case .speak:
            speak("\(timer.name) complete")
        case .haptic:
            if settings.hapticsEnabled {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        case .music:
            // Quick timers don't support music alerts; fall back to default sound
            let volume = Float(settings.alertVolume)
            audioPlayer = SoundLibrary.play(named: SoundLibrary.defaultSoundName, volume: volume)
        }
    }

    private func speak(_ text: String) {
        let synth = AVSpeechSynthesizer()
        speechSynthesizer = synth

        let utt   = AVSpeechUtterance(string: text)
        utt.voice  = AVSpeechSynthesisVoice(identifier: settings.announcementVoice)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utt.volume = Float(settings.alertVolume)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        synth.speak(utt)
    }

    // MARK: - Completion banner

    private func showBanner(timerName: String) {
        completedTimerName  = timerName
        showCompletionBanner = true

        // Auto-dismiss after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self, self.completedTimerName == timerName else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.showCompletionBanner = false
            }
        }
    }

    func dismissBanner() {
        withAnimation(.easeOut(duration: 0.3)) {
            showCompletionBanner = false
        }
    }

    // MARK: - Local notifications

    private func scheduleNotification(for timer: QuickTimer) {
        let center  = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Timer Complete"
        content.body  = "\(timer.name) — \(timer.totalFormatted)"

        // Use the timer's selected alert sound if available
        if timer.alertType == .sound,
           let entry = SoundLibrary.entry(named: SoundLibrary.validated(timer.alertSoundName)) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("\(entry.fileName).wav"))
        } else {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(timer.secondsRemaining),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: timer.id.uuidString,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    private func cancelNotification(for timer: QuickTimer) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Screen awake

    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = hasActiveTimers && settings.keepScreenAwake
    }

    // MARK: - Widget snapshot

    /// Write the most prominent active timer to the shared App Group
    /// so the Home Screen widget can display it.
    private func writeWidgetSnapshot() {
        let featured = timers.first { $0.state == .running }
                    ?? timers.first { $0.state == .paused }

        guard let t = featured else {
            WidgetDataWriter.clear()
            return
        }

        let endDate: Date? = (t.state == .running)
            ? Date().addingTimeInterval(Double(t.secondsRemaining))
            : nil

        let snapshot = WidgetSnapshot(
            isActive: true,
            sessionName: "Quick Timer",
            intervalName: t.name,
            secondsRemaining: t.secondsRemaining,
            totalIntervalSeconds: t.totalSeconds,
            stepIndex: 0,
            totalSteps: 1,
            sessionRepeat: 0,
            sessionRepeatTotal: 1,
            colorName: colorName(for: t),
            nextIntervalName: "",
            nextIntervalSeconds: 0,
            isPaused: t.state == .paused,
            isFinished: false,
            updatedAt: Date(),
            timerEndDate: endDate,
            pausedSecondsRemaining: t.state == .paused ? t.secondsRemaining : nil
        )
        WidgetDataWriter.write(snapshot)
    }

    /// Traffic-light color name for a quick timer, matching PlaybackEngine logic.
    private func colorName(for timer: QuickTimer) -> String {
        let remaining = timer.secondsRemaining
        let duration  = timer.totalSeconds
        guard duration > 0 else { return "green" }

        if duration < 15 {
            if remaining <= 2 { return "red" }
            if remaining <= 5 { return "yellow" }
        } else if duration < 60 {
            if remaining <= 5  { return "red" }
            if remaining <= 10 { return "yellow" }
        } else if duration <= 3600 {
            if Double(remaining) / Double(duration) <= 0.05 { return "red" }
            if Double(remaining) / Double(duration) <= 0.20 { return "yellow" }
        } else {
            if Double(remaining) / Double(duration) <= 0.025 { return "red" }
            if Double(remaining) / Double(duration) <= 0.10  { return "yellow" }
        }
        return "green"
    }
}
