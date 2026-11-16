import UIKit

/// N1 chat shell. Messages and composer behaviour arrive in later steps.
final class ChatViewController: UIViewController {
    private let list = UITableView(frame: .zero, style: .plain)
    private let emptyState = UILabel()
    private let composer = NativeComposerView()
    private var composerHeight: NSLayoutConstraint!
    private let statusBar = UIStackView()
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let pairingStore = PairingStore()
    private var session = LinkSession()
    private var sessionID = UUID()
    private var savedOffer: PairingOffer?
    private var pendingOffer: PairingOffer?
    private var rows: [ChatRow] = []
    private var olderRows: [ChatRow] = []
    private var latestRows: [ChatRow] = []
    private var cursor: JSONValue?
    private var chatSessionID: String?
    private var botID: String?
    private var roomID: String?
    private var selectedTarget: ChatTarget?
    private var teamState: JSONValue?
    private var polling: Task<Void, Never>?
    private var loadingOlder = false
    private var readingLatest = false
    private var readAgain = false
    private var linkStatus: LinkSession.Status = .disconnected

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chat"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Pair", style: .plain, target: self, action: #selector(showPairing)
        )
        let teamButton = UIButton(type: .system)
        teamButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        teamButton.accessibilityLabel = "Team"
        teamButton.addTarget(self, action: #selector(showTeam), for: .touchUpInside)
        let teamIcon = OriginalSidebarIcon(frame: CGRect(x: 9, y: 9, width: 26, height: 26))
        teamIcon.isUserInteractionEnabled = false
        teamIcon.backgroundColor = .clear
        teamButton.addSubview(teamIcon)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: teamButton)
        configureStatusBar()
        configureList()
        configureComposer()
        savedOffer = pairingStore.load()
        navigationItem.rightBarButtonItem?.title = savedOffer == nil ? "Pair" : "Computers"
        updateEmptyState()
        if let savedOffer { connect(to: savedOffer, pairingCode: nil) }
    }

    private func configureStatusBar() {
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.axis = .horizontal
        statusBar.alignment = .center
        statusBar.spacing = 12
        statusBar.isLayoutMarginsRelativeArrangement = true
        statusBar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        statusBar.backgroundColor = .secondarySystemBackground
        view.addSubview(statusBar)
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabel
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusBar.addArrangedSubview(statusLabel)
        retryButton.setTitle("Retry", for: .normal)
        retryButton.addTarget(self, action: #selector(retryConnection), for: .touchUpInside)
        statusBar.addArrangedSubview(retryButton)
        retryButton.isHidden = true
        statusLabel.text = "Not paired"
        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func configureList() {
        list.translatesAutoresizingMaskIntoConstraints = false
        list.dataSource = self
        list.delegate = self
        list.separatorStyle = .none
        list.contentInset.bottom = 76
        list.estimatedRowHeight = 88
        list.rowHeight = UITableView.automaticDimension
        list.register(ChatMessageCell.self, forCellReuseIdentifier: "row")
        view.addSubview(list)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.textColor = .secondaryLabel
        emptyState.textAlignment = .center
        emptyState.numberOfLines = 0
        emptyState.font = .preferredFont(forTextStyle: .subheadline)
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: statusBar.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyState.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func updateEmptyState() {
        emptyState.text = savedOffer == nil
            ? "Pair with your computer to start chatting."
            : botID == nil && roomID == nil ? "No Bot yet" : rows.isEmpty ? "No messages yet" : nil
        emptyState.isHidden = rows.count > 0
    }

    private func connect(to offer: PairingOffer, pairingCode: String?) {
        let oldSession = session
        let nextSession = LinkSession()
        session = nextSession
        let id = UUID()
        sessionID = id
        linkStatus = .connecting
        composer.canSend = false
        composer.running = false
        polling?.cancel()
        polling = nil
        botID = nil
        roomID = nil
        selectedTarget = nil
        teamState = nil
        chatSessionID = nil
        olderRows = []
        latestRows = []
        rows = []
        cursor = nil
        list.reloadData()
        updateEmptyState()
        statusLabel.text = "Connecting…"
        retryButton.isHidden = true
        let phone = PhoneIdentityStore.loadOrCreate()
        let pairing = LinkSession.Pairing(
            serverURL: offer.serverURL,
            hostDeviceId: offer.hostDeviceId,
            hostPublicKey: offer.hostKey,
            identity: SecureTransport.Identity(
                deviceId: phone.deviceId, publicKey: phone.publicKey, privateKey: phone.privateKey
            ),
            accessToken: phone.accessToken,
            pairingCode: pairingCode
        )
        Task {
            await oldSession.disconnect()
            await nextSession.setStatusHandler { [weak self] status in
                Task { @MainActor [weak self] in self?.showStatus(status, for: id) }
            }
            await nextSession.setEventHandler { [weak self] event, data in
                Task { @MainActor [weak self] in self?.handleFeed(event, data: data, for: id) }
            }
            await nextSession.connect(pairing)
        }
    }

    private func handleFeed(_ event: String, data: JSONValue, for id: UUID) {
        guard id == sessionID, linkStatus == .online else { return }
        if event == "revision" || event == "live"
            || (event == "message" && data["sessionId"]?.stringValue == chatSessionID)
            || (event == "room" && data["roomId"]?.stringValue == roomID) {
            Task { await refreshLatest(for: id) }
        }
    }

    private func showStatus(_ status: LinkSession.Status, for id: UUID) {
        guard id == sessionID else { return }
        linkStatus = status
        let pairingSheet = (presentedViewController as? UINavigationController)?
            .topViewController as? PairingViewController
        pairingSheet?.showStatus(status)
        switch status {
        case .connecting:
            statusLabel.text = "Connecting…"
            retryButton.isHidden = true
        case .online:
            statusLabel.text = "Online"
            retryButton.isHidden = true
            if let pendingOffer {
                pairingStore.save(pendingOffer)
                savedOffer = pendingOffer
                self.pendingOffer = nil
                navigationItem.rightBarButtonItem?.title = "Computers"
                updateEmptyState()
                presentedViewController?.dismiss(animated: true)
            }
            startPolling(for: id)
        case .offline:
            statusLabel.text = "Offline · reconnecting"
            retryButton.isHidden = true
            composer.canSend = false
            composer.running = false
            polling?.cancel()
            polling = nil
        case .disconnected:
            statusLabel.text = savedOffer == nil && pendingOffer == nil ? "Not paired" : "Offline"
            retryButton.isHidden = savedOffer == nil && pendingOffer == nil
            composer.canSend = false
            composer.running = false
            polling?.cancel()
            polling = nil
        }
    }

    private func startPolling(for id: UUID) {
        polling?.cancel()
        polling = Task {
            while !Task.isCancelled && id == sessionID {
                await refreshLatest(for: id)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func refreshLatest(for id: UUID) async {
        guard id == sessionID, linkStatus == .online else { return }
        if readingLatest {
            readAgain = true
            return
        }
        readingLatest = true
        defer {
            readingLatest = false
            if readAgain {
                readAgain = false
                Task { await refreshLatest(for: id) }
            }
        }
        do {
            let state = try await BotAPI.call("state", on: session)
            guard id == sessionID, linkStatus == .online else { return }
            teamState = state
            let selected = state["mainBotId"]?.stringValue
            let bots: [JSONValue]
            if case .array(let values)? = state["bots"] { bots = values } else { bots = [] }
            let rooms: [JSONValue]
            if case .array(let values)? = state["rooms"] { rooms = values } else { rooms = [] }
            let chosen: JSONValue?
            let target: ChatTarget?
            if let selectedTarget,
               let item = (selectedTarget.kind == .bot ? bots : rooms)
                    .first(where: { $0["id"]?.stringValue == selectedTarget.id }) {
                chosen = item
                target = selectedTarget
            } else if let item = bots.first(where: { $0["id"]?.stringValue == selected }) ?? bots.first,
                      let botID = item["id"]?.stringValue {
                chosen = item
                target = ChatTarget(kind: .bot, id: botID, name: item["name"]?.stringValue ?? botID)
            } else {
                chosen = nil
                target = nil
            }
            guard let target else {
                botID = nil
                roomID = nil
                rows = []
                list.reloadData()
                emptyState.text = "No Bot yet"
                emptyState.isHidden = false
                return
            }
            if botID != (target.kind == .bot ? target.id : nil)
                || roomID != (target.kind == .room ? target.id : nil) {
                botID = target.kind == .bot ? target.id : nil
                roomID = target.kind == .room ? target.id : nil
                title = chosen?["name"]?.stringValue ?? target.name
                chatSessionID = nil
                olderRows = []
                cursor = nil
            }
            composer.canSend = true
            if target.kind == .bot {
                let work = state["work"]?["bots"]?[target.id]
                let activity = state["activity"]?[target.id]
                composer.running = (work != nil && work != .null) || (activity != nil && activity != .null)
            } else if case .array(let work)? = state["work"]?["rooms"]?[target.id] {
                composer.running = !work.isEmpty
            } else {
                composer.running = false
            }
            let endpoint = target.kind == .bot ? "chat" : "room-chat"
            let parameter = target.kind == .bot ? "botId" : "roomId"
            let value = try await BotAPI.call(endpoint, payload: .object([
                parameter: .string(target.id), "steps": .bool(false),
            ]), on: session)
            guard id == sessionID, linkStatus == .online,
                  botID == (target.kind == .bot ? target.id : nil),
                  roomID == (target.kind == .room ? target.id : nil) else { return }
            let page = ChatPage(value)
            let nearBottom = list.contentSize.height - list.contentOffset.y - list.bounds.height < 120
            let nextSessionID = page.sessionID ?? target.id
            if chatSessionID != nextSessionID {
                olderRows = []
                cursor = page.cursor
            } else if cursor == nil {
                cursor = page.cursor
            }
            chatSessionID = nextSessionID
            latestRows = page.items
            rows = olderRows + latestRows
            list.reloadData()
            updateEmptyState()
            if nearBottom && !rows.isEmpty {
                list.layoutIfNeeded()
                list.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: false)
            }
        } catch {
            guard id == sessionID else { return }
            if rows.isEmpty {
                emptyState.text = error.localizedDescription
                emptyState.isHidden = false
            }
        }
    }

    private func loadOlder() {
        guard linkStatus == .online, !loadingOlder, let cursor, cursor != .null else { return }
        let targetID = botID ?? roomID
        guard let targetID else { return }
        let isRoom = roomID != nil
        let parameter = isRoom ? "roomId" : "botId"
        loadingOlder = true
        let id = sessionID
        let oldHeight = list.contentSize.height
        let oldOffset = list.contentOffset.y
        Task {
            defer { loadingOlder = false }
            do {
                let value = try await BotAPI.call(isRoom ? "room-chat" : "chat", payload: .object([
                    parameter: .string(targetID),
                    "cursor": cursor, "steps": .bool(false),
                ]), on: session)
                guard id == sessionID, linkStatus == .online,
                      (isRoom ? roomID : botID) == targetID else { return }
                let page = ChatPage(value)
                self.cursor = page.cursor
                olderRows.insert(contentsOf: page.items, at: 0)
                rows = olderRows + latestRows
                list.reloadData()
                list.layoutIfNeeded()
                list.contentOffset.y = oldOffset + list.contentSize.height - oldHeight
                updateEmptyState()
            } catch {
                // The next upward scroll can request the same page again.
            }
        }
    }

    @objc private func retryConnection() {
        if let offer = pendingOffer ?? savedOffer {
            connect(to: offer, pairingCode: pendingOffer == nil ? nil : offer.code)
        }
    }

    @objc private func showPairing() {
        if savedOffer != nil {
            let computers = ComputersViewController(store: pairingStore)
            computers.onAdd = { [weak self] in self?.presentPairingSheet() }
            computers.onSwitch = { [weak self] offer in
                guard let self else { return }
                savedOffer = offer
                connect(to: offer, pairingCode: nil)
            }
            computers.onForget = { [weak self] forgottenID in
                guard let self, savedOffer?.hostDeviceId == forgottenID else { return }
                savedOffer = pairingStore.load()
                if let savedOffer {
                    connect(to: savedOffer, pairingCode: nil)
                } else {
                    let old = session
                    session = LinkSession()
                    sessionID = UUID()
                    polling?.cancel()
                    polling = nil
                    linkStatus = .disconnected
                    composer.canSend = false
                    composer.running = false
                    botID = nil
                    roomID = nil
                    selectedTarget = nil
                    teamState = nil
                    chatSessionID = nil
                    cursor = nil
                    olderRows = []
                    latestRows = []
                    rows = []
                    list.reloadData()
                    updateEmptyState()
                    statusLabel.text = "Not paired"
                    navigationItem.rightBarButtonItem?.title = "Pair"
                    Task { await old.disconnect() }
                }
            }
            present(UINavigationController(rootViewController: computers), animated: true)
            return
        }
        presentPairingSheet()
    }

    private func presentPairingSheet() {
        let sheet = PairingViewController()
        sheet.onPair = { [weak self] offer in
            guard let self else { return }
            self.pendingOffer = offer
            self.connect(to: offer, pairingCode: offer.code)
        }
        present(UINavigationController(rootViewController: sheet), animated: true)
    }

    @objc private func showTeam() {
        guard let teamState else { return }
        let team = TeamListViewController(state: teamState)
        team.onSelect = { [weak self] target in self?.selectTarget(target) }
        present(UINavigationController(rootViewController: team), animated: true)
    }

    private func selectTarget(_ target: ChatTarget) {
        guard selectedTarget != target else { return }
        selectedTarget = target
        botID = nil
        roomID = nil
        chatSessionID = nil
        olderRows = []
        latestRows = []
        rows = []
        cursor = nil
        title = target.name
        list.reloadData()
        updateEmptyState()
        Task { await refreshLatest(for: sessionID) }
    }

    /// The resting capsule's height, so step 4 can grow it in place.
    private func configureComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composerHeight = composer.heightAnchor.constraint(equalToConstant: 62)
        composer.onHeightChange = { [weak self] height in
            guard let self else { return }
            composerHeight.constant = height
            list.contentInset.bottom = height + 14
            UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
        }
        composer.onSend = { [weak self] text in self?.sendMessage(text) }
        composer.onStop = { [weak self] in self?.stopChat() }
        view.addSubview(composer)
        if #available(iOS 17.0, *) {
            view.keyboardLayoutGuide.usesBottomSafeArea = true
        }
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            composerHeight,
        ])
    }

    private func sendMessage(_ text: String) {
        guard linkStatus == .online, let sessionID = chatSessionID ?? botID else {
            composer.restoreDraft(text)
            return
        }
        let id = self.sessionID
        Task {
            do {
                _ = try await BotAPI.call("send", payload: .object([
                    "sessionId": .string(sessionID), "text": .string(text),
                ]), on: session)
                await refreshLatest(for: id)
            } catch {
                guard id == self.sessionID else { return }
                composer.restoreDraft(text)
                showActionError(error.localizedDescription)
            }
        }
    }

    private func stopChat() {
        guard linkStatus == .online, let targetID = botID ?? roomID else { return }
        let isRoom = roomID != nil
        let parameter = isRoom ? "roomId" : "botId"
        Task {
            do {
                _ = try await BotAPI.call(isRoom ? "stop-room-work" : "stop-chat", payload: .object([
                    parameter: .string(targetID),
                ]), on: session)
                await refreshLatest(for: sessionID)
            } catch {
                showActionError(error.localizedDescription)
            }
        }
    }

    private func showActionError(_ message: String) {
        let alert = UIAlertController(title: "Could not complete the action", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! ChatMessageCell
        cell.configure(rows[indexPath.row])
        return cell
    }
}

extension ChatViewController: UITableViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if (scrollView.isDragging || scrollView.isDecelerating) && scrollView.contentOffset.y < 100 {
            loadOlder()
        }
    }
}

