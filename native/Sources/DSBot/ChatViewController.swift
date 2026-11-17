import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// N1 chat shell. Messages and composer behaviour arrive in later steps.
final class ChatViewController: UIViewController, UIGestureRecognizerDelegate {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    private let list = UITableView(frame: .zero, style: .plain)
    private let emptyState = UILabel()
    private let composer = NativeComposerView()
    private var computerItem: UIBarButtonItem!
    private var sideItem: UIBarButtonItem!
    private let titleButton = UIButton(type: .system)
    private var composerHeight: NSLayoutConstraint!
    private let pendingButton = UIButton(type: .system)
    private var pendingHeight: NSLayoutConstraint!
    private var pendingItems: [PendingActionsViewController.Item] = []
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
    private var stream = ChatStream()
    private struct Outgoing {
        let id: UUID
        let text: String
        let images: [String]
        let sessionID: String
        let known: Set<String>
        var failureReason: String?
        var delivered = false
    }
    private var outbox: [String: [Outgoing]] = [:]
    private var acknowledgedRows: [String: Set<String>] = [:]
    private var imageCache: [String: UIImage] = [:]
    private var imageReads = Set<String>()
    private var expandedSteps = Set<String>()
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
    private var keyboardTiming: (duration: TimeInterval, options: UIView.AnimationOptions)?
    private let drawerTransition = TeamDrawerTransition()
    private let noticeBanner = UIButton(type: .system)
    private var noticeTarget: ChatTarget?
    private var noticeGeneration = 0

    private var chatKey: String? {
        guard let host = savedOffer?.hostDeviceId, let target = botID ?? roomID else { return nil }
        return "\(host):\(roomID == nil ? "bot" : "room"):\(target)"
    }

    private func rebuildRows() {
        if let key = chatKey {
            let visible = olderRows + latestRows
            var matched = acknowledgedRows[key] ?? []
            outbox[key]?.removeAll { entry in
                guard entry.delivered,
                      let row = visible.first(where: {
                          $0.isUser && $0.messageText.trimmingCharacters(in: .whitespacesAndNewlines) == entry.text
                              && $0.imageCount == entry.images.count
                              && !entry.known.contains($0.sourceKey) && !matched.contains($0.sourceKey)
                      }) else { return false }
                matched.insert(row.sourceKey)
                return true
            }
            acknowledgedRows[key] = matched
            rows = visible + (outbox[key] ?? []).map {
                ChatRow(localID: $0.id, text: $0.text, imageCount: $0.images.count,
                        failureReason: $0.failureReason)
            }
            if stream.sessionID == chatSessionID, !stream.text.isEmpty {
                rows.append(ChatRow(.object(["kind": .string("bot"), "text": .string(stream.text)])))
            }
        } else {
            rows = olderRows + latestRows
        }
        list.reloadData()
        updateEmptyState()
    }

    private func imageKey(_ attachmentID: String) -> String {
        "\(savedOffer?.hostDeviceId ?? ""):\(chatSessionID ?? ""):\(attachmentID)"
    }

    private func updateSideButton() {
        navigationItem.rightBarButtonItems = botID != nil && chatSessionID != nil
            ? [sideItem, computerItem] : [computerItem]
    }

    private func loadPreview(_ attachmentID: String, sessionID: String) {
        let key = imageKey(attachmentID)
        guard imageCache[key] == nil, imageReads.insert(key).inserted else { return }
        let connectionID = self.sessionID
        Task {
            defer { imageReads.remove(key) }
            guard let result = try? await BotAPI.call("image", payload: .object([
                "sessionId": .string(sessionID), "attachmentId": .string(attachmentID),
                "preview": .bool(true),
            ]), on: session),
                  let encoded = result["data"]?.stringValue,
                  let bytes = Data(base64Encoded: encoded), let image = UIImage(data: bytes),
                  connectionID == self.sessionID, self.chatSessionID == sessionID else { return }
            imageCache[key] = image
            for path in list.indexPathsForVisibleRows ?? [] where rows[path.row].imageRefs.contains(attachmentID) {
                if let cell = list.cellForRow(at: path) as? ChatMessageCell {
                    cell.configure(rows[path.row], images: previewImages(for: rows[path.row]),
                                   stepsExpanded: expandedSteps.contains(rows[path.row].sourceKey))
                }
            }
        }
    }

    private func previewImages(for row: ChatRow) -> [String: UIImage] {
        var images: [String: UIImage] = [:]
        for reference in row.imageRefs { images[reference] = imageCache[imageKey(reference)] }
        return images
    }

