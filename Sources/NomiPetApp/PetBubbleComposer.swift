import Foundation

struct PetBubblePresentation: Sendable, Equatable {
    let text: String
    let style: BubblePresentationStyle
}

enum PetBubbleComposer {
    static func presentation(activity: AssistantActivity?, line: PetLine) -> PetBubblePresentation {
        guard let activity else {
            return PetBubblePresentation(text: line.text, style: style(for: line))
        }

        let title = activity.projectName.isEmpty ? (activity.title.isEmpty ? "当前项目" : activity.title) : activity.projectName
        switch line.source {
        case .ai:
            return PetBubblePresentation(text: "\(title)\n\(line.text)", style: .dynamic)
        case .local, .system:
            let detail = activity.detail.isEmpty ? activity.status.displayName : activity.detail
            return PetBubblePresentation(text: "\(title)\n\(detail)", style: .compact)
        }
    }

    static func style(for line: PetLine) -> BubblePresentationStyle {
        line.source == .ai ? .dynamic : .compact
    }
}
