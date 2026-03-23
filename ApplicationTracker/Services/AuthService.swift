import Foundation
import FirebaseAuth
import GoogleSignIn

/// Manages Google Sign-In and Firebase authentication for the app.
///
/// Google Sign-In on macOS works as follows:
/// 1. `GIDSignIn.sharedInstance.signIn(withPresenting:)` opens a local HTTP
///    loopback server and launches the system browser to complete the OAuth flow.
/// 2. After the user grants access, Google redirects back to the app via the
///    REVERSED_CLIENT_ID URL scheme registered in Info.plist.
/// 3. The app delegate (ApplicationTrackerApp) must forward that URL to
///    `GIDSignIn.sharedInstance.handle(_:)`.
/// 4. The resulting GIDGoogleUser credential is exchanged for a Firebase
///    credential, which is used to sign in to Firebase Auth.
///
/// Keychain note: Firebase Auth stores tokens in the keychain. On macOS the
/// sandbox requires `com.apple.security.keychain-access-groups` in the
/// entitlements. The current entitlements use the correct sandbox keychain
/// entitlement key (`com.apple.security.keychain`), but the access group
/// must include the app's bundle-ID-based group so that FirebaseAuth can
/// write to a shared keychain group. See ApplicationTracker.entitlements.
actor AuthService {
    static let shared = AuthService()

    private var cachedToken: String?
    private var tokenExpiry: Date?

    // MARK: - Google Sign-In

    /// Initiates the full Google Sign-In → Firebase Auth flow.
    ///
    /// - Parameter presentingWindow: The `NSWindow` from which the browser
    ///   sheet or popover originates. Required by `GIDSignIn` on macOS.
    func signInWithGoogle(presentingWindow: NSWindow) async throws {
        // Restore a previous sign-in session silently before launching the
        // browser, so we don't force the user through the consent screen again.
        if let restoredUser = try? await restorePreviousSignIn() {
            try await exchangeGoogleUserForFirebaseToken(restoredUser)
            return
        }

        // Full interactive sign-in.
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            DispatchQueue.main.async {
                GIDSignIn.sharedInstance.signIn(withPresenting: presentingWindow) { signInResult, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let signInResult {
                        continuation.resume(returning: signInResult)
                    } else {
                        continuation.resume(throwing: AuthError.signInFailed("No result returned from Google Sign-In"))
                    }
                }
            }
        }

        try await exchangeGoogleUserForFirebaseToken(result.user)
    }

    /// Exchanges a `GIDGoogleUser` for a Firebase Auth credential and signs in.
    private func exchangeGoogleUserForFirebaseToken(_ googleUser: GIDGoogleUser) async throws {
        guard let idToken = googleUser.idToken?.tokenString else {
            throw AuthError.signInFailed("Google ID token was nil after sign-in")
        }

        let accessToken = googleUser.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )

        let authResult = try await Auth.auth().signIn(with: credential)

        let token = try await authResult.user.getIDToken(forcingRefresh: false)
        self.cachedToken = token
        self.tokenExpiry = Date().addingTimeInterval(3600)
    }

    // MARK: - Silent Restore

    /// Attempts to restore the previous Google Sign-In session without showing UI.
    private func restorePreviousSignIn() async throws -> GIDGoogleUser? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                    if let error {
                        // restorePreviousSignIn throws when there is no saved
                        // session – treat that as a non-fatal nil return.
                        let nsError = error as NSError
                        let noSession = (nsError.domain == "com.google.GIDSignIn" && nsError.code == -4)
                        if noSession {
                            continuation.resume(returning: nil)
                        } else {
                            continuation.resume(throwing: error)
                        }
                    } else {
                        continuation.resume(returning: user)
                    }
                }
            }
        }
    }

    // MARK: - Token Management

    /// Returns a valid Firebase ID token, refreshing or signing in as needed.
    ///
    /// Callers that need a presenting window for a fresh sign-in should use
    /// `signInWithGoogle(presentingWindow:)` directly instead.
    func getValidToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }

        if let user = Auth.auth().currentUser {
            let token = try await user.getIDToken(forcingRefresh: true)
            self.cachedToken = token
            self.tokenExpiry = Date().addingTimeInterval(3600)
            return token
        }

        throw AuthError.noToken
    }

    func getCurrentUser() -> FirebaseAuth.User? {
        Auth.auth().currentUser
    }

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
        cachedToken = nil
        tokenExpiry = nil
    }

    func isUserLoggedIn() -> Bool {
        Auth.auth().currentUser != nil
    }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case signInFailed(String)
    case noToken
    case signOutFailed(String)
    case noPresentingWindow

    var errorDescription: String? {
        switch self {
        case .signInFailed(let message):
            return "Sign in failed: \(message)"
        case .noToken:
            return "No authenticated session. Please sign in."
        case .signOutFailed(let message):
            return "Sign out failed: \(message)"
        case .noPresentingWindow:
            return "Cannot present sign-in: no application window available."
        }
    }
}
