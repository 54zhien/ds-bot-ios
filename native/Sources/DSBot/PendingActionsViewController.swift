import UIKit

/// The phone's actionable question and approval queue for the open chat.
final class PendingActionsViewController: UITableViewController {
    enum Item {
        case question(sessionID: String, value: JSONValue)
        case approval(JSONValue)
        case secret(JSONValue)
        case handoff(botID: String, value: JSONValue)
        case view(sessionID: String, value: JSONValue)

        var title: String {
            switch self {
            case .question(_, let value): return value["question"]?.stringValue ?? "Question"
            case .approval(let value): return value["tool"]?.stringValue ?? "Approval"
            case .secret(let value):
                return value["kind"]?.stringValue == "allow" ? "Allow a secret" : "Secret needed"
            case .handoff: return "Browser handoff"
            case .view(_, let value): return value["title"]?.stringValue ?? "Card"
            }
        }

        var detail: String {
            switch self {
            case .question(_, let value): return value["detail"]?.stringValue ?? "Choose an answer"
            case .approval(let value): return value["reason"]?.stringValue ?? "Allow or reject this request"
            case .secret(let value): return value["name"]?.stringValue ?? "Enter a key or decide on access"
            case .handoff(_, let value):
                return value["note"]?.stringValue ?? value["reason"]?.stringValue ?? "Open the browser"
            case .view: return "Open and answer this card"
            }
        }
    }

    var onChanged: (() -> Void)?
    private let session: LinkSession
    private let items: [Item]

    init(items: [Item], session: LinkSession) {
        self.items = items
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Needs you"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
    }

