import Cocoa

// planeB64 由 build.sh 从 plane.png 编译时自动生成
var planePngData: Data {
    Data(base64Encoded: planeB64)!
}

// ========== env.json 配置（每个状态可配提示词、emoji、图片） ==========
struct StatusConfig: Codable {
    var image: String?
    var emoji: String?
    var prompt: String?

    // 兼容旧格式：允许直接写图片路径字符串
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let path = try? single.decode(String.self) {
            image = path
            return
        }
        let obj = try decoder.container(keyedBy: CodingKeys.self)
        image  = try obj.decodeIfPresent(String.self, forKey: .image)
        emoji  = try obj.decodeIfPresent(String.self, forKey: .emoji)
        prompt = try obj.decodeIfPresent(String.self, forKey: .prompt)
    }
}

struct EnvConfig: Codable {
    var image: String?          // 旧版兼容（default 的快捷方式）
    var `default`: StatusConfig?
    var success: StatusConfig?
    var failure: StatusConfig?
    var blocked: StatusConfig?

    subscript(status: String) -> StatusConfig? {
        switch status {
        case "success": return success ?? `default`
        case "failure": return failure ?? `default`
        case "blocked": return blocked ?? `default`
        default:        return `default`
        }
    }
}

func loadEnvConfig() -> EnvConfig {
    let fm = FileManager.default
    var searchPaths = [fm.currentDirectoryPath]
    if let bin = CommandLine.arguments.first {
        searchPaths.append((bin as NSString).deletingLastPathComponent)
    }
    for dir in searchPaths {
        let url = URL(fileURLWithPath: dir).appendingPathComponent("env.json")
        if let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(EnvConfig.self, from: data) {
            return config
        }
    }
    return EnvConfig()
}

let envConfig = loadEnvConfig()

// ========== Notify 模式（取代 cc-notify.py）==========

/// 防并发：通过 PID 文件检查是否已有 cc-planet 实例在运行
var pidFileHandle: FileHandle?

func acquireLock() -> Bool {
    let pidFilePath = "/tmp/cc-planet.pid"
    // 检查已有 PID 文件
    if let existing = try? String(contentsOfFile: pidFilePath).trimmingCharacters(in: .whitespacesAndNewlines),
       let pid = pid_t(existing) {
        if kill(pid, 0) == 0 {
            return false // 已有实例在运行
        }
    }
    // 写自己的 PID
    let pidStr = "\(ProcessInfo.processInfo.processIdentifier)"
    FileManager.default.createFile(atPath: pidFilePath, contents: pidStr.data(using: .utf8), attributes: nil)
    pidFileHandle = FileHandle(forWritingAtPath: pidFilePath)
    atexit { releaseLock() }
    return true
}

func releaseLock() {
    pidFileHandle?.closeFile()
    try? FileManager.default.removeItem(atPath: "/tmp/cc-planet.pid")
    pidFileHandle = nil
}

/// 清理 markdown 格式
func cleanMarkdown(_ text: String) -> String {
    var result = text
    // 移除代码块 ```...```
    if let regex = try? NSRegularExpression(pattern: #"```[^`]*```"#, options: .dotMatchesLineSeparators) {
        let range = NSRange(result.startIndex..., in: result)
        result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
    }
    // 内联代码 `...` → 纯文本
    if let regex = try? NSRegularExpression(pattern: #"`([^`]+)`"#) {
        let range = NSRange(result.startIndex..., in: result)
        result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
    }
    result = result.replacingOccurrences(of: "\n", with: " ")
    result = result.replacingOccurrences(of: "\r", with: " ")
    result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespaces)
}

