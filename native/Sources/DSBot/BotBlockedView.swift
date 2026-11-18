import UIKit

enum BotBlockedAction: Equatable {
    case providers
    case topUp
    case model
}

struct BotBlockedPresentation {
    let message: String
    let actions: [BotBlockedAction]
    let missingKey: Bool

    init(bot: JSONValue, models: [JSONValue]) {
        let blocked = bot["blocked"]
        let code = blocked?["code"]?.stringValue ?? ""
        let name = bot["name"]?.stringValue ?? ""
        let providerID = blocked?["provider"]?.stringValue ?? ""
        let provider = models.first {
            $0["ref"]?.stringValue?.split(separator: "/").first.map(String.init) == providerID
        }?["providerName"]?.stringValue ?? providerID
        let status = blocked?["status"]?.intValue
        switch code {
        case "MISSING_CREDENTIAL":
            message = NativeLanguage.text("{name}'s model has no API key yet.", ["name": name])
        case "INVALID_CREDENTIAL":
            message = NativeLanguage.text("This API key is not in the right format.")
        case "AUTH":
            message = NativeLanguage.text(status == nil
                ? "{provider} did not accept the current API key."
                : "{provider} did not accept the current API key ({status}).",
                ["provider": provider, "status": status.map { String($0) } ?? ""])
        case "QUOTA":
            message = NativeLanguage.text(status == nil
                ? "{provider} is out of balance or quota."
                : "{provider} is out of balance or quota ({status}).",
                ["provider": provider, "status": status.map { String($0) } ?? ""])
        case "ACCOUNT_QUOTA":
            message = NativeLanguage.text("The DeepSeek account balance is too low.")
        case "ACCOUNT_SIGN_IN_REQUIRED", "ACCOUNT_SIGNED_OUT", "ACCOUNT_TOKEN_INVALID":
            message = NativeLanguage.text("The DeepSeek account sign-in has expired.")
        default:
            message = NativeLanguage.text("This turn failed.")
        }
        missingKey = code == "MISSING_CREDENTIAL"
        var repairs: [BotBlockedAction] = []
        if ["MISSING_CREDENTIAL", "INVALID_CREDENTIAL", "AUTH"].contains(code) { repairs.append(.providers) }
        if code == "ACCOUNT_QUOTA" || code == "QUOTA" && providerID == "deepseek-official" {
            repairs.append(.topUp)
        }
        repairs.append(.model)
        actions = repairs
    }
}

final class BotBlockedView: UIStackView {
    var onAction: ((BotBlockedAction) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 8
        isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        backgroundColor = .secondarySystemBackground
        isHidden = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ presentation: BotBlockedPresentation?) {
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        guard let presentation else { isHidden = true; return }
        let message = UILabel()
        message.numberOfLines = 0
        message.font = .preferredFont(forTextStyle: .subheadline)
        message.text = presentation.message
        addArrangedSubview(message)
        let actions = UIStackView()
        actions.axis = .horizontal
        actions.spacing = 8
        actions.distribution = .fillProportionally
        for action in presentation.actions {
            let button = UIButton(type: .system)
            let title: String
            switch action {
            case .providers: title = presentation.missingKey ? "Enter API key" : "Enter the key again"
            case .topUp: title = "Top up ↗"
            case .model: title = "Pick another model"
            }
            button.setTitle(NativeLanguage.text(title), for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
            button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
            actions.addArrangedSubview(button)
        }
        addArrangedSubview(actions)
        isHidden = false
        accessibilityLabel = presentation.message
    }
}
