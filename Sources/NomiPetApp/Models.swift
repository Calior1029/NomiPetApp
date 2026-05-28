import AppKit
import Foundation

struct PetManifest: Decodable {
    let name: String
    let version: String
    let format: PetFormat
    let animations: [PetAnimation]
}

struct PetFormat: Decodable {
    let frameSize: [Int]
}

struct PetAnimation: Decodable {
    let id: String
    let name: String
    let category: String
    let fps: Int
    let loop: Bool
    let frames: [String]
}

struct LoadedAnimation {
    let spec: PetAnimation
    let frames: [NSImage]
}

enum PetMood: Sendable {
    case idle
    case happy
    case thinking
    case working
    case waiting
    case caring
    case sleepy
    case concerned
    case worried
    case nod
    case shrug

    var animationID: String {
        switch self {
        case .idle:      return "idle_breathe"
        case .happy:     return "happy"
        case .thinking:  return "thinking"
        case .working:   return "working"
        case .waiting:   return "waiting"
        case .caring:    return "wave"
        case .sleepy:    return "sleep"
        case .concerned: return "concerned"
        case .worried:   return "worried"
        case .nod:       return "nod"
        case .shrug:     return "shrug"
        }
    }
}

enum PetLineSource: Sendable {
    case local
    case ai
    case system
}

enum BubblePresentationStyle: Sendable, Equatable {
    case compact
    case dynamic
}

enum PersonalityIntensity: Int, CaseIterable, Sendable {
    case calm = 0
    case normal = 1
    case attached = 2

    var label: String {
        switch self {
        case .calm: return "克制"
        case .normal: return "正常"
        case .attached: return "粘人"
        }
    }

    var promptHint: String { voiceNote }

    var voiceNote: String {
        switch self {
        case .calm:
            return "话不多。简短，克制，有时候沉默着也没关系。不会主动撒娇。"
        case .normal:
            return "普通状态。偶尔碎碎念，偶尔一句话说一半，有时候走神。"
        case .attached:
            return "话多一些，容易担心主人，喜欢时不时说一句。有点黏。"
        }
    }
}

enum AssistantStatus: String, Sendable {
    case thinking
    case running
    case waiting
    case failed
    case completed
    case stalled

    var displayName: String {
        switch self {
        case .thinking: return "正在思考"
        case .running: return "正在跑命令"
        case .waiting: return "等待用户确认"
        case .failed: return "出错"
        case .completed: return "完成"
        case .stalled: return "长时间无进展"
        }
    }
}

struct AssistantActivity: Equatable, Sendable {
    let source: String
    let projectName: String
    let title: String
    let path: String
    let updatedAt: Date
    let detail: String
    let status: AssistantStatus

    var keepsBubbleVisible: Bool {
        switch status {
        case .thinking, .running, .waiting, .failed, .stalled:
            return true
        case .completed:
            return false
        }
    }
}

struct PetLine: Sendable {
    let text: String
    let mood: PetMood
    let source: PetLineSource

    init(text: String, mood: PetMood, source: PetLineSource = .local) {
        self.text = text
        self.mood = mood
        self.source = source
    }
}

struct AmbientPetEvent: Sendable {
    let line: String
    let animationID: String
    let duration: TimeInterval
    let bubbleDuration: TimeInterval
}

enum PetInteractionEvent: Hashable, Sendable {
    case hover
    case dragEnded
    case ambient
    case headpat

    var promptName: String {
        switch self {
        case .hover:    return "主人鼠标靠近了你"
        case .dragEnded: return "主人刚把你挪到了新位置"
        case .ambient:  return "主人工作间隙，你主动陪伴一句"
        case .headpat:  return "主人摸了摸你的头"
        }
    }
}

// MARK: - AI Structured Output

struct AIResponse: Sendable {
    let mood: PetMood
    let line: String
}

// MARK: - Generation Context

struct GenerationContext: Sendable {
    let memorySummary: String
    let runningApps: [String]
    let timeDescription: String
    let taskDurationDescription: String
    /// Extra situational notes: weekday, tiredness, boredom, pattern, session gap, etc.
    let situationNotes: [String]
    /// Structured long-term user profile (personality, habits, preferences, projects).
    let userProfileSummary: String

    static let empty = GenerationContext(
        memorySummary: "",
        runningApps: [],
        timeDescription: "",
        taskDurationDescription: "刚开始",
        situationNotes: [],
        userProfileSummary: ""
    )
}

// MARK: - Long-term user memory types

enum UserFactCategory: String, Codable, CaseIterable, Sendable {
    case personality  // 性格、说话风格
    case habit        // 行为规律、时间习惯
    case preference   // 工具偏好、喜好
    case project      // 正在做的项目
    case personal     // 姓名、地点等
}

struct UserFact: Codable, Sendable {
    let id: UUID
    var category: UserFactCategory
    var content: String
    var confidence: Double   // 0.0–1.0
    var frequency: Int       // confirmed by N separate extractions
    var createdAt: Date
    var updatedAt: Date

    init(category: UserFactCategory, content: String, confidence: Double) {
        id = UUID()
        self.category = category
        self.content = content
        self.confidence = confidence
        frequency = 1
        createdAt = Date()
        updatedAt = Date()
    }
}

// MARK: - Chat

enum ChatRole: String, Codable, Sendable {
    case user
    case nomi
}

struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - Memory

enum MemoryType: String, Codable, Sendable {
    case interaction
    case workEvent
    case chat
    case observation
    case chatSummary   // compressed summary of a finished chat session
}

struct MemoryRecord: Codable, Sendable {
    let timestamp: Date
    let type: MemoryType
    let content: String
}
