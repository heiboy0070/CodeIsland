import AppKit
import CodeIslandCore
import os.log

private let terminalWriterLog = Logger(subsystem: "com.codeisland", category: "TerminalWriter")

/// 向终端会话发送文本消息（模拟用户在终端输入）
struct TerminalWriter {

    /// 发送文本到指定 session 对应的终端，并按回车
    /// - Parameters:
    ///   - session: 目标会话快照
    ///   - sessionId: 会话 ID
    ///   - text: 要发送的文本
    ///   - pressEnter: 是否在文本后按回车（默认 true）
    static func sendText(session: SessionSnapshot, sessionId: String? = nil, text: String, pressEnter: Bool = true) {
        guard !session.isRemote else { return }
        guard !text.isEmpty else { return }

        let fullText = pressEnter ? text + "\n" : text

        // IDE 应用（Cursor/Qoder/Factory 等）—— 不支持终端写入
        if session.isIDETerminal || isNativeApp(session: session) {
            // 降级：激活终端窗口，复制文本到剪贴板
            TerminalActivator.activate(session: session, sessionId: sessionId)
            copyToClipboard(text)
            return
        }

        // tmux：最可靠的方式
        if let pane = session.tmuxPane, !pane.isEmpty {
            sendViaTmux(pane: pane, text: text, pressEnter: pressEnter, tmuxEnv: session.tmuxEnv)
            return
        }

        // 根据终端类型分发
        let termApp = resolveTerminal(session: session)
        let lower = termApp.lowercased()

        if lower.contains("iterm") {
            sendViaITerm(session: session, text: fullText)
        } else if lower == "ghostty" {
            sendViaKeystroke(bundleId: "com.mitchellh.ghostty", appName: "Ghostty", session: session, sessionId: sessionId, text: text, pressEnter: pressEnter)
        } else if session.termBundleId == "com.apple.Terminal" || (session.termBundleId == nil && lower == "terminal") {
            sendViaTerminalApp(session: session, text: fullText)
        } else if lower.contains("wezterm") || lower.contains("wez") {
            sendViaWezTerm(text: text, pressEnter: pressEnter)
        } else if lower.contains("kitty") {
            sendViaKitty(session: session, text: text, pressEnter: pressEnter)
        } else {
            // 通用降级：先激活，再通过 System Events keystroke 发送
            sendViaKeystroke(bundleId: session.termBundleId, appName: termApp, session: session, sessionId: sessionId, text: text, pressEnter: pressEnter)
        }
    }

    // MARK: - tmux（最可靠）

