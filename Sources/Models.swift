import Foundation

enum DLStatus: String, Codable {
    case running, paused, completed, failed
}

struct DownloadRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var url: String
    var headers: [String: String] = [:]
    var name: String
    var nameLocked = false
    var total: Int64 = 0
    var received: Int64 = 0
    var status: DLStatus = .running
    var error: String?
    var addedAt = Date()
    var finishedAt: Date?
    var fileName: String?
    // Not saved to disk
    var speed: Double = 0

    enum CodingKeys: String, CodingKey {
        case id, url, headers, name, nameLocked, total, received, status, error, addedAt, finishedAt, fileName
    }

    var progress: Double {
        total > 0 ? min(1, Double(received) / Double(total)) : 0
    }

    var etaSeconds: Double? {
        guard status == .running, speed > 1, total > received else { return nil }
        return Double(total - received) / speed
    }

    var fileURL: URL? {
        guard let fileName else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    var fileExists: Bool {
        guard let u = fileURL else { return false }
        return FileManager.default.fileExists(atPath: u.path)
    }
}
