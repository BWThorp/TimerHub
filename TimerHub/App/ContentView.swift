import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @State private var selectedTab: Int = 0
    private var timerManager = TimerManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selectedTab) {
                TimersView()
                    .tabItem {
                        Label("Timers", systemImage: "clock")
                    }
                    .tag(0)

                SessionsView()
                    .tabItem {
                        Label("Interval", systemImage: "repeat")
                    }
                    .tag(1)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(2)
            }
            .tint(Color("AccentGreen"))

            // Completion banner — shown on non-Timers tabs
            if timerManager.showCompletionBanner,
               selectedTab != 0,
               let name = timerManager.completedTimerName {
                VStack {
                    TimerCompletionBanner(
                        timerName: name,
                        onTap: {
                            timerManager.dismissBanner()
                            withAnimation {
                                selectedTab = 0
                            }
                        },
                        onDismiss: {
                            timerManager.dismissBanner()
                        }
                    )
                    .padding(.top, 4)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: timerManager.showCompletionBanner)
                .zIndex(100)
            }
        }
    }
}