    private func openPhoto(_ attachmentID: String) {
        guard let chatSessionID else { return }
        let viewer = PhotoViewController(image: imageCache[imageKey(attachmentID)])
        present(UINavigationController(rootViewController: viewer), animated: true)
        let connectionID = sessionID
        Task {
            guard let result = try? await BotAPI.call("image", payload: .object([
                "sessionId": .string(chatSessionID), "attachmentId": .string(attachmentID),
            ]), on: session),
                  let encoded = result["data"]?.stringValue,
                  let bytes = Data(base64Encoded: encoded), let image = UIImage(data: bytes),
                  connectionID == sessionID else { return }
            viewer.show(image)
        }
    }

    private func openFile(_ file: ChatFile) {
        guard linkStatus == .online else { return }
        Task {
            do {
                let result = try await BotAPI.call("file-text", payload: .object([
                    "file": file.value,
                ]), on: session)
                let content = result.stringValue ?? result["text"]?.stringValue ?? ""
                let reader = TextReaderViewController(title: file.title, content: content)
                present(UINavigationController(rootViewController: reader), animated: true)
            } catch { showActionError(error.localizedDescription) }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = tr("Chat")
        titleButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        titleButton.setTitle(tr("Chat"), for: .normal)
        titleButton.accessibilityLabel = "Conversation details"
        titleButton.addTarget(self, action: #selector(showDetails), for: .touchUpInside)
        navigationItem.titleView = titleButton
        updateTitleButton()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        view.backgroundColor = .systemBackground
        configureNoticeBanner()
        computerItem = UIBarButtonItem(
            title: "Pair", style: .plain, target: self, action: #selector(showPairing)
        )
        let sideButton = UIButton(type: .system)
        sideButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        NSLayoutConstraint.activate([
            sideButton.widthAnchor.constraint(equalToConstant: 44),
            sideButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        sideButton.accessibilityLabel = "Side chat"
        sideButton.addTarget(self, action: #selector(showSideChat), for: .touchUpInside)
        let sideIcon = OriginalSideIcon()
        sideIcon.translatesAutoresizingMaskIntoConstraints = false
        sideIcon.isOpaque = false
        sideIcon.backgroundColor = .clear
        sideIcon.isUserInteractionEnabled = false
        sideButton.addSubview(sideIcon)
        NSLayoutConstraint.activate([
            sideIcon.centerXAnchor.constraint(equalTo: sideButton.centerXAnchor),
            sideIcon.centerYAnchor.constraint(equalTo: sideButton.centerYAnchor),
            sideIcon.widthAnchor.constraint(equalToConstant: 28),
            sideIcon.heightAnchor.constraint(equalToConstant: 28),
        ])
        sideItem = UIBarButtonItem(customView: sideButton)
        updateSideButton()
        let teamButton = UIButton(type: .system)
        teamButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        NSLayoutConstraint.activate([
            teamButton.widthAnchor.constraint(equalToConstant: 44),
            teamButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        teamButton.accessibilityLabel = "Team"
        teamButton.addTarget(self, action: #selector(showTeam), for: .touchUpInside)
        let teamIcon = OriginalSidebarIcon()
        teamIcon.translatesAutoresizingMaskIntoConstraints = false
        teamIcon.isOpaque = false
        teamIcon.isUserInteractionEnabled = false
        teamIcon.backgroundColor = .clear
        teamButton.addSubview(teamIcon)
        NSLayoutConstraint.activate([
            teamIcon.centerXAnchor.constraint(equalTo: teamButton.centerXAnchor),
            teamIcon.centerYAnchor.constraint(equalTo: teamButton.centerYAnchor),
            teamIcon.widthAnchor.constraint(equalToConstant: 28),
            teamIcon.heightAnchor.constraint(equalToConstant: 28),
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: teamButton)
        configureStatusBar()
        configureList()
        configureComposer()
        let drawerEdge = UIPanGestureRecognizer(target: self, action: #selector(openDrawerFromEdge(_:)))
        drawerEdge.delegate = self
        drawerEdge.cancelsTouchesInView = false
        view.addGestureRecognizer(drawerEdge)
        savedOffer = pairingStore.load()
        computerItem.title = tr(savedOffer == nil ? "Pair" : "Computers")
        updateEmptyState()
        if let savedOffer { connect(to: savedOffer, pairingCode: nil) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if selectedTarget == nil { title = tr("Chat") }
        computerItem?.title = tr(savedOffer == nil ? "Pair" : "Computers")
        retryButton.setTitle(tr("Retry"), for: .normal)
        updateTitleButton()
        updateEmptyState()
        updatePendingButton()
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
        retryButton.setTitle(tr("Retry"), for: .normal)
        retryButton.addTarget(self, action: #selector(retryConnection), for: .touchUpInside)
        statusBar.addArrangedSubview(retryButton)
        retryButton.isHidden = true
        statusLabel.text = tr("Not paired")
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
        let message: String? = savedOffer == nil
            ? "Pair with your computer to start chatting."
            : botID == nil && roomID == nil ? "No Bot yet" : rows.isEmpty ? "No messages yet" : nil
        emptyState.text = message.map(tr)
        emptyState.isHidden = rows.count > 0
    }

    private func connect(to offer: PairingOffer, pairingCode: String?) {
        let oldSession = session
        stream.clear()
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
        updateSideButton()
        selectedTarget = nil
        teamState = nil
        pendingItems = []
        updatePendingButton()
        chatSessionID = nil
        olderRows = []
        latestRows = []
        rows = []
        expandedSteps = []
        cursor = nil
        list.reloadData()
        updateEmptyState()
        statusLabel.text = tr("Connecting…")
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
            await nextSession.setErrorHandler { [weak self] message in
                Task { @MainActor [weak self] in self?.showLinkError(message, for: id) }
            }
            await nextSession.setEventHandler { [weak self] event, data in
                Task { @MainActor [weak self] in self?.handleFeed(event, data: data, for: id) }
            }
            await nextSession.connect(pairing)
        }
    }

    private func handleFeed(_ event: String, data: JSONValue, for id: UUID) {
        guard id == sessionID, linkStatus == .online else { return }
        if event == "notice" { showNoticeBanner(data) }
        let hadStream = !stream.text.isEmpty
        if event == "stream", stream.receive(data, for: chatSessionID) {
            let nearBottom = list.contentSize.height - list.contentOffset.y - list.bounds.height < 120
            if hadStream, !stream.text.isEmpty, !rows.isEmpty {
                let last = rows.count - 1
                rows[last] = ChatRow(.object(["kind": .string("bot"), "text": .string(stream.text)]))
                list.reloadRows(at: [IndexPath(row: last, section: 0)], with: .none)
            } else {
                rebuildRows()
            }
            if nearBottom && !rows.isEmpty {
                list.layoutIfNeeded()
                list.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: false)
            }
            return
        }
        if event == "revision" || event == "live" || event == "notice"
            || (event == "message" && data["sessionId"]?.stringValue == chatSessionID)
            || (event == "room" && data["roomId"]?.stringValue == roomID) {
            Task { await refreshLatest(for: id) }
        }
    }

    private func configureNoticeBanner() {
        noticeBanner.translatesAutoresizingMaskIntoConstraints = false
        noticeBanner.isHidden = true
        noticeBanner.backgroundColor = .secondarySystemGroupedBackground
        noticeBanner.layer.cornerRadius = 12
        noticeBanner.layer.borderWidth = 1
        noticeBanner.layer.borderColor = view.tintColor.cgColor
        noticeBanner.contentHorizontalAlignment = .leading
        noticeBanner.titleLabel?.numberOfLines = 2
        noticeBanner.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        noticeBanner.setTitleColor(.label, for: .normal)
        noticeBanner.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        noticeBanner.addTarget(self, action: #selector(openNotice), for: .touchUpInside)
        view.addSubview(noticeBanner)
        NSLayoutConstraint.activate([
            noticeBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            noticeBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            noticeBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    private func showNoticeBanner(_ data: JSONValue) {
        guard UserDefaults.standard.string(forKey: "dsbot.banners") != "off",
              let kind = data["kind"]?.stringValue, kind == "question" || kind == "approval" else { return }
        let room = data["roomId"]?.stringValue
        let bot = data["botId"]?.stringValue
        guard let targetID = room ?? bot, !targetID.isEmpty else { return }
        let targetKind: ChatTarget.Kind = room == nil ? .bot : .room
        if selectedTarget?.kind == targetKind && selectedTarget?.id == targetID { return }
        let records = targetKind == .bot ? teamState?["bots"] : teamState?["rooms"]
        let name: String
        if case .array(let values)? = records {
            name = values.first { $0["id"]?.stringValue == targetID }?["name"]?.stringValue ?? targetID
        } else { name = targetID }
        noticeTarget = ChatTarget(kind: targetKind, id: targetID, name: name)
        let title = data["title"]?.stringValue
        let message = data["text"]?.stringValue ?? ""
        noticeBanner.setTitle([title, message].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: ": "), for: .normal)
        noticeBanner.isHidden = false
        view.bringSubviewToFront(noticeBanner)
        noticeGeneration += 1
        let generation = noticeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard self?.noticeGeneration == generation else { return }
            self?.noticeBanner.isHidden = true
            self?.noticeTarget = nil
        }
    }

    @objc private func openNotice() {
        guard let target = noticeTarget else { return }
        noticeBanner.isHidden = true
        noticeTarget = nil
        selectTarget(target)
    }

    private func showStatus(_ status: LinkSession.Status, for id: UUID) {
        guard id == sessionID else { return }
        linkStatus = status
        let pairingSheet = (presentedViewController as? UINavigationController)?
            .topViewController as? PairingViewController
        pairingSheet?.showStatus(status)
        switch status {
        case .connecting:
            statusLabel.text = tr("Connecting…")
            retryButton.isHidden = true
        case .online:
            statusLabel.text = tr("Checking computer…")
            retryButton.isHidden = true
            Task { await checkComputer(for: id) }
        case .offline:
            statusLabel.text = tr("Offline · reconnecting")
            retryButton.isHidden = true
            composer.canSend = false
            composer.running = false
            polling?.cancel()
            polling = nil
            stream.clear()
            rebuildRows()
        case .disconnected:
            statusLabel.text = tr(savedOffer == nil && pendingOffer == nil ? "Not paired" : "Offline")
            retryButton.isHidden = savedOffer == nil && pendingOffer == nil
            composer.canSend = false
            composer.running = false
            polling?.cancel()
            polling = nil
            stream.clear()
            rebuildRows()
        }
    }

    private func showLinkError(_ message: String, for id: UUID) {
        guard id == sessionID else { return }
        statusLabel.text = message
        let sheet = (presentedViewController as? UINavigationController)?.topViewController as? PairingViewController
        sheet?.showError(message)
    }

    private func checkComputer(for id: UUID) async {
        do {
            let hello = try await BotAPI.call("hello", on: session)
            guard id == sessionID, linkStatus == .online else { return }
            guard hello["api"]?.intValue != nil else {
                showLinkError("Update DS Bot on the computer to use this phone.", for: id)
                await session.disconnect()
                return
            }
            if let pendingOffer {
                pairingStore.save(pendingOffer)
                savedOffer = pendingOffer
                self.pendingOffer = nil
                computerItem.title = tr("Computers")
                updateEmptyState()
                presentedViewController?.dismiss(animated: true)
            }
            statusLabel.text = tr("Online")
            startPolling(for: id)
            let boot = hello["boot"]?.stringValue ?? ""
            _ = try? await BotAPI.call("notices", payload: .object([
                "boot": .string(boot), "since": .number(0),
            ]), on: session)
        } catch {
            guard id == sessionID, linkStatus == .online else { return }
            showLinkError(error.localizedDescription, for: id)
            await session.disconnect()
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
                chatSessionID = nil
                stream.clear()
                title = "Chat"
                updateTitleButton()
                updateSideButton()
                pendingItems = []
                updatePendingButton()
                rows = []
                list.reloadData()
                emptyState.text = "No Bot yet"
                emptyState.isHidden = false
                return
            }
            UserDefaults.standard.set(Int(Date().timeIntervalSince1970 * 1_000),
                                      forKey: "dsbot.seen.\(target.id)")
            if botID != (target.kind == .bot ? target.id : nil)
                || roomID != (target.kind == .room ? target.id : nil) {
                botID = target.kind == .bot ? target.id : nil
                roomID = target.kind == .room ? target.id : nil
                title = chosen?["name"]?.stringValue ?? target.name
                updateTitleButton()
                chatSessionID = nil
                stream.clear()
                olderRows = []
                expandedSteps = []
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
                parameter: .string(target.id), "steps": .bool(true),
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
                stream.clear()
            } else if cursor == nil {
                cursor = page.cursor
            }
            chatSessionID = nextSessionID
            updateSideButton()
            updatePending(state, sessionID: nextSessionID)
            latestRows = page.items
            rebuildRows()
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
                    "cursor": cursor, "steps": .bool(true),
                ]), on: session)
                guard id == sessionID, linkStatus == .online,
                      (isRoom ? roomID : botID) == targetID else { return }
                let page = ChatPage(value)
                self.cursor = page.cursor
                olderRows.insert(contentsOf: page.items, at: 0)
                rebuildRows()
                list.layoutIfNeeded()
                list.contentOffset.y = oldOffset + list.contentSize.height - oldHeight
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
                    chatSessionID = nil
                    updateSideButton()
                    selectedTarget = nil
                    teamState = nil
                    pendingItems = []
                    updatePendingButton()
                    chatSessionID = nil
                    cursor = nil
                    olderRows = []
                    latestRows = []
                    rows = []
                    list.reloadData()
                    updateEmptyState()
                    statusLabel.text = tr("Not paired")
                    computerItem.title = tr("Pair")
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
        view.endEditing(true)
        let team = TeamListViewController(state: teamState)
        team.onSelect = { [weak self] target in self?.selectTarget(target) }
        team.onSettings = { [weak self] in self?.showSettings() }
        team.onNeeds = { [weak self] in self?.showNeedsYou() }
        team.onCreateBot = { [weak self] in self?.showBotEditor(id: nil) }
        team.onCreateGroup = { [weak self] in self?.showGroupEditor(id: nil) }
        team.onEditBot = { [weak self] id in self?.showBotEditor(id: id) }
        team.onEditGroup = { [weak self] id in self?.showGroupEditor(id: id) }
        let navigation = UINavigationController(rootViewController: team)
        let closePan = UIPanGestureRecognizer(target: self, action: #selector(closeDrawerFromHeader(_:)))
        closePan.cancelsTouchesInView = false
        navigation.navigationBar.addGestureRecognizer(closePan)
        navigation.modalPresentationStyle = .custom
        navigation.transitioningDelegate = drawerTransition
        present(navigation, animated: true)
    }

    private func showNeedsYou() {
        guard let teamState else { return }
        let needs = NeedsYouViewController(state: teamState)
        needs.onOpen = { [weak self] target in self?.selectTarget(target) }
        present(UINavigationController(rootViewController: needs), animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              presentedViewController == nil, teamState != nil else { return false }
        let movement = pan.translation(in: view)
        let originX = pan.location(in: view).x - movement.x
        return originX <= 24 && movement.x > 8 && abs(movement.x) > abs(movement.y)
    }

    @objc private func openDrawerFromEdge(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        let distance = pan.translation(in: view).x
        if distance > 80 || pan.velocity(in: view).x > 350 { showTeam() }
    }

    @objc private func closeDrawerFromHeader(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        if pan.translation(in: pan.view).x < -60 || pan.velocity(in: pan.view).x < -350 {
            presentedViewController?.dismiss(animated: true)
        }
    }

    @objc private func showSideChat() {
        guard linkStatus == .online, let botID, let chatSessionID else { return }
        let name: String
        if case .array(let bots)? = teamState?["bots"],
           let bot = bots.first(where: { $0["id"]?.stringValue == botID }) {
            name = bot["name"]?.stringValue ?? "Bot"
        } else { name = "Bot" }
        let side = SideChatViewController(botID: botID, botName: name,
                                          sessionID: chatSessionID, session: session)
        present(UINavigationController(rootViewController: side), animated: true)
    }

    private func updateTitleButton() {
        titleButton.setTitle((title ?? tr("Chat")) + (botID != nil || roomID != nil ? "  ⌄" : ""), for: .normal)
        titleButton.isEnabled = teamState != nil && (botID != nil || roomID != nil)
    }

    @objc private func showDetails() {
        guard let teamState, let id = botID ?? roomID else { return }
        let target = ChatTarget(kind: roomID == nil ? .bot : .room, id: id, name: title ?? id)
        let details = ConversationDetailsViewController(target: target, state: teamState, session: session)
        details.onEdit = { [weak self, weak details] in
            details?.dismiss(animated: true) { [weak self] in
                if target.kind == .bot { self?.showBotEditor(id: id) }
                else { self?.showGroupEditor(id: id) }
            }
        }
        present(UINavigationController(rootViewController: details), animated: true)
    }

    private func showBotEditor(id: String?) {
        guard linkStatus == .online, let teamState else { return }
        let bot: JSONValue?
        if let id, case .array(let bots)? = teamState["bots"] {
            bot = bots.first(where: { $0["id"]?.stringValue == id })
        } else { bot = nil }
        if id != nil && bot == nil { return }
        let editor = BotEditorViewController(bot: bot, state: teamState, session: session)
        editor.onSaved = { [weak self] target in
            guard let self else { return }
            if let target { self.selectTarget(target) }
            Task { await self.refreshLatest(for: self.sessionID) }
        }
        present(UINavigationController(rootViewController: editor), animated: true)
    }

    private func showGroupEditor(id: String?) {
        guard linkStatus == .online, let teamState else { return }
        let room: JSONValue?
        if let id, case .array(let rooms)? = teamState["rooms"] {
            room = rooms.first(where: { $0["id"]?.stringValue == id })
        } else { room = nil }
        if id != nil && room == nil { return }
        let editor = GroupEditorViewController(room: room, state: teamState, session: session)
        editor.onSaved = { [weak self] target in
            guard let self else { return }
            if let target { self.selectTarget(target) }
            Task { await self.refreshLatest(for: self.sessionID) }
        }
        present(UINavigationController(rootViewController: editor), animated: true)
    }

    private func showSettings() {
        let settings = NativeSettingsViewController(computerName: savedOffer?.name ?? "", session: session)
        settings.onComputers = { [weak self] in self?.showPairing() }
        settings.onUsage = { [weak self] in self?.showUsage() }
        present(UINavigationController(rootViewController: settings), animated: true)
    }

    private func showUsage() {
        let usage = UsageViewController(session: session)
        present(UINavigationController(rootViewController: usage), animated: true)
    }

    private func selectTarget(_ target: ChatTarget) {
        guard selectedTarget != target else { return }
        selectedTarget = target
        botID = nil
        roomID = nil
        chatSessionID = nil
        stream.clear()
        updateSideButton()
        olderRows = []
        latestRows = []
        rows = []
        expandedSteps = []
        cursor = nil
        title = target.name
        updateTitleButton()
        pendingItems = []
        updatePendingButton()
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
            list.contentInset.bottom = height + pendingHeight.constant + 22
            let timing = keyboardTiming
            keyboardTiming = nil
            UIView.animate(
                withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : timing?.duration ?? 0.25,
                delay: 0,
                options: (timing?.options ?? [.curveEaseInOut]).union([.beginFromCurrentState, .allowUserInteraction]),
                animations: { self.view.layoutIfNeeded() }
            )
        }
        composer.onSend = { [weak self] text, images in self?.sendMessage(text, images: images) }
        composer.onAddPhoto = { [weak self] in self?.pickPhotos() }
        composer.onStop = { [weak self] in self?.stopChat() }
        view.addSubview(composer)
        pendingButton.translatesAutoresizingMaskIntoConstraints = false
        pendingButton.backgroundColor = .secondarySystemBackground
        pendingButton.layer.cornerRadius = 18
        pendingButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        pendingButton.addTarget(self, action: #selector(showPending), for: .touchUpInside)
        view.addSubview(pendingButton)
        pendingHeight = pendingButton.heightAnchor.constraint(equalToConstant: 0)
        pendingButton.isHidden = true
        if #available(iOS 17.0, *) {
            view.keyboardLayoutGuide.usesBottomSafeArea = true
        }
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            composerHeight,
            pendingButton.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            pendingButton.trailingAnchor.constraint(equalTo: composer.trailingAnchor),
            pendingButton.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            pendingHeight,
        ])
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard composer.editor.isFirstResponder, let info = notification.userInfo,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber,
              let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber else { return }
        keyboardTiming = (duration.doubleValue, UIView.AnimationOptions(rawValue: UInt(curve.intValue) << 16))
    }

    private func updatePending(_ state: JSONValue, sessionID: String) {
        var items: [PendingActionsViewController.Item] = []
        if let question = state["questions"]?[sessionID], question != .null {
            items.append(.question(sessionID: sessionID, value: question))
        }
        if case .array(let approvals)? = state["work"]?["approvals"] {
            for approval in approvals where approval["sessionId"]?.stringValue == sessionID
                || (roomID != nil && approval["roomId"]?.stringValue == roomID) {
                items.append(.approval(approval))
            }
        }
        if let botID, case .array(let secrets)? = state["secretRequests"]?[botID] {
            items += secrets.filter { $0["status"]?.stringValue == "pending" }.map { .secret($0) }
        }
        if let botID, let hold = state["browserHolds"]?[botID],
           hold["callId"]?.stringValue != nil {
            items.append(.handoff(botID: botID, value: hold))
        }
        if let view = state["views"]?[sessionID], view != .null {
            items.append(.view(sessionID: sessionID, value: view))
        }
        if let botID, case .array(let cards)? = state["btwCards"]?[botID] {
            items += cards.filter {
                $0["partId"]?.stringValue == nil || $0["partId"]?.stringValue == sessionID
            }.map { .aside(sessionID: sessionID, value: $0) }
        }
        pendingItems = items
        updatePendingButton()
    }

    private func updatePendingButton() {
        let count = pendingItems.count
        let needsAttention = pendingItems.contains {
            if case .aside = $0 { return false }
            return true
        }
        pendingButton.isHidden = count == 0
        let label = needsAttention ? "Needs you" : "Aside"
        pendingButton.setTitle("\(tr(label)) · \(count) \(tr(count == 1 ? "item" : "items"))", for: .normal)
        pendingHeight.constant = count == 0 ? 0 : 48
        list.contentInset.bottom = composerHeight.constant + pendingHeight.constant + 22
    }

    @objc private func showPending() {
        guard !pendingItems.isEmpty else { return }
        let actions = PendingActionsViewController(items: pendingItems, session: session)
        actions.onChanged = { [weak self] in
            guard let self else { return }
            Task { await self.refreshLatest(for: self.sessionID) }
        }
        present(UINavigationController(rootViewController: actions), animated: true)
    }

    private func sendMessage(_ text: String, images: [String]) {
        guard linkStatus == .online, let sessionID = chatSessionID ?? botID else {
            composer.restoreDraft(text)
            return
        }
        guard let key = chatKey else { composer.restoreDraft(text); return }
        let entry = Outgoing(id: UUID(), text: text, images: images, sessionID: sessionID,
                             known: Set((olderRows + latestRows).map(\.sourceKey)))
        outbox[key, default: []].append(entry)
        rebuildRows()
        list.layoutIfNeeded()
        list.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: true)
        deliver(entry, key: key)
    }

    private func deliver(_ entry: Outgoing, key: String) {
        let id = self.sessionID
        Task {
            do {
                var staged: [JSONValue] = []
                for image in entry.images {
                    let result = try await BotAPI.call("stage-image", payload: .object([
                        "mediaType": .string("image/jpeg"), "data": .string(image),
                    ]), on: session)
                    guard let imageID = result["id"]?.stringValue else { throw NSError(
                        domain: "DSBot", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "The photo could not be staged."]
                    ) }
                    staged.append(.string(imageID))
                }
                // The host only expects the field when photos ride along; an empty
                // array is a different shape than the one the phone normally sends.
                var payload: [String: JSONValue] = [
                    "sessionId": .string(entry.sessionID), "text": .string(entry.text),
                ]
                if !staged.isEmpty { payload["images"] = .array(staged) }
                _ = try await BotAPI.call("send", payload: .object(payload), on: session)
                guard id == self.sessionID else { return }
                if let index = outbox[key]?.firstIndex(where: { $0.id == entry.id }) {
                    outbox[key]?[index].delivered = true
                    outbox[key]?[index].failureReason = nil
                }
                await refreshLatest(for: id)
            } catch {
                guard id == self.sessionID else { return }
                if let index = outbox[key]?.firstIndex(where: { $0.id == entry.id }) {
                    outbox[key]?[index].failureReason = error.localizedDescription
                }
                if chatKey == key { rebuildRows() }
            }
        }
    }

    private func pickPhotos() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
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

extension ChatViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                guard let data else { return }
                Task { @MainActor [weak self] in self?.composer.addPhoto(data: data) }
            }
        }
    }
}

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! ChatMessageCell
        let row = rows[indexPath.row]
        cell.configure(row, images: previewImages(for: row),
                       stepsExpanded: expandedSteps.contains(row.sourceKey))
        cell.onOpenFile = { [weak self] file in self?.openFile(file) }
        cell.onOpenPhoto = { [weak self] reference in self?.openPhoto(reference) }
        if let chatSessionID {
            for reference in row.imageRefs where imageCache[imageKey(reference)] == nil {
                loadPreview(reference, sessionID: chatSessionID)
            }
        }
        return cell
    }
}

extension ChatViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard rows.indices.contains(indexPath.row) else { return }
        if rows[indexPath.row].kind == "steps" {
            let key = rows[indexPath.row].sourceKey
            if !expandedSteps.insert(key).inserted { expandedSteps.remove(key) }
            tableView.reloadRows(at: [indexPath], with: .none)
            return
        }
        if let attachmentID = rows[indexPath.row].imageRefs.first {
            openPhoto(attachmentID)
            return
        }
        guard let localID = rows[indexPath.row].localID,
              rows[indexPath.row].failed, let key = chatKey,
              let entry = outbox[key]?.first(where: { $0.id == localID }) else { return }
        let sheet = UIAlertController(title: "Message not sent", message: entry.failureReason,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            guard let self, let index = self.outbox[key]?.firstIndex(where: { $0.id == localID }) else { return }
            self.outbox[key]?[index].failureReason = nil
            self.rebuildRows()
            self.deliver(entry, key: key)
        })
        sheet.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.outbox[key]?.removeAll(where: { $0.id == localID })
            self?.rebuildRows()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(sheet, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if (scrollView.isDragging || scrollView.isDecelerating) && scrollView.contentOffset.y < 100 {
            loadOlder()
        }
    }
}

