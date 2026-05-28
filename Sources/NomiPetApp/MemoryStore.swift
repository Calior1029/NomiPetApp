import Foundation

@MainActor
final class MemoryStore {
    private static let maxRecords = 60
    /// When record count reaches this level, old records should be compressed.
    static let compressionThreshold = 44
    /// How many of the oldest records to hand off for compression each pass.
    static let compressionBatchSize = 16

    private struct Payload: Codable {
        var records: [MemoryRecord]
        var lastSessionEnd: Date?
    }

    private let storeURL: URL
    private var records: [MemoryRecord] = []
    private var lastSessionEnd: Date?

    init() {
        storeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nomi-pet/memory.json")
        load()
    }

    // MARK: - Interaction memory

    func append(type: MemoryType, content: String) {
        guard content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        records.append(MemoryRecord(timestamp: Date(), type: type, content: content))
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
        save()
    }

    // MARK: - Compression support

    var needsCompression: Bool { records.count >= Self.compressionThreshold }

    /// Returns the oldest `count` records for AI compression (excludes existing summaries).
    func recordsForCompression() -> [MemoryRecord] {
        let compressible = records.filter { $0.type != .chatSummary }
        return Array(compressible.prefix(Self.compressionBatchSize))
    }

    /// Replaces the oldest `count` plain records with a single compressed summary record.
    func applyCompression(replacing count: Int, with summary: String) {
        guard count > 0, count <= records.count else { return }
        // Remove the first `count` non-chatSummary records
        var removed = 0
        records = records.filter { record in
            if removed < count, record.type != .chatSummary {
                removed += 1
                return false
            }
            return true
        }
        // Insert compressed record at the front (oldest position)
        let compressed = MemoryRecord(timestamp: Date(), type: .observation, content: "[压缩记忆] \(summary)")
        records.insert(compressed, at: 0)
        save()
    }

    func contextSummary() -> String {
        guard records.isEmpty == false else { return "" }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/d"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "M/d HH:mm"

        // 1. Chat session summaries — highest priority, up to 6
        let summaries = records
            .filter { $0.type == .chatSummary }
            .suffix(6)
            .map { "【聊天摘要 \(dateFormatter.string(from: $0.timestamp))】\($0.content)" }

        // 2. Compressed memory blobs (from AI compression passes)
        let compressed = records
            .filter { $0.type == .observation && $0.content.hasPrefix("[压缩记忆]") }
            .suffix(2)
            .map { "[\(timeFormatter.string(from: $0.timestamp))] \($0.content)" }

        // 3. Recent work events — at most 4, to avoid flooding the context
        let workEvents = records
            .filter { $0.type == .workEvent }
            .suffix(4)
            .map { "[\(timeFormatter.string(from: $0.timestamp))] \($0.content)" }

        // 4. Other recent observations/interactions — at most 3
        let other = records
            .filter { $0.type == .interaction || ($0.type == .observation && $0.content.hasPrefix("[压缩记忆]") == false) }
            .suffix(3)
            .map { "[\(timeFormatter.string(from: $0.timestamp))] \($0.content)" }

        return (summaries + compressed + workEvents + other).joined(separator: "\n")
    }

    // MARK: - Session tracking

    /// Returns how many seconds it has been since the last recorded session end.
    func timeSinceLastSession() -> TimeInterval? {
        guard let last = lastSessionEnd else { return nil }
        return Date().timeIntervalSince(last)
    }

    /// Call on app launch after reading the gap — starts the new session clock.
    func recordSessionStart() {
        // Nothing stored here; session end is what matters
    }

    /// Call on app termination or when the user explicitly quits.
    func recordSessionEnd() {
        lastSessionEnd = Date()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }

        // Try new format first
        if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            records = payload.records
            lastSessionEnd = payload.lastSessionEnd
            return
        }
        // Fall back to legacy format (plain [MemoryRecord])
        if let legacy = try? JSONDecoder().decode([MemoryRecord].self, from: data) {
            records = legacy
        }
    }

    private func save() {
        let payload = Payload(records: records, lastSessionEnd: lastSessionEnd)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