/// 处理 PreToolUse 事件：提取 AskUserQuestion
func handlePreToolUse(_ data: [String: Any]) -> String? {
    guard let toolName = data["tool_name"] as? String, toolName == "AskUserQuestion" else {
        return nil
    }
    guard let toolInput = data["tool_input"] as? [String: Any],
          let questions = toolInput["questions"] as? [[String: Any]],
          let q = questions.first,
          let header = q["header"] as? String,
          let question = q["question"] as? String else {
        return nil
    }
    let msg = "\(header): \(question)"
    return String(msg.prefix(24))
}

/// 处理 Stop 事件：提取 last_assistant_message，清理 markdown
func handleStop(_ data: [String: Any]) -> String? {
    guard let last = data["last_assistant_message"] as? String, !last.isEmpty else {
        return nil
    }
    let text = cleanMarkdown(last)
    let truncated = text.count > 23 ? String(text.prefix(23)) + "…" : text
    return "✅ \(truncated)"
}

/// 从 stdin 读取并处理 JSON 事件
func handleNotifyJSON() -> String? {
    let stdinData = FileHandle.standardInput.readDataToEndOfFile()
    guard !stdinData.isEmpty,
          let json = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] else {
        return nil
    }

    if json["tool_name"] != nil {
        return handlePreToolUse(json)
    } else if json["session_id"] != nil || json["stop_reason"] != nil {
        return handleStop(json)
    }
    return nil
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// 不激活 app，避免抢占键盘焦点和鼠标焦点
NSApp.preventWindowOrdering()

guard let screen = NSScreen.main else { exit(1) }
let sw = screen.frame.width
let sh = screen.frame.height
let sf = screen.backingScaleFactor

// ========== 消息 + 状态 ==========
var message: String?
var planeStatus: String?
let args = CommandLine.arguments

// 检测是否通过 cc-notify 符号链接调用
let isNotifySymlink = (args[0] as NSString).lastPathComponent == "cc-notify"

if args.count > 1 {
    switch args[1] {
    // --- Notify 模式（取代 cc-notify.py）---
    case "--notify":
        if args.count > 2, args[2] == "--json" {
            // JSON 事件模式: 等效于 cc-notify --json
            guard acquireLock() else { exit(0) }
            message = handleNotifyJSON()
            if message == nil { exit(0) }
        } else {
            // 纯文本模式: 等效于 cc-notify <消息>
            guard acquireLock() else { exit(0) }
            var m = args.dropFirst(2).joined(separator: " ")
            if m.count > 24 { m = String(m.prefix(24)) + "…" }
            message = m
        }

    // --- 隐式 JSON 通知模式（--notify 可省略）---
    case "--json":
        guard acquireLock() else { exit(0) }
        message = handleNotifyJSON()
        if message == nil { exit(0) }

    // --- 帮助 ---
    case "--help", "-h":
        print("""
        用法: cc-planet [--success|--failure|--blocked] [消息]
               cc-planet --notify <消息>                           (发送文本通知)
               cc-planet --notify --json                           (从 stdin 读取 JSON 事件)
               echo '{"last_assistant_message":"...","stop_reason":"stop"}' | cc-planet --json
        """)
        exit(0)

    // --- 原始模式（向后兼容）---
    default:
        let statusFlags: Set<String> = ["--success", "--failure", "--blocked"]

        // 通过 cc-notify 符号链接 + 裸文本 → 进入通知模式
        if isNotifySymlink && !statusFlags.contains(args[1]) {
            guard acquireLock() else { exit(0) }
            var m = args.dropFirst(1).joined(separator: " ")
            if m.count > 24 { m = String(m.prefix(24)) + "…" }
            message = m
            break
        }

        var idx = 1
        if statusFlags.contains(args[idx]) {
            planeStatus = String(args[idx].dropFirst(2)) // "success" / "failure" / "blocked"
            idx += 1
        }
        // 组装消息：状态 emoji（有则加） + 自定义内容
        var parts: [String] = []
        if let s = planeStatus, let cfg = envConfig[s], let e = cfg.emoji { parts.append(e) }
        if idx < args.count {
            var m = args[idx...].joined(separator: " ")
            if m.count > 22 { m = String(m.prefix(22)) + "…" }
            parts.append(m)
        } else if let s = planeStatus, let cfg = envConfig[s], let p = cfg.prompt {
            // 没有自定义消息时使用状态默认 prompt
            parts.append(p)
        }
        message = parts.isEmpty ? nil : parts.joined(separator: " ")
    }
} else if isNotifySymlink {
    print("用法: cc-notify <消息>")
    exit(0)
}

