import UIKit

/// N1 chat shell. Messages and composer behaviour arrive in later steps.
final class ChatViewController: UIViewController {
    private let list = UITableView(frame: .zero, style: .plain)
    private let emptyState = UILabel()
    private let composer = UIView()
    private let statusBar = UIStackView()
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let pairingStore = PairingStore()
    private var session = LinkSession()
    private var sessionID = UUID()
    private var savedOffer: PairingOffer?
    private var pendingOffer: PairingOffer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chat"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Pair", style: .plain, target: self, action: #selector(showPairing)
        )
        configureStatusBar()
        configureList()
        configureComposer()
        savedOffer = pairingStore.load()
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
        list.separatorStyle = .none
        list.contentInset.bottom = 76
        list.register(UITableViewCell.self, forCellReuseIdentifier: "row")
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
            : "No messages yet"
    }

    private func connect(to offer: PairingOffer, pairingCode: String?) {
        let oldSession = session
        let nextSession = LinkSession()
        session = nextSession
        let id = UUID()
        sessionID = id
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
            await nextSession.connect(pairing)
        }
    }

    private func showStatus(_ status: LinkSession.Status, for id: UUID) {
        guard id == sessionID else { return }
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
                updateEmptyState()
                presentedViewController?.dismiss(animated: true)
            }
        case .offline:
            statusLabel.text = "Offline · reconnecting"
            retryButton.isHidden = true
        case .disconnected:
            statusLabel.text = savedOffer == nil && pendingOffer == nil ? "Not paired" : "Offline"
            retryButton.isHidden = savedOffer == nil && pendingOffer == nil
        }
    }

    @objc private func retryConnection() {
        if let offer = pendingOffer ?? savedOffer {
            connect(to: offer, pairingCode: pendingOffer == nil ? nil : offer.code)
        }
    }

    @objc private func showPairing() {
        let sheet = PairingViewController()
        sheet.onPair = { [weak self] offer in
            guard let self else { return }
            self.pendingOffer = offer
            self.connect(to: offer, pairingCode: offer.code)
        }
        present(UINavigationController(rootViewController: sheet), animated: true)
    }

    /// The resting capsule's height, so step 4 can grow it in place.
    private func configureComposer() {
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.backgroundColor = .secondarySystemBackground
        composer.layer.cornerRadius = 31
        composer.layer.borderWidth = 1
        composer.layer.borderColor = UIColor.separator.cgColor
        view.addSubview(composer)
        let placeholder = UILabel()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.text = "Message"
        placeholder.textColor = .placeholderText
        placeholder.font = .preferredFont(forTextStyle: .body)
        composer.addSubview(placeholder)
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            composer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            composer.heightAnchor.constraint(equalToConstant: 62),
            placeholder.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 20),
            placeholder.centerYAnchor.constraint(equalTo: composer.centerYAnchor),
        ])
    }
}

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
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
