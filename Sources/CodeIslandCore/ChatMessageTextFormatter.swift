import Foundation
import os.log

public enum ChatMessageTextFormatter {
    private static var markdownCache: [String: AttributedString] = [:]
    private static let markdownCacheLimit = 128

    public static func displayText(for message: ChatMessage) -> AttributedString {
        message.isUser ? literalText(message.text) : inlineMarkdown(message.text)
    }

    public static func literalText(_ text: String) -> AttributedString {
        AttributedString(text)
    }

    public static func inlineMarkdown(_ text: String) -> AttributedString {
        if let cached = markdownCache[text] { return cached }

        let result: AttributedString
        // 使用 full 模式支持块级元素（标题、列表、代码块等）
        do {
            let attr = try AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .full)
            )
            result = attr
        } catch {
            // 解析失败时记录错误并使用纯文本
            os_log("Markdown parse failed: %@", error.localizedDescription)
            result = AttributedString(text)
        }

        if markdownCache.count >= markdownCacheLimit {
            markdownCache.removeAll(keepingCapacity: true)
        }
        markdownCache[text] = result
        return result
    }
}
