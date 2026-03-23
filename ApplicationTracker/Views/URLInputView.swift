import SwiftUI
import SwiftData

struct URLInputView: View {
    @Environment(AppState.self) var appState
    @Environment(\.modelContext) var modelContext
    @State private var urlError: String?
    @State private var company: String = ""
    @State private var jobTitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Paste job URL…", text: Binding(
                get: { appState.urlInput },
                set: {
                    appState.urlInput = $0
                    urlError = nil
                }
            ))
            .textFieldStyle(.roundedBorder)
            .onSubmit(addJob)
            .font(.body)
            .controlSize(.large)

            HStack(spacing: 8) {
                TextField("Company", text: $company)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(addJob)
                TextField("Job title", text: $jobTitle)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit(addJob)
            }

            if let error = urlError {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
                .background(Color(.systemRed).opacity(0.1))
                .cornerRadius(4)
            }
        }
    }

    private func addJob() {
//        print("userID at submit time: \(String(describing: appState.currentUserID))")
        let trimmed = appState.urlInput.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            urlError = "Please enter a URL"
            return
        }

        // Try to parse as-is first, then with https:// if needed
        let urlString: String
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            // Valid URL with scheme
            urlString = trimmed
        } else if trimmed.contains(".") {
            // Likely a domain name without scheme, add https://
            if let url = URL(string: "https://\(trimmed)"), url.host != nil {
                urlString = "https://\(trimmed)"
            } else {
                urlError = "Please enter a valid domain (e.g., example.com)"
                return
            }
        } else {
            urlError = "Please enter a valid URL (e.g., example.com)"
            return
        }

        guard let userID = appState.currentUserID else {
            urlError = "Not logged in"
            return
        }

        let job = PendingJob(url: urlString, userID: userID)
        modelContext.insert(job)
        job.company = company.isEmpty ? nil : company
        job.jobTitle = jobTitle.isEmpty ? nil : jobTitle
        appState.urlInput = ""
        company = ""
        jobTitle = ""
        urlError = nil

        do {
            try modelContext.save()

            // Kick off background HTML pre-fetch.
            // The result is written back to job.cachedHTMLPath so applyJob() can
            // skip a live fetch later. We use a detached Task to avoid blocking
            // the UI and to escape the MainActor context for the actor hop.

            let jobID = job.id
            let jobURL = job.url
            Task.detached(priority: .background) {
                do {
                    let path = try await WebViewFetcher.shared.fetchAndCacheHTML(
                        url: jobURL,
                        jobID: jobID,
                        userID: userID
                    )
                    // Write the cached path back on MainActor so SwiftData is
                    // accessed on the correct thread.
                    await MainActor.run {
                        job.cachedHTMLPath = path
                        try? modelContext.save()
                    }
                } catch {
                    print("[URLInputView] Pre-fetch failed: \(error)")
                    // Pre-fetch failed; applyJob() will fall back to a live fetch.
                }
            }
        } catch {
            urlError = "Failed to save job"
        }
    }
}

#Preview {
    URLInputView()
        .environment(AppState())
        .modelContainer(for: PendingJob.self, inMemory: true)
}
