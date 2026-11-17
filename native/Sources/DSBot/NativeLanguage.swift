import Foundation

enum NativeLanguage {
    static let changed = Notification.Name("DSBotLanguageChanged")
    private static let preference = "dsbot.language"
    private static let chinese: [String: String] = {
        guard let url = Bundle.main.url(forResource: "zh", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }()
    private static let nativeChinese: [String: String] = [
        "Pair with your computer to start chatting.": "与电脑配对后开始对话。",
        "Chat": "对话",
        "Main Bots": "主 Bot",
        "Bot capabilities": "Bot 能力",
        "Custom provider": "自定义模型服务商",
        "No Bot yet": "还没有 Bot",
        "Checking computer…": "正在检查电脑…",
        "Offline · reconnecting": "离线 · 正在重连",
        "Offline": "离线",
        "Online": "在线",
        "Needs you": "等你处理",
        "Aside": "侧问",
        "item": "项",
        "items": "项",
        "No providers": "还没有模型服务商",
        "This computer cannot set up model providers": "这台电脑无法配置模型服务商",
        "Provider action failed": "模型服务商操作失败",
        "Connector action failed": "连接器操作失败",
        "Secret action failed": "密钥操作失败",
        "Capability action failed": "能力操作失败",
        "Could not update capabilities": "无法更新能力",
        "No capabilities": "还没有能力",
        "No capabilities in team library": "团队能力库为空",
        "Tap + to add an MCP server, skill, or pack": "点按 + 添加 MCP 服务、技能或能力包",
        "Local command": "本地命令",
        "HTTP server": "HTTP 服务",
        "Connection error": "连接错误",
        "MCP transport": "MCP 连接方式",
        "Edit capability": "编辑能力",
        "Items (comma separated)": "项目（逗号分隔）",
        "Arguments (comma separated)": "参数（逗号分隔）",
        "Environment (JSON object)": "环境变量（JSON 对象）",
        "Headers (JSON object)": "请求头（JSON 对象）",
        "No connectors": "还没有连接器",
        "Paste a token from {name}.": "粘贴来自 {name} 的令牌。",
        "Connected as {name}": "已连接：{name}",
        "Add secret": "添加密钥",
        "Tap + to add a secret": "点按 + 添加密钥",
        "Paste or type the key": "粘贴或输入密钥",
        "Data location": "数据位置",
        "Usage unavailable": "无法获取用量",
        "Install DS Bot update": "安装 DS Bot 更新",
        "Install DSH update": "安装 DSH 更新",
        "Installed · restart DSH": "已安装 · 请重启 DSH",
        "Version {version} available": "有新版本 {version}",
        "Update checks are off": "已关闭更新检查",
        "Update from the local folder": "从本地文件夹更新",
        "Could not load diagnostics": "无法加载诊断信息",
        "Forget {name}?": "忘记 {name}？",
        "this computer": "这台电脑",
    ]

    static var mode: String { UserDefaults.standard.string(forKey: preference) ?? "system" }

    static var isChinese: Bool {
        mode == "zh" || mode == "system"
            && (Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true)
    }

    static func set(_ mode: String) {
        guard ["system", "zh", "en"].contains(mode) else { return }
        UserDefaults.standard.set(mode, forKey: preference)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func text(_ english: String, _ values: [String: String] = [:]) -> String {
        var result = isChinese ? nativeChinese[english] ?? chinese[english] ?? english : english
        for (key, value) in values { result = result.replacingOccurrences(of: "{\(key)}", with: value) }
        return result
    }
}
