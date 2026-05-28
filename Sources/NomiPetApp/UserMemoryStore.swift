import Foundation

/// Hermes-style long-term user knowledge base.
/// Stores AI-extracted facts about the user: personality, habits, preferences, projects.
/// After each chat session the AI distils new facts; duplicates are merged in, old weak
/// facts are eventually pruned. The resulting profile is injected into every AI prompt.
@MainActor
final class UserMemoryStore {

    private let storeURL: URL
    private(set) var facts: [UserFact] = []
    private static let maxFacts = 40

    // MARK: - Init

    init() {
        storeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nomi-pet/user_memory.json")
        load()
    }

    // MARK: - Read

    /// Returns a compact multi-line profile for injection into AI system prompts.
    func profileSummary() -> String {
        guard facts.isEmpty == false else { return "" }

        // Rank by confidence × frequency (most reliable / most-confirmed facts first)
        let ranked = facts
            .sorted { ($0.confidence * Double($0.frequency)) > ($1.confidence * Double($1.frequency)) }
            .prefix(20)

        var lines: [String] = []
        for cat in UserFactCategory.allCases {
            let catFacts = ranked.filter { $0.category == cat }
            guard catFacts.isEmpty == false else { continue }
            let label: String
            switch cat {
            case .personal:     label = "关于主人"
            case .personality:  label = "性格"
            case .habit:        label = "习惯"
            case .preference:   label = "偏好"
            case .project:      label = "项目"
            }
            lines.append("\(label)：\(catFacts.map(\.content).joined(separator: "；"))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Write

    /// Merge a batch of newly extracted facts, deduplicating against existing ones.
    func merge(newFacts: [UserFact]) {
        guard newFacts.isEmpty == false else { return }
        for new in newFacts {
            if let idx = facts.firstIndex(where: { existing in
                existing.category == new.category && stringSimilar(existing.content, new.content)
            }) {
                // Reinforce an existing fact
                facts[idx].confidence = max(facts[idx].confidence, new.confidence)
                facts[idx].frequency += 1
                facts[idx].updatedAt = Date()
            } else {
                facts.append(new)
            }
        }
        prune()
        save()
    }

    // MARK: - Private helpers

    private func prune() {
        guard facts.count > Self.maxFacts else { return }
        facts = facts
            .sorted { ($0.confidence * Double($0.frequency)) > ($1.confidence * Double($1.frequency)) }
            .prefix(Self.maxFacts)
            .map { $0 }
    }

    /// Simple Chinese-friendly overlap check — catches "用TypeScript" vs "用TypeScript开发".
    private func stringSimilar(_ a: String, _ b: String) -> Bool {
        let la = a.lowercased().trimmingCharacters(in: .whitespaces)
        let lb = b.lowercased().trimmingCharacters(in: .whitespaces)
        return la == lb || la.contains(lb) || lb.contains(la)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let loaded = try? JSONDecoder().decode([UserFact].self, from: data) else { return }
        facts = loaded
    }

    private func save() {
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(facts) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
