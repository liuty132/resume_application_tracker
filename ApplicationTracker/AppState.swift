import Foundation
import SwiftUI
import AppKit
import Observation

@Observable
final class AppState {
    var urlInput: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var isLoggedIn: Bool = false
    var todayCount: Int = 0

    /// The NSWindow used to present the Google Sign-In browser sheet.
    /// MenuBarView sets this before triggering sign-in.
    var presentingWindow: NSWindow? = nil

    /// The Firebase UID of the currently authenticated user.
    /// Set after login succeeds; cleared on logout.
    var currentUserID: String? = nil

    nonisolated init() {}
}
