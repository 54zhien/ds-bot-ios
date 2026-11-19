import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// N1 chat shell. Messages and composer behaviour arrive in later steps.
final class ChatViewController: UIViewController, UIGestureRecognizerDelegate {
    private func tr(_ key: String) -> String { NativeLanguage.text(key) }
    private let list = UITableView(frame: .zero, style: .plain)
    private let emptyState = UILabel()
    private let retryLoadButton = UIButton(type: .system)
    private let emptyChatView = EmptyChatView()
    private let emptyChatGuide = UILayoutGuide()
    private let latestButton = UIButton(type: .system)
    private let composer = NativeComposerView()
    private let header = PassthroughHeader()
    private let headerRow = UIStackView()
    private let drawerControl = GlassControlView(
        label: NativeLanguage.text("Team"),
        icon: OriginalSidebarIcon())
    private let sideControl = GlassControlView(
        label: NativeLanguage.text("Side chat"),
        icon: OriginalSideIcon())
    private let sidePlaceholder = UIView()
    private let headerCenter = UIControl()
    private let headerTitle = UILabel()
    private let headerPill = GlassPillView(height: Glass.control)
    private let pillAvatar = UILabel()
    private let pillName = UILabel()
    private var composerHeight: NSLayoutConstraint!
    private var composerLeading: NSLayoutConstraint!
    private var composerTrailing: NSLayoutConstraint!
    private var composerBottomRest: NSLayoutConstraint!
    private var composerBottomKeyboard: NSLayoutConstraint!
    private var keyboardUp = false
    private let pendingDock = PendingDockView()
    private let blockedView = BotBlockedView()
    private let computerUseView = ComputerUseView()
    private let workStatusView = WorkStatusView()
    private var pendingHeight: NSLayoutConstraint!
    private var pendingItems: [PendingActionsViewController.Item] = []
    private let statusPill = GlassPillView(height: 30)
    private let headerFade = FadeOverlayView()
    private var headerFadeHeight: NSLayoutConstraint!
    private let pillSpinner = UIActivityIndicatorView(style: .medium)
    private let pillLabel = UILabel()
    private let pillAction = UIButton(type: .system)

    /// The palette follows the appearance, so no token values are copied here.
    private var palette: Palette { ThemeStore.palette(trait: traitCollection) }
    private let roomGoalView = RoomGoalView()
    private var goalHiddenHeight: NSLayoutConstraint!
    private var goalShown: NSLayoutConstraint!
    private var goalHidden: NSLayoutConstraint!

