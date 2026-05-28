import Foundation

struct DeepSeekConfigPayload: Codable, Sendable, Equatable {
    var apiKey: String?
    var baseURL: String?
    var model: String?
}

struct DeepSeekResolvedConfig: Sendable, Equatable {
    let apiKey: String
    let baseURL: String
    let model: String
}

enum DeepSeekConfigFile {
    static let didChange = Notification.Name("NomiDeepSeekConfigDidChange")
    static let defaultBaseURL = "https://api.deepseek.com/chat/completions"
    static let defaultModel = "deepseek-chat"

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".nomi-pet", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static func load() -> DeepSeekConfigPayload {
        guard let data = try? Data(contentsOf: configURL),
              let payload = try? JSONDecoder().decode(DeepSeekConfigPayload.self, from: data) else {
            return DeepSeekConfigPayload(apiKey: nil, baseURL: nil, model: nil)
        }
        return payload
    }

    static func save(_ payload: DeepSeekConfigPayload) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    static func resolve(_ payload: DeepSeekConfigPayload, environment: [String: String] = [:]) -> DeepSeekResolvedConfig {
        DeepSeekResolvedConfig(
            apiKey: trimmed(environment["DEEPSEEK_API_KEY"] ?? payload.apiKey),
            baseURL: normalizedBaseURL(environment["DEEPSEEK_BASE_URL"] ?? payload.baseURL),
            model: normalizedModel(environment["DEEPSEEK_MODEL"] ?? payload.model)
        )
    }

    static func endpointURL(for baseURL: String) -> URL? {
        let normalized = normalizedBaseURL(baseURL)
        guard var components = URLComponents(string: normalized),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false else {
            return nil
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") {
            return components.url
        }

        components.path = "/" + ([path, "chat/completions"].filter { $0.isEmpty == false }.joined(separator: "/"))
        return components.url
    }

    static func payload(apiKey: String, baseURL: String, model: String) -> DeepSeekConfigPayload {
        DeepSeekConfigPayload(
            apiKey: optionalTrimmed(apiKey),
            baseURL: optionalTrimmed(baseURL),
            model: optionalTrimmed(model)
        )
    }

    private static func normalizedBaseURL(_ value: String?) -> String {
        let trimmedValue = trimmed(value)
        return trimmedValue.isEmpty ? defaultBaseURL : trimmedValue
    }

    private static func normalizedModel(_ value: String?) -> String {
        let trimmedValue = trimmed(value)
        return trimmedValue.isEmpty ? defaultModel : trimmedValue.lowercased()
    }

    private static func optionalTrimmed(_ value: String) -> String? {
        let trimmedValue = trimmed(value)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

@MainActor
final class DeepSeekConfigStore {
    private var payload: DeepSeekConfigPayload

    init() {
        payload = DeepSeekConfigFile.load()
    }

    var config: DeepSeekResolvedConfig {
        DeepSeekConfigFile.resolve(payload)
    }

    func update(apiKey: String, baseURL: String, model: String) throws {
        let updated = DeepSeekConfigFile.payload(apiKey: apiKey, baseURL: baseURL, model: model)
        try DeepSeekConfigFile.save(updated)
        payload = updated
        NotificationCenter.default.post(name: DeepSeekConfigFile.didChange, object: self)
    }

    func reload() {
        payload = DeepSeekConfigFile.load()
    }
}
