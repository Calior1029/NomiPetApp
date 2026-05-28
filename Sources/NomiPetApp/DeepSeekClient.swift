import Foundation

final class DeepSeekClient {
    private let environment: [String: String]

    var isConfigured: Bool {
        currentConfig.apiKey.isEmpty == false
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    // MARK: - Activity line (structured JSON output: mood + line)

    func generateLine(
        activity: AssistantActivity,
        intensity: PersonalityIntensity,
        context: GenerationContext,
        completion: @escaping @Sendable (AIResponse?) -> Void
    ) {
        var parts = [
            "来源：\(activity.source)",
            "状态：\(activity.status.displayName)",
            "项目：\(activity.projectName)",
            "任务：\(activity.title)",
            "细节：\(activity.detail)",
            "任务已运行：\(context.taskDurationDescription)",
            "现在：\(context.timeDescription)"
        ]
        if context.runningApps.isEmpty == false {
            parts.append("用户正在使用：\(context.runningApps.joined(separator: "、"))")
        }
        if context.userProfileSummary.isEmpty == false {
            parts.append("主人画像：\n\(context.userProfileSummary)")
        }
        if context.situationNotes.isEmpty == false {
            parts.append("补充：\(context.situationNotes.joined(separator: "；"))")
        }
        if context.memorySummary.isEmpty == false {
            parts.append("你的近期记忆：\n\(context.memorySummary)")
        }
        generateStructured(userContent: parts.joined(separator: "\n"), intensity: intensity, completion: completion)
    }

    // MARK: - Interaction line (hover / drag / ambient)

    func generateInteractionLine(
        event: PetInteractionEvent,
        context: String,
        generationContext: GenerationContext,
        intensity: PersonalityIntensity,
        completion: @escaping @Sendable (AIResponse?) -> Void
    ) {
        var parts = [
            "互动：\(event.promptName)",
            "当前上下文：\(context)",
            "现在：\(generationContext.timeDescription)"
        ]
        if generationContext.runningApps.isEmpty == false {
            parts.append("用户正在使用：\(generationContext.runningApps.joined(separator: "、"))")
        }
        if generationContext.userProfileSummary.isEmpty == false {
            parts.append("主人画像：\n\(generationContext.userProfileSummary)")
        }
        if generationContext.situationNotes.isEmpty == false {
            parts.append("补充：\(generationContext.situationNotes.joined(separator: "；"))")
        }
        if generationContext.memorySummary.isEmpty == false {
            parts.append("你的近期记忆：\n\(generationContext.memorySummary)")
        }
        generateStructured(userContent: parts.joined(separator: "\n"), intensity: intensity, completion: completion)
    }

    // MARK: - App launch observation

    func generateAppObservation(
        apps: [String],
        context: GenerationContext,
        intensity: PersonalityIntensity,
        completion: @escaping @Sendable (AIResponse?) -> Void
    ) {
        var parts = [
            "用户刚刚打开了：\(apps.joined(separator: "、"))",
            "现在：\(context.timeDescription)"
        ]
        if context.userProfileSummary.isEmpty == false {
            parts.append("主人画像：\n\(context.userProfileSummary)")
        }
        if context.situationNotes.isEmpty == false {
            parts.append("补充：\(context.situationNotes.joined(separator: "；"))")
        }
        if context.memorySummary.isEmpty == false {
            parts.append("近期记忆：\n\(context.memorySummary)")
        }
        parts.append("根据用户打开的应用，用一句自然的话表达你的好奇或关心，不要机械罗列应用名。")
        generateStructured(userContent: parts.joined(separator: "\n"), intensity: intensity, completion: completion)
    }

    // MARK: - Chat (conversational, with history)

    func chat(
        history: [ChatMessage],
        userMessage: String,
        context: GenerationContext,
        intensity: PersonalityIntensity,
        completion: @escaping @Sendable (AIResponse?) -> Void
    ) {
        let config = currentConfig
        guard config.apiKey.isEmpty == false,
              let endpoint = DeepSeekConfigFile.endpointURL(for: config.baseURL) else {
            completion(nil)
            return
        }

        var messages: [[String: Any]] = [[
            "role": "system",
            "content": NomiPersonality.chatSystemPrompt(
                intensity: intensity,
                memorySummary: context.memorySummary,
                userProfileSummary: context.userProfileSummary,
                runningApps: context.runningApps,
                timeDescription: context.timeDescription
            )
        ]]

        for msg in history.suffix(20) {
            messages.append([
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ])
        }
        messages.append(["role": "user", "content": userMessage])

        let payload: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": 1.05,
            "max_tokens": 200
        ]

        send(payload: payload, endpoint: endpoint, apiKey: config.apiKey, timeout: 18) { data in
            guard let data else { completion(nil); return }
            let text = Self.extractContent(from: data)
            let cleaned = text.flatMap(NomiPersonality.cleanChatSpeech)
            completion(cleaned.map { AIResponse(mood: .caring, line: $0) })
        }
    }

    // MARK: - Memory record compression

