import Foundation
import SwiftData

@Model
final class PendingJob: Identifiable {
    @Attribute(.unique) var id: UUID
    var url: String
    var userID: String
    var addedAt: Date
    var statusValue: String
    /// On-disk path to the pre-fetched HTML snapshot, if cached.
    var cachedHTMLPath: String? = nil
    var company: String? = nil
    var jobTitle: String? = nil

    var status: PendingJobStatus {
        get { PendingJobStatus(rawValue: statusValue) ?? .pending }
        set { statusValue = newValue.rawValue }
    }

    init(url: String, userID: String) {
        self.id = UUID()
        self.url = url
        self.userID = userID
        self.addedAt = Date()
        self.statusValue = PendingJobStatus.pending.rawValue
    }
}

enum PendingJobStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case applying = "applying"
    case applied = "applied"
}