// ========== 画布 ==========
let canvas = NSWindow(contentRect: NSRect(x: 0, y: 0, width: sw, height: sh),
                      styleMask: [.borderless], backing: .buffered, defer: false)
canvas.isOpaque = false; canvas.backgroundColor = .clear
canvas.level = .popUpMenu
canvas.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
canvas.hasShadow = false; canvas.ignoresMouseEvents = true
let cv = NSView(frame: NSRect(x: 0, y: 0, width: sw, height: sh))
cv.wantsLayer = true; cv.layer?.backgroundColor = .clear
canvas.contentView = cv; canvas.orderFrontRegardless()

// ========== 飞机图片（编译时嵌入二进制，无需外部文件）==========
func loadPlane(status: String?) -> NSImage? {
    // 从 env.json 获取对应状态的图片路径
    let path: String? = envConfig[status ?? ""]?.image ?? envConfig.image
    if let p = path, let custom = NSImage(contentsOfFile: p) {
        return custom
    }
    guard let raw = NSImage(data: planePngData) else {
        return nil
    }
    // 水平翻转（镜像），确保飞机朝右飞行
    let flipped = NSImage(size: raw.size)
    flipped.lockFocus()
    let t = NSAffineTransform()
    t.scaleX(by: -1, yBy: 1)
    t.translateX(by: -raw.size.width, yBy: 0)
    t.concat()
    raw.draw(at: .zero, from: NSRect(origin: .zero, size: raw.size), operation: .copy, fraction: 1)
    flipped.unlockFocus()
    return flipped
}

let planeImage = loadPlane(status: planeStatus)
let planeSize: CGFloat = 220
if let img = planeImage {
    let r = img.size.width / img.size.height
    if r > 1 { img.size = NSSize(width: planeSize, height: planeSize / r) }
    else { img.size = NSSize(width: planeSize * r, height: planeSize) }
}

let actualW = planeImage?.size.width ?? planeSize
let actualH = planeImage?.size.height ?? planeSize

let planeLayer = CALayer()
planeLayer.frame = CGRect(x: 0, y: 0, width: actualW, height: actualH)
planeLayer.contents = planeImage
planeLayer.contentsGravity = .resizeAspect
planeLayer.contentsScale = sf
planeLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

// 上下浮动
let bob = CABasicAnimation(keyPath: "position.y")
bob.fromValue = actualH / 2; bob.toValue = actualH / 2 - 6
bob.duration = 0.7; bob.autoreverses = true; bob.repeatCount = .infinity
bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
planeLayer.add(bob, forKey: nil)

// ========== 横幅 ==========
func makeBanner(_ text: String) -> CALayer {
    let font = NSFont.systemFont(ofSize: 26, weight: .semibold)
    let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let s = (text as NSString).size(withAttributes: a)
    let pad: CGFloat = 16, bw = s.width + pad*2, bh: CGFloat = 42
    let c = CALayer(); c.frame = CGRect(x: 0, y: 0, width: bw, height: bh)
    let bg = CAShapeLayer()
    bg.path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: bw, height: bh),
                     cornerWidth: 6, cornerHeight: 6, transform: nil)
    bg.fillColor = NSColor.black.withAlphaComponent(0.75).cgColor
    bg.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
    bg.shadowOffset = CGSize(width: 0, height: -2); bg.shadowRadius = 3; bg.shadowOpacity = 1
    c.addSublayer(bg)
    let t = CATextLayer()
    t.string = text; t.font = font; t.fontSize = 26
    t.foregroundColor = NSColor.white.cgColor
    t.alignmentMode = .center; t.contentsScale = sf
    t.frame = CGRect(x: 0, y: (bh - s.height)/2, width: bw, height: s.height)
    c.addSublayer(t)
    return c
}

