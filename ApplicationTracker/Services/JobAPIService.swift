import Foundation
import SwiftData

// MARK: - JobRecord

struct JobRecord: Codable, Identifiable {
    let id: Int
    let url: String
    let title: String?
    let company: String?
    let status: String
    let createdAt: String
}

enum JobAPIError: LocalizedError {
    case invalidResponse
    case serverError(Int, String)
    case missingPresignedURL
    case s3UploadFailed(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code, let msg):
            return "Server error (\(code)): \(msg)"
        case .missingPresignedURL:
            return "No presigned URL from server"
        case .s3UploadFailed(let msg):
            return "S3 upload failed: \(msg)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

actor JobAPIService {
    static let shared = JobAPIService()

    private let baseURL = URL(string: "https://api.applicationtracker.example.com")!
    private let session = URLSession.shared

    // MARK: - Public API

    /// Applies a job: uploads HTML to S3, then posts metadata to Lambda for RDS storage.
    ///
    /// - Parameters:
    ///   - job: The pending job to apply.
    ///   - modelContext: The SwiftData context for persisting status changes.
    ///   - currentUserID: The authenticated user's UID, used to locate disk-cached HTML.
    func applyJob(_ job: PendingJob, modelContext: ModelContext, currentUserID: String?) async throws {
        do {
            // Step 1: Get presigned S3 upload URL
            let presignResp = try await getPresignedURL()

            // Step 2: Resolve HTML — use disk cache if available, otherwise fetch live.
            // Read job properties on MainActor since PendingJob is a SwiftData @Model.
            let (jobURL, cachedPath) = await MainActor.run {
                (job.url, job.cachedHTMLPath)
            }

            // Attempt to read from disk cache; fall back to live fetch on any failure.
            let html: String = try await resolveHTML(jobURL: jobURL, cachedPath: cachedPath)

            // Step 3: Upload HTML to S3 via presigned URL
            // NOTE: S3 upload retry logic is not yet implemented. See CLAUDE.md TODO.
            try await uploadHTMLToS3(html: html, presignedURL: presignResp.uploadURL)

            // Step 4: Call Lambda to extract metadata and save to RDS
            try await postJobToRDS(url: jobURL, s3Key: presignResp.s3Key)

            // Step 5: On success, clear the disk cache and update job status.
            await MainActor.run {
                if let cachePath = job.cachedHTMLPath {
                    try? FileManager.default.removeItem(atPath: cachePath)
                }
                job.cachedHTMLPath = nil
                job.status = .applied
            }
        } catch {
            // Revert status on failure
            await MainActor.run {
                job.status = .pending
            }
            throw error
        }
    }

    // MARK: - GET /jobs

    /// Fetches all applied job records from the Lambda backend.
    func getJobs() async throws -> [JobRecord] {
        let token = try await AuthService.shared.getValidToken()

        var request = URLRequest(url: baseURL.appendingPathComponent("jobs"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JobAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JobAPIError.serverError(httpResponse.statusCode, errorMsg)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([JobRecord].self, from: data)
    }

    // MARK: - GET /jobs/today-count

    /// Fetches the number of jobs applied today for the authenticated user.
    func getTodayCount() async throws -> Int {
        let token = try await AuthService.shared.getValidToken()

        var request = URLRequest(url: baseURL.appendingPathComponent("jobs/today-count"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JobAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JobAPIError.serverError(httpResponse.statusCode, errorMsg)
        }

        let decoded = try JSONDecoder().decode(TodayCountResponse.self, from: data)
        return decoded.count
    }

    private struct TodayCountResponse: Decodable {
        let count: Int
    }

    // MARK: - HTML Resolution

    /// Returns HTML for the given job URL. If a valid cache file exists at `cachedPath`,
    /// reads from disk; otherwise fetches live via WKWebView.
    private func resolveHTML(jobURL: String, cachedPath: String?) async throws -> String {
        if let cachePath = cachedPath,
           FileManager.default.fileExists(atPath: cachePath),
           let data = FileManager.default.contents(atPath: cachePath),
           let html = String(data: data, encoding: .utf8) {
            return html
        }
        return try await WebViewFetcher.shared.fetchHTML(from: jobURL)
    }

    // MARK: - Step 1: Get Presigned URL

    private func getPresignedURL() async throws -> (uploadURL: String, s3Key: String) {
        let token = try await AuthService.shared.getValidToken()

        var request = URLRequest(url: baseURL.appendingPathComponent("presign"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JobAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JobAPIError.serverError(httpResponse.statusCode, errorMsg)
        }

        let decoder = JSONDecoder()
        let resp = try decoder.decode(PresignResponse.self, from: data)

        guard !resp.uploadURL.isEmpty, !resp.s3Key.isEmpty else {
            throw JobAPIError.missingPresignedURL
        }

        return (uploadURL: resp.uploadURL, s3Key: resp.s3Key)
    }

    private struct PresignResponse: Decodable {
        let uploadURL: String
        let s3Key: String

        enum CodingKeys: String, CodingKey {
            case uploadURL = "uploadURL"
            case s3Key = "s3Key"
        }
    }

    // MARK: - Step 3: Upload to S3

    private func uploadHTMLToS3(html: String, presignedURL: String) async throws {
        guard let url = URL(string: presignedURL) else {
            throw JobAPIError.s3UploadFailed("Invalid presigned URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("text/html; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = html.data(using: .utf8)
        request.timeoutInterval = 30

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JobAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw JobAPIError.s3UploadFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - Step 4: Post to Lambda for extraction

    private func postJobToRDS(url: String, s3Key: String) async throws {
        let token = try await AuthService.shared.getValidToken()

        var request = URLRequest(url: baseURL.appendingPathComponent("jobs"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body = PostJobRequest(url: url, s3Key: s3Key)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JobAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 201 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw JobAPIError.serverError(httpResponse.statusCode, errorMsg)
        }
    }

    private struct PostJobRequest: Encodable {
        let url: String
        let s3Key: String
    }
}
