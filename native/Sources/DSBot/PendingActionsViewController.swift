import UIKit

/// The phone's actionable question and approval queue for the open chat.
final class PendingActionsViewController: UITableViewController {
    enum Item {
        case question(sessionID: String, value: JSONValue)
        case approval(JSONValue)

        var title: String {
            switch self {
            case .question(_, let value): return value["question"]?.stringValue ?? "Question"
            case .approval(let value): return value["tool"]?.stringValue ?? "Approval"
            }
        }

        var detail: String {
            switch self {
            case .question(_, let value): return value["detail"]?.stringValue ?? "Choose an answer"
            case .approval(let value): return value["reason"]?.stringValue ?? "Allow or reject this request"
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
