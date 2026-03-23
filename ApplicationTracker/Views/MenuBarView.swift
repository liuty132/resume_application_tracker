import SwiftUI
import SwiftData
import AppKit
import FirebaseAuth

struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(\.modelContext) var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PendingJob.addedAt, order: .reverse)
    var allJobs: [PendingJob]

    var pendingJobs: [PendingJob] {
        allJobs.filter { $0.status == .pending || $0.status == .applying }
    }

    var body: some View {
        if !appState.isLoggedIn {
            loginView
                .onAppear {
                    // Auto-login if user has a saved session, and populate UID.
                    if AuthService.shared.isUserLoggedIn() {
                        appState.isLoggedIn = true
                        Task {
                            let uid = await AuthService.shared.getCurrentUser()?.uid
                            await MainActor.run { appState.currentUserID = uid }
                        }
                    }
                }
        } else {
            mainView
        }
    }

    // MARK: - Login

    private var loginView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()

                Button(action: login) {
                    if appState.isLoading {
                        VStack(spacing: 4) {
                            ProgressView().scaleEffect(0.8).frame(width: 16, height: 16)
                            Text("Signing In…").font(.caption2)
                        }
                        .frame(width: 72)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "person.circle.fill").font(.system(size: 16))
                            Text("Login").font(.caption2)
                        }
                        .frame(width: 72)
                    }
                }
                .buttonStyle(ShadeStyle())
                .disabled(appState.isLoading)

                Button(action: quit) {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark").font(.system(size: 16))
                        Text("Quit").font(.caption2)
                    }
                    .frame(width: 72)
                }
                .buttonStyle(ShadeStyle())

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let error = appState.errorMessage {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .background(WindowAccessor { window in
            appState.presentingWindow = window
        })
    }

    // MARK: - Main (authenticated)

    private var mainView: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider()

            // URL input
            URLInputView()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            // Pending jobs list or empty state
            if pendingJobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(pendingJobs) { job in
                            PendingJobRow(job: job)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 300)
                .scrollBounceBehavior(.always)
            }
        }
        .environment(\.modelContext, modelContext)
        .task {
            await refreshTodayCount()
        }
    }

    // MARK: - Today Count

    private func refreshTodayCount() async {
        do {
            appState.todayCount = try await JobAPIService.shared.getTodayCount()
        } catch {
            // Silently ignore — counter stays at last known value
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 0) {
            // Left half — today's count (opens dashboard)
            Button { dismiss(); openWindow(id: "dashboard") } label: {
                VStack(spacing: 4) {
                    Text("\(appState.todayCount)")
                        .font(.system(size: 16, weight: .semibold))
                    Text("submitted today")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ShadeStyle())
            .frame(maxWidth: .infinity)

            // Right half — actions
            HStack(spacing: 8) {
                Button(action: logout) {
                    VStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 16))
                        Text("Logout")
                            .font(.caption2)
                    }
                    .frame(width: 72)
                }
                .buttonStyle(ShadeStyle())

                Button(action: quit) {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                        Text("Quit")
                            .font(.caption2)
                    }
                    .frame(width: 72)
                }
                .buttonStyle(ShadeStyle())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No pending jobs")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Paste a URL above to get started.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Actions

    private func login() {
        guard let window = appState.presentingWindow else {
            appState.errorMessage = "Cannot present sign-in: no window found. Please try again."
            return
        }

        Task {
            await MainActor.run {
                appState.isLoading = true
                appState.errorMessage = nil
            }

            do {
                try await AuthService.shared.signInWithGoogle(presentingWindow: window)
                let uid = await AuthService.shared.getCurrentUser()?.uid
                await MainActor.run {
                    appState.isLoading = false
                    appState.isLoggedIn = true
                    appState.currentUserID = uid
                    appState.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    appState.isLoading = false
                    appState.errorMessage = friendlyError(for: error)
                }
            }
        }
    }

    private func logout() {
        Task {
            do {
                try AuthService.shared.signOut()
                await MainActor.run {
                    appState.isLoggedIn = false
                    appState.currentUserID = nil
                    appState.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    appState.errorMessage = "Failed to sign out: \(error.localizedDescription)"
                }
            }
        }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Maps known error codes to user-friendly messages.
    private func friendlyError(for error: Error) -> String {
        let nsError = error as NSError

        // GIDSignIn error domain
        if nsError.domain == "com.google.GIDSignIn" {
            switch nsError.code {
            case -5: return "Sign-in was cancelled."
            case -4: return "No previous sign-in session found."
            default: break
            }
        }

        // Firebase Auth errors (AuthErrorCode)
        if nsError.domain == "FIRAuthErrorDomain" {
            switch nsError.code {
            case 17020: return "Network error. Check your internet connection and try again."
            case 17999: return "An internal authentication error occurred. Please try again."
            default: break
            }
        }

        // Keychain errors
        if nsError.domain == NSOSStatusErrorDomain {
            return "Keychain access error (\(nsError.code)). Check your app's keychain entitlements."
        }

        return error.localizedDescription
    }
}

// MARK: - WindowAccessor

/// An invisible `NSViewRepresentable` that retrieves the hosting `NSWindow`
/// and forwards it to a callback. Required because `MenuBarExtra` windows are
/// not directly accessible via the SwiftUI environment on macOS 13+.
private struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Schedule on the next run-loop tick so the window hierarchy is set up.
        DispatchQueue.main.async {
            self.callback(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.callback(nsView.window)
        }
    }
}


// MARK: - ShadeStyle Button Style

private struct ShadeStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        configuration.isPressed
                            ? Color(.controlBackgroundColor).opacity(0.9)
                            : isHovered
                                ? Color(.controlBackgroundColor).opacity(0.8)
                                : Color(.controlBackgroundColor).opacity(0.5)
                    )
            )
            .onContinuousHover { phase in
                switch phase {
                case .active: isHovered = true
                case .ended:  isHovered = false
                }
            }
    }
}

#Preview {
    MenuBarView()
        .environment(AppState())
        .modelContainer(for: PendingJob.self, inMemory: true)
}
