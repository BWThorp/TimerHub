import SwiftUI
import Combine

struct PlaybackView: View {
    let session: TimerSession
    @Bindable var engine: PlaybackEngine
    @Environment(\.dismiss) private var dismiss

    @State private var pageIndex: Int
    @State private var showCancelConfirmation = false

    init(session: TimerSession, engine: PlaybackEngine) {
        self.session = session
        self.engine = engine
        let style = AppSettings.shared.playbackViewStyleEnum
        _pageIndex = State(initialValue: style == .ring ? 1 : 0)
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            // Ambient glow
            RadialGradient(
                colors: [timerColor.color.opacity(0.18), Color.clear],
                center: .center,
                startRadius: 40,
                endRadius: 280
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: timerColor)

            VStack(spacing: 0) {

                // Header
                ZStack {
                    // Session name centered
                    Text(session.name.uppercased())
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .kerning(1.5)

                    // Cancel on leading edge, only when paused
                    HStack {
                        if engine.isPaused {
                            Button("Cancel") {
                                showCancelConfirmation = true
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color("Surface2"))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .animation(.easeInOut(duration: 0.25), value: engine.isPaused)

                // Session repeat progress (only when session repeats > 1)
                if engine.sessionRepeatTotal > 1 {
                    SessionRepeatTrack(engine: engine)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                }

                // Interval segment track
                IntervalSegmentTrack(engine: engine)
                    .padding(.horizontal, 20)
                    .padding(.top, engine.sessionRepeatTotal > 1 ? 6 : 12)

                // Interval name + round
                VStack(spacing: 3) {
                    Text(engine.currentInterval?.name ?? "")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(timerColor.color)
                        .animation(.easeInOut(duration: 0.3), value: timerColor)

                    if let step = engine.currentStep,
                       step.interval.repeatCount > 1 {
                        Text("Round \(step.repeatIndex + 1) of \(step.interval.repeatCount)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 10)

                // Swipeable countdown views
                TabView(selection: $pageIndex) {
                    FillCountdownView(engine: engine, accentColor: timerColor.color)
                        .tag(0)
                    RingCountdownView(engine: engine, accentColor: timerColor.color)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: pageIndex)

                // Bottom controls
                VStack(spacing: 10) {

                    // Page dots
                    HStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { i in
                            Circle()
                                .fill(i == pageIndex ? Color.primary : Color.primary.opacity(0.2))
                                .frame(width: 5, height: 5)
                                .animation(.easeInOut(duration: 0.2), value: pageIndex)
                        }
                    }

                    // Next interval
                    if let next = engine.nextStep {
                        HStack(spacing: 0) {
                            Text("Next: ")
                                .foregroundStyle(.tertiary)
                            Text(next.interval.name)
                                .foregroundStyle(next.interval.color)
                            Text(" · \(next.interval.durationFormatted)")
                                .foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 17, weight: .regular, design: .monospaced))
                    } else if engine.isRunning {
                        Text("Last interval")
                            .font(.system(size: 17, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    // Repeat progress dots
                    if let step = engine.currentStep, step.interval.repeatCount > 1 {
                        RepeatProgressDots(current: step.repeatIndex, total: step.interval.repeatCount)
                    }

                    // Transport bar
                    TransportBar(engine: engine, accentColor: timerColor.color)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            // Session complete overlay
            if engine.isFinished {
                SessionCompleteOverlay(session: session) {
                    dismiss()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: engine.isFinished)
        .onAppear {
            engine.load(session: session)
            engine.start()
        }
        .alert("Cancel Timer?", isPresented: $showCancelConfirmation) {
            Button("Keep Going", role: .cancel) { }
            Button("End Session", role: .destructive) {
                engine.stop()
                dismiss()
            }
        } message: {
            Text("Your current progress will be lost.")
        }
    }

    private var timerColor: TimerColor { engine.timerColor }
}

// MARK: - Interval Segment Track

struct IntervalSegmentTrack: View {
    @Bindable var engine: PlaybackEngine

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 5) {
                ForEach(Array(engine.steps.enumerated()), id: \.offset) { i, step in
                    let isDone   = i < engine.stepIndex
                    let isActive = i == engine.stepIndex
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(step.interval.color)
                        .opacity(isDone ? 0.5 : isActive ? 1.0 : 0.25)
                        .animation(.easeInOut(duration: 0.3), value: engine.stepIndex)
                }
            }
        }
        .frame(height: 9)
    }
}

// MARK: - Fill countdown view

struct FillCountdownView: View {
    @Bindable var engine: PlaybackEngine
    let accentColor: Color

    var body: some View {
        VStack {
            Spacer()

            // Paused label
            if engine.isPaused {
                Text("PAUSED")
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accentColor.opacity(0.7))
                    .kerning(3)
                    .modifier(PulseOpacity())
                    .transition(.opacity)
                    .padding(.bottom, 12)
            }

            ZStack(alignment: .bottom) {
                // Container
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color("Surface2"))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    }

                // Fill
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.5), accentColor.opacity(0.12)],
                                    startPoint: .bottom, endPoint: .top
                                )
                            )
                            .frame(height: geo.size.height * (engine.countsUp ? engine.progressFraction : 1 - engine.progressFraction))
                            .animation(.linear(duration: 1.0), value: engine.progressFraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))

                // Countdown
                Text(countdownText)
                    .font(.system(size: 72, weight: .light, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .animation(.easeInOut(duration: 0.3), value: accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 210)

            Spacer()
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.3), value: engine.isPaused)
    }

    private var countdownText: String {
        let sec = engine.countsUp ? engine.secondsElapsed : engine.secondsRemaining
        if sec >= 3600 {
            return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
        } else if sec >= 60 {
            return String(format: "%d:%02d", sec / 60, sec % 60)
        } else {
            return String(format: ":%02d", sec)
        }
    }
}

// MARK: - Ring countdown view

struct RingCountdownView: View {
    @Bindable var engine: PlaybackEngine
    let accentColor: Color

