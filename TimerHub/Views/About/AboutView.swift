import SwiftUI
import Combine

struct AboutView: View {
    private let appVersion  = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {

                    // App identity
                    VStack(spacing: 10) {
                        if let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                           let primaryIcons = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
                           let iconFiles = primaryIcons["CFBundleIconFiles"] as? [String],
                           let iconName = iconFiles.last,
                           let uiImage = UIImage(named: iconName) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 22))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                }
                        }

                        Text("Timer Hub")
                            .font(.system(size: 28, weight: .semibold))

                        Text("Version \(appVersion) · Build \(buildNumber)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 16)

                    // Links
                    VStack(spacing: 0) {
                        aboutRow(
                            icon: "star.fill",
                            iconColor: .yellow,
                            label: "Rate Timer Hub"
                        ) {
                            // Replace YOUR_APP_ID with the App Store ID once live
                            if let url = URL(string: "https://apps.apple.com/app/idYOUR_APP_ID?action=write-review") {
                                UIApplication.shared.open(url)
                            }
                        }

                        Divider()
                            .padding(.leading, 56)

                        aboutRow(
                            icon: "lock.shield.fill",
                            iconColor: .blue,
                            label: "Privacy Policy"
                        ) {
                            if let url = URL(string: "https://bwthorp.github.io/timerhub/privacy") {
                                UIApplication.shared.open(url)
                            }
                        }

                        Divider()
                            .padding(.leading, 56)

                        aboutRow(
                            icon: "lifepreserver.fill",
                            iconColor: Color("AccentGreen"),
                            label: "Support"
                        ) {
                            if let url = URL(string: "https://bwthorp.github.io/timerhub/support") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    .background(Color("Surface"))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    }
                    .padding(.horizontal, 16)

                    // Credit
                    Text("Made with ♥ by Brigg Thorp")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Row builder

    private func aboutRow(
        icon: String,
        iconColor: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundStyle(iconColor)
                    }

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}
