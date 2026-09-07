import SwiftUI
import UIKit

@main
struct SomaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before the first view: Theme resolves each face by name and falls
        // back to a system font when the name is unknown.
        SomaFonts.registerBundledFaces()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, session.isSignedIn else { return }
            Task { await HealthKitSync.shared.syncIfConnected() }
        }
    }
}

/// Exists for one reason: HealthKit background delivery.
///
/// HealthKit can launch the app straight into the background to hand us new
/// samples, and it expects the observer queries to already be installed when
/// it does. A SwiftUI `.task` hangs off a view that a background launch may
/// never build, so registration has to happen at the UIKit launch point.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        MainActor.assumeIsolated {
            HealthKitSync.shared.startObservingIfConnected()
        }
        return true
    }
}
