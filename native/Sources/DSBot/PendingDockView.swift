import UIKit

/// The open conversation's pending cards, directly above the composer.
final class PendingDockView: UIScrollView {
    typealias Item = PendingActionsViewController.Item

    var onHeightChange: (() -> Void)?
    var onChanged: (() -> Void)?
    var onOpen: ((Item) -> Void)?
    var onError: ((String) -> Void)?

    private let cards = UIStackView()
    private var items: [Item] = []
    private var session: LinkSession?
    private var expandedKey: String?
    private var chosenKey: String?
    private var rows: [String: UIView] = [:]
    private var selected: [String: Set<String>] = [:]
    private var busy = false
    private var language = NativeLanguage.mode

    override init(frame: CGRect) {
        super.init(frame: frame)
        alwaysBounceVertical = false
        showsVerticalScrollIndicator = false
        keyboardDismissMode = .interactive
        cards.axis = .vertical
        cards.spacing = 8
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.isLayoutMarginsRelativeArrangement = true
        cards.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)
        addSubview(cards)
        NSLayoutConstraint.activate([
            cards.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            cards.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            cards.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            cards.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            cards.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ next: [Item], session: LinkSession) -> Bool {
        self.session = session
        guard next != items || language != NativeLanguage.mode else { return false }
        items = next
        language = NativeLanguage.mode
        let keys = next.enumerated().map { key(for: $0.element, index: $0.offset) }
        if !keys.contains(chosenKey ?? "") { chosenKey = nil }
        expandedKey = chosenKey ?? next.enumerated().first { entry in
            if case .aside = entry.element { return false }
            return true
        }.map { key(for: $0.element, index: $0.offset) } ?? keys.first
        cards.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.removeAll()
        for (index, item) in next.enumerated() {
            let key = key(for: item, index: index)
            cards.addArrangedSubview(makeCard(item, key: key))
        }
        return true
    }

    func requiredHeight(width: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return cards.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func key(for item: Item, index: Int) -> String {
        switch item {
        case .question(_, let value): return "question:\(value["id"]?.stringValue ?? String(index))"
        case .approval(let value): return "approval:\(value["id"]?.stringValue ?? String(index))"
        case .secret(let value): return "secret:\(value["id"]?.stringValue ?? String(index))"
        case .handoff(_, let value): return "handoff:\(value["callId"]?.stringValue ?? String(index))"
        case .view(_, let value): return "view:\(value["id"]?.stringValue ?? String(index))"
        case .aside(_, let value): return "aside:\(value["id"]?.stringValue ?? String(index))"
        }
    }

    private func makeCard(_ item: Item, key: String) -> UIView {
        let card = UIStackView()
        card.axis = .vertical
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 26
        card.layer.borderWidth = 0.5
        card.layer.borderColor = UIColor.separator.cgColor
        card.clipsToBounds = true

        let header = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.title = item.title
        configuration.image = UIImage(systemName: "chevron.right")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        header.configuration = configuration
        header.contentHorizontalAlignment = .fill
        header.titleLabel?.numberOfLines = 2
        header.accessibilityValue = expandedKey == key ? NativeLanguage.text("Expanded") : NativeLanguage.text("Collapsed")
        header.addAction(UIAction { [weak self] _ in self?.toggle(key) }, for: .touchUpInside)
        header.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        card.addArrangedSubview(header)

        let body = UIStackView()
        body.axis = .vertical
        body.spacing = 10
        body.isLayoutMarginsRelativeArrangement = true
        body.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 2, leading: 16, bottom: 14, trailing: 16)
        populate(body, item: item, key: key)
        body.isHidden = expandedKey != key
        card.addArrangedSubview(body)
        rows[key] = body
        return card
    }

    private func toggle(_ key: String) {
        chosenKey = chosenKey == key ? nil : key
        expandedKey = chosenKey ?? items.enumerated().first { entry in
            if case .aside = entry.element { return false }
            return true
        }.map { self.key(for: $0.element, index: $0.offset) } ?? items.indices.first.map { self.key(for: items[$0], index: $0) }
        for (rowKey, body) in rows { body.isHidden = rowKey != expandedKey }
        onHeightChange?()
    }

    private func populate(_ body: UIStackView, item: Item, key: String) {
        switch item {
        case .question(let sessionID, let question):
            if let detail = question["detail"]?.stringValue, !detail.isEmpty { body.addArrangedSubview(label(detail)) }
            let options: [String]
            if case .array(let values)? = question["options"] {
                options = values.compactMap { $0["label"]?.stringValue ?? $0.stringValue }
            } else { options = [] }
            let multi = question["multiSelect"] == .bool(true)
            for option in options {
                let button = actionButton(option)
                button.addAction(UIAction { [weak self, weak button] _ in
                    guard let self, let id = question["id"]?.stringValue else { return }
                    if multi {
                        var picked = self.selected[key] ?? []
                        if !picked.insert(option).inserted { picked.remove(option) }
                        self.selected[key] = picked
                        if var configuration = button?.configuration {
                            configuration.title = (picked.contains(option) ? "✓  " : "") + option
                            button?.configuration = configuration
                        }
                    } else {
                        self.answerQuestion(sessionID: sessionID, id: id, options: [option], custom: "")
                    }
                }, for: .touchUpInside)
                body.addArrangedSubview(button)
            }
            if multi || options.isEmpty {
                let field = UITextField()
                field.borderStyle = .roundedRect
                field.placeholder = NativeLanguage.text("Your answer")
                field.returnKeyType = .done
                field.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
                body.addArrangedSubview(field)
                let submit = actionButton(NativeLanguage.text("Submit"), filled: true)
                submit.addAction(UIAction { [weak self, weak field] _ in
                    guard let self, let id = question["id"]?.stringValue else { return }
                    let custom = field?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let picked = options.filter { self.selected[key]?.contains($0) == true }
                    guard !picked.isEmpty || !custom.isEmpty else { return }
                    self.answerQuestion(sessionID: sessionID, id: id, options: picked, custom: custom)
                }, for: .touchUpInside)
                body.addArrangedSubview(submit)
            }
        case .approval(let approval):
            if let detail = approval["detail"]?["text"]?.stringValue { body.addArrangedSubview(label(detail)) }
            if let reason = approval["reason"]?.stringValue, !reason.isEmpty { body.addArrangedSubview(label(reason)) }
            if let code = approval["detail"]?["code"]?.stringValue, !code.isEmpty {
                let snippet = label(code)
                snippet.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                body.addArrangedSubview(snippet)
            }
            if approval["answerable"] == .bool(true), let id = approval["id"]?.stringValue {
                body.addArrangedSubview(actionRow([
                    (NativeLanguage.text("Reject"), { [weak self] in self?.run("approval-answer", ["id": .string(id), "choice": .string("reject")]) }),
                    (NativeLanguage.text("Allow once"), { [weak self] in self?.run("approval-answer", ["id": .string(id), "choice": .string("allow")]) }),
                ]))
            } else { body.addArrangedSubview(label(NativeLanguage.text("Answer on the computer"))) }
        case .secret(let secret):
            guard let id = secret["id"]?.stringValue else { break }
            let allow = secret["kind"]?.stringValue == "allow"
            if allow {
                if let scope = secret["scope"]?.stringValue { body.addArrangedSubview(label(scope)) }
                body.addArrangedSubview(actionRow([
                    (NativeLanguage.text("Cancel"), { [weak self] in self?.run("secret-cancel", ["requestId": .string(id)]) }),
                    (NativeLanguage.text("Allow"), { [weak self] in self?.run("secret-allow", ["requestId": .string(id)]) }),
                ]))
            } else {
                let field = UITextField()
                field.borderStyle = .roundedRect
                field.isSecureTextEntry = true
                field.placeholder = NativeLanguage.text("Value of {name}", ["name": secret["name"]?.stringValue ?? ""])
                field.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
                body.addArrangedSubview(field)
                body.addArrangedSubview(actionRow([
                    (NativeLanguage.text("Cancel"), { [weak self] in self?.run("secret-cancel", ["requestId": .string(id)]) }),
                    (NativeLanguage.text("Save"), { [weak self, weak field] in
                        guard let value = field?.text, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        self?.run("secret-set", ["requestId": .string(id), "value": .string(value)])
                    }),
                ]))
            }
        case .handoff(let botID, let hold):
            if let note = hold["note"]?.stringValue ?? hold["reason"]?.stringValue { body.addArrangedSubview(label(note)) }
            let callID = hold["callId"]?.stringValue ?? ""
            body.addArrangedSubview(actionRow([
                (NativeLanguage.text("Card"), { [weak self] in self?.onOpen?(item) }),
                (NativeLanguage.text("Skip"), { [weak self] in self?.run("browser-give-back", ["botId": .string(botID), "callId": .string(callID), "outcome": .string("skip")]) }),
                (NativeLanguage.text("Done"), { [weak self] in self?.run("browser-give-back", ["botId": .string(botID), "callId": .string(callID), "outcome": .string("done")]) }),
            ]))
        case .view:
            let button = actionButton(NativeLanguage.text("Open and answer this card"), filled: true)
            button.addAction(UIAction { [weak self] _ in self?.onOpen?(item) }, for: .touchUpInside)
            body.addArrangedSubview(button)
        case .aside(let sessionID, let aside):
            if let answer = aside["answer"]?.stringValue ?? aside["failure"]?.stringValue {
                body.addArrangedSubview(label(answer))
            }
            if let id = aside["id"]?.stringValue {
                let button = actionButton(NativeLanguage.text("Dismiss"))
                button.addAction(UIAction { [weak self] _ in
                    self?.run("btw-delete", ["sessionId": .string(sessionID), "cardId": .string(id)])
                }, for: .touchUpInside)
                body.addArrangedSubview(button)
            }
        }
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        return label
    }

    private func actionButton(_ title: String, filled: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
        configuration.title = title
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        return button
    }

    private func actionRow(_ actions: [(String, () -> Void)]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        for (index, action) in actions.enumerated() {
            let button = actionButton(action.0, filled: index == actions.count - 1)
            button.addAction(UIAction { _ in action.1() }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func answerQuestion(sessionID: String, id: String, options: [String], custom: String) {
        run("answer-question", [
            "sessionId": .string(sessionID), "questionId": .string(id),
            "answer": .object(["selected": .array(options.map(JSONValue.string)), "custom": .string(custom)]),
        ])
    }

    private func run(_ endpoint: String, _ values: [String: JSONValue]) {
        guard !busy, let session else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await BotAPI.call(endpoint, payload: .object(values), on: session)
                onChanged?()
            } catch { onError?(error.localizedDescription) }
        }
    }
}
