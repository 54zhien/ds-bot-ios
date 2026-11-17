import UIKit

final class MemoryViewController: UITableViewController {
    enum Owner {
        case bot(String)
        case room(String)

        var payload: [String: JSONValue] {
            switch self {
            case .bot(let id): return ["botId": .string(id)]
            case .room(let id): return ["roomId": .string(id)]
            }
        }
    }

    private let owner: Owner
    private let session: LinkSession
    private var entries: [JSONValue] = []
    private var summary: String?
    private var loaded = false

    init(owner: Owner, session: LinkSession) {
        self.owner = owner
        self.session = session
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Memory"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(add)
        )
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        Task { await load() }
    }

    @objc private func refresh() { Task { await load() } }

    private func load() async {
        do {
            let result = try await BotAPI.call("memory-view", payload: .object(owner.payload), on: session)
            if case .array(let values)? = result["entries"] { entries = values } else { entries = [] }
            summary = result["summary"]?["text"]?.stringValue ?? result["summary"]?.stringValue
            loaded = true
            tableView.reloadData()
        } catch { showError(error.localizedDescription) }
        refreshControl?.endRefreshing()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Memory" : "\(entries.count) entries"
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 2 : max(1, entries.count)
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "memory")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "memory")
        cell.accessoryView = nil
        cell.detailTextLabel?.numberOfLines = 0
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            cell.textLabel?.text = "Summary"
            cell.detailTextLabel?.text = summary ?? "—"
            cell.selectionStyle = .none
        case (0, 1):
            cell.textLabel?.text = "Ask memory"
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .default
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        default:
            if entries.isEmpty {
                cell.textLabel?.text = loaded ? "Nothing saved yet" : "Loading…"
                cell.detailTextLabel?.text = nil
                cell.selectionStyle = .none
            } else {
                let entry = entries[indexPath.row]
                cell.textLabel?.text = entry["topic"]?.stringValue ?? "Memory"
                cell.detailTextLabel?.text = entry["text"]?.stringValue
                cell.selectionStyle = .default
                cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 && indexPath.row == 1 { ask() }
        else if indexPath.section == 1 && entries.indices.contains(indexPath.row) {
            openEditor(entry: entries[indexPath.row])
        }
    }

    override func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 && entries.indices.contains(indexPath.row) else { return nil }
        let entry = entries[indexPath.row]
        let action = UIContextualAction(style: .destructive, title: "Remove") { [weak self] _, _, done in
            self?.confirmForget(entry)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func add() { openEditor(entry: nil) }

    private func openEditor(entry: JSONValue?) {
        let editor = MemoryEntryEditorViewController(owner: owner, entry: entry, session: session)
        editor.onSaved = { [weak self] in Task { await self?.load() } }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func ask() {
        let alert = UIAlertController(title: "Ask memory", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Question" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Ask", style: .default) { [weak self, weak alert] _ in
            guard let self, let question = alert?.textFields?.first?.text,
                  !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            var payload = self.owner.payload
            payload["text"] = .string(question)
            Task {
                do {
                    let result = try await BotAPI.call("memory-ask", payload: .object(payload), on: self.session)
                    let answer = UIAlertController(title: "Memory", message: result["reply"]?.stringValue ?? "",
                                                   preferredStyle: .alert)
                    answer.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(answer, animated: true)
                    await self.load()
                } catch { self.showError(error.localizedDescription) }
            }
        })
        present(alert, animated: true)
    }

    private func confirmForget(_ entry: JSONValue) {
        let alert = UIAlertController(title: "Remove from memory?", message: entry["text"]?.stringValue,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self else { return }
            var payload = self.owner.payload
            payload["scope"] = entry["scope"] ?? .string("own")
            payload["topic"] = entry["topic"] ?? .null
            payload["text"] = entry["text"] ?? .string("")
            Task {
                do {
                    _ = try await BotAPI.call("memory-forget", payload: .object(payload), on: self.session)
                    await self.load()
                } catch { self.showError(error.localizedDescription) }
            }
        })
        present(alert, animated: true)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Memory unavailable", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

private final class MemoryEntryEditorViewController: UIViewController {
    var onSaved: (() -> Void)?
    private let owner: MemoryViewController.Owner
    private let entry: JSONValue?
    private let session: LinkSession
    private let topic = UITextField()
    private let text = UITextView()

    init(owner: MemoryViewController.Owner, entry: JSONValue?, session: LinkSession) {
        self.owner = owner
        self.entry = entry
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = entry == nil ? "Add memory" : "Edit memory"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done,
                                                            target: self, action: #selector(save))
        topic.translatesAutoresizingMaskIntoConstraints = false
        topic.borderStyle = .roundedRect
        topic.placeholder = "Topic"
        topic.text = entry?["topic"]?.stringValue
        view.addSubview(topic)
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .preferredFont(forTextStyle: .body)
        text.layer.borderWidth = 1
        text.layer.borderColor = UIColor.separator.cgColor
        text.layer.cornerRadius = 12
        text.text = entry?["text"]?.stringValue
        view.addSubview(text)
        NSLayoutConstraint.activate([
            topic.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            topic.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            topic.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            topic.heightAnchor.constraint(equalToConstant: 44),
            text.topAnchor.constraint(equalTo: topic.bottomAnchor, constant: 12),
            text.leadingAnchor.constraint(equalTo: topic.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: topic.trailingAnchor),
            text.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
        ])
    }

    @objc private func save() {
        let content = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        var payload = owner.payload
        payload["scope"] = entry?["scope"] ?? .string("own")
        let topicText = topic.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        payload["topic"] = topicText.isEmpty ? .null : .string(topicText)
        if let entry {
            payload["text"] = entry["text"] ?? .string("")
            payload["next"] = .string(content)
        } else { payload["text"] = .string(content) }
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task {
            do {
                _ = try await BotAPI.call(entry == nil ? "memory-add" : "memory-edit",
                                          payload: .object(payload), on: session)
                onSaved?()
                navigationController?.popViewController(animated: true)
            } catch {
                navigationItem.rightBarButtonItem?.isEnabled = true
                let alert = UIAlertController(title: "Could not save memory", message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }
}
