import SwiftUI
import CodeIslandCore
import AppKit

/// 消息输入卡片 — 在刘海面板中输入文字发送到终端
struct MessageInputBar: View {
    let session: SessionSnapshot
    let sessionId: String
    let appState: AppState
    let onSend: (String) -> Void
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines

    // 使用持久化的输入文本
    private var inputText: Binding<String> {
        Binding(
            get: { appState.pendingInputText[sessionId] ?? "" },
            set: { appState.pendingInputText[sessionId] = $0 }
        )
    }

    private var fontSize: CGFloat { CGFloat(contentFontSize) }
    private var aiLineLimit: Int? { aiMessageLines > 0 ? aiMessageLines : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题栏
            HStack(spacing: 8) {
                MascotView(source: session.source, status: session.status, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.projectDisplayName)
                            .font(.system(size: fontSize + 2, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        // Model 标识
                        if let model = session.model {
                            Text("(\(modelShortName(model)))")
                                .font(.system(size: fontSize - 2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    // 完整路径（带截断）
                    if let cwd = session.cwd {
                        Text(displayPath(cwd))
                            .font(.system(size: fontSize - 1, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer()
                // 终端类型标识
                if let termApp = session.termApp, !termApp.isEmpty {
                    Text(terminalIcon(termApp))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
                // 跳转终端按钮
                Button {
                    TerminalActivator.activate(session: session, sessionId: sessionId)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                // 关闭按钮
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            // 上下文区域：最近对话 + AI 状态 + 工具历史
            if !session.recentMessages.isEmpty || session.status != .idle || !session.toolHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    let visibleMessages = Array(session.recentMessages.suffix(5))
                    if !visibleMessages.isEmpty {
                        // 分离前面的消息和最后一条消息
                        let earlierMessages = visibleMessages.dropLast().prefix(3)
                        let lastMessage = visibleMessages.last

                        // 前面的消息（简洁显示）
                        if !earlierMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(earlierMessages, id: \.id) { msg in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(msg.isUser ? ">" : "$")
                                            .font(.system(size: fontSize - 1, weight: .bold, design: .monospaced))
                                            .foregroundStyle(msg.isUser ? Color(red: 0.3, green: 0.85, blue: 0.4) : Color(red: 0.85, green: 0.47, blue: 0.34))
                                        Text(markdownPreview(msg.text, maxLines: 2))
                                            .font(.system(size: fontSize - 1, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.6))
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }

                        // 最后一条消息（展开显示，支持滚动和 Markdown）
                        if let last = lastMessage {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(last.isUser ? ">" : "$")
                                        .font(.system(size: fontSize - 1, weight: .bold, design: .monospaced))
                                        .foregroundStyle(last.isUser ? Color(red: 0.3, green: 0.85, blue: 0.4) : Color(red: 0.85, green: 0.47, blue: 0.34))
                                    AppleStyleScrollView(minHeight: 44, maxHeight: 120) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            renderMarkdown(last.text)
                                        }
                                        .font(.system(size: fontSize - 1, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }

                    // AI 当前状态
                    if session.status != .idle {
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.system(size: fontSize - 1, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                            if let tool = session.currentTool {
                                Text(session.toolDescription ?? tool)
                                    .font(.system(size: fontSize - 1, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            } else {
                                Text("thinking...")
                                    .font(.system(size: fontSize - 1, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }

                    // 最近工具使用（最多显示 3 个）
                    if !session.toolHistory.isEmpty {
                        let recentTools = Array(session.toolHistory.prefix(3))
                        HStack(spacing: 4) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 8))
                                .foregroundStyle(.white.opacity(0.4))
                            ForEach(Array(recentTools.enumerated()), id: \.offset) { _, tool in
                                Text(toolShortName(tool.tool))
                                    .font(.system(size: fontSize - 2, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                )
            }

            // 输入区域
            HStack(spacing: 6) {
                Text(">")
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                IMECompatibleTextField(
                    placeholder: L10n.shared["send_message_placeholder"],
                    text: inputText,
                    isFocused: $isFocused,
                    onSubmit: {
                        guard !inputText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onSend(inputText.wrappedValue)
                    }
                )
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.white)

                // 发送按钮
                Button {
                    guard !inputText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSend(inputText.wrappedValue)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            inputText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .white.opacity(0.3)
                                : Color(red: 0.3, green: 0.85, blue: 0.4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.10))
            )

            // 提示
            if session.isRemote {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow.opacity(0.7))
                    Text(L10n.shared["remote_input_unsupported"])
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            isFocused = true
        }
    }

    // MARK: - Helpers

    /// 简短显示模型名称
    private func modelShortName(_ model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("opus") { return "Opus" }
        if lower.contains("haiku") { return "Haiku" }
        if lower.contains("gpt-4") { return "GPT-4" }
        if lower.contains("gpt-3.5") { return "GPT-3.5" }
        if lower.contains("gemini-2") || lower.contains("gemini 2") { return "Gemini 2" }
        if lower.contains("gemini-1.5") || lower.contains("gemini 1.5") { return "Gemini 1.5" }
        // 提取第一部分（如 "claude-sonnet-4-20250514" -> "claude-sonnet-4"）
        let parts = model.split(separator: "-").prefix(3).joined(separator: "-")
        return parts.isEmpty ? model : parts
    }

    /// 显示路径（太长时智能截断）
    private func displayPath(_ path: String) -> String {
        // 如果路径长度 <= 40，直接显示
        if path.count <= 40 { return path }

        // 尝试保留关键部分
        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count >= 4 {
            // 显示: ~/.../parent/folder
            let parent = components[components.count - 2]
            let current = components[components.count - 1]
            if path.hasPrefix("/Users/") || path.hasPrefix("~") {
                return "~/.../\(parent)/\(current)"
            } else {
                return "/.../\(parent)/\(current)"
            }
        }

        // 直接截断中间
        let start = path.index(path.startIndex, offsetBy: 15)
        let end = path.index(path.endIndex, offsetBy: -15)
        return "\(path[..<start])...\(path[end...])"
    }

    /// 终端类型图标
    private func terminalIcon(_ termApp: String) -> String {
        let lower = termApp.lowercased()
        if lower.contains("iterm") { return "⌘" }
        if lower == "ghostty" { return "👻" }
        if lower.contains("wez") { return "🔥" }
        if lower.contains("kitty") { return "🐱" }
        if lower.contains("warp") { return "🌀" }
        if lower.contains("alacritty") { return "⚡" }
        if lower.contains("cmux") { return "🎛️" }
        if lower.contains("tmux") { return "⑆" }
        return "⌨️"
    }

    /// 工具名称简写
    private func toolShortName(_ tool: String) -> String {
        let lower = tool.lowercased()
        if lower.contains("readfile") { return "Read" }
        if lower.contains("writefile") { return "Write" }
        if lower.contains("editfile") { return "Edit" }
        if lower.contains("search") || lower.contains("grep") { return "Search" }
        if lower.contains("list") { return "List" }
        if lower.contains("bash") || lower.contains("run") { return "Exec" }
        if lower.contains("git") { return "Git" }
        if lower.contains("create") { return "Create" }
        if lower.contains("delete") { return "Delete" }
        // 提取驼峰命名
        let words = tool.camelCaseWords()
        return words.prefix(2).joined()
    }

    /// Markdown 格式化（用于前面消息的简洁显示，已被 renderMarkdown 替代）
    private func markdownFormatted(_ text: String) -> AttributedString {
        let processed = parseSystemTags(text)
        return ChatMessageTextFormatter.inlineMarkdown(processed)
    }

    /// Markdown 预览（用于前面消息的简洁显示）
    private func markdownPreview(_ text: String, maxLines: Int = 2) -> String {
        let processed = parseSystemTags(text)

        // 移除代码块标记
        var result = processed.replacingOccurrences(of: #"```[\w]*\n?"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"```"#, with: "")

        // 简化代码标记
        result = result.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)

        // 移除粗体标记
        result = result.replacingOccurrences(of: #"\*\*"#, with: "")

        // 移除斜体标记
        result = result.replacingOccurrences(of: #"(?<!\*)\*(?!\*)"#, with: "", options: .regularExpression)

        // 清理多余空白
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(of: "\n+", with: " ")

        return result
    }

    /// 解析系统标签并格式化输出
    private func parseSystemTags(_ text: String) -> String {
        var result = text
        var extractedInfos: [String] = []

        // 处理 <task-notification> - 提取摘要信息
        if let taskMatch = regexFirstMatch(result, pattern: #"<task-notification>([\s\S]*?)</task-notification>"#) {
            if taskMatch.numberOfRanges > 1 {
                let nsRange = taskMatch.range(at: 1)
                if let range = Range(nsRange, in: result) {
                    let content = String(result[range])
                    // 提取 summary
                    if let summaryMatch = regexFirstMatch(content, pattern: #"<summary>([^<]*)</summary>"#) {
                        if summaryMatch.numberOfRanges > 1,
                           let summaryRange = Range(summaryMatch.range(at: 1), in: content) {
                            let summary = String(content[summaryRange])
                            extractedInfos.append("✓ \(summary)")
                        }
                    }
                    // 提取 status
                    if let statusMatch = regexFirstMatch(content, pattern: #"<status>([^<]*)</status>"#) {
                        if statusMatch.numberOfRanges > 1,
                           let statusRange = Range(statusMatch.range(at: 1), in: content) {
                            let status = String(content[statusRange])
                            extractedInfos.append("Status: \(status)")
                        }
                    }
                }
            }
            result = regexReplace(result, pattern: #"<task-notification>[\s\S]*?</task-notification>"#, replacement: "")
        }

        // 处理 <system-reminder> - 提取关键信息
        if let reminderMatch = regexFirstMatch(result, pattern: #"<system-reminder>([\s\S]*?)</system-reminder>"#) {
            if reminderMatch.numberOfRanges > 1 {
                let nsRange = reminderMatch.range(at: 1)
                if let range = Range(nsRange, in: result) {
                    let content = String(result[range])
                    let cleaned = extractReminderContent(content)
                    if !cleaned.isEmpty {
                        extractedInfos.append("ℹ️ \(cleaned)")
                    }
                }
            }
            result = regexReplace(result, pattern: #"<system-reminder>[\s\S]*?</system-reminder>"#, replacement: "")
        }

        // 处理 <local-command-caveat> - 提取警告
        if let caveatMatch = regexFirstMatch(result, pattern: #"<local-command-caveat>([\s\S]*?)</local-command-caveat>"#) {
            if caveatMatch.numberOfRanges > 1 {
                let nsRange = caveatMatch.range(at: 1)
                if let range = Range(nsRange, in: result) {
                    let content = String(result[range])
                    let cleaned = extractReminderContent(content)
                    if !cleaned.isEmpty {
                        extractedInfos.append("⚠️ \(cleaned)")
                    }
                }
            }
            result = regexReplace(result, pattern: #"<local-command-caveat>[\s\S]*?</local-command-caveat>"#, replacement: "")
        }

        // 处理 <companion-reminder> - 完全隐藏
        result = regexReplace(result, pattern: #"<companion-reminder>[\s\S]*?</companion-reminder>"#, replacement: "")

        // 处理 <new-diagnostics> - 完全隐藏
        result = regexReplace(result, pattern: #"<new-diagnostics>[\s\S]*?</new-diagnostics>"#, replacement: "")

        // 清理多余的换行
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果提取到了系统标签信息，且实际内容为空或很短，显示提取的信息
        if !extractedInfos.isEmpty && (trimmed.isEmpty || trimmed.count < 20) {
            return extractedInfos.joined(separator: "\n")
        }

        // 如果有实际内容，返回实际内容
        if !trimmed.isEmpty {
            return trimmed
        }

        // 如果完全为空，返回提取的信息或占位符
        if !extractedInfos.isEmpty {
            return extractedInfos.joined(separator: "\n")
        }

        return "(系统消息)"
    }

    /// 正则替换
    private func regexReplace(_ text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let result = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
        return result
    }

    /// 正则首次匹配
    private func regexFirstMatch(_ text: String, pattern: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    /// 提取 system-reminder 的有效内容（去除指令性文本）
    private func extractReminderContent(_ text: String) -> String {
        var result = text

        // 移除 XML 标签
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // 移除指令性文本（只删除完整的句子）
        let ignorePatterns = [
            "DO NOT respond to the user",
            "DO NOT mention this to the user",
            "DO NOT quote the original",
            "DO NOT explain what these messages mean",
            "You do not have a choice"
        ]
        for pattern in ignorePatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }

        // 清理多余空白
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 移除开头的常见无意义词
        let prefixPatterns = [
            "Note: ", "NOTE: ", "Important: ", "IMPORTANT: ",
            "Remember: ", "REMINDER: ", "⚠️ ", "ℹ️ "
        ]
        for prefix in prefixPatterns {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
            }
        }

        // 限制长度但保留完整单词
        if result.count > 80 {
            result = String(result.prefix(80))
            if let lastSpace = result.lastIndex(of: " ") {
                result = String(result[..<lastSpace]) + "..."
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 自定义 Markdown 渲染 - 支持块级元素
    private func renderMarkdown(_ text: String) -> some View {
        let processed = parseSystemTags(text)
        let blocks = parseMarkdownBlocks(processed)

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderMarkdownBlock(block)
            }
        }
    }

    /// 解析 Markdown 块
    private func parseMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码块
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1  // 跳过结束标记
                blocks.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            // 标题
            if trimmed.hasPrefix("###") {
                let content = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                blocks.append(.header3(String(content)))
            } else if trimmed.hasPrefix("##") {
                let content = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                blocks.append(.header2(String(content)))
            } else if trimmed.hasPrefix("#") {
                let content = trimmed.dropFirst(1).trimmingCharacters(in: .whitespaces)
                blocks.append(.header1(String(content)))
            }
            // 表格（检测 | 包围的行）
            else if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                var tableRows: [[String]] = []
                var headers: [String] = []

                // 解析表头 - 保留空单元格
                func parseTableRow(_ line: String) -> [String] {
                    // 移除首尾的 |
                    var content = line
                    content.removeFirst()
                    content.removeLast()
                    // 分割并保留空字符串
                    let cells = content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    return cells
                }

                headers = parseTableRow(trimmed)

                // 检查下一行是否是分隔线
                i += 1
                if i < lines.count {
                    let nextLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if nextLine.hasPrefix("|") && nextLine.contains("---") {
                        // 这是分隔线，跳过
                        i += 1
                        // 解析数据行
                        while i < lines.count {
                            let dataLine = lines[i].trimmingCharacters(in: .whitespaces)
                            if dataLine.hasPrefix("|") && dataLine.hasSuffix("|") {
                                let cells = parseTableRow(dataLine)
                                // 确保列数与表头一致
                                if cells.count == headers.count || cells.count > 0 {
                                    tableRows.append(cells)
                                }
                                i += 1
                            } else {
                                break
                            }
                        }
                        i -= 1  // 回退一行
                    } else {
                        i -= 2  // 不是表格，回退
                    }
                } else {
                    i -= 1
                }

                // 只在有表头和至少一行数据时添加表格
                if !headers.isEmpty {
                    blocks.append(.table(rows: tableRows, headers: headers))
                }
            }
            // 列表项
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.listItem(String(trimmed.dropFirst(2))))
            }
            // 编号列表
            else if trimmed.range(of: "^\\d+\\. ", options: .regularExpression) != nil {
                blocks.append(.numberedList(trimmed))
            }
            // 引用
            else if trimmed.hasPrefix("> ") {
                blocks.append(.quote(String(trimmed.dropFirst(2))))
            }
            // 分隔线
            else if trimmed == "---" || trimmed == "___" || trimmed == "***" {
                blocks.append(.divider)
            }
            // 普通段落
            else if !trimmed.isEmpty {
                // 合并连续的非空行
                var paragraph = trimmed
                i += 1
                while i < lines.count {
                    let nextTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if !nextTrimmed.isEmpty && !nextTrimmed.hasPrefix("-") && !nextTrimmed.hasPrefix("*") &&
                       !nextTrimmed.hasPrefix(">") && !nextTrimmed.hasPrefix("#") &&
                       !nextTrimmed.hasPrefix("```") && !nextTrimmed.hasPrefix("---") &&
                       nextTrimmed.range(of: "^\\d+\\. ", options: .regularExpression) == nil {
                        paragraph += " " + nextTrimmed
                        i += 1
                    } else {
                        break
                    }
                }
                i -= 1  // 回退一行，因为外层会加 1
                blocks.append(.paragraph(paragraph))
            }
            // 空行
            else {
                blocks.append(.spacer)
            }

            i += 1
        }

        return blocks
    }

    /// 渲染单个 Markdown 块
    @ViewBuilder
    private func renderMarkdownBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .code(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
        case .header1(let text):
            Text(renderInlineMarkdown(text))
                .font(.system(size: fontSize + 1, weight: .bold, design: .monospaced))
        case .header2(let text):
            Text(renderInlineMarkdown(text))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
        case .header3(let text):
            Text(renderInlineMarkdown(text))
                .font(.system(size: fontSize - 1, weight: .semibold, design: .monospaced))
        case .listItem(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(.white.opacity(0.6))
                Text(renderInlineMarkdown(text))
            }
        case .numberedList(let text):
            if let matchRange = text.range(of: "^\\d+\\. ", options: .regularExpression) {
                let number = String(text[matchRange]).dropLast(2)
                let content = String(text[matchRange.upperBound...].trimmingCharacters(in: .whitespaces))
                HStack(alignment: .top, spacing: 6) {
                    Text("\(number).")
                        .foregroundStyle(.white.opacity(0.6))
                    Text(renderInlineMarkdown(content))
                }
            } else {
                Text(renderInlineMarkdown(text))
            }
        case .quote(let text):
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 3)
                Text(renderInlineMarkdown(text))
                    .italic()
                    .foregroundStyle(.white.opacity(0.8))
            }
        case .divider:
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        case .paragraph(let text):
            Text(renderInlineMarkdown(text))
        case .spacer:
            Spacer()
                .frame(height: 4)
        case .table(let rows, let headers):
            VStack(alignment: .leading, spacing: 0) {
                // 表头
                HStack(spacing: 12) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        Text(renderInlineMarkdown(header.isEmpty ? " " : header))
                            .font(.system(size: fontSize - 2, weight: .bold, design: .monospaced))
                            .frame(minWidth: 50, maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))

                // 数据行
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 12) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(renderInlineMarkdown(cell.isEmpty ? " " : cell))
                                .font(.system(size: fontSize - 2, design: .monospaced))
                                .frame(minWidth: 50, maxWidth: .infinity, alignment: .leading)
                                .lineLimit(3)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(rowIndex % 2 == 0 ? Color.clear : Color.white.opacity(0.02))
                    if rowIndex < rows.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, 10)
                    }
                }
            }
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 渲染行内 Markdown（粗体、斜体、代码）
    private func renderInlineMarkdown(_ text: String) -> AttributedString {
        do {
            let attr = try AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            return attr
        } catch {
            return AttributedString(text)
        }
    }
}

/// Markdown 块类型
enum MarkdownBlock: Equatable {
    case code(String)
    case header1(String)
    case header2(String)
    case header3(String)
    case listItem(String)
    case numberedList(String)
    case quote(String)
    case divider
    case paragraph(String)
    case spacer
    case table(rows: [[String]], headers: [String])
}

// MARK: - Apple Style Scrollbar View Modifier

/// Apple 风格滚动条包装器 - 参考 DESIGN.md 的设计原则
struct AppleStyleScrollView<Content: View>: View {
    let content: Content
    var minHeight: CGFloat = 44
    var maxHeight: CGFloat = 120

    init(minHeight: CGFloat = 44, maxHeight: CGFloat = 120, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content
                .padding(.trailing, 2)
        }
        .background(Color.clear)
        .scrollContentBackground(.hidden)
        .frame(minHeight: minHeight, maxHeight: maxHeight)
    }
}

// MARK: - IME Compatible TextField

/// 兼容中文输入法的 TextField - 使用 NSTextField 包装
struct IMECompatibleTextField: View {
    let placeholder: String
    let text: Binding<String>
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextFieldRepresentable(
            placeholder: placeholder,
            text: text,
            isFocused: isFocused,
            onSubmit: onSubmit
        )
    }
}

private struct TextFieldRepresentable: NSViewRepresentable {
    let placeholder: String
    let text: Binding<String>
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text.wrappedValue
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = false
        textField.isBordered = false
        textField.focusRingType = .none
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text.wrappedValue {
            nsView.stringValue = text.wrappedValue
        }
        // 更新焦点状态
        let hasFocus = nsView.window?.firstResponder == nsView.currentEditor()
        if isFocused.wrappedValue != hasFocus {
            if isFocused.wrappedValue {
                DispatchQueue.main.async {
                    nsView.window?.makeFirstResponder(nsView)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: text, isFocused: isFocused, onSubmit: onSubmit)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let text: Binding<String>
        let isFocused: FocusState<Bool>.Binding
        let onSubmit: () -> Void

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text.wrappedValue = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // 处理 Enter 键
            if commandSelector == #selector(NSText.insertNewline(_:)) {
                // 检查是否有未完成的中文输入（marked text）
                if textView.hasMarkedText() {
                    // 让 IME 处理 Enter 键（确认输入）
                    return false
                }
                // 没有 marked text，执行发送
                onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - String Extension for CamelCase

private extension String {
    func camelCaseWords() -> [String] {
        var words: [String] = []
        var current = ""
        for char in self {
            if char.isUppercase {
                if !current.isEmpty { words.append(current) }
                current = String(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}