private final class PhotoViewController: UIViewController {
    private let photo = UIImageView()

    init(image: UIImage?) {
        super.init(nibName: nil, bundle: nil)
        photo.image = image
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Photo"
        view.backgroundColor = .black
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        photo.translatesAutoresizingMaskIntoConstraints = false
        photo.contentMode = .scaleAspectFit
        view.addSubview(photo)
        NSLayoutConstraint.activate([
            photo.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            photo.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            photo.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            photo.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    func show(_ image: UIImage) { photo.image = image }
    @objc private func close() { dismiss(animated: true) }
}

private final class TextReaderViewController: UIViewController {
    private let content: String
    private let reader = UITextView()

    init(title: String, content: String) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        reader.translatesAutoresizingMaskIntoConstraints = false
        reader.isEditable = false
        reader.isSelectable = true
        reader.font = .preferredFont(forTextStyle: .body)
        reader.text = content
        view.addSubview(reader)
        NSLayoutConstraint.activate([
            reader.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            reader.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            reader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            reader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
        ])
    }

    @objc private func close() { dismiss(animated: true) }
}

private final class ChatMessageCell: UITableViewCell {
    var onOpenFile: ((ChatFile) -> Void)?
    var onOpenPhoto: ((String) -> Void)?
    private let bubble = UIView()
    private let authorLabel = UILabel()
    private let messageLabel = UILabel()
    private let photoScroll = UIScrollView()
    private let photoStack = UIStackView()
    private let fileStack = UIStackView()
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
        photoScroll.showsHorizontalScrollIndicator = false
        photoStack.translatesAutoresizingMaskIntoConstraints = false
        photoStack.axis = .horizontal
        photoStack.spacing = 6
        photoScroll.addSubview(photoStack)
        NSLayoutConstraint.activate([
            photoScroll.heightAnchor.constraint(equalToConstant: 150),
            photoScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            photoStack.topAnchor.constraint(equalTo: photoScroll.contentLayoutGuide.topAnchor),
            photoStack.bottomAnchor.constraint(equalTo: photoScroll.contentLayoutGuide.bottomAnchor),
            photoStack.leadingAnchor.constraint(equalTo: photoScroll.contentLayoutGuide.leadingAnchor),
            photoStack.trailingAnchor.constraint(equalTo: photoScroll.contentLayoutGuide.trailingAnchor),
            photoStack.heightAnchor.constraint(equalTo: photoScroll.frameLayoutGuide.heightAnchor),
        ])
        fileStack.axis = .vertical
        fileStack.spacing = 6
        timeLabel.font = .preferredFont(forTextStyle: .caption2)
        timeLabel.textColor = .tertiaryLabel
        let text = UIStackView(arrangedSubviews: [authorLabel, messageLabel, photoScroll, fileStack, timeLabel])
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

    func configure(_ row: ChatRow, images: [String: UIImage] = [:], stepsExpanded: Bool = false) {
        leading.isActive = false
        trailing.isActive = false
        centered.isActive = false
        if row.isNotice || row.kind == "steps" {
            centered.isActive = true
        } else if row.isUser {
            trailing.isActive = true
        } else {
            leading.isActive = true
        }
        bubble.backgroundColor = row.isNotice || row.kind == "steps" ? .clear
            : row.isUser ? tintColor.withAlphaComponent(0.12) : .secondarySystemBackground
        authorLabel.isHidden = row.isNotice || row.kind == "steps"
        authorLabel.text = row.author
        if let summary = row.stepSummary {
            messageLabel.attributedText = nil
            messageLabel.text = summary
                + (stepsExpanded && !row.stepDetails.isEmpty ? "\n" + row.stepDetails.joined(separator: "\n") : "")
        } else if !row.isNotice, let markdown = try? AttributedString(markdown: row.text) {
            messageLabel.attributedText = NSAttributedString(markdown)
        } else {
            messageLabel.attributedText = nil
            messageLabel.text = row.text
        }
        for view in photoStack.arrangedSubviews { photoStack.removeArrangedSubview(view); view.removeFromSuperview() }
        for reference in row.imageRefs {
            let button = UIButton(type: .custom)
            button.clipsToBounds = true
            button.layer.cornerRadius = 12
            button.backgroundColor = .tertiarySystemBackground
            button.imageView?.contentMode = .scaleAspectFill
            button.setImage(images[reference], for: .normal)
            button.accessibilityLabel = "Open photo"
            button.widthAnchor.constraint(equalToConstant: 150).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onOpenPhoto?(reference) }, for: .touchUpInside)
            photoStack.addArrangedSubview(button)
        }
        photoScroll.isHidden = row.imageRefs.isEmpty
        for view in fileStack.arrangedSubviews { fileStack.removeArrangedSubview(view); view.removeFromSuperview() }
        for file in row.files {
            let button = UIButton(type: .system)
            button.setTitle(file.title, for: .normal)
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.lineBreakMode = .byTruncatingMiddle
            button.backgroundColor = .tertiarySystemBackground
            button.layer.cornerRadius = 10
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onOpenFile?(file) }, for: .touchUpInside)
            fileStack.addArrangedSubview(button)
        }
        fileStack.isHidden = row.files.isEmpty
        messageLabel.textAlignment = row.isNotice || row.kind == "steps" ? .center : .left
        messageLabel.textColor = row.isNotice || row.kind == "steps" ? .secondaryLabel : .label
        timeLabel.text = row.localID == nil ? row.time.map { Self.clock.string(from: $0) }
            : row.failed ? "Not sent · \(row.failureReason ?? "Tap to retry")" : "Sending…"
        timeLabel.numberOfLines = row.failed ? 2 : 1
        timeLabel.isHidden = (row.time == nil && row.localID == nil) || row.isNotice || row.kind == "steps"
        accessibilityLabel = [row.author, row.text, row.failureReason ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
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
        let scanButton = UIButton(type: .system)
        scanButton.setTitle("Scan QR code", for: .normal)
        scanButton.addTarget(self, action: #selector(scanCode), for: .touchUpInside)
        scanButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        let stack = UIStackView(arrangedSubviews: [instructions, scanButton, field, errorLabel, progressLabel])
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

    @objc private func scanCode() {
        let scanner = PairingScannerViewController()
        scanner.onCode = { [weak self] code in
            guard let self else { return }
            field.text = code
            submit()
        }
        present(UINavigationController(rootViewController: scanner), animated: true)
    }

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

    func showError(_ message: String) { errorLabel.text = message }

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
