import Foundation

@MainActor
final class UsagePatternStore {
    private struct DayRecord: Codable {
        let dateKey: String   // "yyyy-MM-dd"
        let startHour: Double // fractional: 14.5 = 2:30 pm
        var endHour: Double?
    }

    private let storeURL: URL
    private var records: [DayRecord] = []
    private var todayRecorded = false

    init() {
        storeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nomi-pet/patterns.json")
        load()
        prune()
    }

    // MARK: - Recording

    /// Call once when the first work activity of the day arrives.
    func recordActivityStart() {
        guard todayRecorded == false else { return }
        let key = todayKey()
        guard records.contains(where: { $0.dateKey == key }) == false else { return }
        records.append(DayRecord(dateKey: key, startHour: fractionalHour()))
        todayRecorded = true
        save()
    }

    /// Call on app quit.
    func recordSessionEnd() {
        let key = todayKey()
        guard let idx = records.firstIndex(where: { $0.dateKey == key }) else { return }
        records[idx].endHour = fractionalHour()
        save()
    }

    // MARK: - Pattern note

    /// Returns a natural language note comparing today to the recent average, or nil if not enough data.
    func patternNote() -> String? {
        let key = todayKey()
        guard let today = records.first(where: { $0.dateKey == key }) else { return nil }
        let recent = records.filter { $0.dateKey != key }
        guard recent.count >= 3 else { return nil }

        let avgStart = recent.map(\.startHour).reduce(0, +) / Double(recent.count)
        let diff = today.startHour - avgStart

        if diff < -1.5 { return "今天开始得比平时早" }
        if diff > 1.5  { return "今天开始得比平时晚" }
        return nil
    }

    // MARK: - Helpers

    private func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func fractionalHour() -> Double {
        let c = Calendar.current
        return Double(c.component(.hour, from: Date()))
             + Double(c.component(.minute, from: Date())) / 60.0
    }

    private func prune() {
        if records.count > 14 { records = Array(records.suffix(14)) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let loaded = try? JSONDecoder().decode([DayRecord].self, from: data) else { return }
        records = loaded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
