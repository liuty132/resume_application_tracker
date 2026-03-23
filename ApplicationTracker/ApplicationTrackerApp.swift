import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn

@main
struct ApplicationTrackerApp: App {
    @State private var appState = AppState()

    let modelContainer: ModelContainer

    init() {
        FirebaseApp.configure()

        // Configure GoogleSignIn with the client ID from GoogleService-Info.plist.
        // This must happen after FirebaseApp.configure() so FirebaseApp has
        // already parsed the plist and populated FirebaseOptions.
        if let clientID = FirebaseApp.app()?.options.clientID {
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
        }

        do {
            modelContainer = try ModelContainer(for: PendingJob.self)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra("Job Application Tracker", systemImage: "briefcase.fill") {
            MenuBarView()
                .environment(appState)
                .frame(minWidth: 380)
                .modelContainer(modelContainer)
                // Forward OAuth redirect URLs to GIDSignIn.
                // The system delivers the REVERSED_CLIENT_ID scheme URL here
                // after the user completes the Google consent screen in Safari.
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .menuBarExtraStyle(.window)

        Window("Job Dashboard", id: "dashboard") {
            DashboardView(appState: appState)
                .modelContainer(modelContainer)
                .environment(appState)
        }
    }

    // MARK: - URL Handling

    /// Forwards OAuth redirect URLs to GoogleSignIn.
    ///
    /// On macOS, GIDSignIn uses a loopback server for OAuth so URLs arrive
    /// via the local HTTP server rather than URL schemes in most cases.
    /// However `handle(_:)` must be called for any scheme-based redirects.
    private func handleIncomingURL(_ url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }
}