    private static func sendViaTmux(pane: String, text: String, pressEnter: Bool, tmuxEnv: String?) {
        guard let bin = findBinary("tmux") else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            // tmux send-keys 会将文本逐字符发送到目标 pane
            var args = ["send-keys", "-t", pane, text]
            if pressEnter { args.append("Enter") }
            _ = runProcess(bin, args: args, env: tmuxProcessEnv(tmuxEnv))
        }
    }

    // MARK: - iTerm2（AppleScript write text）

    private static func sendViaITerm(session: SessionSnapshot, text: String) {
        if let itermId = session.itermSessionId, !itermId.isEmpty {
            // 通过 session ID 找到目标 session，找到后立即 return 避免发送到错误的 session
            let scriptById = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if unique ID of s is "\(escapeAppleScript(itermId))" then
                                tell s to write text "\(escapeAppleScript(text))"
                                return "found"
                            end if
                        end repeat
                    end repeat
                end repeat
                return "not_found"
            end tell
            """

            if let script = NSAppleScript(source: scriptById) {
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if let error = error {
                    terminalWriterLog.error("AppleScript error finding iTerm session: \(error)")
                } else if let resultStr = result.stringValue, resultStr == "not_found" {
                    terminalWriterLog.warning("iTerm session not found: \(itermId)")
                }
            }
        }
    }

    // MARK: - Terminal.app（AppleScript do script）

    private static func sendViaTerminalApp(session: SessionSnapshot, text: String) {
        let tty = session.ttyPath ?? ""
        if !tty.isEmpty {
            let script = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(escapeAppleScript(tty))" then
                            do script "\(escapeAppleScript(text))" in t
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
            runAppleScript(script)
        } else {
            let script = """
            tell application "Terminal"
                do script "\(escapeAppleScript(text))" in selected tab of front window
            end tell
            """
            runAppleScript(script)
        }
    }

    // MARK: - WezTerm（CLI send-text）

    private static func sendViaWezTerm(text: String, pressEnter: Bool) {
        guard let bin = findBinary("wezterm") else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let fullText = pressEnter ? text + "\r\n" : text
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = ["cli", "send-text", "--no-paste", fullText]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
        }
    }

    // MARK: - kitty（CLI send-text）

    private static func sendViaKitty(session: SessionSnapshot, text: String, pressEnter: Bool) {
        guard let bin = findBinary("kitten") else { return }
        let fullText = pressEnter ? text + "\r" : text
        DispatchQueue.global(qos: .userInitiated).async {
            var args = ["@", "send-text"]
            if let windowId = session.kittyWindowId, !windowId.isEmpty {
                args += ["--match", "id:\(windowId)"]
            }
            args.append(fullText)
            _ = runProcess(bin, args: args)
        }
    }

    // MARK: - 通用降级：激活终端 + 粘贴 + 回车

    private static func sendViaKeystroke(bundleId: String?, appName: String, session: SessionSnapshot, sessionId: String?, text: String, pressEnter: Bool) {
        // 先激活目标终端窗口
        TerminalActivator.activate(session: session, sessionId: sessionId)

        // 复制到剪贴板
        copyToClipboard(text)

        // 短暂延迟确保窗口激活和复制完成，然后粘贴并按回车
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            // 使用 Cmd+V 粘贴，然后按回车
            let enterLine = pressEnter ? """
                keystroke return using command down
            """ : ""
            let script = """
            tell application "System Events"
                keystroke "v" using command down
                delay 0.1
                \(enterLine)
            end tell
            """
            runAppleScript(script)
        }
    }

    // MARK: - Helpers

    private static func isNativeApp(session: SessionSnapshot) -> Bool {
        guard let bid = session.termBundleId else { return false }
        let nativeApps: Set<String> = [
            "com.openai.codex", "com.todesktop.230313mzl4w4u92", "com.trae.app",
            "com.qoder.ide", "com.factory.app", "com.tencent.codebuddy",
            "com.tencent.codebuddy.cn", "com.stepfun.app", "ai.opencode.desktop",
        ]
        return nativeApps.contains(bid)
    }

    private static func resolveTerminal(session: SessionSnapshot) -> String {
        let knownTerminals: [(name: String, bundleId: String)] = [
            ("cmux", "com.cmuxterm.app"),
            ("Ghostty", "com.mitchellh.ghostty"),
            ("iTerm2", "com.googlecode.iterm2"),
            ("WezTerm", "com.github.wez.wezterm"),
            ("kitty", "net.kovidgoyal.kitty"),
            ("Alacritty", "org.alacritty"),
            ("Warp", "dev.warp.Warp-Stable"),
            ("Terminal", "com.apple.Terminal"),
        ]
        if let bundleId = session.termBundleId,
           let resolved = knownTerminals.first(where: { $0.bundleId == bundleId })?.name {
            return resolved
        }
        return session.termApp ?? "Terminal"
    }

    private static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private static func escapeAppleScript(_ s: String) -> String {
        var result = s
        // 必须先处理反斜杠，避免重复转义
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        // 处理双引号
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        // 处理换行符 - AppleScript 字符串中使用 \n
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        // 处理回车符
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        // 处理制表符
        result = result.replacingOccurrences(of: "\t", with: "\\t")
        return result
    }

    private static func findBinary(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    private static func runProcess(_ path: String, args: [String], env: [String: String]? = nil) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        if let env {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            proc.environment = merged
        }
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            _ = script.executeAndReturnError(&error)
            if let error = error {
                terminalWriterLog.error("AppleScript error: \(error)")
            }
        }
    }

    private static func tmuxProcessEnv(_ tmuxEnv: String?) -> [String: String]? {
        guard let tmuxEnv = tmuxEnv?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tmuxEnv.isEmpty else { return nil }
        return ["TMUX": tmuxEnv]
    }
}
