import SwiftUI
import SwiftData

struct PendingJobRow: View {
    @Bindable var job: PendingJob
    @Environment(\.modelContext) var modelContext
    @Environment(AppState.self) var appState
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Status indicator dot
            statusDot

            // Job info
            VStack(alignment: .leading, spacing: 2) {
                Text(hostName)
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
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .help("Apply for this job")

                    Button(action: disregardJob) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Disregard this job")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered
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

    // MARK: - Subviews

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .strokeBorder(statusColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 14, height: 14)
            )
    }

    // MARK: - Helpers

    private var hostName: String {
        if let url = URL(string: job.url), let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return "Job"
    }

    private var statusColor: Color {
        switch job.status {
        case .pending:  return .orange
        case .applying: return .blue
        case .applied:  return .green
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
    @Previewable @State var job = PendingJob(url: "https://jobs.greenhouse.io/example/engineer")
    return PendingJobRow(job: job)
        .modelContainer(for: PendingJob.self, inMemory: true)
        .padding()
        .frame(width: 380)
}