private final class ChatMessageCell: UITableViewCell {
    private let bubble = UIView()
    private let authorLabel = UILabel()
    private let messageLabel = UILabel()
    private let timeLabel = UILabel()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private var centered: NSLayoutConstraint!
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer.cornerRadius = 18
        contentView.addSubview(bubble)
        authorLabel.font = .preferredFont(forTextStyle: .caption1)
        authorLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.numberOfLines = 0
        timeLabel.font = .preferredFont(forTextStyle: .caption2)
        timeLabel.textColor = .tertiaryLabel
        let text = UIStackView(arrangedSubviews: [authorLabel, messageLabel, timeLabel])
        text.translatesAutoresizingMaskIntoConstraints = false
        text.axis = .vertical
        text.spacing = 4
        bubble.addSubview(text)
        leading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        centered = bubble.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.86),
            text.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            text.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            text.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ row: ChatRow) {
        leading.isActive = false
        trailing.isActive = false
        centered.isActive = false
        if row.isNotice {
            centered.isActive = true
        } else if row.isUser {
            trailing.isActive = true
        } else {
            leading.isActive = true
        }
        bubble.backgroundColor = row.isNotice ? .clear
            : row.isUser ? tintColor.withAlphaComponent(0.12) : .secondarySystemBackground
        authorLabel.isHidden = row.isNotice
        authorLabel.text = row.author
        messageLabel.text = row.text
        messageLabel.textAlignment = row.isNotice ? .center : .left
        messageLabel.textColor = row.isNotice ? .secondaryLabel : .label
        timeLabel.text = row.time.map { Self.clock.string(from: $0) }
        timeLabel.isHidden = row.time == nil || row.isNotice
        accessibilityLabel = [row.author, row.text].joined(separator: ": ")
    }
}