    @objc private func close() { dismiss(animated: true) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "pending")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "pending")
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.detail
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = .none
        cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        if case .approval(let value) = item, value["answerable"] != .bool(true) {
            cell.detailTextLabel?.text = "Answer on the computer"
            cell.accessoryView = nil
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch items[indexPath.row] {
        case .question(let sessionID, let value):
            let answer = QuestionAnswerViewController(sessionID: sessionID, question: value, session: session)
            answer.onChanged = { [weak self] in self?.onChanged?() }
            navigationController?.pushViewController(answer, animated: true)
        case .approval(let value):
            guard value["answerable"] == .bool(true), let id = value["id"]?.stringValue else { return }
            let sheet = UIAlertController(title: value["tool"]?.stringValue ?? "Approval",
                                          message: value["reason"]?.stringValue, preferredStyle: .actionSheet)
            for choice in ["reject", "allow"] {
                sheet.addAction(UIAlertAction(title: choice == "allow" ? "Allow once" : "Reject",
                                              style: choice == "reject" ? .destructive : .default) { [weak self] _ in
                    self?.submitApproval(id: id, choice: choice)
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            present(sheet, animated: true)
        case .secret(let value):
            showSecret(value)
        case .handoff(let botID, let value):
            let browser = BrowserHandoffViewController(botID: botID, hold: value, session: session)
            browser.onChanged = { [weak self] in self?.onChanged?() }
            navigationController?.pushViewController(browser, animated: true)
        case .view(let sessionID, let value):
            let card = PendingViewController(sessionID: sessionID, record: value, session: session)
            card.onChanged = { [weak self] in self?.onChanged?() }
            navigationController?.pushViewController(card, animated: true)
        }
    }

    private func showSecret(_ value: JSONValue) {
        guard let id = value["id"]?.stringValue else { return }
        let name = value["name"]?.stringValue ?? "key"
        if value["kind"]?.stringValue == "allow" {
            let sheet = UIAlertController(title: "Let the Bot use \(name)?",
                                          message: value["scope"]?.stringValue, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Allow", style: .default) { [weak self] _ in
                self?.submitSecret("secret-allow", id: id)
            })
            sheet.addAction(UIAlertAction(title: "Cancel request", style: .destructive) { [weak self] _ in
                self?.submitSecret("secret-cancel", id: id)
            })
            sheet.addAction(UIAlertAction(title: "Back", style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView
            present(sheet, animated: true)
        } else {
            let alert = UIAlertController(title: "\(name) needs a key", message: nil, preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = "Value of \(name)"
                field.isSecureTextEntry = true
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "Cancel request", style: .destructive) { [weak self] _ in
                self?.submitSecret("secret-cancel", id: id)
            })
            alert.addAction(UIAlertAction(title: "Back", style: .cancel))
            alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
                let entered = alert?.textFields?.first?.text ?? ""
                guard !entered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self?.submitSecret("secret-set", id: id, value: entered)
            })
            present(alert, animated: true)
        }
    }

    private func submitSecret(_ endpoint: String, id: String, value: String? = nil) {
        var payload: [String: JSONValue] = ["requestId": .string(id)]
        if let value { payload["value"] = .string(value) }
        Task {
            do {
                _ = try await BotAPI.call(endpoint, payload: .object(payload), on: session)
                onChanged?()
                dismiss(animated: true)
            } catch { showError(error.localizedDescription) }
        }
    }

    private func submitApproval(id: String, choice: String) {
        Task {
            do {
                _ = try await BotAPI.call("approval-answer", payload: .object([
                    "id": .string(id), "choice": .string(choice),
                ]), on: session)
                onChanged?()
                dismiss(animated: true)
            } catch { showError(error.localizedDescription) }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Could not answer", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private final class QuestionAnswerViewController: UITableViewController {
    var onChanged: (() -> Void)?
    private let sessionID: String
    private let question: JSONValue
    private let session: LinkSession
    private let options: [String]
    private var selected = Set<String>()
    private let custom = UITextField()
    private var busy = false

    init(sessionID: String, question: JSONValue, session: LinkSession) {
        self.sessionID = sessionID
        self.question = question
        self.session = session
        if case .array(let values)? = question["options"] {
            options = values.compactMap { $0["label"]?.stringValue ?? $0.stringValue }
        } else { options = [] }
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Question"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Submit", style: .done, target: self, action: #selector(submit)
        )
        custom.placeholder = "Your answer"
        custom.borderStyle = .roundedRect
        custom.autocorrectionType = .no
        custom.frame = CGRect(x: 16, y: 8, width: tableView.bounds.width - 32, height: 44)
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 60))
        footer.addSubview(custom)
        custom.autoresizingMask = [.flexibleWidth]
        tableView.tableFooterView = footer
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : options.count
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "answer") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "answer")
        if indexPath.section == 0 {
            cell.textLabel?.text = question["question"]?.stringValue ?? "Question"
            cell.detailTextLabel?.text = question["detail"]?.stringValue
            cell.detailTextLabel?.numberOfLines = 0
            cell.selectionStyle = .none
            cell.accessoryType = .none
            cell.accessoryView = nil
        } else {
            let option = options[indexPath.row]
            cell.textLabel?.text = option
            cell.detailTextLabel?.text = nil
            cell.accessoryType = selected.contains(option) ? .checkmark : .none
            cell.accessoryView = nil
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let option = options[indexPath.row]
        if question["multiSelect"] == .bool(true) {
            if !selected.insert(option).inserted { selected.remove(option) }
        } else { selected = [option] }
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }

    @objc private func submit() {
        guard !busy, let id = question["id"]?.stringValue else { return }
        let answer = custom.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !selected.isEmpty || !answer.isEmpty else { return }
        busy = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task {
            do {
                _ = try await BotAPI.call("answer-question", payload: .object([
                    "sessionId": .string(sessionID), "questionId": .string(id),
                    "answer": .object(["selected": .array(options.filter { selected.contains($0) }.map(JSONValue.string)),
                                       "custom": .string(answer)]),
                ]), on: session)
                onChanged?()
                navigationController?.dismiss(animated: true)
            } catch {
                busy = false
                navigationItem.rightBarButtonItem?.isEnabled = true
                let alert = UIAlertController(title: "Could not answer", message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }
}