    private let pairingStore = PairingStore()
    private var session = LinkSession()
    private var sessionID = UUID()
    private var savedOffer: PairingOffer?
    private var pendingOffer: PairingOffer?
    private var rows: [ChatRow] = []
    private var olderRows: [ChatRow] = []
    private var latestRows: [ChatRow] = []
    /// The newest page per conversation, so switching back renders immediately.
    /// Memory only: a cold start shows nothing until the first read lands.
    private let pageCache = ChatPageCache()
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
    private var originalImages: [String: UIImage] = [:]
    private var imageReads = Set<String>()
    private var expandedSteps = Set<String>()
    private var cursor: JSONValue?
    private var chatSessionID: String?
    private var botID: String?
    private var roomID: String?
    private var selectedTarget: ChatTarget?
    private var teamState: JSONValue?
    /// The last state error, shown until a read succeeds. It used to be overwritten by
    /// the empty-state text, which is why a failure looked like "No Bot yet".
    private var loadError: String?
    /// The live key the host gave us; sent back so the host can answer unchanged.
    private var liveKey: String?
    private var polling: Task<Void, Never>?
    private var loadingOlder = false
    private var readingLatest = false
    private var readAgain = false
    /// The notices read position, and the rows message events brought ahead of the
    /// read that confirms them: both live off-screen so they stay testable.
    private var feedState = FeedState()
    private var feedBuffer = ChatFeedBuffer()
    private var linkStatus: LinkSession.Status = .disconnected
    /// Set when the Server refused this phone's identity: retrying the dead offer
    /// cannot work, so the retry button becomes the way back into pairing.
    private var linkNeedsPairing = false
    /// The conversation a retry should reopen into once the fresh state lands.
    private var reconnectTarget: ChatTarget?
    /// The cold-start restore ran once; later refreshes never re-pick.
    private var restoredLastChat = false
    private var keyboardTiming: (duration: TimeInterval, options: UIView.AnimationOptions)?
    private let drawerTransition = TeamDrawerTransition()
    private var noticeTarget: ChatTarget?

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
            rows = visible + feedBuffer.pending(among: visible) + (outbox[key] ?? []).map { entry in
                ChatRow(localID: entry.id, text: entry.text,
                        localImageData: entry.images.compactMap { Data(base64Encoded: $0) },
                        failureReason: entry.failureReason)
            }
            if stream.sessionID == chatSessionID, !stream.text.isEmpty {
                rows.append(ChatRow(.object(["kind": .string("bot"), "text": .string(stream.text)])))
            }
        } else {
            rows = olderRows + latestRows
        }
        // Chat.tsx stampOf: a run's time lands on its last bubble, so a bot/post row
        // hides its stamp while the next row is the same name's bot/post. User rows
        // keep their own, and rows without a time never had one to hide.
        for index in rows.indices where index + 1 < rows.count {
            let next = rows[index + 1]
            rows[index].stampFolded = (rows[index].kind == "bot" || rows[index].kind == "post")
                && (next.kind == "bot" || next.kind == "post")
                && next.name == rows[index].name
        }
        list.reloadData()
        updateEmptyState()
    }

    private func imageKey(_ attachmentID: String) -> String {
        "\(savedOffer?.hostDeviceId ?? ""):\(chatSessionID ?? ""):\(attachmentID)"
    }

    private func updateSideButton() {
        let available = botID != nil && chatSessionID != nil
        sideControl.isHidden = !available
        sidePlaceholder.isHidden = available
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

    private func openPhotos(_ refs: [String], startingWith attachmentID: String) {
        guard let chatSessionID else { return }
        let index = refs.firstIndex(of: attachmentID) ?? 0
        let viewer = PhotoViewController(refs: refs, images: refs.map { imageCache[imageKey($0)] }, index: index)
        let connectionID = sessionID
        viewer.onSelect = { [weak self, weak viewer] reference, page in
            guard let self, let viewer else { return }
            let cacheKey = "\(savedOffer?.hostDeviceId ?? ""):\(chatSessionID):\(reference)"
            if let image = originalImages[cacheKey] {
                viewer.show(image, at: page)
                return
            }
            Task {
                guard let result = try? await BotAPI.call("image", payload: .object([
                    "sessionId": .string(chatSessionID), "attachmentId": .string(reference),
                ]), on: session),
                      let encoded = result["data"]?.stringValue,
                      let bytes = Data(base64Encoded: encoded), let image = UIImage(data: bytes),
                      connectionID == sessionID, self.chatSessionID == chatSessionID else { return }
                originalImages[cacheKey] = image
                viewer.show(image, at: page)
            }
        }
        present(UINavigationController(rootViewController: viewer), animated: true)
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
        // The chat has no navigation bar: the header floats, pushed screens get it back.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: ThemeStore.changed, object: nil)
        view.backgroundColor = palette.main
        // A push tap names a chat by id; routing goes through the same door
        // the banner uses, so taps, banners and pushes land identically.
        PushCenter.shared.openChat = { [weak self] kind, id in
            self?.openPushTarget(kind: kind, id: id)
        }
        configureHeader()
        updateSideButton()
        configureDiagnosticsMenu()
        configureRoomGoal()
        configureList()
        configureComposer()
        configureLatestButton()
        let drawerEdge = UIPanGestureRecognizer(target: self, action: #selector(openDrawerFromEdge(_:)))
        drawerEdge.delegate = self
        drawerEdge.cancelsTouchesInView = false
        view.addGestureRecognizer(drawerEdge)
        savedOffer = pairingStore.load()
        updateEmptyState()
        if let savedOffer {
            connect(to: savedOffer, pairingCode: nil)
        } else {
            setStatus(tr("Not paired"))
            pillAction.setTitle(tr("Pair"), for: .normal)
            pillAction.isHidden = false
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if selectedTarget == nil { title = tr("Chat") }
        navigationController?.setNavigationBarHidden(true, animated: animated)
        retryLoadButton.setTitle(tr("Retry"), for: .normal)
        latestButton.setTitle(tr("Latest messages"), for: .normal)
        updateTitleButton()
        updateEmptyState()
        updatePendingButton()
        refreshStatusPill()
    }

    /// The team theme changed: repaint what the screen already shows.
    @objc private func themeChanged() {
        view.backgroundColor = palette.main
        headerFade.configure(color: palette.main)
        headerTitle.textColor = palette.ink
        pillName.textColor = palette.ink
        pillLabel.textColor = palette.ink3
        pillSpinner.color = palette.ink3
        pillAction.setTitleColor(palette.accent, for: .normal)
        updateTitleButton()
        refreshStatusPill()
        list.reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || navigationController?.topViewController !== self {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    /// The floating header ShellB.tsx draws: no navigation bar, glass over content.
    private func configureHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = Glass.gap
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerRow)

        drawerControl.addTarget(self, action: #selector(showTeam), for: .touchUpInside)
        sideControl.addTarget(self, action: #selector(showSideChat), for: .touchUpInside)
        sidePlaceholder.translatesAutoresizingMaskIntoConstraints = false
        sidePlaceholder.widthAnchor.constraint(equalToConstant: Glass.control).isActive = true
        sidePlaceholder.heightAnchor.constraint(equalToConstant: Glass.control).isActive = true

        headerCenter.translatesAutoresizingMaskIntoConstraints = false
        headerCenter.accessibilityTraits = .button
        headerCenter.addTarget(self, action: #selector(showDetails), for: .touchUpInside)
        headerTitle.font = TypeScale.headerTitle.font
        headerTitle.textColor = palette.ink
        headerTitle.textAlignment = .center
        headerTitle.lineBreakMode = .byTruncatingTail
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerCenter.addSubview(headerTitle)
        headerPill.isHidden = true
        headerPill.translatesAutoresizingMaskIntoConstraints = false
        headerCenter.addSubview(headerPill)
        pillAvatar.font = .systemFont(ofSize: TypeScale.small.size, weight: .medium)
        pillAvatar.textAlignment = .center
        pillAvatar.textColor = .white
        pillAvatar.layer.cornerRadius = 14
        pillAvatar.clipsToBounds = true
        pillAvatar.translatesAutoresizingMaskIntoConstraints = false
        headerPill.content.addArrangedSubview(pillAvatar)
        pillName.font = .systemFont(ofSize: 15, weight: .medium)
        pillName.textColor = palette.ink
        pillName.lineBreakMode = .byTruncatingTail
        pillName.translatesAutoresizingMaskIntoConstraints = false
        headerPill.content.addArrangedSubview(pillName)
        headerRow.addArrangedSubview(drawerControl)
        headerRow.addArrangedSubview(headerCenter)
        headerRow.addArrangedSubview(sideControl)
        headerRow.addArrangedSubview(sidePlaceholder)
        sideControl.isHidden = true

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            headerRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Glass.margin),
            headerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Glass.margin),
            headerRow.heightAnchor.constraint(equalToConstant: Glass.control),
            headerCenter.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            headerTitle.topAnchor.constraint(equalTo: headerCenter.topAnchor),
            headerTitle.bottomAnchor.constraint(equalTo: headerCenter.bottomAnchor),
            headerTitle.leadingAnchor.constraint(equalTo: headerCenter.leadingAnchor),
            headerTitle.trailingAnchor.constraint(equalTo: headerCenter.trailingAnchor),
            headerPill.topAnchor.constraint(equalTo: headerCenter.topAnchor),
            headerPill.bottomAnchor.constraint(equalTo: headerCenter.bottomAnchor),
            headerPill.leadingAnchor.constraint(equalTo: headerCenter.leadingAnchor),
            headerPill.trailingAnchor.constraint(equalTo: headerCenter.trailingAnchor),
            pillAvatar.widthAnchor.constraint(equalToConstant: 28),
            pillAvatar.heightAnchor.constraint(equalToConstant: 28),
        ])
        configureStatusPill()
        updateTitleButton()
    }

    /// The 30pt GlassPill ShellB puts under the header while the link is not online.
    private func configureStatusPill() {
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        statusPill.isHidden = true
        view.addSubview(statusPill)
        pillSpinner.color = palette.ink3
        pillSpinner.hidesWhenStopped = true
        pillLabel.font = TypeScale.caption.font
        pillLabel.textColor = palette.ink3
        pillAction.titleLabel?.font = .systemFont(ofSize: TypeScale.caption.size, weight: .semibold)
        pillAction.setTitleColor(palette.accent, for: .normal)
        pillAction.contentEdgeInsets = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        pillAction.addTarget(self, action: #selector(statusPillAction), for: .touchUpInside)
        statusPill.content.addArrangedSubview(pillSpinner)
        statusPill.content.addArrangedSubview(pillLabel)
        statusPill.content.addArrangedSubview(pillAction)
        pillAction.isHidden = true
        NSLayoutConstraint.activate([
            statusPill.topAnchor.constraint(equalTo: headerRow.bottomAnchor),
            statusPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        pillLabel.text = tr("Not paired")
    }

    /// The pill's button is the entry the deleted bar item used to carry: never
    /// paired opens pairing, anything else retries the link.
    @objc private func statusPillAction() {
        if savedOffer == nil && pendingOffer == nil { showPairing() } else { retryConnection() }
    }

    private func setStatus(_ text: String) {
        pillLabel.text = text
        refreshStatusPill()
    }

    /// Online is the quiet state: nothing on screen, nothing reserved for it.
    private func refreshStatusPill() {
        let text = pillLabel.text ?? ""
        let quiet = text.isEmpty || text == tr("Online")
        statusPill.isHidden = quiet
        let spinning = text == tr("Connecting…") || text == tr("Checking computer…")
            || text == tr("Offline · reconnecting")
        if spinning && !pillSpinner.isAnimating { pillSpinner.startAnimating() }
        if !spinning { pillSpinner.stopAnimating() }
    }

    /// A build on a phone has no console, so a long press is the only way to get the dump
    /// out. It sits on the title and the status bar because both are always on screen.
    private func configureDiagnosticsMenu() {
        for target in [headerCenter, drawerControl] as [UIView] {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(showDiagnosticsMenu(_:)))
            press.minimumPressDuration = 0.6
            target.addGestureRecognizer(press)
        }
    }

    @objc private func showDiagnosticsMenu(_ press: UILongPressGestureRecognizer) {
        guard press.state == .began else { return }
        // The dump is written before the sheet appears: a user who only copies would
        // otherwise never leave a file behind, and the Updates page would be empty exactly
        // when someone needs it.
        let written = try? Diagnostics.shared.save()
        let sheet = UIAlertController(title: tr("Diagnostics"), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: tr("Copy diagnostics"), style: .default) { _ in
            // The paste is the file this sheet wrote, so it matches what the Updates page
            // lists; the in-memory text is only a fallback for a failed write.
            let text = written.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            UIPasteboard.general.string = text ?? Diagnostics.shared.text()
        })
        sheet.addAction(UIAlertAction(title: tr("Save diagnostics"), style: .default) { [weak self] _ in
            // Save names the file the sheet already wrote instead of making a second one.
            if let written {
                self?.showSavedDiagnostics(written)
            } else if let url = try? Diagnostics.shared.save() {
                self?.showSavedDiagnostics(url)
            } else {
                self?.showActionError(NativeLanguage.text("The dump could not be written."))
            }
        })
        sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        // An action sheet on iPad is a popover, and a popover needs an anchor.
        sheet.popoverPresentationController?.sourceView = press.view
        sheet.popoverPresentationController?.sourceRect = press.view?.bounds ?? .zero
        present(sheet, animated: true)
    }

    private func showSavedDiagnostics(_ url: URL) {
        let alert = UIAlertController(title: tr("Diagnostics saved"), message: url.lastPathComponent, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("Copy path"), style: .default) { _ in
            UIPasteboard.general.string = url.path
        })
        alert.addAction(UIAlertAction(title: tr("OK"), style: .cancel))
        present(alert, animated: true)
    }

    /// Messages start under the glass: the inset is the header's height when no goal
    /// card sits above the list, and zero when the goal already pushes it down.
    private func updateTopInset() {
        list.contentInset.top = roomGoalView.isHidden
            ? Metrics.headerHeight(insetTop: view.safeAreaInsets.top) : 0
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTopInset()
        updateComposerSide()
        headerFadeHeight?.constant = Metrics.headerFade(insetTop: view.safeAreaInsets.top)
    }

    private func configureRoomGoal() {
        roomGoalView.translatesAutoresizingMaskIntoConstraints = false
        goalHiddenHeight = roomGoalView.heightAnchor.constraint(equalToConstant: 0)
        goalHiddenHeight.isActive = true
        // With no goal the card collapses to the very top so the list runs under
        // the glass; with one it sits just below the header, as ShellB pads it.
        goalShown = roomGoalView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                                     constant: Glass.control + Glass.gap)
        goalHidden = roomGoalView.topAnchor.constraint(equalTo: view.topAnchor)
        roomGoalView.onHeightChange = { [weak self] in
            guard let self else { return }
            goalHiddenHeight.isActive = roomGoalView.isHidden
            goalShown.isActive = !roomGoalView.isHidden
            goalHidden.isActive = roomGoalView.isHidden
            updateTopInset()
            view.setNeedsLayout()
        }
        view.addSubview(roomGoalView)
        NSLayoutConstraint.activate([

            roomGoalView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            roomGoalView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    private func configureList() {
        list.translatesAutoresizingMaskIntoConstraints = false
        list.dataSource = self
        list.delegate = self
        list.separatorStyle = .none
        list.contentInset.bottom = 76
        updateTopInset()
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
        retryLoadButton.translatesAutoresizingMaskIntoConstraints = false
        retryLoadButton.setTitle(tr("Retry"), for: .normal)
        retryLoadButton.addTarget(self, action: #selector(retryChatLoad), for: .touchUpInside)
        retryLoadButton.isHidden = true
        view.addSubview(retryLoadButton)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: roomGoalView.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyState.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            retryLoadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            retryLoadButton.topAnchor.constraint(equalTo: emptyState.bottomAnchor, constant: 8),
        ])
        emptyChatView.translatesAutoresizingMaskIntoConstraints = false
        emptyChatView.isHidden = true
        view.addSubview(emptyChatView)
        view.addLayoutGuide(emptyChatGuide)
        NSLayoutConstraint.activate([
            emptyChatGuide.topAnchor.constraint(equalTo: view.topAnchor),
            emptyChatGuide.heightAnchor.constraint(equalTo: view.heightAnchor,
                                                   multiplier: EmptyChatView.topPercent),
            emptyChatView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: EmptyChatView.sideInset),
            emptyChatView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -EmptyChatView.sideInset),
            // Chat.tsx styles.empty pins the block at 28% of the screen. A percentage
            // offset needs a guide: pairing .top with .height is rejected at runtime.
            emptyChatView.topAnchor.constraint(equalTo: emptyChatGuide.bottomAnchor),
        ])
        headerFade.configure(color: palette.main)
        view.addSubview(headerFade)
        headerFadeHeight = headerFade.heightAnchor.constraint(
            equalToConstant: Metrics.headerFade(insetTop: view.safeAreaInsets.top))
        NSLayoutConstraint.activate([
            headerFade.topAnchor.constraint(equalTo: view.topAnchor),
            headerFade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerFade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerFadeHeight,
        ])
        // The header and its pill float over the list and the fade, so they stay frontmost.
        view.bringSubviewToFront(header)
        view.bringSubviewToFront(statusPill)
    }

    @objc private func retryChatLoad() { Task { await refreshLatest(for: sessionID) } }

    private func configureLatestButton() {
        latestButton.translatesAutoresizingMaskIntoConstraints = false
        latestButton.setTitle(tr("Latest messages"), for: .normal)
        latestButton.backgroundColor = .secondarySystemBackground
        latestButton.layer.cornerRadius = 20
        latestButton.layer.borderWidth = 1
        latestButton.layer.borderColor = UIColor.separator.cgColor
        latestButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        latestButton.addTarget(self, action: #selector(scrollToLatest), for: .touchUpInside)
        latestButton.isHidden = true
        view.addSubview(latestButton)
        NSLayoutConstraint.activate([
            latestButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            latestButton.bottomAnchor.constraint(equalTo: workStatusView.topAnchor, constant: -8),
        ])
    }

    @objc private func scrollToLatest() {
        guard !rows.isEmpty else { return }
        list.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: true)
    }

    private func updateEmptyState() {
        // A failed read keeps the old label, because the retry button belongs to it.
        if let loadError {
            emptyChatView.isHidden = true
            emptyState.text = loadError
            emptyState.isHidden = rows.count > 0
            retryLoadButton.isHidden = rows.count > 0
            return
        }
        // Unpaired keeps the old label too: the computer button in the navigation bar
        // is the pairing entry, and it is already on screen.
        if savedOffer == nil {
            emptyChatView.isHidden = true
            emptyState.text = tr("Pair with your computer to start chatting.")
            emptyState.isHidden = rows.count > 0
            if !rows.isEmpty { retryLoadButton.isHidden = true }
            return
        }
        // A conversation that exists but has nothing in it yet. chatSessionID is set
        // only by a read or a restored page, so this never claims "no messages" while
        // the first page is still on its way.
        if rows.isEmpty, chatSessionID != nil, let botID, let bot = teamBot(with: botID) {
            emptyChatView.configure(
                name: bot["name"]?.stringValue ?? selectedTarget?.name ?? "",
                role: bot["role"]?.stringValue ?? "",
                color: bot["color"]?.stringValue,
                caption: tr("No messages yet"))
            showEmptyChat()
            return
        }
        if rows.isEmpty, chatSessionID != nil, let roomID, let room = teamRoom(with: roomID) {
            emptyChatView.configure(
                name: room["name"]?.stringValue ?? selectedTarget?.name ?? "",
                role: "", color: nil,
                caption: tr("No messages yet"))
            showEmptyChat()
            return
        }
        // A computer whose team has no Bot at all: the one state with an action,
        // straight into the flow that fixes it.
        if rows.isEmpty, botID == nil, roomID == nil, teamHasNoBots {
            emptyChatView.configure(
                name: "", role: "", color: nil,
                caption: tr("No Bot yet"),
                actionTitle: tr("New Bot"),
                onAction: { [weak self] in self?.showBotEditor(id: nil) })
            showEmptyChat()
            return
        }
        // The first page of a fresh conversation, or the team state on its way: the
        // React Native app spins here, and a wrong caption would be worse than none.
        emptyChatView.isHidden = true
        emptyState.isHidden = true
        retryLoadButton.isHidden = true
    }

    private func showEmptyChat() {
        emptyChatView.isHidden = false
        emptyState.isHidden = true
        retryLoadButton.isHidden = true
    }

    private func teamBot(with id: String) -> JSONValue? {
        guard let teamState, case .array(let bots)? = teamState["bots"] else { return nil }
        return bots.first { $0["id"]?.stringValue == id }
    }

    private func teamRoom(with id: String) -> JSONValue? {
        guard let teamState, case .array(let rooms)? = teamState["rooms"] else { return nil }
        return rooms.first { $0["id"]?.stringValue == id }
    }

    private var teamHasNoBots: Bool {
        guard let teamState else { return false }
        if case .array(let bots)? = teamState["bots"] { return bots.isEmpty }
        return true
    }

    /// The same call the React Native app makes: since -1 asks for a full state, and
    /// avatars as refs keeps the reply small. An empty payload made the host's
    /// "nothing changed" early exit possible.
    private func statePayload() -> JSONValue {
        .object([
            "since": .number(-1),
            "avatars": .string("ref"),
            "live": liveKey.map { JSONValue.string($0) } ?? .null,
        ])
    }

    private func connect(to offer: PairingOffer, pairingCode: String?) {
        let oldSession = session
        stream.clear()
        let nextSession = LinkSession()
        session = nextSession
        // A fresh session means a fresh hello; push reporting waits for it.
        PushCenter.shared.hostOffline()
        let id = UUID()
        sessionID = id
        linkStatus = .connecting
        linkNeedsPairing = false
        reconnectTarget = nil
        composer.canSend = false
        composer.running = false
        composer.clear()
        polling?.cancel()
        polling = nil
        botID = nil
        roomID = nil
        updateSideButton()
        selectedTarget = nil
        teamState = nil
        blockedView.configure(nil)
        computerUseView.configure(nil)
        workStatusView.configure(nil)
        roomGoalView.configure(nil)
        pendingItems = []
        updatePendingButton()
        chatSessionID = nil
        olderRows = []
        latestRows = []
        rows = []
        latestButton.isHidden = true
        expandedSteps = []
        cursor = nil
        list.reloadData()
        updateEmptyState()
        setStatus(tr("Connecting…"))
        pillAction.isHidden = true
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
            await nextSession.setErrorHandler { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.showLinkError(error.userText, pairing: error.needsPairing, for: id)
                }
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
            let nearBottom = ScrollAnchor.atBottom(
                contentSize: list.contentSize.height, offset: list.contentOffset.y, viewport: list.bounds.height)
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
            if event == "message" {
                // Our own send comes back as an event while the outbox still shows it;
                // taking the echo would draw the message twice until the read lands.
                let sendsPending = !(outbox[chatKey ?? ""]?.isEmpty ?? true)
                if feedBuffer.feed(data, for: chatSessionID, sendsPending: sendsPending) != nil {
                    // The stream branch's own anchor dance: follow a pinned reader,
                    // leave a history reader where they are.
                    let nearBottom = ScrollAnchor.atBottom(
                        contentSize: list.contentSize.height, offset: list.contentOffset.y,
                        viewport: list.bounds.height)
                    rebuildRows()
                    if nearBottom && !rows.isEmpty {
                        list.layoutIfNeeded()
                        list.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0),
                                         at: .bottom, animated: false)
                    }
                }
            }
            Task { await refreshLatest(for: id) }
        }
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
        // Window level, not this view: a notice that lands while a sheet is up
        // has to stay visible above it, the way the RN shell banner does.
        NoticeOverlay.shared.show(
            text: [title, message].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": "),
            onTap: { [weak self] in self?.openNotice() },
            onAutoHide: { [weak self] in self?.noticeTarget = nil })
    }

    private func openNotice() {
        guard let target = noticeTarget else { return }
        noticeTarget = nil
        route(to: target)
    }

    /// A push tap carries ids only; the display name comes from team state.
    private func openPushTarget(kind: ChatTarget.Kind, id: String) {
        let records = kind == .bot ? teamState?["bots"] : teamState?["rooms"]
        var name = id
        if case .array(let values)? = records {
            name = values.first { $0["id"]?.stringValue == id }?["name"]?.stringValue ?? id
        }
        route(to: ChatTarget(kind: kind, id: id, name: name))
    }

    /// The one landing door for banners and push taps: a sheet that happens to
    /// be open closes first, so the user sees the chat they were pointed at.
    private func route(to target: ChatTarget) {
        let sheet = presentedViewController ?? navigationController?.presentedViewController
        if let sheet {
            sheet.dismiss(animated: true) { [weak self] in self?.selectTarget(target) }
        } else {
            selectTarget(target)
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
            setStatus(tr("Connecting…"))
            pillAction.isHidden = true
        case .online:
            setStatus(tr("Checking computer…"))
            pillAction.isHidden = true
            Task { await checkComputer(for: id) }
        case .offline:
            setStatus(tr("Offline · reconnecting"))
            pillAction.isHidden = true
            composer.canSend = false
            composer.running = false
            polling?.cancel()
            polling = nil
            stream.clear()
            rebuildRows()
        case .disconnected:
            if linkNeedsPairing {
                // The saved offer is dead until a new pairing link says otherwise.
                setStatus(tr("This phone is not paired with the computer yet."))
                pillAction.setTitle(tr("Pair"), for: .normal)
                pillAction.isHidden = false
            } else {
                setStatus(tr(savedOffer == nil && pendingOffer == nil ? "Not paired" : "Offline"))
                pillAction.setTitle(tr(savedOffer == nil && pendingOffer == nil ? "Pair" : "Retry"), for: .normal)
                pillAction.isHidden = false
            }
            composer.canSend = false
            composer.running = false
            polling?.cancel()
            polling = nil
            stream.clear()
            rebuildRows()
        }
    }

    private func showLinkError(_ message: String, pairing: Bool = false, for id: UUID) {
        guard id == sessionID else { return }
        if pairing { linkNeedsPairing = true }
        setStatus(message)
        let sheet = (presentedViewController as? UINavigationController)?.topViewController as? PairingViewController
        sheet?.showError(message)
    }

    private func checkComputer(for id: UUID) async {
        do {
            let hello = try await BotAPI.call("hello", on: session)
            guard id == sessionID, linkStatus == .online else { return }
            guard hello["api"]?.intValue != nil else {
                showLinkError(tr("Update DS Bot on the computer to use this phone."), for: id)
                await session.disconnect()
                return
            }
            // The hello reply names what the host takes; the push token rides
            // only when the computer listed "push-token", and the API version
            // never moves for it.
            PushCenter.shared.hostOnline(hello: hello, session: session)
            if let pendingOffer {
                pairingStore.save(pendingOffer)
                savedOffer = pendingOffer
                self.pendingOffer = nil
        
                updateEmptyState()
                presentedViewController?.dismiss(animated: true)
            }
            setStatus(tr("Online"))
            startPolling(for: id)
            // The read position outlives reconnects: a host that restarted answers
            // reset, and the team is read again instead of trusting stale numbers.
            if let reply = try? await BotAPI.call("notices", payload: feedState.parameters(), on: session),
               feedState.receive(reply) {
                await refreshLatest(for: id)
            }
        } catch {
            guard id == sessionID, linkStatus == .online else { return }
            showLinkError(error.userText, for: id)
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
            let state = try await BotAPI.call("state", payload: statePayload(), on: session)
            guard id == sessionID, linkStatus == .online else { return }
            if let live = state["liveKey"]?.stringValue { liveKey = live }
            // The host answers {revision, unchanged, liveKey} when nothing moved; the
            // screen keeps what it has instead of falling into the no-target branch.
            if state["unchanged"] == .bool(true) {
                loadError = nil
                updateEmptyState()
                return
            }
            loadError = nil
            teamState = state
            ThemeStore.update(from: state)
            let selected = state["mainBotId"]?.stringValue
            let bots: [JSONValue]
            if case .array(let values)? = state["bots"] { bots = values } else { bots = [] }
            let rooms: [JSONValue]
            if case .array(let values)? = state["rooms"] { rooms = values } else { rooms = [] }
            // A bots array we cannot use is a shape problem, not an empty team: say so
            // rather than letting the screen claim there is no Bot.
            switch state["bots"] {
            case .array(let values):
                if !values.isEmpty, !values.contains(where: { $0["id"]?.stringValue != nil }) {
                    loadError = "state reply: bots carried no string id"
                }
            case .some:
                loadError = "state reply: bots is not an array"
            case .none:
                loadError = "state reply: bots is missing"
            }
            // A retry remembered where the reader was. The reconnect opens straight
            // back into that conversation; one the team no longer has falls to the
            // normal pick below without a word. Nothing here touches the composer.
            if let back = reconnectTarget {
                reconnectTarget = nil
                let present = (back.kind == .bot ? bots : rooms)
                    .contains { $0["id"]?.stringValue == back.id }
                if present { selectedTarget = back }
            }
            // Cold start lands on the chat the reader last opened
            // (ShellB.tsx:326-330 reads it before the navigator renders);
            // a target the team no longer has clears the store itself
            // (ShellB.tsx:175-180), so the Main-Bot pick below stays the
            // fallback and the name is refilled from the team arrays.
            if !restoredLastChat {
                restoredLastChat = true
                if selectedTarget == nil,
                   let saved = LastChatStore.restore(stillKnown: { target in
                       (target.kind == .bot ? bots : rooms)
                           .contains { $0["id"]?.stringValue == target.id }
                   }) {
                    selectedTarget = saved
                }
            }
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
                title = tr("Chat")
                updateTitleButton()
                updateSideButton()
                pendingItems = []
                updatePendingButton()
                blockedView.configure(nil)
                computerUseView.configure(nil)
                workStatusView.configure(nil)
                roomGoalView.configure(nil)
                updateBottomInset()
                rows = []
                latestButton.isHidden = true
                list.reloadData()
                updateEmptyState()
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
            if target.kind == .bot, chosen?["blocked"] != nil {
                let models: [JSONValue]
                if case .array(let values)? = state["models"] { models = values } else { models = [] }
                blockedView.configure(BotBlockedPresentation(bot: chosen ?? .null, models: models))
            } else { blockedView.configure(nil) }
            if target.kind == .bot {
                computerUseView.configure(ComputerUsePresentation(bot: chosen ?? .null,
                                                                   live: state["computerLive"]))
            } else { computerUseView.configure(nil) }
            if target.kind == .room, let goal = chosen?["goal"], goal != .null {
                roomGoalView.configure(RoomGoalPresentation(goal: goal))
            } else { roomGoalView.configure(nil) }
            workStatusView.configure(WorkStatusPresentation(target: target, state: state))
            updateBottomInset()
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
            let page = ChatPage(value, inRoom: target.kind == .room)
            retryLoadButton.isHidden = true
            let nearBottom = ScrollAnchor.atBottom(
                contentSize: list.contentSize.height, offset: list.contentOffset.y, viewport: list.bounds.height)
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
            // The confirming read replaces everything the message events brought.
            feedBuffer.clear()
            latestRows = page.items
            // The fresh page overwrites whatever the cache held for this chat.
            if let key = chatKey {
                pageCache.store(key: key, older: olderRows, rows: page.items,
                                cursor: cursor, sessionID: nextSessionID)
            }
            rebuildRows()
            if nearBottom && !rows.isEmpty {
                list.layoutIfNeeded()
                list.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: false)
            }
        } catch {
            guard id == sessionID else { return }
            // A failed read is visible until one succeeds: updateEmptyState prefers it
            // over the placeholder text and keeps the retry button.
            loadError = error.localizedDescription
            updateEmptyState()
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
        Task {
            defer { loadingOlder = false }
            do {
                let value = try await BotAPI.call(isRoom ? "room-chat" : "chat", payload: .object([
                    parameter: .string(targetID),
                    "cursor": cursor, "steps": .bool(true),
                ]), on: session)
                guard id == sessionID, linkStatus == .online,
                      (isRoom ? roomID : botID) == targetID else { return }
                let page = ChatPage(value, inRoom: isRoom)
                self.cursor = page.cursor
                // An exhausted page only moves the cursor; reloading an unchanged list
                // would blink the reader's rows for nothing.
                guard !page.items.isEmpty else { return }
                // Captured at the moment of insertion, not when the read left: a
                // rebuild in between must not move the reader's rows.
                let oldHeight = list.contentSize.height
                let oldOffset = list.contentOffset.y
                olderRows.insert(contentsOf: page.items, at: 0)
                rebuildRows()
                list.layoutIfNeeded()
                // The page arrived above the viewport, so the offset moves down by
                // what the content grew; the same rows stay under the reader's eyes.
                // The full refresh below never does this: it replaces the newest rows
                // and either follows a pinned reader or leaves the offset alone.
                list.contentOffset.y = ScrollAnchor.offset(
                    keepingFocus: oldOffset, oldHeight: oldHeight,
                    newHeight: list.contentSize.height)
            } catch {
                // The next upward scroll can request the same page again.
            }
        }
    }

    @objc private func retryConnection() {
        if linkNeedsPairing {
            // Reconnecting the refused offer cannot succeed; the pairing sheet is
            // the way back in.
            presentPairingSheet()
            return
        }
        if let offer = pendingOffer ?? savedOffer {
            // connect resets the pending restore, so it is remembered after it: the
            // reader lands back in the conversation they were watching.
            connect(to: offer, pairingCode: pendingOffer == nil ? nil : offer.code)
            reconnectTarget = selectedTarget
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
                    composer.clear()
                    botID = nil
                    roomID = nil
                    chatSessionID = nil
                    updateSideButton()
                    selectedTarget = nil
                    teamState = nil
                    blockedView.configure(nil)
                    computerUseView.configure(nil)
                    workStatusView.configure(nil)
                    roomGoalView.configure(nil)
                    pendingItems = []
                    updatePendingButton()
                    chatSessionID = nil
                    cursor = nil
                    olderRows = []
                    latestRows = []
                    rows = []
                    latestButton.isHidden = true
                    list.reloadData()
                    updateEmptyState()
                    setStatus(tr("Not paired"))
            
                    Task { await old.disconnect() }
                }
            }
            present(UINavigationController(rootViewController: computers), animated: true)
            return
        }
        presentPairingSheet()
    }

    private func presentPairingSheet(prefill: String? = nil) {
        let sheet = PairingViewController()
        sheet.onPair = { [weak self] offer in
            guard let self else { return }
            self.pendingOffer = offer
            self.connect(to: offer, pairingCode: offer.code)
        }
        present(UINavigationController(rootViewController: sheet), animated: true)
        if let prefill { sheet.open(link: prefill) }
    }

    /// A dsbot://pair link from the system (App.tsx:104-110 in RN) lands here
    /// from the scene delegate, cold start or live tap alike: it goes through
    /// the same sheet, so a bad link is explained where the link is shown.
    func openPairingURL(_ url: URL) {
        let link = url.absoluteString
        if let sheet = (presentedViewController as? UINavigationController)?.topViewController as? PairingViewController {
            sheet.open(link: link)
            return
        }
        let present: () -> Void = { [weak self] in
            guard let self else { return }
            presentPairingSheet(prefill: link)
        }
        if presentedViewController != nil {
            dismiss(animated: true, completion: present)
        } else {
            present()
        }
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
        // ShellB.tsx:354: the drawer is the bare list panel, no navigation stack.
        team.modalPresentationStyle = .custom
        team.transitioningDelegate = drawerTransition
        present(team, animated: true)
    }

    private func showNeedsYou() {
        guard let teamState else { return }
        // ShellB.tsx:339: the sheet is the bare list with its own grabber.
        let needs = NeedsYouViewController(state: teamState)
        needs.onOpen = { [weak self] target in self?.selectTarget(target) }
        present(needs, animated: true)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              presentedViewController == nil, teamState != nil else { return false }
        let movement = pan.translation(in: view)
        let originX = pan.location(in: view).x - movement.x
        // Drawer.tsx:65-66: activate past 8 horizontally, fail past 12 vertically.
        return originX <= 24 && movement.x > 8 && abs(movement.y) <= 12
    }

    @objc private func openDrawerFromEdge(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        // Drawer.tsx:69,:74: past half the panel's width or a fast flick opens it.
        let width = min(view.bounds.width * 0.85, 340)
        let distance = pan.translation(in: view).x
        if distance > width / 2 || pan.velocity(in: view).x > 350 { showTeam() }
    }

    @objc private func showSideChat() {
        guard linkStatus == .online, let botID, let chatSessionID else { return }
        let name: String
        if case .array(let bots)? = teamState?["bots"],
           let bot = bots.first(where: { $0["id"]?.stringValue == botID }) {
            name = bot["name"]?.stringValue ?? tr("Bot")
        } else { name = "Bot" }
        let side = SideChatViewController(botID: botID, botName: name,
                                          sessionID: chatSessionID, session: session)
        present(UINavigationController(rootViewController: side), animated: true)
    }

    private func updateTitleButton() {
        let named = teamState != nil && (botID != nil || roomID != nil)
        headerCenter.isEnabled = named
        headerTitle.isHidden = named
        headerPill.isHidden = !named
        if named, let name = title {
            pillName.text = name
            pillAvatar.text = String(name.prefix(1)).uppercased()
            if roomID == nil {
                let botColor = teamState?["bots"].flatMap { value -> String? in
                    guard case .array(let bots) = value else { return nil }
                    return bots.first { $0["id"]?.stringValue == botID }?["color"]?.stringValue
                }
                pillAvatar.backgroundColor = Inks.bot(botColor, dark: traitCollection.userInterfaceStyle == .dark)
                pillAvatar.textColor = .white
            } else {
                pillAvatar.backgroundColor = palette.card
                pillAvatar.textColor = palette.ink
            }
            headerCenter.accessibilityLabel = name
        } else {
            headerTitle.text = title ?? tr("Chat")
            headerCenter.accessibilityLabel = tr("Conversation details")
        }
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
        details.onEditBot = { [weak self, weak details] id in
            details?.dismiss(animated: true) { [weak self] in self?.showBotEditor(id: id) }
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

    private func showProviders() {
        let settings = NativeSettingsViewController(computerName: savedOffer?.name ?? "", session: session)
        let navigation = UINavigationController(rootViewController: settings)
        navigation.pushViewController(ProviderSettingsViewController(session: session), animated: false)
        present(navigation, animated: true)
    }

    private func showUsage() {
        let usage = UsageViewController(session: session)
        present(UINavigationController(rootViewController: usage), animated: true)
    }

    private func selectTarget(_ target: ChatTarget) {
        guard selectedTarget != target else { return }
        // The draft goes before the fields change: the height callback then fires with
        // the outgoing rows still on screen, and no half-typed text rides into the new
        // target's send.
        composer.clear()
        // What the outgoing chat last showed is worth coming back to: the page as it
        // stood, including anything paged older since the last read.
        if let key = chatKey {
            pageCache.store(key: key, older: olderRows, rows: latestRows,
                            cursor: cursor, sessionID: chatSessionID)
        }
        selectedTarget = target
        // ShellB.tsx:167: every target switch saves the chat the user opened.
        LastChatStore.save(target)
        // The fields name the incoming chat right away: the restored page below then
        // lives under the same key the reads use, and the refresh's own reset block is
        // skipped, so what the cache restored survives until the fresh read lands.
        botID = target.kind == .bot ? target.id : nil
        roomID = target.kind == .room ? target.id : nil
        chatSessionID = nil
        stream.clear()
        olderRows = []
        latestRows = []
        rows = []
        latestButton.isHidden = true
        expandedSteps = []
        cursor = nil
        title = target.name
        updateTitleButton()
        pendingItems = []
        updatePendingButton()
        blockedView.configure(nil)
        computerUseView.configure(nil)
        workStatusView.configure(nil)
        roomGoalView.configure(nil)
        updateBottomInset()
        // The cached page renders in this same frame and the read that follows replaces
        // it. A page past the cache's age is not shown at all, so nothing stale flashes.
        if let key = ChatPageCache.key(host: savedOffer?.hostDeviceId, target: target),
           let cached = pageCache.retrieve(key) {
            olderRows = cached.older
            latestRows = cached.rows
            cursor = cached.cursor
            chatSessionID = cached.sessionID
        }
        updateSideButton()
        rebuildRows()
        // A conversation opens with its newest rows in view, restored page or empty
        // alike; the read that follows then keeps it pinned to the bottom.
        if !rows.isEmpty {
            list.layoutIfNeeded()
            list.scrollToRow(at: IndexPath(row: rows.count - 1, section: 0), at: .bottom, animated: false)
        }
        Task { await refreshLatest(for: sessionID) }
    }

    /// The resting capsule's height, so step 4 can grow it in place.
    private func configureComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composerHeight = composer.heightAnchor.constraint(equalToConstant: 62)
        composer.onExpandedChange = { [weak self] _ in
            guard let self else { return }
            self.updateComposerSide()
            let spring = Springs.shape
            UIView.animate(withDuration: spring.settling, delay: 0, usingSpringWithDamping: spring.dampingRatio,
                           initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.view.layoutIfNeeded()
            }
        }
        composer.onHeightChange = { [weak self] height in
            guard let self else { return }
            composerHeight.constant = height
            updateBottomInset()
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
        pendingDock.translatesAutoresizingMaskIntoConstraints = false
        pendingDock.onHeightChange = { [weak self] in self?.resizePendingDock(animated: true) }
        pendingDock.onChanged = { [weak self] in
            guard let self else { return }
            Task { await self.refreshLatest(for: self.sessionID) }
        }
        pendingDock.onOpen = { [weak self] item in self?.showPending(item) }
        pendingDock.onError = { [weak self] message in self?.showActionError(message) }
        view.addSubview(pendingDock)
        pendingHeight = pendingDock.heightAnchor.constraint(equalToConstant: 0)
        pendingDock.isHidden = true
        blockedView.translatesAutoresizingMaskIntoConstraints = false
        blockedView.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .providers: showProviders()
            case .topUp:
                if let url = URL(string: "https://platform.deepseek.com/top_up") { UIApplication.shared.open(url) }
            case .model: showDetails()
            }
        }
        view.addSubview(blockedView)
        computerUseView.translatesAutoresizingMaskIntoConstraints = false
        computerUseView.onAnswer = { [weak self] askID, answer in
            self?.answerComputerUse(askID: askID, answer: answer)
        }
        computerUseView.onStop = { [weak self] botID in self?.stopComputerUse(botID: botID) }
        view.addSubview(computerUseView)
        workStatusView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(workStatusView)
        if #available(iOS 17.0, *) {
            view.keyboardLayoutGuide.usesBottomSafeArea = true
        }
        composerLeading = composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Glass.margin)
        composerTrailing = composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Glass.margin)
        // Two anchors, one live at a time. With usesBottomSafeArea on, the guide's
        // top rests on the safe-area edge, so a composer pinned to it floats a
        // status bar high and its end circles miss the display corner's centre.
        composerBottomRest = composer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Glass.margin)
        composerBottomKeyboard = composer.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        composerBottomRest.isActive = true
        NSLayoutConstraint.activate([
            composerLeading,
            composerTrailing,
            composerHeight,
            pendingDock.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            pendingDock.trailingAnchor.constraint(equalTo: composer.trailingAnchor),
            pendingDock.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
            pendingHeight,
            blockedView.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            blockedView.trailingAnchor.constraint(equalTo: composer.trailingAnchor),
            blockedView.bottomAnchor.constraint(equalTo: pendingDock.topAnchor, constant: -8),
            computerUseView.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            computerUseView.trailingAnchor.constraint(equalTo: composer.trailingAnchor),
            computerUseView.bottomAnchor.constraint(equalTo: blockedView.topAnchor, constant: -8),
            workStatusView.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            workStatusView.trailingAnchor.constraint(lessThanOrEqualTo: composer.trailingAnchor),
            workStatusView.bottomAnchor.constraint(equalTo: computerUseView.topAnchor, constant: -8),
        ])
        updateComposerSide()
    }

    /// The composer's sides follow the display corner's centre at rest and take the
    /// standard margin while editing; 12 above the keyboard either way.
    private func updateComposerSide() {
        let screenR = Metrics.screenRadius(bottomInset: view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom,
                                           bounds: view.window?.bounds ?? view.bounds)
        let side = composer.isExpanded ? Glass.margin : Metrics.Composer.restInset(screenR: screenR)
        composerLeading.constant = side
        composerTrailing.constant = -side
        composerBottomRest.constant = -side
        composerBottomKeyboard.constant = -12
        if keyboardUp {
            composerBottomRest.isActive = false
            composerBottomKeyboard.isActive = true
        } else {
            composerBottomKeyboard.isActive = false
            composerBottomRest.isActive = true
        }
        updateBottomInset()
    }

    /// The composer's own distance from the bottom edge, so the list can clear it.
    private var composerBottomGap: CGFloat {
        keyboardUp ? 12 : -composerBottomRest.constant
    }

    private func updateBottomInset() {
        let blockedHeight = blockedView.isHidden ? 0 : blockedView.systemLayoutSizeFitting(
            CGSize(width: max(1, view.bounds.width - 32), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height + 8
        let computerHeight = computerUseView.isHidden ? 0 : computerUseView.systemLayoutSizeFitting(
            CGSize(width: max(1, view.bounds.width - 32), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height + 8
        let workHeight = workStatusView.isHidden ? 0 : workStatusView.systemLayoutSizeFitting(
            CGSize(width: max(1, view.bounds.width - 32), height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height + 8
        list.contentInset.bottom = composerHeight.constant + pendingHeight.constant + blockedHeight
            + computerHeight + workHeight + composerBottomGap + 12
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard composer.editor.isFirstResponder, let info = notification.userInfo,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber,
              let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber else { return }
        keyboardTiming = (duration.doubleValue, UIView.AnimationOptions(rawValue: UInt(curve.intValue) << 16))
        if let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let height = view.window?.bounds.height ?? view.bounds.height
            let up = frame.cgRectValue.minY < height - 1
            if up != keyboardUp {
                keyboardUp = up
                updateComposerSide()
            }
        }
    }

    private func updatePending(_ state: JSONValue, sessionID: String) {
        var items: [PendingActionsViewController.Item] = []
        if case .array(let approvals)? = state["work"]?["approvals"] {
            for approval in approvals where approval["sessionId"]?.stringValue == sessionID
                || (roomID != nil && approval["roomId"]?.stringValue == roomID) {
                items.append(.approval(approval))
            }
        }
        if let question = state["questions"]?[sessionID], question != .null {
            items.append(.question(sessionID: sessionID, value: question))
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
        if pendingDock.update(pendingItems, session: session) {
            resizePendingDock(animated: view.window != nil)
        }
        drawerControl.showsDot = !pendingItems.isEmpty
    }

    private func resizePendingDock(animated: Bool) {
        pendingDock.isHidden = pendingItems.isEmpty
        let width = max(1, view.bounds.width - 32)
        let maxHeight = max(1, view.bounds.height * 0.52)
        pendingHeight.constant = min(pendingDock.requiredHeight(width: width), maxHeight)
        updateBottomInset()
        let updates = { self.view.layoutIfNeeded() }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.82,
                           initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: updates)
        } else { updates() }
    }

    private func showPending(_ item: PendingActionsViewController.Item) {
        if case .view(let sessionID, let value) = item {
            let card = PendingViewController(sessionID: sessionID, record: value, session: session)
            card.onChanged = { [weak self] in
                guard let self else { return }
                Task { await self.refreshLatest(for: self.sessionID) }
            }
            present(UINavigationController(rootViewController: card), animated: true)
            return
        }
        if case .handoff(let botID, let value) = item {
            let browser = BrowserHandoffViewController(botID: botID, hold: value, session: session)
            browser.onChanged = { [weak self] in
                guard let self else { return }
                Task { await self.refreshLatest(for: self.sessionID) }
            }
            present(UINavigationController(rootViewController: browser), animated: true)
            return
        }
        let actions = PendingActionsViewController(items: [item], session: session)
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
                // Chat.tsx:371 buzzes once the send has landed, not when the
                // button goes down, so a failed send never clicks.
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    private func answerComputerUse(askID: String, answer: String) {
        guard linkStatus == .online, botID != nil,
              ["deny", "once", "always"].contains(answer) else { return }
        let connectionID = sessionID
        Task {
            do {
                _ = try await BotAPI.call("computer-app-answer",
                                          payload: ComputerUsePresentation.answerPayload(id: askID, answer: answer),
                                          on: session)
                await refreshLatest(for: connectionID)
            } catch { showActionError(error.localizedDescription) }
        }
    }

    private func stopComputerUse(botID targetID: String) {
        guard linkStatus == .online, botID == targetID else { return }
        let connectionID = sessionID
        Task {
            do {
                _ = try await BotAPI.call("computer-stop", payload: .object(["botId": .string(targetID)]), on: session)
                await refreshLatest(for: connectionID)
            } catch { showActionError(error.localizedDescription) }
        }
    }

    private func showActionError(_ message: String) {
        let alert = UIAlertController(title: tr("Could not complete the action"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: tr("OK"), style: .default))
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
        cell.onOpenPhoto = { [weak self] reference in self?.openPhotos(row.imageRefs, startingWith: reference) }
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
        if let record = rows[indexPath.row].viewRecord {
            let card = PendingViewController(sessionID: chatSessionID ?? "", record: record,
                                             session: session, readOnly: true)
            present(UINavigationController(rootViewController: card), animated: true)
            return
        }
        if let attachmentID = rows[indexPath.row].imageRefs.first {
            openPhotos(rows[indexPath.row].imageRefs, startingWith: attachmentID)
            return
        }
        guard let localID = rows[indexPath.row].localID,
              rows[indexPath.row].failed, let key = chatKey,
              let entry = outbox[key]?.first(where: { $0.id == localID }) else { return }
        let sheet = UIAlertController(title: tr("Message not sent"), message: entry.failureReason,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: tr("Retry"), style: .default) { [weak self] _ in
            guard let self, let index = self.outbox[key]?.firstIndex(where: { $0.id == localID }) else { return }
            self.outbox[key]?[index].failureReason = nil
            self.rebuildRows()
            self.deliver(entry, key: key)
        })
        sheet.addAction(UIAlertAction(title: tr("Discard"), style: .destructive) { [weak self] _ in
            self?.outbox[key]?.removeAll(where: { $0.id == localID })
            self?.rebuildRows()
        })
        sheet.addAction(UIAlertAction(title: tr("Cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(sheet, animated: true)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let distance = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.bounds.height
        latestButton.isHidden = rows.isEmpty || distance <= 600
        if (scrollView.isDragging || scrollView.isDecelerating) && scrollView.contentOffset.y < 100 {
            loadOlder()
        }
    }
}
