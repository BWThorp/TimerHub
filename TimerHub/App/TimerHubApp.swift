import SwiftUI
import SwiftData
import Combine
import UserNotifications

@main
struct TimerHubApp: App {

    let container: ModelContainer

    init() {
        let schema = Schema([TimerSession.self, TimerInterval.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // If the store is corrupt or incompatible, wipe it and start fresh.
            // This is safe during development; add a migration plan before shipping.
            print("ModelContainer init failed: \(error). Wiping store and retrying.")
            do {
                let storeURL = config.url
                let fm = FileManager.default
                let shmURL = storeURL.appendingPathExtension("shm")
                let walURL = storeURL.appendingPathExtension("wal")
                try? fm.removeItem(at: storeURL)
                try? fm.removeItem(at: shmURL)
                try? fm.removeItem(at: walURL)
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Could not create ModelContainer even after wiping store: \(error)")
            }
        }

        // Request notification permission for background timer alerts
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