// ========== 飞行 ==========
let startY = sh * CGFloat.random(in: 0.22...0.50)
let midY1 = startY + CGFloat.random(in: -40...40)
let midY2 = startY + CGFloat.random(in: -30...30)
let endY = startY + CGFloat.random(in: -25...25)
let duration: TimeInterval = 14.0

let pathAnim = CAKeyframeAnimation(keyPath: "position")
pathAnim.duration = duration
pathAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
pathAnim.isRemovedOnCompletion = true; pathAnim.fillMode = .forwards

let path = CGMutablePath()
let half = actualW / 2
path.move(to: CGPoint(x: -half*3, y: startY))
path.addCurve(to: CGPoint(x: sw + half*3, y: endY),
               control1: CGPoint(x: sw*0.35, y: midY1),
               control2: CGPoint(x: sw*0.7, y: midY2))
pathAnim.path = path

let fadeIn = CABasicAnimation(keyPath: "opacity")
fadeIn.fromValue = 0; fadeIn.toValue = 1
fadeIn.duration = 0.3; fadeIn.isRemovedOnCompletion = false; fadeIn.fillMode = .forwards

let fadeOut = CABasicAnimation(keyPath: "opacity")
fadeOut.fromValue = 1; fadeOut.toValue = 0
fadeOut.duration = 0.5; fadeOut.beginTime = duration - 0.5
fadeOut.isRemovedOnCompletion = false; fadeOut.fillMode = .forwards

let group = CAAnimationGroup()
group.animations = [pathAnim, fadeIn, fadeOut]
group.duration = duration
group.isRemovedOnCompletion = true; group.fillMode = .forwards

CATransaction.begin()
CATransaction.setCompletionBlock {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
}
planeLayer.add(group, forKey: "fly")
cv.layer?.addSublayer(planeLayer)

// 横幅
if let msg = message {
    let banner = makeBanner(msg)
    banner.setAffineTransform(CGAffineTransform(scaleX: 1.1, y: 1.1))
    banner.frame = CGRect(x: 40, y: -55, width: banner.frame.width, height: banner.frame.height)
    let bFadeIn = CABasicAnimation(keyPath: "opacity")
    bFadeIn.fromValue = 0; bFadeIn.toValue = 1
    bFadeIn.duration = 0.5; bFadeIn.isRemovedOnCompletion = false; bFadeIn.fillMode = .forwards
    let bFadeOut = CABasicAnimation(keyPath: "opacity")
    bFadeOut.fromValue = 1; bFadeOut.toValue = 0
    bFadeOut.duration = 0.5; bFadeOut.beginTime = duration - 0.5
    bFadeOut.isRemovedOnCompletion = false; bFadeOut.fillMode = .forwards
    let bGroup = CAAnimationGroup()
    bGroup.animations = [bFadeIn, bFadeOut]; bGroup.duration = duration
    bGroup.isRemovedOnCompletion = true; bGroup.fillMode = .forwards
    banner.add(bGroup, forKey: "fade")
    planeLayer.addSublayer(banner)

    // 牵引虚线（飞机到下方横幅）
    let line = CAShapeLayer()
    let lp = CGMutablePath()
    lp.move(to: CGPoint(x: 100, y: 30))
    lp.addLine(to: CGPoint(x: 100, y: -30))
    line.path = lp; line.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
    line.lineWidth = 1; line.lineDashPattern = [3, 3]
    planeLayer.addSublayer(line)
}

CATransaction.commit()

DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1) { NSApp.terminate(nil) }
app.run()
