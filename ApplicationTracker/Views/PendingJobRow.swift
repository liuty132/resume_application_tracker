import SwiftUI
import SwiftData

struct PendingJobRow: View {
    @Bindable var job: PendingJob
    @Environment(\.modelContext) var modelContext
    @Environment(AppState.self) var appState
    @State private var isHovered = false
    @State private var isApplyHovered = false
    @State private var isDisregardHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Job info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(job.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action area
            if job.status == .applying {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .controlSize(.mini)
                    Text("Applying…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 90)
            } else {
                HStack(spacing: 6) {
                    Button(action: applyJob) {
                        Label("Apply", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(isApplyHovered ? 0.1 : 0)))
                    .onContinuousHover { phase in
                        if case .active = phase { isApplyHovered = true } else { isApplyHovered = false }
                    }
                    .help("Apply for this job")

                    Button(action: disregardJob) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(isDisregardHovered ? 0.1 : 0)))
                    .onContinuousHover { phase in
                        if case .active = phase { isDisregardHovered = true } else { isDisregardHovered = false }
                    }
                    .help("Disregard this job")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(isHovered ? 0.07 : 0))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active: isHovered = true
            case .ended:  isHovered = false
            }
        }
    }

    // MARK: - Helpers

    private var displayTitle: String {
        let company = job.company
        let title = job.jobTitle
        switch (company, title) {
        case let (c?, t?): return "\(c) — \(t)"
        case let (c?, nil): return c
        case let (nil, t?): return t
        default:
            if let url = URL(string: job.url), let host = url.host {
                return host.replacingOccurrences(of: "www.", with: "")
            }
            return "Job"
        }
    }

    // MARK: - Actions

    private func disregardJob() {
        modelContext.delete(job)
        try? modelContext.save()
    }

    private func applyJob() {
        job.status = .applying
        try? modelContext.save()

        let userID = appState.currentUserID
        Task {
            do {
                try await JobAPIService.shared.applyJob(
                    job,
                    modelContext: modelContext,
                    currentUserID: userID
                )
                await MainActor.run {
                    job.status = .applied
                    try? modelContext.save()
                    appState.todayCount += 1
                }
            } catch {
                await MainActor.run {
                    job.status = .pending
                    try? modelContext.save()
                }
            }
        }
    }

}

#Preview {
    @Previewable @State var job = PendingJob(url: "https://jobs.greenhouse.io/example/engineer", userID: "preview-user")
    PendingJobRow(job: job)
        .modelContainer(for: PendingJob.self, inMemory: true)
        .padding()
        .frame(width: 380)
}
