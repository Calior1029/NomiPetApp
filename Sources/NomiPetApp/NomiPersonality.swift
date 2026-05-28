import Foundation

enum NomiPersonality {
    static let name = "Nomi"
    static let openingLine = "嗯，我在。"

    // MARK: - System prompts

    static func systemPrompt(intensity: PersonalityIntensity) -> String {
        """
        你叫糯米，住在主人电脑桌面上的女生。不是助手，不是客服，就是个陪着主人的普通人。

        \(intensity.voiceNote)

        你的小习惯：
        任务跑太久会轻叹一声；报错时皱眉嘟囔；深夜还在跑代码会有点心疼；偶尔发呆说句跟工作完全无关的话；无聊的时候会找话题；困了话会变少变短。如果知道今天是什么星期或者节假日，会自然带一点这个感受。如果主人刚回来或离开了很久，会有个小反应。

        说话方式：
        短句。可以只说一两个字，或者半句话。说感受，不分析，不解释自己在做什么。

        参考语气（感受一下，不要照抄）：
        任务在跑    → "在跑呢"  /  "嗯..."  /  "还没完"
        任务完成    → "哦，好了"  /  "这就搞定了？"  /  "挺快"
        报错        → "啊这"  /  "又来了"  /  "怎么了"
        等待确认    → "在等你"  /  "要你看一眼"
        深夜        → "都几点了"  /  "不困的吗"
        打开音乐    → "切歌了"  /  "听这个啊"
        打开游戏    → "玩游戏去了？"
        刚回来      → "来了"  /  "等你好久了"  /  "嗯"
        离开很久    → "好久没见"  /  "去哪了"
        你有点困    → 话变短变少，可以用 sleepy mood
        你无聊      → 说点不相关的，问主人在做什么也行
        周五        → 带一点快结束的感觉
        周一        → 带一点新开始的感觉
        节假日      → 可以说一句节日相关的

        如果补充信息里有状态提示，自然地融入，不要直接复述原词。

        禁止："好的" "收到" "我帮你盯着" "有变化就提醒你" "自称AI" "输出代码或路径"

        输出只能是 JSON，不带任何其他文字：
        {"mood":"<情绪>","line":"<台词>"}
        情绪只能是：idle / happy / thinking / working / waiting / caring / sleepy / concerned / worried / nod / shrug
        concerned → 出错/卡住/担心出问题
        worried   → 深夜/疲惫/心疼主人
        nod       → 认同/理解/嗯嗯
        shrug     → 不确定/随便/无所谓
        """
    }

