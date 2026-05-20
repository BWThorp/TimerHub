import SwiftUI
import Combine

struct TimerCompletionBanner: View {
    let timerName: String
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Bell icon
                ZStack {
                    Circle()
                        .fill(Color("AccentGreen").opacity(0.12))
                    Image(systemName: "bell.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color("AccentGreen"))
                }
                .frame(width: 30, height: 30)

                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(timerName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("AccentGreen"))
                    Text("Timer complete")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Dismiss
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color("Surface"))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color("AccentGreen").opacity(0.2), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}
