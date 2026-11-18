import UIKit

/// A Bot's side questions, kept separate from its main chat by the host.
final class SideChatViewController: UIViewController {
    private let botID: String
    private let botName: String
    private let sessionID: String
    private let session: LinkSession
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let field = UITextField()
    private let sendButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let closeChatButton = UIButton(type: .system)
    private var chats: [JSONValue] = []
    private let emptyLabel = UILabel()
    private var openID: String?
    private var entries: [JSONValue] = []
    private var polling: Task<Void, Never>?
    private var busy = false

    init(botID: String, botName: String, sessionID: String, session: LinkSession) {
        self.botID = botID
        self.botName = botName
        self.sessionID = sessionID
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NativeLanguage.text("{name} · Side chat", ["name": botName])
        view.backgroundColor = .systemBackground
        backButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        backButton.accessibilityLabel = NativeLanguage.text("Back")
        backButton.addTarget(self, action: #selector(back), for: .touchUpInside)
        let backIcon = OriginalChevronRightIcon(frame: CGRect(x: 8, y: 8, width: 28, height: 28))
        backIcon.transform = CGAffineTransform(rotationAngle: .pi)
        backIcon.isUserInteractionEnabled = false
        backButton.addSubview(backIcon)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backButton)
        closeChatButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        closeChatButton.accessibilityLabel = NativeLanguage.text("Close side chat")
        closeChatButton.addTarget(self, action: #selector(closeChat), for: .touchUpInside)
        let closeIcon = OriginalCloseIcon(frame: CGRect(x: 8, y: 8, width: 28, height: 28))
        closeIcon.isUserInteractionEnabled = false
        closeChatButton.addSubview(closeIcon)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: closeChatButton)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 90
        view.addSubview(table)
        // side.tsx parks the empty line 30pt below the list top when no chat exists;
        // the composer below is already the way forward.
        emptyLabel.text = NativeLanguage.text("Ask about the work so far")
        emptyLabel.font = TypeScale.small.font
        emptyLabel.textColor = Palette.make(dark: traitCollection.userInterfaceStyle == .dark).ink3
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Glass.margin),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Glass.margin),
        ])
        let composer = UIStackView()
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.axis = .horizontal
        composer.alignment = .center
        composer.spacing = 8
        composer.isLayoutMarginsRelativeArrangement = true
        composer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        view.addSubview(composer)
        field.borderStyle = .roundedRect
        field.placeholder = NativeLanguage.text("Ask about the work so far")
        field.returnKeyType = .send
        field.delegate = self
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        composer.addArrangedSubview(field)
        let arrow = OriginalActionIcon(frame: CGRect(x: 9, y: 9, width: 26, height: 26))
        arrow.isUserInteractionEnabled = false
        sendButton.addSubview(arrow)
        sendButton.accessibilityLabel = NativeLanguage.text("Send side question")
        sendButton.backgroundColor = view.tintColor
        sendButton.layer.cornerRadius = 22
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        sendButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        sendButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        composer.addArrangedSubview(sendButton)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: composer.topAnchor),
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        updateHeader()
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        polling?.cancel()
        polling = nil
    }

    private func startPolling() {
        polling?.cancel()
        polling = Task {
            while !Task.isCancelled {
                await refresh()
                let running = entries.contains { $0["status"]?.stringValue == "answering" }
                try? await Task.sleep(for: .milliseconds(running ? 1_500 : 15_000))
            }
        }
    }

    private func refresh() async {
        guard let state = try? await BotAPI.call("state", payload: .object([
            "since": .number(-1), "avatars": .string("ref"),
        ]), on: session) else { return }
        if case .array(let values)? = state["sideChats"]?[botID] { chats = values } else { chats = [] }
        if let openID,
           let chat = chats.first(where: { $0["chatId"]?.stringValue == openID }),
           case .array(let values)? = chat["entries"] {
            entries = values
        } else {
            if openID != nil && !chats.contains(where: { $0["chatId"]?.stringValue == openID }) {
                self.openID = nil
            }
            entries = []
        }
        updateHeader()
        table.reloadData()
    }

    private func updateHeader() {
        closeChatButton.isHidden = openID == nil
        emptyLabel.isHidden = !chats.isEmpty
    }

    @objc private func back() {
        if openID == nil { dismiss(animated: true) }
        else { showChats() }
    }

    @objc private func showChats() {
        openID = nil
        entries = []
        updateHeader()
        table.reloadData()
    }

    @objc private func closeChat() {
        guard let openID else { return }
        Task {
            do {
                _ = try await BotAPI.call("side-close", payload: .object([
                    "chatId": .string(openID),
                ]), on: session)
                self.openID = nil
                await refresh()
            } catch { showError(error.localizedDescription) }
        }
    }

    @objc private func send() {
        let text = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !busy, !text.isEmpty else { return }
        busy = true
        sendButton.isEnabled = false
        Task {
            do {
                var target = openID
                if target == nil {
                    let created = try await BotAPI.call("side-new", payload: .object([
                        "sessionId": .string(sessionID),
                    ]), on: session)
                    target = created["chatId"]?.stringValue
                    openID = target
                }
                guard let target else { throw NSError(domain: "DSBot", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: NativeLanguage.text("The side chat has no ID.")]) }
                _ = try await BotAPI.call("side-ask", payload: .object([
                    "sessionId": .string(sessionID), "chatId": .string(target),
                    "recent": .bool(true), "text": .string(text),
                ]), on: session)
                field.text = ""
                await refresh()
            } catch { showError(error.localizedDescription) }
            busy = false
            sendButton.isEnabled = true
        }
    }

    private func cancel(_ entry: JSONValue) {
        guard let openID, let entryID = entry["id"]?.stringValue else { return }
        Task {
            do {
                _ = try await BotAPI.call("side-cancel", payload: .object([
                    "chatId": .string(openID), "entryId": .string(entryID),
                ]), on: session)
                await refresh()
            } catch { showError(error.localizedDescription) }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: NativeLanguage.text("Side chat failed"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeLanguage.text("OK"), style: .default))
        present(alert, animated: true)
    }
}