    private let ringSize: CGFloat  = 210
    private let strokeWidth: CGFloat = 14

    var body: some View {
        VStack {
            Spacer()

            // Paused label
            if engine.isPaused {
                Text("PAUSED")
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accentColor.opacity(0.7))
                    .kerning(3)
                    .modifier(PulseOpacity())
                    .transition(.opacity)
                    .padding(.bottom, 12)
            }

            ZStack {
                // Track
                Circle()
                    .stroke(Color("Surface2"), lineWidth: strokeWidth)

                // Progress arc
                Circle()
                    .trim(from: 0, to: engine.countsUp ? engine.progressFraction : 1 - engine.progressFraction)
                    .stroke(
                        accentColor,
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: engine.progressFraction)

                // Countdown
                Text(countdownText)
                    .font(.system(size: 54, weight: .light, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .animation(.easeInOut(duration: 0.3), value: accentColor)
            }
            .frame(width: ringSize, height: ringSize)
            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: engine.isPaused)
    }

    private var countdownText: String {
        let sec = engine.countsUp ? engine.secondsElapsed : engine.secondsRemaining
        if sec >= 3600 {
            return String(format: "%d:%02d:%02d", sec / 3600, (sec % 3600) / 60, sec % 60)
        } else if sec >= 60 {
            return String(format: "%d:%02d", sec / 60, sec % 60)
        } else {
            return String(format: ":%02d", sec)
        }
    }
}

// MARK: - Repeat progress dots

struct RepeatProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<min(total, 12), id: \.self) { i in
                Circle()
                    .fill(i <= current ? Color.secondary : Color("Surface2"))
                    .overlay {
                        Circle().stroke(Color.white.opacity(0.07), lineWidth: 1)
                    }
                    .frame(width: 5, height: 5)
            }
            if total > 12 {
                Text("+\(total - 12)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Pulse opacity modifier

struct PulseOpacity: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.25 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Session repeat track

struct SessionRepeatTrack: View {
    @Bindable var engine: PlaybackEngine

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Round \(engine.sessionRepeat + 1) of \(engine.sessionRepeatTotal)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .kerning(1)
                    .textCase(.uppercase)
                Spacer()
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(0..<engine.sessionRepeatTotal, id: \.self) { i in
                        let isDone   = i < engine.sessionRepeat
                        let isActive = i == engine.sessionRepeat
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color("AccentGreen"))
                            .opacity(isDone ? 0.5 : isActive ? 1.0 : 0.2)
                            .animation(.easeInOut(duration: 0.3), value: engine.sessionRepeat)
                    }
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Session complete overlay

struct SessionCompleteOverlay: View {
    let session: TimerSession
    let onDone: () -> Void

    @State private var checkmarkScale: CGFloat = 0.3
    @State private var checkmarkOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Checkmark circle
                ZStack {
                    Circle()
                        .fill(Color("AccentGreen").opacity(0.12))
                        .frame(width: 120, height: 120)

                    Circle()
                        .stroke(Color("AccentGreen").opacity(0.25), lineWidth: 1)
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(Color("AccentGreen"))
                }
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)

                // Title
                Text("Session Complete")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 28)
                    .opacity(contentOpacity)

                // Session name
                Text(session.name)
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .opacity(contentOpacity)

                // Duration summary
                Text(session.totalDurationFormatted)
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .opacity(contentOpacity)

                Spacer()

                // Done button
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color("Background"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color("AccentGreen"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                contentOpacity = 1.0
            }
        }
    }
}
