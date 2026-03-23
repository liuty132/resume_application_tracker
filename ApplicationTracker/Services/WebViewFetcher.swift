import Foundation
import WebKit

enum FetchError: LocalizedError {
    case invalidURL
    case noHTML
    case fetchTimeout
    case navigationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noHTML:
            return "No HTML content retrieved"
        case .fetchTimeout:
            return "Fetch timed out after 20 seconds"
        case .navigationFailed(let msg):
            return "Navigation failed: \(msg)"
        }
    }
}

@MainActor
final class WebViewFetcher: NSObject, WKNavigationDelegate {
    static let shared = WebViewFetcher()

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent cookies
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        return wv
    }()

    private var continuation: CheckedContinuation<String, Error>?
    private var navigationTimer: Timer?

    override init() {
        super.init()
    }

    // MARK: - Disk Cache Helpers

    /// Returns the expected on-disk cache URL for a given job and user.
    static func cachedHTMLPath(jobID: UUID, userID: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches
            .appendingPathComponent("com.example.ApplicationTracker", isDirectory: true)
            .appendingPathComponent(userID, isDirectory: true)
        return dir.appendingPathComponent("\(jobID.uuidString).html")
    }

    /// Fetches the HTML for `url`, writes it to disk under the caches directory,
    /// and returns the on-disk file path string.
    ///
    /// Path: `<cachesDir>/com.example.ApplicationTracker/<userID>/<jobID>.html`
    func fetchAndCacheHTML(url: String, jobID: UUID, userID: String) async throws -> String {
        let html = try await fetchHTML(from: url)

        let destination = WebViewFetcher.cachedHTMLPath(jobID: jobID, userID: userID)
        let dir = destination.deletingLastPathComponent()

        // Create intermediate directories if needed.
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let data = html.data(using: .utf8) else {
            throw FetchError.noHTML
        }
        try data.write(to: destination, options: .atomic)
        return destination.path
    }

    func fetchHTML(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw FetchError.invalidURL
        }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: FetchError.navigationFailed("WebViewFetcher deallocated"))
                return
            }

            self.continuation = continuation

            // Set a timeout
            self.navigationTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in
                if self.continuation != nil {
                    self.continuation?.resume(throwing: FetchError.fetchTimeout)
                    self.continuation = nil
                }
                self.navigationTimer = nil
            }

            let request = URLRequest(url: url, timeoutInterval: 20)
            self.webView.load(request)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationTimer?.invalidate()
        navigationTimer = nil

        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            if let html = result as? String {
                self?.continuation?.resume(returning: html)
            } else {
                self?.continuation?.resume(throwing: error ?? FetchError.noHTML)
            }
            self?.continuation = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationTimer?.invalidate()
        navigationTimer = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationTimer?.invalidate()
        navigationTimer = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