private final class PairingViewController: UIViewController {
    var onPair: ((PairingOffer) -> Void)?
    private let field = UITextField()
    private let errorLabel = UILabel()
    private let progressLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pair with computer"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Connect", style: .done, target: self, action: #selector(submit)
        )
        let instructions = UILabel()
        instructions.text = "On your computer, open DS Bot → Settings → Phone, then copy the pairing link."
        instructions.numberOfLines = 0
        instructions.font = .preferredFont(forTextStyle: .body)
        instructions.textColor = .secondaryLabel
        field.placeholder = "dsbot://pair?…"
        field.accessibilityLabel = "Pairing link"
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.textContentType = .URL
        errorLabel.numberOfLines = 0
        errorLabel.font = .preferredFont(forTextStyle: .subheadline)
        errorLabel.textColor = .systemRed
        progressLabel.font = .preferredFont(forTextStyle: .subheadline)
        progressLabel.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [instructions, field, errorLabel, progressLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    @objc private func close() { dismiss(animated: true) }

    func showStatus(_ status: LinkSession.Status) {
        switch status {
        case .connecting:
            progressLabel.text = "Connecting…"
        case .offline:
            progressLabel.text = "Waiting for computer…"
        case .online:
            progressLabel.text = "Connected"
        case .disconnected:
            progressLabel.text = "Could not connect. Check the link and try again."
            navigationItem.rightBarButtonItem?.isEnabled = true
        }
    }

    @objc private func submit() {
        do {
            let offer = try PairingLink.parse(field.text ?? "")
            errorLabel.text = nil
            navigationItem.rightBarButtonItem?.isEnabled = false
            onPair?(offer)
        } catch let error as PairingLinkError {
            errorLabel.text = error.explanation
        } catch {
            errorLabel.text = error.localizedDescription
        }
    }
}
