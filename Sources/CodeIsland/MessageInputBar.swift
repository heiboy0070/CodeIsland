import SwiftUI
import CodeIslandCore

/// 消息输入卡片 — 在刘海面板中输入文字发送到终端
struct MessageInputBar: View {
    let session: SessionSnapshot
    let sessionId: String
    let onSend: (String) -> Void
    let onDismiss: () -> Void

    @State private var inputText = ""
    @FocusState private var isFocused: Bool
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines

    private var fontSize: CGFloat { CGFloat(contentFontSize) }
    private var aiLineLimit: Int? { aiMessageLines > 0 ? aiMessageLines : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题栏
            HStack(spacing: 8) {
                MascotView(source: session.source, status: session.status, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.projectDisplayName)
                        .font(.system(size: fontSize + 2, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let cwd = session.cwd {
                        Text((cwd as NSString).lastPathComponent)
                            .font(.system(size: fontSize - 1, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
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

            // 上下文区域：最近对话 + AI 状态
            if !session.recentMessages.isEmpty || session.status != .idle {
                VStack(alignment: .leading, spacing: 4) {
                    // 最近对话历史
                    let visibleMessages = Array(session.recentMessages.suffix(3))
                    ForEach(visibleMessages) { msg in
                        HStack(alignment: .top, spacing: 6) {
                            Text(msg.isUser ? ">" : "$")
                                .font(.system(size: fontSize - 1, weight: .bold, design: .monospaced))
                                .foregroundStyle(msg.isUser ? Color(red: 0.3, green: 0.85, blue: 0.4) : Color(red: 0.85, green: 0.47, blue: 0.34))
                            Text(msg.text)
                                .font(.system(size: fontSize - 1, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(aiLineLimit ?? 2)
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
                TextField(L10n.shared["send_message_placeholder"] ?? "输入消息...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit {
                        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        onSend(inputText)
                        inputText = ""
                    }

                // 发送按钮
                Button {
                    guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onSend(inputText)
                    inputText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .white.opacity(0.3)
                                : Color(red: 0.3, green: 0.85, blue: 0.4)
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Text(L10n.shared["remote_input_unsupported"] ?? "远程会话不支持直接输入")
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
}
