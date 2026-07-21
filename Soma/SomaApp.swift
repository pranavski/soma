import SwiftUI

@main
struct SomaApp: App {
    @StateObject private var session = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.isSignedIn else { return }
            Task { await HealthKitForegroundSync.shared.syncIfConnected() }
        }
    }
}