extension SideChatViewController: UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        openID == nil
            ? NativeLanguage.text("Ask about the work so far")
            : NativeLanguage.text("Answered from progress so far; nothing was run")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        openID == nil ? chats.count : entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "side")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "side")
        cell.detailTextLabel?.numberOfLines = 0
        cell.textLabel?.numberOfLines = 0
        if openID == nil {
            let chat = chats[indexPath.row]
            let history: [JSONValue]
            if case .array(let values)? = chat["entries"] { history = values } else { history = [] }
            cell.textLabel?.text = history.last?["question"]?.stringValue ?? NativeLanguage.text("New side chat")
            cell.detailTextLabel?.text = NativeLanguage.text("{count} questions", ["count": String(history.count)])
            cell.accessoryView = OriginalChevronRightIcon(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        } else {
            let entry = entries[indexPath.row]
            cell.textLabel?.text = entry["question"]?.stringValue ?? ""
            let status = entry["status"]?.stringValue
            let detail = status == "answering" ? NativeLanguage.text("Answering…")
                : status == "failed" ? entry["failure"]?.stringValue ?? NativeLanguage.text("The side answer failed.")
                : status == "cancelled" ? NativeLanguage.text("Cancelled") : entry["answer"]?.stringValue ?? ""
            if status != "answering", status != "failed", status != "cancelled",
               let markdown = try? AttributedString(markdown: detail) {
                cell.detailTextLabel?.attributedText = NSAttributedString(markdown)
            } else {
                cell.detailTextLabel?.attributedText = nil
                cell.detailTextLabel?.text = detail
            }
            if status == "answering" {
                let cancelButton = UIButton(type: .system)
                cancelButton.setTitle(NativeLanguage.text("Cancel"), for: .normal)
                cancelButton.accessibilityLabel = NativeLanguage.text("Cancel this side question")
                cancelButton.frame = CGRect(x: 0, y: 0, width: 70, height: 44)
                cancelButton.addAction(UIAction { [weak self] _ in self?.cancel(entry) }, for: .touchUpInside)
                cell.accessoryView = cancelButton
            } else { cell.accessoryView = nil }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard openID == nil else { return }
        openID = chats[indexPath.row]["chatId"]?.stringValue
        entries = []
        updateHeader()
        Task { await refresh() }
    }

    func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard openID != nil, entries[indexPath.row]["status"]?.stringValue == "answering" else { return nil }
        let entry = entries[indexPath.row]
        let action = UIContextualAction(style: .normal, title: NativeLanguage.text("Cancel")) { [weak self] _, _, done in
            self?.cancel(entry)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        send()
        return true
    }
}