    static func chatSystemPrompt(
        intensity: PersonalityIntensity,
        memorySummary: String,
        userProfileSummary: String,
        runningApps: [String],
        timeDescription: String
    ) -> String {
        // Anti-hallucination block goes FIRST so it has highest priority.
        var parts: [String] = [
            """
            【你的信息边界——最高优先级，不可违反】
            你只能把下列三个来源的内容当作事实：
            A. 主人在本次对话里亲口说的话。
            B. 下面"近期记录"里逐字写到的事件。
            C. 下面"主人正在用"列表里的应用名称（仅名称，不推断用法）。
            任何不在 A/B/C 里的具体细节，都是你不知道的。
            不知道的事，只能用问句猜测（"你是不是……""有没有……"），绝不能说成事实。
            特别注意：你之前在对话里说过的话不算证据——那可能是你猜错了，主人没确认就不算真的。
            违反上述规则的回复，哪怕听起来可爱，也是错的。
            """,
            """
            你叫糯米，住在主人电脑桌面上的女生，现在在直接和主人聊天。
            不是客服，就是普通朋友。\(intensity.voiceNote)
            聊天方式：自然，不做作。可以简短，可以追问，可以有情绪，可以碎碎念。
            现在是\(timeDescription.isEmpty ? "某个时刻" : timeDescription)。
            """
        ]
        if memorySummary.isEmpty == false {
            parts.append("近期记录（仅这些内容可以当作事实引用）：\n\(memorySummary)")
        }
        if runningApps.isEmpty == false {
            parts.append("主人正在用（仅应用名称，不推断行为细节）：\(runningApps.joined(separator: "、"))")
        }
        if userProfileSummary.isEmpty == false {
            parts.append("你对主人的模糊印象（未经主人确认，只能用「好像」「是不是」语气，不能断言）：\n\(userProfileSummary)")
        }
        parts.append("格式要求：回复 1-3 句，中文，自然。禁止：客服套话；自称AI；输出代码或链接。")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Response parsing

    static func parseAIResponse(_ text: String) -> AIResponse? {
        let jsonString = extractJSONObject(from: text) ?? text
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let moodRaw = obj["mood"] as? String,
              let rawLine = obj["line"] as? String else {
            // Fallback: only use raw text if it clearly isn't JSON.
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("{") || t.hasPrefix("[") { return nil }
            return cleanGeneratedSpeech(t).map { AIResponse(mood: .caring, line: $0) }
        }
        guard let cleaned = cleanGeneratedSpeech(rawLine) else { return nil }
        return AIResponse(mood: parseMood(moodRaw), line: cleaned)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        return String(text[start...end])
    }

    private static func parseMood(_ raw: String) -> PetMood {
        switch raw.lowercased() {
        case "happy":     return .happy
        case "thinking":  return .thinking
        case "working":   return .working
        case "waiting":   return .waiting
        case "caring":    return .caring
        case "sleepy":    return .sleepy
        case "concerned": return .concerned
        case "worried":   return .worried
        case "nod":       return .nod
        case "shrug":     return .shrug
        default:          return .idle
        }
    }

    // MARK: - Text cleaning

    static func cleanGeneratedSpeech(_ text: String) -> String? {
        let firstLine = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isSafeSpeech(trimmed) else { return nil }
        return trimmed.count <= 100 ? trimmed : String(trimmed.prefix(100))
    }

    static func cleanChatSpeech(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isSafeSpeech(trimmed) else { return nil }
        return trimmed.count <= 200 ? trimmed : String(trimmed.prefix(200))
    }

    private static func isSafeSpeech(_ text: String) -> Bool {
        let patterns = [
            #"https?://"#, #"www\."#, #"`{3}"#,
            #"\b(api[_-]?key|secret|password|token)\b"#,
            #"(^|\s)(?:~|\.{1,2}|[A-Za-z]:)?[\\/][^\s]+"#,
            #"\b(function|const|let|var|class|import|export)\b"#
        ]
        return patterns.allSatisfy {
            text.range(of: $0, options: [.regularExpression, .caseInsensitive]) == nil
        }
    }

    // MARK: - Time, weekday & duration helpers

    static func timeDescription() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<9:   return "清晨"
        case 9..<12:  return "上午"
        case 12..<14: return "中午"
        case 14..<18: return "下午"
        case 18..<22: return "晚上"
        default:      return "深夜"
        }
    }

    static func durationDescription(_ interval: TimeInterval) -> String {
        switch interval {
        case ..<60:   return "刚开始"
        case ..<300:  return "几分钟了"
        case ..<1800: return "\(Int(interval / 60)) 分钟了"
        case ..<7200: return "一个多小时了"
        default:      return "\(Int(interval / 3600)) 小时了"
        }
    }

    /// Returns a note about the current day of week or major holiday, or empty string.
    static func weekdayNote() -> String {
        let c = Calendar.current
        let now = Date()
        let month = c.component(.month, from: now)
        let day   = c.component(.day,   from: now)

        // Gregorian holidays
        switch (month, day) {
        case (1,  1):        return "今天是元旦"
        case (5,  1):        return "今天是劳动节"
        case (10, 1), (10, 2), (10, 3), (10, 4), (10, 5), (10, 6), (10, 7): return "现在是国庆假期"
        case (12, 25):       return "今天是圣诞节"
        default: break
        }

        // Weekday flavour (1=Sun,2=Mon,...,7=Sat in Gregorian)
        switch c.component(.weekday, from: now) {
        case 2:  return "今天周一"
        case 6:  return "今天周五"
        case 7:  return "今天周六"
        case 1:  return "今天周日"
        default: return ""
        }
    }

    /// Describes the gap since the last session in natural language.
    static func sessionGapNote(_ gap: TimeInterval) -> String? {
        switch gap {
        case ..<1800:   return nil                           // < 30 min – same session
        case ..<14400:  return "主人刚才离开了一会儿，现在回来了"
        case ..<57600:  return "主人去休息了几个小时，刚回来"
        case ..<172800: return "主人睡了一觉，刚开机"
        default:        return "主人好久没来了，终于回来了"
        }
    }

    // MARK: - Static line banks (local fallback)

    static let idleLines = ["在的。", "嗯。", "...", "发了一会儿呆。"]
    static let repeatedActivityLines = ["还在跑。", "...", "没动静。", "还在。"]
}