    /// Compresses a batch of raw memory records into a 2-3 sentence distillation.
    func compressMemoryRecords(
        _ records: String,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        let config = currentConfig
        guard config.apiKey.isEmpty == false,
              let endpoint = DeepSeekConfigFile.endpointURL(for: config.baseURL) else {
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": """
                把下面这些记忆条目提炼成2-3句中文摘要，保留最有价值的信息。
                重点：主人的行为规律、重要事件、情绪状态、项目进展。
                语气简洁自然，像写日记一样。只输出摘要，不要其他内容。
                重要：只提炼记录里已有的信息，不要推断或补充任何记录中没有的细节。
                """],
                ["role": "user", "content": records]
            ],
            "temperature": 0.3,
            "max_tokens": 150
        ]

        send(payload: payload, endpoint: endpoint, apiKey: config.apiKey, timeout: 15) { data in
            guard let data,
                  let text = Self.extractContent(from: data),
                  text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else { completion(nil); return }
            completion(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Conversation summary

    /// Compresses a finished chat session into 2-3 sentences of key points.
    func summarizeConversation(
        messages: [ChatMessage],
        completion: @escaping @Sendable (String?) -> Void
    ) {
        let config = currentConfig
        guard config.apiKey.isEmpty == false,
              let endpoint = DeepSeekConfigFile.endpointURL(for: config.baseURL),
              messages.count >= 4 else {
            completion(nil)
            return
        }

        let lines = messages.suffix(40).map { msg -> String in
            let role = msg.role == .user ? "主人" : "糯米"
            return "\(role)：\(msg.content)"
        }.joined(separator: "\n")

        let systemPrompt = """
        把下面这段聊天记录压缩成2-3句中文摘要。
        重点记录：聊了什么话题、主人提到的重要事情、情绪状态、有没有计划或决定。
        语气自然，像写日记一样，不要罗列条目。只输出摘要，不要其他内容。
        重要：只记录对话里实际出现的内容，不要推测或补充任何对话中没有明确说到的细节。
        """

        let payload: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": lines]
            ],
            "temperature": 0.4,
            "max_tokens": 180
        ]

        send(payload: payload, endpoint: endpoint, apiKey: config.apiKey, timeout: 20) { data in
            guard let data,
                  let text = Self.extractContent(from: data),
                  text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else { completion(nil); return }
            completion(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - User fact extraction

    /// Extracts structured facts about the user from a chat conversation.
    /// Runs silently in background after chat sessions; results are merged into UserMemoryStore.
    func extractUserFacts(
        conversation: [ChatMessage],
        completion: @escaping @Sendable ([UserFact]?) -> Void
    ) {
        let config = currentConfig
        guard config.apiKey.isEmpty == false,
              let endpoint = DeepSeekConfigFile.endpointURL(for: config.baseURL),
              conversation.isEmpty == false else {
            completion(nil)
            return
        }

        let lines = conversation.suffix(20).map { msg -> String in
            let role = msg.role == .user ? "主人" : "糯米"
            return "\(role)：\(msg.content)"
        }.joined(separator: "\n")

        let systemPrompt = """
        从以下对话中提取关于"主人"的关键信息。
        只提取对话中明确出现的信息，不要推测。
        输出 JSON 数组，每条格式：
        {"category":"<类别>","content":"<一句话，中文>","confidence":<0.0-1.0>}
        类别只能是：personality / habit / preference / project / personal
        - personality：性格特点、说话风格、情绪倾向
        - habit：行为规律、时间习惯、工作节奏
        - preference：工具偏好、语言偏好、喜欢或不喜欢的事物
        - project：正在做的项目、当前工作内容
        - personal：姓名、职业、地点等个人信息
        没有有效信息时返回 []。只输出 JSON，不要其他文字。
        """

        let payload: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": lines]
            ],
            "temperature": 0.3,
            "max_tokens": 400
        ]

        send(payload: payload, endpoint: endpoint, apiKey: config.apiKey, timeout: 15) { data in
            guard let data,
                  let content = Self.extractContent(from: data),
                  let start = content.firstIndex(of: "["),
                  let end = content.lastIndex(of: "]") else {
                completion([])
                return
            }
            let jsonStr = String(content[start...end])
            guard let jsonData = jsonStr.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                completion([])
                return
            }
            let facts: [UserFact] = arr.compactMap { obj in
                guard let categoryRaw = obj["category"] as? String,
                      let factContent = obj["content"] as? String,
                      let confidence = obj["confidence"] as? Double,
                      let category = UserFactCategory(rawValue: categoryRaw),
                      factContent.trimmingCharacters(in: .whitespaces).isEmpty == false
                else { return nil }
                return UserFact(category: category, content: factContent, confidence: min(1.0, max(0.0, confidence)))
            }
            completion(facts)
        }
    }

    // MARK: - Private helpers

    private func generateStructured(
        userContent: String,
        intensity: PersonalityIntensity,
        completion: @escaping @Sendable (AIResponse?) -> Void
    ) {
        let config = currentConfig
        guard config.apiKey.isEmpty == false,
              let endpoint = DeepSeekConfigFile.endpointURL(for: config.baseURL) else {
            completion(nil)
            return
        }

        let payload: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": NomiPersonality.systemPrompt(intensity: intensity)],
                ["role": "user", "content": userContent]
            ],
            "temperature": 1.1,
            "max_tokens": 200
        ]

        send(payload: payload, endpoint: endpoint, apiKey: config.apiKey, timeout: 12) { data in
            guard let data else { completion(nil); return }
            let text = Self.extractContent(from: data)
            completion(text.flatMap(NomiPersonality.parseAIResponse))
        }
    }

    private func send(
        payload: [String: Any],
        endpoint: URL,
        apiKey: String,
        timeout: TimeInterval,
        completion: @escaping @Sendable (Data?) -> Void
    ) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(nil)
            return
        }
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { data, _, error in
            completion(error == nil ? data : nil)
        }.resume()
    }

    private var currentConfig: DeepSeekResolvedConfig {
        DeepSeekConfigFile.resolve(DeepSeekConfigFile.load(), environment: environment)
    }

    private static func extractContent(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
