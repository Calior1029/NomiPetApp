import AppKit
import Foundation

@main
struct AIBubbleComposerCheck {
    static func main() {
        let activity = AssistantActivity(
            source: "Codex",
            projectName: "桌宠开发",
            title: "桌宠开发",
            path: "/tmp/nomi",
            updatedAt: Date(timeIntervalSince1970: 0),
            detail: "这个工具链 XCTest 都没装，标准测试目标不能用",
            status: .thinking
        )

        let aiLine = PetLine(
            text: "这个环境少测试模块，我先帮你盯住构建状态。",
            mood: .thinking,
            source: .ai
        )
        let aiPresentation = PetBubbleComposer.presentation(activity: activity, line: aiLine)
        precondition(aiPresentation.text == "桌宠开发\n这个环境少测试模块，我先帮你盯住构建状态。")
        precondition(aiPresentation.style == .dynamic)

        let localLine = PetLine(text: "本地兜底", mood: .thinking, source: .local)
        let localPresentation = PetBubbleComposer.presentation(activity: activity, line: localLine)
        precondition(localPresentation.text == "桌宠开发\n这个工具链 XCTest 都没装，标准测试目标不能用")
        precondition(localPresentation.style == .compact)
    }
}
