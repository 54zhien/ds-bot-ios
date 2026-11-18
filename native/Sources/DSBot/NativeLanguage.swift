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
        "Secret needed": "需要密钥",
        "Choose an answer": "选择答案",
        "Allow or reject this request": "允许或拒绝此请求",
        "Enter a key or decide on access": "输入密钥或决定是否授权",
        "Open the browser": "打开浏览器",
        "Open and answer this card": "打开并回答此卡片",
        "Waiting for an answer": "等待回答",
        "Let the Bot use {name}?": "允许 Bot 使用 {name}？",
        "Could not answer": "无法提交回答",
        "Expanded": "已展开",
        "Collapsed": "已收起",
        "Provider ID": "服务商 ID",
        "Provider name": "服务商名称",
        "API base URL": "API 基础地址",
        "Manual model IDs": "手动输入模型 ID",
        "Model IDs, comma separated": "模型 ID（逗号分隔）",
        "Finding models…": "正在查找模型…",
        "Find models": "查找模型",
        "API protocol": "API 协议",
        "Could not find models": "无法查找模型",
        "Could not add provider": "无法添加服务商",
        "Missing details": "缺少必要信息",
        "Provider ID, API URL and at least one model are required.": "需要服务商 ID、API 地址和至少一个模型。",
        "Choose at least one weekday.": "至少选择一个星期日期。",
        "Enter a positive repeat interval.": "输入大于零的重复间隔。",
        "Hidden": "已隐藏",
        "Visible": "已显示",
        "OK": "好",
        "Open photo": "打开照片",
        "The computer could not load this chat.": "这台电脑无法加载此对话。",
        "Tool": "工具",
        "Not paired": "未配对",
        "Copy diagnostics": "复制诊断信息",
        "Save diagnostics": "保存诊断信息",
        "The dump could not be written.": "诊断信息写入失败。",
        "Diagnostics saved": "诊断信息已保存",
        "Copy path": "复制路径",
        "Could not complete the action": "操作未能完成",
        "Message not sent": "消息未发出",
        "Could not connect": "无法连接",
        "Connect {name}": "连接 {name}",
        "Token": "令牌",
        "Scan pairing code": "扫描配对码",
        "Point the camera at the QR code in DS Bot → Settings → Phone.": "把摄像头对准 DS Bot → 设置 → 手机 中显示的二维码。",
        "Camera access is off. Paste the pairing link instead.": "相机权限已关闭，请改为粘贴配对链接。",
        "The camera is unavailable. Paste the pairing link instead.": "相机不可用，请改为粘贴配对链接。",
        "QR scanning is unavailable. Paste the pairing link instead.": "无法扫码，请改为粘贴配对链接。",
        "Pair with computer": "与电脑配对",
        "On your computer, open DS Bot → Settings → Phone, then copy the pairing link.": "在电脑上打开 DS Bot → 设置 → 手机，复制配对链接。",
        "Scan QR code": "扫描二维码",
        "Waiting for computer…": "正在等待电脑…",
        "Could not connect. Check the link and try again.": "无法连接，请检查链接后重试。",
        "Answer on the computer": "在电脑上回答",
        "Cancel request": "取消请求",
        "Card action failed": "卡片操作失败",
        "Add custom provider": "添加自定义服务商",
        "API URL and model IDs": "API 地址和模型 ID",
        "Replace API key": "替换 API 密钥",
        "Set API key": "设置 API 密钥",
        "Paste API key": "粘贴 API 密钥",
        "Enter an API key if you have one.": "有 API 密钥就填进来。",
        "Bots using this provider need another model.": "使用这个服务商的 Bot 需要换一个模型。",
        "Task": "任务",
        "Latest dump": "最新诊断文件",
        "None yet": "暂无",
        "Diagnostics folder": "诊断文件夹",
        "Installing…": "正在安装…",
        "Update failed": "更新失败",
        "There is no dump yet. Long-press the chat title to save one.": "还没有诊断文件。长按聊天标题即可保存一份。",
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

    /// Whether a key has a Chinese entry, whichever table carries it. The guard test asks
    /// this so a call site cannot reach the screen without a translation.
    static func hasEntry(_ key: String) -> Bool {
        nativeChinese[key] != nil || chinese[key] != nil
    }

    /// The keys written in this file, for the other half of the guard: entries nothing uses.
    static var nativeKeys: Set<String> { Set(nativeChinese.keys) }

    static func text(_ english: String, _ values: [String: String] = [:]) -> String {
        var result = isChinese ? nativeChinese[english] ?? chinese[english] ?? english : english
        for (key, value) in values { result = result.replacingOccurrences(of: "{\(key)}", with: value) }
        return result
    }
}
