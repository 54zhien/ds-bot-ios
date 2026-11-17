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
