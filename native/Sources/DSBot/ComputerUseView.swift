import UIKit

struct ComputerUsePresentation {
    struct Ask: Equatable {
        let id: String
        let appName: String
    }

    let botID: String
    let botName: String
    let asks: [Ask]
    let activeApp: String?
    let isActive: Bool

    init(bot: JSONValue, live: JSONValue?) {
        botID = bot["id"]?.stringValue ?? ""
        botName = bot["name"]?.stringValue ?? ""
        if case .object(let values)? = live?["asks"] {
            asks = values.values.compactMap { ask in
                guard ask["botId"]?.stringValue == botID,
                      let id = ask["id"]?.stringValue else { return nil }
                return Ask(id: id, appName: ask["appName"]?.stringValue ?? "")
            }.sorted { $0.id < $1.id }
        } else { asks = [] }
        let control = live?["bots"]?[botID]
        let state = control?["state"]?.stringValue
        isActive = state != nil && state != "idle"
        activeApp = control?["app"]?.stringValue
    }

    static func answerPayload(id: String, answer: String) -> JSONValue {
        .object(["id": .string(id), "answer": .string(answer)])
    }
}

final class ComputerUseView: UIStackView {
    var onAnswer: ((String, String) -> Void)?
    var onStop: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 8
        isHidden = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ presentation: ComputerUsePresentation?) {
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        guard let presentation, !presentation.asks.isEmpty || presentation.isActive else {
            isHidden = true
            return
        }
        for ask in presentation.asks {
            let card = cardView()
            let label = UILabel()
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.text = NativeLanguage.text("Allow {name} to use {app}?", ["name": presentation.botName, "app": ask.appName])
            card.addArrangedSubview(label)
            let buttons = UIStackView()
            buttons.axis = .horizontal
            buttons.spacing = 8
            for (title, answer) in [("Deny", "deny"), ("This time", "once"), ("Always", "always")] {
                let button = UIButton(type: .system)
                button.setTitle(NativeLanguage.text(title), for: .normal)
                button.addAction(UIAction { [weak self] _ in self?.onAnswer?(ask.id, answer) }, for: .touchUpInside)
                buttons.addArrangedSubview(button)
            }
            card.addArrangedSubview(buttons)
            addArrangedSubview(card)
        }
        if presentation.isActive {
            let card = cardView()
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
            let label = UILabel()
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.text = NativeLanguage.text("Computer use") + (presentation.activeApp.map { " · \($0)" } ?? "")
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(label)
            let stop = UIButton(type: .system)
            stop.setTitle(NativeLanguage.text("Stop"), for: .normal)
            stop.setTitleColor(.systemRed, for: .normal)
            stop.addAction(UIAction { [weak self] _ in self?.onStop?(presentation.botID) }, for: .touchUpInside)
            row.addArrangedSubview(stop)
            card.addArrangedSubview(row)
            addArrangedSubview(card)
        }
        isHidden = false
    }

    private func cardView() -> UIStackView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 8
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.separator.cgColor
        return card
    }
}
