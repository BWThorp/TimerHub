import SwiftUI
import Combine

// MARK: - Custom SVG transport icons

struct PlayIcon: View {
    var size: CGFloat = 20
    var color: Color  = .primary

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            // Triangle offset slightly right for optical centering
            var path = Path()
            path.move(to:    CGPoint(x: w * 0.33, y: h * 0.14))
            path.addLine(to: CGPoint(x: w * 0.33, y: h * 0.86))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.50))
            path.closeSubpath()
            ctx.fill(path, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

struct PauseIcon: View {
    var size: CGFloat = 20
    var color: Color  = .primary

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let barW  = w * 0.22
            let barH  = h * 0.72
            let top   = (h - barH) / 2
            let r     = barW / 2

            // Left bar
            let left = Path(roundedRect: CGRect(x: w * 0.18, y: top, width: barW, height: barH),
                            cornerRadius: r)
            // Right bar
            let right = Path(roundedRect: CGRect(x: w * 0.60, y: top, width: barW, height: barH),
                             cornerRadius: r)
            ctx.fill(left,  with: .color(color))
            ctx.fill(right, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

struct PrevIcon: View {
    var size: CGFloat = 18
    var color: Color  = .primary

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let barW: CGFloat = w * 0.13
            let r = barW / 2

            // Vertical bar on left
            let bar = Path(roundedRect: CGRect(x: w * 0.10, y: h * 0.14, width: barW, height: h * 0.72),
                           cornerRadius: r)
            ctx.fill(bar, with: .color(color))

            // Chevron pointing left
            var chev = Path()
            chev.move(to:    CGPoint(x: w * 0.90, y: h * 0.16))
            chev.addLine(to: CGPoint(x: w * 0.32, y: h * 0.50))
            chev.addLine(to: CGPoint(x: w * 0.90, y: h * 0.84))
            ctx.stroke(chev, with: .color(color),
                       style: StrokeStyle(lineWidth: barW * 1.1, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

struct NextIcon: View {
    var size: CGFloat = 18
    var color: Color  = .primary

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let barW: CGFloat = w * 0.13
            let r = barW / 2

            // Vertical bar on right
            let bar = Path(roundedRect: CGRect(x: w * 0.77, y: h * 0.14, width: barW, height: h * 0.72),
                           cornerRadius: r)
            ctx.fill(bar, with: .color(color))

            // Chevron pointing right
            var chev = Path()
            chev.move(to:    CGPoint(x: w * 0.10, y: h * 0.16))
            chev.addLine(to: CGPoint(x: w * 0.68, y: h * 0.50))
            chev.addLine(to: CGPoint(x: w * 0.10, y: h * 0.84))
            ctx.stroke(chev, with: .color(color),
                       style: StrokeStyle(lineWidth: barW * 1.1, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Transport button shells

struct LargeTransportButton<Icon: View>: View {
    let action: () -> Void
    let accentColor: Color
    let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(width: 72, height: 72)
                .overlay {
                    Circle()
                        .stroke(accentColor.opacity(0.25), lineWidth: 1)
                }
                .overlay {
                    icon()
                }
        }
        .buttonStyle(TransportButtonStyle())
    }
}

struct SmallTransportButton<Icon: View>: View {
    let action: () -> Void
    let disabled: Bool
    let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color("Surface2"))
                .frame(width: 52, height: 52)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                .overlay {
                    icon()
                }
        }
        .buttonStyle(TransportButtonStyle())
        .opacity(disabled ? 0.3 : 1.0)
        .disabled(disabled)
    }
}

struct TransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Full transport bar

struct TransportBar: View {
    @Bindable var engine: PlaybackEngine
    let accentColor: Color

    var body: some View {
        HStack(spacing: 28) {
            // Play / Pause
            VStack(spacing: 7) {
                LargeTransportButton(action: togglePlayPause, accentColor: accentColor) {
                    AnyView(
                        engine.isPaused || !engine.isRunning
                            ? AnyView(PlayIcon(size: 26, color: accentColor))
                            : AnyView(PauseIcon(size: 26, color: accentColor))
                    )
                }
                controlLabel(engine.isPaused || !engine.isRunning ? "Play" : "Pause")
            }

            // Next
            VStack(spacing: 7) {
                SmallTransportButton(action: { engine.skipForward() },
                                     disabled: engine.isOnLastStep) {
                    NextIcon(size: 20, color: .primary)
                }
                controlLabel("Next")
            }
        }
    }

    private func togglePlayPause() {
        if !engine.isRunning {
            engine.start()
        } else if engine.isPaused {
            engine.resume()
        } else {
            engine.pause()
        }
    }

    private func controlLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .kerning(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
    }
}
