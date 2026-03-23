import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PendingJob.addedAt, order: .reverse) private var pendingJobs: [PendingJob]
    @State var appState: AppState

    // MARK: - Filter

    enum FilterSelection: String, CaseIterable, Identifiable {
        case all     = "All"
        case pending = "Pending"
        case applied = "Applied"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all:     return "list.bullet"
            case .pending: return "clock"
            case .applied: return "checkmark.circle"
            }
        }

        var accentColor: Color {
            switch self {
            case .all:     return .primary
            case .pending: return .orange
            case .applied: return .green
            }
        }
    }

    @State private var selectedFilter: FilterSelection = .all
    @State private var appliedJobs: [JobRecord] = []
    @State private var isLoadingJobs = false
    @State private var jobsError: String? = nil

    // MARK: - Computed counts

    private var pendingCount: Int {
        pendingJobs.filter { $0.status == .pending || $0.status == .applying }.count
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            detailView
                .navigationTitle(selectedFilter.rawValue)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await loadAppliedJobs() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh applied jobs")
                        .disabled(isLoadingJobs)
                    }
                }
        }
        .task {
            await loadAppliedJobs()
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await loadAppliedJobs() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(FilterSelection.allCases, selection: $selectedFilter) { filter in
            Label {
                HStack {
                    Text(filter.rawValue)
                    Spacer()
                    filterCountBadge(for: filter)
                }
            } icon: {
                Image(systemName: filter.icon)
                    .foregroundStyle(filter.accentColor)
            }
            .tag(filter)
            .padding(.vertical, 2)
        }
        .listStyle(.sidebar)
        .navigationTitle("Job Tracker")
    }

    /// Count badge shown next to each sidebar filter label.
    @ViewBuilder
    private func filterCountBadge(for filter: FilterSelection) -> some View {
        let count = badgeCount(for: filter)
        if count > 0 {
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(filter.accentColor, in: Capsule())
        }
    }

    private func badgeCount(for filter: FilterSelection) -> Int {
        switch filter {
        case .all:     return pendingCount + appliedJobs.count
        case .pending: return pendingCount
        case .applied: return appliedJobs.count
        }
    }

    // MARK: - Detail View

    private var detailView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Pending section
                if selectedFilter == .all || selectedFilter == .pending {
                    sectionHeader("Pending", count: pendingCount, color: .orange)
                    pendingSection
                        .padding(.bottom, 16)
                }

                // Applied section
                if selectedFilter == .all || selectedFilter == .applied {
                    sectionHeader("Applied", count: appliedJobs.count, color: .green)
                    appliedSection
                        .padding(.bottom, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 8)
    }

    // MARK: - Pending Section

    private var pendingSection: some View {
        let visible = pendingJobs.filter { $0.status == .pending || $0.status == .applying }

        return Group {
            if visible.isEmpty {
                emptyStateRow(
                    icon: "tray",
                    message: "No pending jobs",
                    caption: "Paste a URL in the menu bar to add a job."
                )
            } else {
                VStack(spacing: 1) {
                    ForEach(visible) { job in
                        pendingJobRow(job)
                        if job.id != visible.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func pendingJobRow(_ job: PendingJob) -> some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(job.status == .applying ? Color.blue : Color.orange)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                // Show company+title extracted from URL hostname as a best-effort placeholder
                Text(hostDisplay(for: job.url))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(job.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            StatusBadge(status: job.status == .applying ? "applying" : "pending")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Applied Section

    private var appliedSection: some View {
        Group {
            if isLoadingJobs {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading applied jobs…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
            } else if let error = jobsError {
                errorStateRow(message: error)
            } else if appliedJobs.isEmpty {
                emptyStateRow(
                    icon: "checkmark.circle",
                    message: "No applied jobs yet",
                    caption: "Jobs you apply to will appear here."
                )
            } else {
                VStack(spacing: 1) {
                    ForEach(appliedJobs) { job in
                        appliedJobRow(job)
                        if job.id != appliedJobs.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func appliedJobRow(_ job: JobRecord) -> some View {
        HStack(spacing: 12) {
            // Colored left border accent
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.green.opacity(0.8))
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                // Company (bold) + title
                HStack(spacing: 6) {
                    if let company = job.company, !company.isEmpty {
                        Text(company)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                    }
                    if let title = job.title, !title.isEmpty {
                        if job.company != nil {
                            Text("·")
                                .foregroundStyle(.tertiary)
                        }
                        Text(title)
                            .font(.system(size: 13, weight: .regular))
                            .lineLimit(1)
                            .foregroundStyle(job.company == nil ? .primary : .secondary)
                    }
                    if job.company == nil && job.title == nil {
                        Text(hostDisplay(for: job.url))
                            .font(.system(size: 13, weight: .semibold))
                    }
                }

                // URL caption
                Text(job.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: job.status)
                Text(formattedDate(job.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Empty & Error States

    private func emptyStateRow(icon: String, message: String, caption: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private func errorStateRow(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text("Could not load jobs")
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button {
                Task { await loadAppliedJobs() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Helpers

    private func hostDisplay(for urlString: String) -> String {
        if let url = URL(string: urlString), let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return urlString
    }

    private func formattedDate(_ dateString: String) -> String {
        // Try ISO-8601 first (with or without fractional seconds)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var date: Date? = iso.date(from: dateString)

        if date == nil {
            iso.formatOptions = [.withInternetDateTime]
            date = iso.date(from: dateString)
        }

        guard let date else { return dateString }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Data Loading

    private func loadAppliedJobs() async {
        guard selectedFilter == .all || selectedFilter == .applied else { return }
        isLoadingJobs = true
        jobsError = nil
        do {
            appliedJobs = try await JobAPIService.shared.getJobs()
        } catch {
            jobsError = error.localizedDescription
        }
        isLoadingJobs = false
    }
}

// MARK: - StatusBadge

/// A colored pill badge displaying a job status string.
private struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(statusLabel)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.15), in: Capsule())
    }

    private var statusLabel: String {
        switch status.lowercased() {
        case "pending":  return "Pending"
        case "applying": return "Applying"
        case "applied":  return "Applied"
        default:         return status.capitalized
        }
    }

    private var badgeColor: Color {
        switch status.lowercased() {
        case "pending":  return .orange
        case "applying": return .blue
        case "applied":  return .green
        default:         return .secondary
        }
    }
}

#Preview {
    DashboardView(appState: AppState())
        .modelContainer(for: PendingJob.self, inMemory: true)
        .frame(width: 860, height: 560)
}
