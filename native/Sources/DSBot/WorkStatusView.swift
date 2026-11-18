import UIKit

struct WorkStatusPresentation {
    let text: String

    init?(target: ChatTarget, state: JSONValue) {
        let doing: JSONValue
        let prefix: String
        if target.kind == .bot {
            guard let value = state["work"]?["bots"]?[target.id] ?? state["activity"]?[target.id], value != .null else { return nil }
            doing = value
            prefix = ""
        } else {
            guard case .array(let work)? = state["work"]?["rooms"]?[target.id], let first = work.first else { return nil }
            doing = first
            let botID = first["botId"]?.stringValue ?? ""
            if case .array(let bots)? = state["bots"] {
                prefix = (bots.first { $0["id"]?.stringValue == botID }?["name"]?.stringValue ?? "") + " · "
            } else { prefix = "" }
        }
        text = prefix + Self.phrase(doing) + "…"
    }

    private static func phrase(_ value: JSONValue) -> String {
        let tool = value.stringValue ?? value["tool"]?.stringValue ?? ""
        if value["switching"] == .bool(true) {
            return NativeLanguage.text(value["folder"] == .bool(true)
                ? "Switching working folder" : "Moving to a fresh conversation")
        }
        let own = (value["said"]?.stringValue ?? value["note"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".。…")))
        if !own.isEmpty { return own }
        if tool.isEmpty { return NativeLanguage.text("Thinking about it") }
        let lower = tool.lowercased()
        let phrase: String
        if lower.contains("search") && lower.contains("web") { phrase = "Searching online" }
        else if ["fetch", "browse", "browser", "web"].contains(where: lower.contains) { phrase = "Reading a page" }
        else if ["shell", "bash", "pwsh", "powershell", "exec", "command", "terminal"].contains(where: lower.contains) { phrase = "Running shell commands" }
        else if ["read", "view", "cat"].contains(where: lower.hasPrefix) { phrase = "Opening a file" }
        else if ["write", "edit", "patch", "create_file"].contains(where: lower.contains) { phrase = "Writing a file" }
        else if ["recall", "memory", "remember"].contains(where: lower.contains) { phrase = "Checking memory" }
        else { phrase = "On it" }
        let target = value["target"]?.stringValue ?? ""
        return target.isEmpty ? NativeLanguage.text(phrase) : "\(NativeLanguage.text(phrase)) · \(target)"
    }
}

final class WorkStatusView: UIStackView {
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .horizontal
        alignment = .center
        spacing = 8
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 20
        addArrangedSubview(indicator)
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        addArrangedSubview(label)
        isHidden = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ presentation: WorkStatusPresentation?) {
        label.text = presentation?.text
        isHidden = presentation == nil
        if presentation == nil { indicator.stopAnimating() } else { indicator.startAnimating() }
    }
}
